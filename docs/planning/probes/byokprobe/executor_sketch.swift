// Compile check for providerDesign's executor sketch. Builds a request but never sends it.
import Foundation
import FoundationModels

struct Usage: Sendable { var input = 0, cacheWrite = 0, cacheRead = 0, output = 0 }
actor CallRecorder {   // content-free facts the session's usage can't carry
    var usage = Usage(); var stopReason: String?; var servedModel: String?; var messageID: String?
    func started(model: String?, id: String?) { servedModel = model; messageID = id }
    func delta(stop: String?, input: Int?, output: Int?, cacheRead: Int?, cacheWrite: Int?) {
        stopReason = stop ?? stopReason
        usage.input = input ?? usage.input; usage.output = output ?? usage.output
        usage.cacheRead = cacheRead ?? usage.cacheRead; usage.cacheWrite = cacheWrite ?? usage.cacheWrite
    }
}

enum BYOKError: Error { case truncated, http(Int), missingKey }

struct ClaudeLanguageModel: LanguageModel {
    typealias Executor = ClaudeExecutor
    let modelID: String          // "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"
    let effort: String           // "low" | "medium"
    let recorder: CallRecorder
    var capabilities: LanguageModelCapabilities { LanguageModelCapabilities([.guidedGeneration]) }
    var executorConfiguration: ClaudeExecutor.Configuration { .init(keychainAccount: "anthropic") }
}

struct ClaudeExecutor: LanguageModelExecutor {
    struct Configuration: Hashable, Sendable { let keychainAccount: String }
    let account: String
    init(configuration: Configuration) throws { account = configuration.keychainAccount }

    static let session = URLSession(configuration: .ephemeral)   // no disk cache, no cookies

    nonisolated(nonsending) func respond(to request: LanguageModelExecutorGenerationRequest,
                                         model: ClaudeLanguageModel,
                                         streamingInto channel: LanguageModelExecutorGenerationChannel) async throws {
        var system = "", user = ""
        for entry in request.transcript {
            switch entry {
            case .instructions(let i): system += text(i.segments)
            case .prompt(let p):
                if p.segments.contains(where: { if case .attachment = $0 { true } else { false } }) {
                    throw LanguageModelError.unsupportedTranscriptContent(.init(unsupportedContent: [entry], debugDescription: "media is never sent"))
                }
                user += text(p.segments)
            default: throw LanguageModelError.unsupportedTranscriptContent(.init(unsupportedContent: [entry], debugDescription: "single-turn only"))
            }
        }
        var body: [String: Any] = [
            "model": model.modelID, "stream": true,
            "max_tokens": request.generationOptions.maximumResponseTokens ?? 8_000,
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": user]],
        ]
        var output: [String: Any] = ["effort": model.effort]
        if let schema = request.schema { output["format"] = ["type": "json_schema", "schema": try claudeSchema(schema)] }
        body["output_config"] = output
        let fallback = model.modelID != "claude-haiku-5-5"            // Haiku 5.5 has no server-side fallback
        if fallback { body["fallbacks"] = "default" }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue(try KeyStoreRead(account), forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if fallback { req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("Saro-Lab/1", forHTTPHeaderField: "user-agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await Self.session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw BYOKError.http(0) }
        guard http.statusCode == 200 else { throw BYOKError.http(http.statusCode) }  // mapped by SaroAI (12.9)
        for try await line in bytes.lines where line.hasPrefix("data: ") {
            guard let event = try JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any] else { continue }
            switch event["type"] as? String {
            case "content_block_delta":
                if let d = event["delta"] as? [String: Any], d["type"] as? String == "text_delta", let t = d["text"] as? String {
                    await channel.send(.response(action: .appendText(t, tokenCount: 1)))
                }
            case "message_start":
                let m = event["message"] as? [String: Any]
                await model.recorder.started(model: m?["model"] as? String, id: m?["id"] as? String)
            case "message_delta":
                let stop = (event["delta"] as? [String: Any])?["stop_reason"] as? String
                let u = event["usage"] as? [String: Any] ?? [:]
                await model.recorder.delta(stop: stop, input: u["input_tokens"] as? Int, output: u["output_tokens"] as? Int,
                                           cacheRead: u["cache_read_input_tokens"] as? Int,
                                           cacheWrite: u["cache_creation_input_tokens"] as? Int)
                if stop == "refusal" {
                    throw LanguageModelError.refusal(.init(explanation: "", debugDescription: "stop_reason refusal"))
                }
                if stop == "max_tokens" { throw BYOKError.truncated }
            case "error": throw BYOKError.http(529)
            default: break        // ping, thinking deltas, signatures, unknown event types
            }
        }
    }
    private func text(_ segments: [Transcript.Segment]) -> String {
        segments.compactMap { if case .text(let t) = $0 { t.content } else { nil } }.joined(separator: "\n")
    }
}

func KeyStoreRead(_ account: String) throws -> String { throw BYOKError.missingKey }
func claudeSchema(_ schema: GenerationSchema) throws -> Any { [:] as [String: Any] }

// Cost in micro-dollars. Rates are $ per million tokens = micro-dollars per token.
struct Rates { let input, output, cacheWrite, cacheRead: Double }
let opus55 = Rates(input: 4, output: 20, cacheWrite: 5, cacheRead: 0.20)
func costMicros(_ u: Usage, _ r: Rates) -> Int {
    Int((Double(u.input) * r.input + Double(u.cacheWrite) * r.cacheWrite
       + Double(u.cacheRead) * r.cacheRead + Double(u.output) * r.output).rounded())
}
let c = costMicros(Usage(input: 2_500, cacheWrite: 0, cacheRead: 500, output: 1_500), opus55)
assert(c == 40_100, "cost \(c)")   // $0.0401
print("cost self-check passed:", c, "micro-dollars")
