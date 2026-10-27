// BYOK probe: does a custom LanguageModel plug into LanguageModelSession with guided generation?
// No network. The fake executor returns canned JSON in place of a Claude call.
import Foundation
import FoundationModels

@Generable struct Obs {
    @Guide(description: "kind of observation") var kind: String
    @Guide(.range(0...23)) var candidateIndex: Int
}
@Generable struct EntryExtraction {
    @Guide(description: "A 3 to 6 word title in the writer's words") var title: String
    var summary: String
    @Guide(.anyOf(["calm", "tired", "low"])) var mood: String
    @Guide(.range(0...23)) var quoteIndex: Int
    @Guide(.maximumCount(12)) var observations: [Obs]
}

nonisolated(unsafe) var mode = "ok"

struct FakeClaude: LanguageModel {
    typealias Executor = FakeExecutor
    var caps: [LanguageModelCapabilities.Capability] = [.guidedGeneration]
    var capabilities: LanguageModelCapabilities { LanguageModelCapabilities(caps) }
    var executorConfiguration: FakeExecutor.Configuration { .init(modelID: "claude-opus-5-5", keychainAccount: "anthropic") }
}

struct FakeExecutor: LanguageModelExecutor {
    struct Configuration: Hashable, Sendable { var modelID: String; var keychainAccount: String }
    typealias Model = FakeClaude
    init(configuration: Configuration) throws { print("executor init:", configuration.modelID) }
    func prewarm(model: FakeClaude, transcript: Transcript) { print("prewarm called") }
    nonisolated(nonsending) func respond(to request: LanguageModelExecutorGenerationRequest, model: FakeClaude, streamingInto channel: LanguageModelExecutorGenerationChannel) async throws {
        print("--- request", request.id)
        for e in request.transcript {
            switch e {
            case .instructions(let i): print("instructions:", i.segments.count, "segments")
            case .prompt(let p):
                for s in p.segments { if case .text(let t) = s { print("prompt text:", t.content) } }
                print("prompt.responseFormat:", p.responseFormat?.name ?? "nil")
            default: print("other entry")
            }
        }
        print("options:", request.generationOptions)
        print("contextOptions:", request.contextOptions)
        if let s = request.schema {
            let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .prettyPrinted]
            print("schema JSON:\n" + String(decoding: try enc.encode(s), as: UTF8.self))
        } else { print("schema: nil") }
        if mode == "refusal" {
            throw LanguageModelError.refusal(.init(explanation: "declined", debugDescription: "stop_reason refusal"))
        }
        let json = mode == "bad"
            ? #"{"title":"Long day"}"#
            : #"{"title":"Long day, tired but good","summary":"Shipped the flow.","mood":"tired","quoteIndex":2,"observations":[{"kind":"person","candidateIndex":4}]}"#
        var i = json.startIndex
        while i < json.endIndex {
            let j = json.index(i, offsetBy: 20, limitedBy: json.endIndex) ?? json.endIndex
            await channel.send(.response(action: .appendText(String(json[i..<j]), tokenCount: 5)))
            i = j
        }
        await channel.send(.response(action: .updateUsage(input: .init(totalTokenCount: 1200, cachedTokenCount: 900), output: .init(totalTokenCount: 80, reasoningTokenCount: 30), metadata: ["cache_write_tokens": 300, "model_served": "claude-opus-5-5", "stop_reason": "end_turn"])))
    }
}

let session = LanguageModelSession(model: FakeClaude(), instructions: "You are Saro. Return only what the schema asks.")
do {
    let r = try await session.respond(to: "Long day at work. Shipped the onboarding flow.", generating: EntryExtraction.self, options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 600))
    print("DECODED:", r.content.title, "|", r.content.mood, "|", r.content.quoteIndex, "|", r.content.observations.count)
    print("session.usage:", session.usage)
} catch { print("respond error:", error) }

print("=== streaming")
let s2 = LanguageModelSession(model: FakeClaude())
do {
    var n = 0
    for try await snap in s2.streamResponse(to: "x", generating: EntryExtraction.self) { n += 1; _ = snap }
    print("stream snapshots:", n)
} catch { print("stream error:", error) }

print("=== bad JSON (missing fields)")
mode = "bad"
do { let r = try await LanguageModelSession(model: FakeClaude()).respond(to: "x", generating: EntryExtraction.self); print("bad decoded?", r.content) }
catch { print("bad error:", error) }

print("=== refusal thrown by executor")
mode = "refusal"
do { _ = try await LanguageModelSession(model: FakeClaude()).respond(to: "x", generating: EntryExtraction.self) }
catch let e as LanguageModelError { if case .refusal = e { print("refusal surfaced as LanguageModelError.refusal") } else { print("other LME:", e) } }
catch { print("refusal error:", error) }

print("=== model without guidedGeneration")
mode = "ok"
do { _ = try await LanguageModelSession(model: FakeClaude(caps: [])).respond(to: "x", generating: EntryExtraction.self); print("no-cap: dispatched anyway") }
catch { print("no-cap error:", error) }

print("=== plain String")
do { let r = try await LanguageModelSession(model: FakeClaude()).respond(to: "hello"); print("string:", r.content.prefix(40)) }
catch { print("string error:", error) }
