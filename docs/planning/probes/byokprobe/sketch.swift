// Compile check for the BRD section 12 sketches. Makes no network call.
import Foundation
import FoundationModels
import Security

@Generable struct Obs { var kind: String; @Guide(.range(0...23)) var candidateIndex: Int }
@Generable struct EntryExtraction {
    @Guide(description: "A 3 to 6 word title in the writer's words") var title: String
    var summary: String
    @Guide(.range(0...23)) var quoteIndex: Int
    @Guide(.maximumCount(12)) var observations: [Obs]
}

// Claude structured outputs return 400 on minimum/maximum/maxItems; Saro checks bounds after decoding.
func claudeSchema(_ schema: GenerationSchema) throws -> Any {
    let keep: Set = ["type", "properties", "required", "additionalProperties", "items", "enum",
                     "const", "anyOf", "$ref", "$defs", "description", "format", "default"]
    func clean(_ node: Any, names: Bool = false) -> Any {
        if let list = node as? [Any] { return list.map { clean($0) } }
        guard let dict = node as? [String: Any] else { return node }
        if names { return dict.mapValues { clean($0) } }   // property and $defs names are data
        var out: [String: Any] = [:]
        for (k, v) in dict where keep.contains(k) { out[k] = clean(v, names: k == "properties" || k == "$defs") }
        if out["type"] as? String == "object" { out["additionalProperties"] = false }
        return out
    }
    return clean(try JSONSerialization.jsonObject(with: JSONEncoder().encode(schema)))
}

enum KeyStore {
    static func save(_ key: String, account: String) -> OSStatus {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Saro BYOK",
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
        ]
        SecItemDelete(item as CFDictionary)
        var add = item
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil)
    }
    static func read(_ account: String) throws -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "Saro BYOK",
                                kSecAttrAccount as String: account,
                                kSecUseDataProtectionKeychain as String: true,
                                kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else {
            throw CocoaError(.userCancelled)
        }
        return String(decoding: d, as: UTF8.self)
    }
}

actor CallRecorder { var stopReason: String?; func record(stop: String?) { stopReason = stop } }

struct ClaudeLanguageModel: LanguageModel {
    typealias Executor = ClaudeExecutor
    let modelID: String
    let effort: String
    let recorder: CallRecorder
    var capabilities: LanguageModelCapabilities { LanguageModelCapabilities([.guidedGeneration]) }
    var executorConfiguration: ClaudeExecutor.Configuration { .init(keychainAccount: "anthropic") }
}

struct ClaudeExecutor: LanguageModelExecutor {
    struct Configuration: Hashable, Sendable { let keychainAccount: String } // never the key itself
    let account: String
    init(configuration: Configuration) throws { account = configuration.keychainAccount }
    nonisolated(nonsending) func respond(to request: LanguageModelExecutorGenerationRequest,
                                         model: ClaudeLanguageModel,
                                         streamingInto channel: LanguageModelExecutorGenerationChannel) async throws {
        _ = try KeyStore.read(account)
        if let s = request.schema { _ = try claudeSchema(s) }
        // SSE loop elided in this compile check: text_delta -> .appendText, message_delta -> stop_reason and usage.
        let stop = "refusal"
        await model.recorder.record(stop: stop)
        if stop == "refusal" {
            throw LanguageModelError.refusal(.init(explanation: "", debugDescription: "stop_reason refusal"))
        }
        await channel.send(.response(action: .appendText("{}", tokenCount: 1)))
    }
}

let cleaned = try claudeSchema(EntryExtraction.generationSchema)
let text = String(decoding: try JSONSerialization.data(withJSONObject: cleaned, options: [.sortedKeys]), as: UTF8.self)
print(text)
for banned in ["minimum", "maximum", "maxItems", "x-order", "\"title\":\"EntryExtraction\""] {
    assert(!text.contains("\"\(banned)\"") && !text.contains(banned == "\"title\":\"EntryExtraction\"" ? banned : "§"), "kept \(banned)")
}
assert(text.contains("\"quoteIndex\"") && text.contains("\"title\":{"), "lost a property name")
print("sanitiser self-check passed")
