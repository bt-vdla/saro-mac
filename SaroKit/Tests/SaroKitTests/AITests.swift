import Foundation
import FoundationModels
import Testing
@testable import SaroKit

actor CallLog {
    var permissive = 0, guided = 0
    func hitPermissive() { permissive += 1 }
    func hitGuided() { guided += 1 }
}

let entryJSON = #"{"title": "Chai with Ravi", "summary": "You had chai with Ravi.", "mood": "calm", "moodBasis": "tired but good", "quoteIndex": 1}"#
let fallbackReading = EntryReading(title: "In your words", summary: "", mood: .neutral)
let guidedReading = EntryReading(title: "Guided", summary: "You wrote.", mood: .reflective)
let guardrail = LanguageModelError.guardrailViolation(.init(debugDescription: "test"))
let rateLimited = LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "test"))
let assetsMissing = SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: "test"))

func walk(permissive: @escaping @Sendable (Int) async throws -> String,
          guided: @escaping @Sendable (Int) async throws -> EntryReading,
          validate: @escaping @Sendable (EntryReading) -> Bool = { _ in true },
          log: CallLog) async -> (value: EntryReading, rung: Rung, calls: Int, stop: String?) {
    await Ladder.walk(
        permissive: { attempt in await log.hitPermissive(); return try await permissive(attempt) },
        decode: { try SaroAI.reading(Ladder.decode(EntryOut.self, from: $0)) },
        guided: { attempt in await log.hitGuided(); return try await guided(attempt) },
        prose: { $0.prose },
        validate: validate,
        fallback: fallbackReading)
}

@Test func fencedJSONDecodes() throws {
    let raw = "Here you go:\n```json\n\(entryJSON)\n```"
    let reading = try SaroAI.reading(Ladder.decode(EntryOut.self, from: raw))
    #expect(reading == EntryReading(title: "Chai with Ravi", summary: "You had chai with Ravi.", mood: .calm,
                                    moodBasis: "tired but good", quoteIndex: 1))
}

@Test func nullQuoteIndexAndMoodSpellings() throws {
    let raw = #"{"title": "t", "summary": "s", "mood": "Energized.", "moodBasis": "b", "quoteIndex": null}"#
    let reading = try SaroAI.reading(Ladder.decode(EntryOut.self, from: raw))
    #expect(reading.mood == .energised)
    #expect(reading.quoteIndex == nil)
}

@Test func unknownMoodIsADecodeFailure() {
    let raw = entryJSON.replacingOccurrences(of: "calm", with: "Happy")
    #expect(throws: (any Error).self) { try SaroAI.reading(Ladder.decode(EntryOut.self, from: raw)) }
}

@Test func dayJSONDecodesAndDedupes() throws {
    let raw = #"{"mood": "Bittersweet", "moodBasis": "b", "quoteIndexes": [2, 2, 5], "question": " What helped? ", "narrative": ""}"#
    let day = try SaroAI.reading(Ladder.decode(DayOut.self, from: raw))
    #expect(day == DayReading(mood: .bittersweet, moodBasis: "b", quoteIndexes: [2, 5], question: "What helped?", narrative: nil))
}

@Test func permissiveSuccessUsesOneCall() async {
    let log = CallLog()
    let result = await walk(permissive: { _ in entryJSON }, guided: { _ in guidedReading }, log: log)
    #expect(result.rung == .permissiveJSON)
    #expect(result.calls == 1)
    #expect(result.value.quoteIndex == 1)
}

@Test func garbageTwiceGoesGuided() async {
    let log = CallLog()
    let result = await walk(permissive: { _ in "I can't help with that." }, guided: { _ in guidedReading }, log: log)
    #expect(result.rung == .guided)
    #expect(result.value == guidedReading)
    #expect(result.calls == 3)
    #expect(await log.permissive == 2)
}

@Test func guardrailOnGuidedStopsAtHeuristic() async {
    let log = CallLog()
    let result = await walk(permissive: { _ in "nope" }, guided: { _ in throw guardrail }, log: log)
    #expect(result.rung == .heuristic)
    #expect(result.value == fallbackReading)
    #expect(result.calls == 3)
    #expect(await log.guided == 1)
}

@Test func guardrailOnPermissiveNeverReasks() async {
    let log = CallLog()
    let result = await walk(permissive: { _ in throw guardrail }, guided: { _ in guidedReading }, log: log)
    #expect(result.rung == .heuristic)
    #expect(result.calls == 1)
    #expect(await log.guided == 0)
}

@Test func validateFailureRetriesOnceThenDrops() async {
    let log = CallLog()
    let result = await walk(permissive: { _ in entryJSON }, guided: { _ in guidedReading },
                            validate: { $0 == guidedReading }, log: log)
    #expect(result.rung == .guided)
    #expect(await log.permissive == 2)
    #expect(result.calls == 3)
}

@Test func retryCarriesTheCorrectionAttempt() async {
    let log = CallLog()
    let result = await walk(permissive: { attempt in attempt == 0 ? "garbage" : entryJSON }, guided: { _ in guidedReading }, log: log)
    #expect(result.rung == .permissiveJSON)
    #expect(result.calls == 2)
    #expect(SaroAI.entryTask("x", [], json: true, retry: true).hasSuffix(SaroAI.correction))
    #expect(!SaroAI.entryTask("x", [], json: true, retry: false).contains(SaroAI.correction))
}

@Test func neverMoreThanFourCalls() async {
    struct Flaky: Error {}
    let log = CallLog()
    let result = await walk(permissive: { _ in throw Flaky() }, guided: { _ in guidedReading },
                            validate: { _ in false }, log: log)
    #expect(result.rung == .heuristic)
    #expect(result.calls == 4)
    #expect(await log.permissive + log.guided == 4)
}

@Test func outputGateHitEndsTheLadder() async {
    // SR-08: a hit is a hold, never a grounding miss that a clean retry or the next rung can paper over.
    let hit = entryJSON.replacingOccurrences(of: "You had chai with Ravi.", with: "You said you want to end it all.")
    let log = CallLog()
    let first = await walk(permissive: { _ in hit }, guided: { _ in guidedReading }, log: log)
    #expect(first.stop == "output_gate" && first.rung == .heuristic && first.calls == 1)
    #expect(await log.guided == 0)
    let hitGuided = EntryReading(title: "Guided", summary: "You want to end it all.", mood: .reflective)
    let second = await walk(permissive: { _ in "garbage" }, guided: { _ in hitGuided }, log: CallLog())
    #expect(second.stop == "output_gate" && second.calls == 3)
    #expect(await walk(permissive: { _ in entryJSON }, guided: { _ in guidedReading }, log: CallLog()).stop == nil)
}

@Test func rateLimitedStopsTheLadderAtOnce() async {
    let log = CallLog()
    let result = await walk(permissive: { _ in throw rateLimited }, guided: { _ in guidedReading }, log: log)
    #expect(result.stop == "rate_limited" && result.calls == 1)
    #expect(await log.guided == 0)
}

@Test func withoutPermissiveTheLadderStartsOnGuided() async {
    let log = CallLog()
    let result = await Ladder.walk(permissive: nil, decode: { try SaroAI.reading(Ladder.decode(EntryOut.self, from: $0)) },
                                   guided: { _ in await log.hitGuided(); return guidedReading }, prose: { $0.prose },
                                   validate: { _ in true }, fallback: fallbackReading)
    #expect(result.rung == .guided && result.calls == 1 && result.value == guidedReading)
}

@Test func quoteIndexOutOfRangeIsRejected() {
    let shown: Set<Int> = [0, 1, 2]
    #expect(SaroAI.grounded(EntryReading(title: "", summary: "", mood: .calm, quoteIndex: 2), in: shown))
    #expect(SaroAI.grounded(EntryReading(title: "", summary: "", mood: .calm, quoteIndex: nil), in: shown))
    #expect(!SaroAI.grounded(EntryReading(title: "", summary: "", mood: .calm, quoteIndex: 3), in: shown))
    #expect(!SaroAI.grounded(EntryReading(title: "", summary: "", mood: .calm, quoteIndex: -1), in: shown))
    #expect(SaroAI.grounded(DayReading(mood: .calm, quoteIndexes: [0, 2]), in: shown))
    #expect(!SaroAI.grounded(DayReading(mood: .calm, quoteIndexes: []), in: shown))
    #expect(!SaroAI.grounded(DayReading(mood: .calm, quoteIndexes: [0, 9]), in: shown))
    #expect(!SaroAI.grounded(DayReading(mood: .calm, quoteIndexes: [0, 1, 2, 0]), in: shown))
}

@Test func classifierLabels() {
    #expect(SafetyGate.parseLabel(" none.") == .label(.none))
    #expect(SafetyGate.parseLabel("PASSIVE\n") == .label(.passive))
    #expect(SafetyGate.parseLabel("Label: ACTIVE") == .label(.active))
    #expect(SafetyGate.parseLabel("I can't help with that.") == .uncertain(reason: "unparsed"))
    #expect(SafetyGate.parseLabel("") == .uncertain(reason: "unparsed"))
    #expect(SafetyGate.parseLabel("Sorry, I cannot say. None") == .uncertain(reason: "unparsed"))
}

@Test func truncatesAtASentenceBoundary() {
    let text = "First sentence here. Second one is longer than that. Third"
    #expect(Ladder.truncated(text, maxChars: 55) == "First sentence here. Second one is longer than that.")
    #expect(Ladder.truncated(text, maxChars: 200) == text)
    #expect(Ladder.truncated("one two three four five six", maxChars: 16) == "one two three")
}

@Test func timeoutReturnsNil() async throws {
    let start = ContinuousClock.now
    let value = try await SaroAI.withTimeout(.milliseconds(50)) { try await Task.sleep(for: .seconds(5)); return 1 }
    #expect(value == nil)
    #expect(ContinuousClock.now - start < .seconds(2))
    #expect(try await SaroAI.withTimeout(.seconds(5)) { 7 } == 7)
}

// MARK: Live model (synthetic text only, SR-28)

let liveModelAvailable = SystemLanguageModel.default.availability == .available

private let neutralEntry = "Long day at work. Shipped the onboarding flow finally. Had chai with Ravi and we talked about his move to Pune. Feeling tired but good."

func candidates(_ entryId: String, _ text: String, from start: Int = 0) -> [Candidate] {
    text.split(separator: ". ").enumerated().map { i, s in
        Candidate(index: start + i, entryId: entryId, field: "body", text: String(s), utf16From: 0, utf16To: 0)
    }
}

@Test(.enabled(if: liveModelAvailable)) func liveEntryReading() async {
    let ai = SaroAI()
    let (reading, provenance) = await ai.readEntry(entryId: "e1", text: neutralEntry, candidates: candidates("e1", neutralEntry),
                                                   fallback: fallbackReading, validate: { _ in true })
    #expect(provenance.executor == "on_device")
    #expect(provenance.rung != .heuristic)
    #expect((1...4).contains(provenance.modelCalls))
    #expect(provenance.contextSize ?? 0 >= 4096)
    #expect(!provenance.osBuild.isEmpty)
    #expect(reading.quoteIndex.map { (0..<4).contains($0) } ?? true)
    print("live entry:", reading, provenance)
}

@Test(.enabled(if: liveModelAvailable)) func liveDayReading() async {
    let second = "Walked home in the rain and called my sister. We laughed about the old flat."
    let digests = [EntryDigest(entryId: "e1", kind: "writing", time: "09:10", title: "Shipped the onboarding flow",
                               summary: "You shipped the onboarding flow and had chai with Ravi.", mood: .calm),
                   EntryDigest(entryId: "e2", kind: "voice", time: "19:40", title: "Rain and my sister",
                               summary: "You walked home in the rain and laughed with your sister.", mood: .grateful)]
    let (day, provenance) = await SaroAI().readDay(day: "2026-10-27", digests: digests,
                                                   candidates: candidates("e1", neutralEntry) + candidates("e2", second, from: 4),
                                                   fallback: DayReading(mood: .neutral, quoteIndexes: []), validate: { _ in true })
    #expect(provenance.rung != .heuristic)
    #expect((1...3).contains(day.quoteIndexes.count))
    print("live day:", day, provenance)
}

@Test(.enabled(if: liveModelAvailable)) func liveClassifier() async {
    let instructions = "You label private journal entries for a safety system. Answer with exactly one word: NONE, PASSIVE or ACTIVE. Most entries are NONE."
    let outcome = await SaroAI().classify(neutralEntry, instructions: instructions, prompt: "Entry: {text}\nLabel:")
    #expect(outcome == .label(.none))
}
