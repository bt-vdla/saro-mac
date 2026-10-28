import Foundation
import FoundationModels

@Generable
struct EntryOut {
    @Guide(description: "3 to 6 words, in the writer's own words")
    var title: String
    @Guide(description: "One sentence in second person reflecting back only what the writer said")
    var summary: String
    @Guide(.anyOf(Mood.allCases.map(\.rawValue)))
    var mood: String
    @Guide(description: "A few of the writer's words that show the mood")
    var moodBasis: String
    @Guide(description: "The number of the phrase that best captures the entry, or null")
    var quoteIndex: Int?
}

@Generable
struct DayOut {
    @Guide(.anyOf(Mood.allCases.map(\.rawValue)))
    var mood: String
    @Guide(description: "A few words naming what in the notes shows the mood")
    var moodBasis: String
    @Guide(description: "1 to 3 numbers of the phrases that best capture the day", .count(1...3))
    var quoteIndexes: [Int]
    @Guide(description: "One gentle open question about something the writer mentioned")
    var question: String
    @Guide(description: "One or two sentences in second person reflecting the day back, using only what the notes say")
    var narrative: String?
}

/// Apple's on-device model behind the ladder (§11.3). Every call opens a fresh session (§11.7); callers pass in
/// the safety side's candidates, heuristic fallback and output checks.
public actor SaroAI {
    public enum Status: Sendable, Hashable {
        case available
        case unavailable(reason: String)
    }

    public static let entryPromptVersion = "entry-2"
    public static let dayPromptVersion = "day-2"
    public static let osBuild: String = {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else {
            return ProcessInfo.processInfo.operatingSystemVersionString
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else {
            return ProcessInfo.processInfo.operatingSystemVersionString
        }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }()

    static let outputReserve = 600
    static let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: outputReserve)
    static let classifierTimeout: Duration = .seconds(6)
    /// Every other call. // calibration knob: a reading answers in a few seconds; this only catches one that never does.
    static let callTimeout: Duration = .seconds(30)

    let base = SystemLanguageModel.default
    private let permissive = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    private var warm: LanguageModelSession?
    private var personal: (name: String?, tone: Tone, focus: [FocusArea], known: [String])?
    /// Tests only: answers every prompt (classifier and both rungs) in the model's place, with the model's status.
    let stub: (@Sendable (String) async throws -> String)?
    private let stubStatus: Status?

    public init() { (stub, stubStatus) = (nil, nil) }

    init(stub: @escaping @Sendable (String) async throws -> String, status: Status = .available) {
        (self.stub, stubStatus) = (stub, status)
    }

    public nonisolated var status: Status {
        if let stubStatus { return stubStatus }
        return switch base.availability {
        case .available: .available
        case .unavailable(let reason): .unavailable(reason: "\(reason)")
        }
    }

    // A test stub stands in for the model, so it never asks the system model anything (that waits while it's busy).
    public nonisolated var variant: String { stub == nil ? base.variant.displayName : "stub" }
    /// The model can report 0 while it is busy or still loading; budgeting against 0 would mark every entry too long,
    /// and that is never retried (§11.5). 4096 is the smallest context the on-device model has shipped with.
    public nonisolated var contextSize: Int {
        let n = stub == nil ? base.contextSize : 0
        return n > 0 ? n : 4096
    }

    /// Loads the model ahead of a call (recorder open, inspector shown). The session is kept so it isn't torn down mid-warm.
    public func prewarm() {
        guard status == .available else { return }
        warm = LanguageModelSession(model: permissive, instructions: entryInstructions)
        warm?.prewarm()
    }

    // MARK: Personalisation

    /// Tone, name and focus for the next sessions (prompts.py personalization; FR-SET-01: a change applies to the next
    /// session). `known` are the person's own words (their name) that the drift check takes as known, not invented.
    public func setPersonalization(name: String?, tone: Tone, focus: [FocusArea], known: [String]) {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        personal = (name?.isEmpty == false ? name : nil, tone, focus, known.filter { !$0.isEmpty })
    }

    public var tone: Tone { personal?.tone ?? .neutral }
    public var known: [String] { personal?.known ?? [] }
    /// The person's name: it may be addressed, but never put inside quote marks as if they had said it.
    public var name: String? { personal?.name }

    static let toneLines: [Tone: String] = [
        .gentle: "Lean gentle: soft wording, no pushing.",
        .neutral: "Balanced and observational.",
        .direct: "Be brief and direct.",
        .contemplative: "Allow slower, more reflective questions. The plain-language rules still apply.",
    ]

    var personalization: String {
        guard let p = personal else { return "" }
        var parts = [Self.toneLines[p.tone]!]
        if let name = p.name { parts.append("You may address the user as \(name), sparingly.") }
        if !p.focus.isEmpty {
            parts.append("Areas the user cares about: \(p.focus.map(\.label).joined(separator: ", ")). Connect to them only when an entry does.")
        }
        return "\n\nPersonalisation:\n" + parts.map { "- \($0)" }.joined(separator: "\n")
    }

    /// What shaped the prompt, content-free, for ai_run.prompt_version: the tone, and whether a name or focus areas went in.
    var personalTag: String {
        guard let p = personal else { return "" }
        return "+\(p.tone.rawValue)" + (p.name == nil ? "" : "+name") + (p.focus.isEmpty ? "" : "+focus\(p.focus.count)")
    }

    var entryInstructions: String { Self.entryInstructions + personalization }
    var dayInstructions: String { Self.dayInstructions + personalization }

    // MARK: Layer-2 classifier

    /// Permissive, greedy, 8 output tokens, 6 s timeout. `prompt` holds `{text}` where the entry goes (else the
    /// text is appended). Errors and timeouts are `.uncertain` (a safety hold); a missing model is `.unavailable`;
    /// a rate limit is `.deferred` (§11.7).
    public func classify(_ text: String, instructions: String, prompt: String) async -> ClassifierOutcome {
        if case .unavailable(let reason) = status { return .unavailable(reason: reason) }
        let full = prompt.contains("{text}") ? prompt.replacingOccurrences(of: "{text}", with: text) : prompt + "\n" + text
        // ponytail: over-budget text fails closed as a hold; chunk at 3,000 tokens (§11.5) when long entries show up.
        guard await tokens(instructions, full, nil) <= contextSize - 16 else { return .uncertain(reason: "too_long") }
        let (model, stub) = (permissive, self.stub)
        do {
            let reply = try await Self.withTimeout(Self.classifierTimeout) {
                try await Self.ask(model, instructions, full, GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 8), stub)
            }
            guard let reply else { return .uncertain(reason: "timeout") }
            return SafetyGate.parseLabel(reply)
        } catch {
            let reason = Ladder.reason(error)
            if reason == "rate_limited" { return .deferred(reason: reason) }
            return ["unsupportedLanguageOrLocale", "assetsUnavailable"].contains(reason)
                ? .unavailable(reason: reason) : .uncertain(reason: reason)
        }
    }

    // MARK: Per-entry reading

    /// Title, summary, mood and one quote index for one gate-cleared entry. `validate` is the caller's drift check;
    /// an out-of-range quote index is rejected here before it runs. A layer-3 hit ends with status `output_gate`.
    public func readEntry(entryId: String, text: String, candidates: [Candidate], fallback: EntryReading,
                          validate: @escaping @Sendable (EntryReading) -> Bool) async -> (EntryReading, Provenance) {
        let start = ContinuousClock.now
        let shown = candidates.filter { $0.entryId == entryId }
        let version = Self.entryPromptVersion + personalTag
        guard status == .available else { return (fallback, provenance(.heuristic, 0, nil, version, start)) }
        // Text that can't be fitted never will be (§11.5): marked, so a later pass doesn't read it again.
        let instructions = entryInstructions
        guard let fitted = await fit(text, instructions: instructions, schema: EntryOut.generationSchema,
                                     prompt: { Self.entryTask($0, shown, json: true, retry: true) })
        else { return (fallback, provenance(.heuristic, 0, nil, version, start, "too_long")) }

        let text = fitted.text
        let indexes = Set(shown.map(\.index))
        let (base, permissive, stub) = (self.base, self.permissive, self.stub)
        let result = await Ladder.walk(
            permissive: { attempt in
                try await Self.ask(permissive, instructions, Self.entryTask(text, shown, json: true, retry: attempt > 0),
                                   Self.options, stub)
            },
            decode: { try Self.reading(Ladder.decode(EntryOut.self, from: $0)) },
            guided: { attempt in
                try await Self.reading(Self.ask(EntryOut.self, base, instructions,
                                                Self.entryTask(text, shown, json: false, retry: attempt > 0), Self.options, stub))
            },
            prose: { $0.prose },
            validate: { Self.grounded($0, in: indexes) && validate($0) },
            fallback: fallback)
        return (result.value, provenance(result.rung, result.calls, fitted.tokens, version, start, result.stop))
    }

    // MARK: Day reading

    /// Map-reduce (revised.json `insights`): the day call sees only per-entry digests and numbered candidates, never
    /// raw day text. Digests are oldest first; over budget, the oldest are dropped with their candidates. Without
    /// `permissiveOK` (a digest the model refused), the ladder starts on guided. A `seed` samples (Refresh, FR-REF-11)
    /// instead of greedy; `avoid` is the narrative to say differently, and `exclude` the questions asked lately.
    public func readDay(day: String, digests: [EntryDigest], candidates: [Candidate], fallback: DayReading, permissiveOK: Bool = true,
                        seed: UInt64? = nil, avoid: String? = nil, exclude: [String] = [],
                        validate: @escaping @Sendable (DayReading) -> Bool) async -> (DayReading, Provenance) {
        let start = ContinuousClock.now
        let version = Self.dayPromptVersion + personalTag
        let instructions = dayInstructions
        let task = { @Sendable (d: [EntryDigest], c: [Candidate], json: Bool, retry: Bool) in
            Self.dayTask(d, c, json: json, retry: retry, avoid: avoid, exclude: exclude)
        }
        var digests = digests
        var shown: [Candidate] = []
        var tokensIn = 0
        while !digests.isEmpty {
            let ids = Set(digests.map(\.entryId))
            shown = candidates.filter { ids.contains($0.entryId) }
            tokensIn = await tokens(instructions, task(digests, shown, true, true), DayOut.generationSchema)
            if tokensIn <= contextSize - Self.outputReserve { break }
            digests.removeFirst()
        }
        guard status == .available, !digests.isEmpty, !shown.isEmpty else {
            return (fallback, provenance(.heuristic, 0, nil, version, start))
        }

        let indexes = Set(shown.map(\.index))
        let options = seed.map { GenerationOptions(samplingMode: .random(probabilityThreshold: 0.9, seed: $0), maximumResponseTokens: Self.outputReserve) }
            ?? Self.options
        let (base, permissive, stub, kept) = (self.base, self.permissive, self.stub, digests)
        let ask: (@Sendable (Int) async throws -> String)? = permissiveOK ? { @Sendable [shown] attempt in
            try await Self.ask(permissive, instructions, task(kept, shown, true, attempt > 0), options, stub)
        } : nil
        let result = await Ladder.walk(
            permissive: ask,
            decode: { try Self.reading(Ladder.decode(DayOut.self, from: $0)) },
            guided: { [shown] attempt in
                try await Self.reading(Self.ask(DayOut.self, base, instructions, task(kept, shown, false, attempt > 0), options, stub))
            },
            prose: { $0.prose },
            validate: { Self.grounded($0, in: indexes) && !exclude.contains($0.question ?? "") && validate($0) },
            fallback: fallback)
        return (result.value, provenance(result.rung, result.calls, tokensIn, version, start, result.stop))
    }

    // MARK: Prompts

    static let voice = """
    You are Saro, a private journal. Reflect back only what the person said, in their own words. \
    Never invent people, places, facts or history. Never give advice, diagnose or judge.
    """
    static let entryInstructions = voice
    static let dayInstructions = voice + " You see Saro's short notes on today's entries, not the entries themselves."
    static let correction = "Your last reply could not be used. Use only the writer's own words, and only numbers from the list."
    static let moodList = Mood.allCases.map(\.rawValue).joined(separator: ", ")

    static func entryTask(_ text: String, _ candidates: [Candidate], json: Bool, retry: Bool) -> String {
        var parts = candidates.isEmpty ? [] : ["Numbered phrases from the entry:\n" + Ladder.numbered(candidates)]
        parts.append("Entry:\n" + text)
        if json {
            parts.append("""
            Reply with only a JSON object, no markdown, with exactly these keys:
            "title": 3 to 6 words, in the writer's own words
            "summary": one sentence in second person reflecting back what the writer said
            "mood": one of \(moodList)
            "moodBasis": a few of the writer's words that show the mood
            "quoteIndex": the number of the phrase that best captures the entry, or null
            """)
        }
        if retry { parts.append(correction) }
        return parts.joined(separator: "\n\n")
    }

    static func dayTask(_ digests: [EntryDigest], _ candidates: [Candidate], json: Bool, retry: Bool, avoid: String? = nil,
                        exclude: [String] = []) -> String {
        let notes = digests.map { d in
            "- \(d.time) \(d.kind): \"\(d.title)\". \(d.summary)" + (d.mood.map { " Mood: \($0.rawValue)." } ?? "")
        }
        var parts = ["Notes on today's entries, oldest first:\n" + notes.joined(separator: "\n"),
                     "Numbered phrases from today's entries:\n" + Ladder.numbered(candidates)]
        if json {
            parts.append("""
            Reply with only a JSON object, no markdown, with exactly these keys:
            "mood": one of \(moodList)
            "moodBasis": a few words naming what in the notes shows the mood
            "quoteIndexes": an array of 1 to 3 numbers of the phrases that best capture the day
            "question": one gentle open question about something the writer mentioned
            "narrative": one or two sentences in second person reflecting the day back, using only what the notes say, or null
            """)
        }
        if !exclude.isEmpty { parts.append("Ask a question that is not one of these:\n" + exclude.map { "- \($0)" }.joined(separator: "\n")) }
        if let avoid, !avoid.isEmpty { parts.append("Say it differently from this earlier narrative: \(avoid)") }
        if retry { parts.append(correction) }
        return parts.joined(separator: "\n\n")
    }

    /// Quote indexes must name a shown candidate (§11.6); a miss is a grounding failure.
    static func grounded(_ reading: EntryReading, in indexes: Set<Int>) -> Bool {
        reading.quoteIndex.map(indexes.contains) ?? true
    }

    static func grounded(_ reading: DayReading, in indexes: Set<Int>) -> Bool {
        (1...3).contains(reading.quoteIndexes.count) && reading.quoteIndexes.allSatisfy(indexes.contains)
    }

    static func reading(_ out: EntryOut) throws -> EntryReading {
        EntryReading(title: out.title.trimmingCharacters(in: .whitespacesAndNewlines),
                     summary: out.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                     mood: try Ladder.mood(out.mood), moodBasis: out.moodBasis, quoteIndex: out.quoteIndex)
    }

    static func reading(_ out: DayOut) throws -> DayReading {
        var seen = Set<Int>()
        let narrative = out.narrative?.trimmingCharacters(in: .whitespacesAndNewlines)
        return DayReading(mood: try Ladder.mood(out.mood), moodBasis: out.moodBasis,
                          quoteIndexes: out.quoteIndexes.filter { seen.insert($0).inserted },
                          question: out.question.trimmingCharacters(in: .whitespacesAndNewlines),
                          narrative: narrative?.isEmpty == false ? narrative : nil)
    }

    // MARK: Budget, timing, provenance

    private func tokens(_ instructions: String, _ prompt: String, _ schema: GenerationSchema?) async -> Int {
        // A test stub answers in the model's place, so it shouldn't wait on the system model to count tokens.
        if stub != nil { return Self.estimate(instructions, prompt, schema) }
        do {
            var n = try await base.tokenCount(for: Instructions(instructions))
            n += try await base.tokenCount(for: prompt)
            if let schema { n += try await base.tokenCount(for: schema) }
            return n
        } catch {
            return Self.estimate(instructions, prompt, schema)
        }
    }

    // ponytail: 3 chars/token is the BRD's conservative knob, used only when tokenCount can't be asked.
    private static func estimate(_ instructions: String, _ prompt: String, _ schema: GenerationSchema?) -> Int {
        (instructions.count + prompt.count) / 3 + (schema == nil ? 0 : 350)
    }

    /// Shrinks the user's text at a sentence boundary until instructions + prompt + schema leave the output reserve.
    private func fit(_ text: String, instructions: String, schema: GenerationSchema,
                     prompt: (String) -> String) async -> (text: String, tokens: Int)? {
        let limit = contextSize - Self.outputReserve
        let fixed = await tokens(instructions, prompt(""), schema)
        guard fixed < limit else { return nil }
        var text = text
        for _ in 0..<4 {
            let n = await tokens(instructions, prompt(text), schema)
            if n <= limit { return (text, n) }
            text = Ladder.truncated(text, maxChars: Int(Double(text.count) * Double(limit - fixed) / Double(n - fixed) * 0.95))
        }
        return nil
    }

    static func withTimeout<T: Sendable>(_ limit: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T? {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await operation() }
            group.addTask { try await Task.sleep(for: limit); return nil }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }

    /// One call in a fresh session (§11.7); the test stub answers in the model's place. A call that outlasts `limit`
    /// throws `Ladder.Timeout`, so one that never answers can't hold the one-job queue.
    static func ask(_ model: SystemLanguageModel, _ instructions: String, _ prompt: String, _ options: GenerationOptions,
                    _ stub: (@Sendable (String) async throws -> String)?, limit: Duration = callTimeout) async throws -> String {
        guard let reply = try await withTimeout(limit, {
            if let stub { return try await stub(prompt) }
            return try await LanguageModelSession(model: model, instructions: instructions).respond(to: prompt, options: options).content
        }) else { throw Ladder.Timeout() }
        return reply
    }

    static func ask<T: Generable & Sendable>(_ type: T.Type, _ model: SystemLanguageModel, _ instructions: String, _ prompt: String,
                                             _ options: GenerationOptions, _ stub: (@Sendable (String) async throws -> String)?) async throws -> T {
        guard let reply = try await withTimeout(callTimeout, {
            if let stub { return try await Ladder.decode(T.self, from: stub(prompt)) }
            return try await LanguageModelSession(model: model, instructions: instructions)
                .respond(to: prompt, generating: T.self, options: options).content
        }) else { throw Ladder.Timeout() }
        return reply
    }

    private func provenance(_ rung: Rung, _ calls: Int, _ tokensIn: Int?, _ promptVersion: String,
                            _ start: ContinuousClock.Instant, _ stop: String? = nil) -> Provenance {
        Provenance(executor: rung == .heuristic ? "heuristic" : "on_device", rung: rung,
                   guardrails: rung == .permissiveJSON ? "permissive" : rung == .guided ? "default" : nil,
                   variant: variant, osBuild: Self.osBuild, contextSize: contextSize, promptVersion: promptVersion,
                   tokensIn: tokensIn, modelCalls: calls, latencyMs: Int((ContinuousClock.now - start) / .milliseconds(1)),
                   status: stop ?? "ok")
    }
}
