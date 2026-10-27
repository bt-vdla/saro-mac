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

    public static let entryPromptVersion = "entry-1"
    public static let dayPromptVersion = "day-1"
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

    private let base = SystemLanguageModel.default
    private let permissive = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    private var warm: LanguageModelSession?

    public init() {}

    public nonisolated var status: Status {
        switch base.availability {
        case .available: .available
        case .unavailable(let reason): .unavailable(reason: "\(reason)")
        }
    }

    public nonisolated var variant: String { base.variant.displayName }
    public nonisolated var contextSize: Int { base.contextSize }

    /// Loads the model ahead of a call (recorder open, inspector shown). The session is kept so it isn't torn down mid-warm.
    public func prewarm() {
        guard status == .available else { return }
        warm = LanguageModelSession(model: permissive, instructions: Self.entryInstructions)
        warm?.prewarm()
    }

    // MARK: Layer-2 classifier

    /// Permissive, greedy, 8 output tokens, 6 s timeout. `prompt` holds `{text}` where the entry goes (else the
    /// text is appended). Errors and timeouts are `.uncertain` (a safety hold); a missing model is `.unavailable`.
    public func classify(_ text: String, instructions: String, prompt: String) async -> ClassifierOutcome {
        if case .unavailable(let reason) = status { return .unavailable(reason: reason) }
        let full = prompt.contains("{text}") ? prompt.replacingOccurrences(of: "{text}", with: text) : prompt + "\n" + text
        // ponytail: over-budget text fails closed as a hold; chunk at 3,000 tokens (§11.5) when long entries show up.
        guard await tokens(instructions, full, nil) <= contextSize - 16 else { return .uncertain(reason: "too_long") }
        let model = permissive
        do {
            let reply = try await Self.withTimeout(Self.classifierTimeout) {
                try await LanguageModelSession(model: model, instructions: instructions)
                    .respond(to: full, options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 8)).content
            }
            guard let reply else { return .uncertain(reason: "timeout") }
            return Ladder.label(reply)
        } catch {
            let reason = Ladder.reason(error)
            return ["unsupportedLanguageOrLocale", "assetsUnavailable"].contains(reason)
                ? .unavailable(reason: reason) : .uncertain(reason: reason)
        }
    }

    // MARK: Per-entry reading

    /// Title, summary, mood and one quote index for one gate-cleared entry. `validate` is the caller's drift check
    /// and output gate; an out-of-range quote index is rejected here before it runs.
    public func readEntry(entryId: String, text: String, candidates: [Candidate], fallback: EntryReading,
                          validate: @escaping @Sendable (EntryReading) -> Bool) async -> (EntryReading, Provenance) {
        let start = ContinuousClock.now
        let shown = candidates.filter { $0.entryId == entryId }
        guard status == .available,
              let fitted = await fit(text, instructions: Self.entryInstructions, schema: EntryOut.generationSchema,
                                     prompt: { Self.entryTask($0, shown, json: true, retry: true) })
        else { return (fallback, provenance(.heuristic, 0, nil, Self.entryPromptVersion, start)) }

        let text = fitted.text
        let indexes = Set(shown.map(\.index))
        let (base, permissive) = (self.base, self.permissive)
        let result = await Ladder.walk(
            permissive: { attempt in
                try await LanguageModelSession(model: permissive, instructions: Self.entryInstructions)
                    .respond(to: Self.entryTask(text, shown, json: true, retry: attempt > 0), options: Self.options).content
            },
            decode: { try Self.reading(Ladder.decode(EntryOut.self, from: $0)) },
            guided: { attempt in
                let out = try await LanguageModelSession(model: base, instructions: Self.entryInstructions)
                    .respond(to: Self.entryTask(text, shown, json: false, retry: attempt > 0), generating: EntryOut.self,
                             options: Self.options).content
                return try Self.reading(out)
            },
            validate: { Self.grounded($0, in: indexes) && validate($0) },
            fallback: fallback)
        return (result.value, provenance(result.rung, result.calls, fitted.tokens, Self.entryPromptVersion, start))
    }

    // MARK: Day reading

    /// Map-reduce (revised.json `insights`): the day call sees only per-entry digests and numbered candidates, never
    /// raw day text. Digests are oldest first; over budget, the oldest are dropped with their candidates.
    public func readDay(day: String, digests: [EntryDigest], candidates: [Candidate], fallback: DayReading,
                        validate: @escaping @Sendable (DayReading) -> Bool) async -> (DayReading, Provenance) {
        let start = ContinuousClock.now
        var digests = digests
        var shown: [Candidate] = []
        var tokensIn = 0
        while !digests.isEmpty {
            let ids = Set(digests.map(\.entryId))
            shown = candidates.filter { ids.contains($0.entryId) }
            tokensIn = await tokens(Self.dayInstructions, Self.dayTask(digests, shown, json: true, retry: true),
                                    DayOut.generationSchema)
            if tokensIn <= contextSize - Self.outputReserve { break }
            digests.removeFirst()
        }
        guard status == .available, !digests.isEmpty, !shown.isEmpty else {
            return (fallback, provenance(.heuristic, 0, nil, Self.dayPromptVersion, start))
        }

        let indexes = Set(shown.map(\.index))
        let (base, permissive, kept) = (self.base, self.permissive, digests)
        let result = await Ladder.walk(
            permissive: { [shown] attempt in
                try await LanguageModelSession(model: permissive, instructions: Self.dayInstructions)
                    .respond(to: Self.dayTask(kept, shown, json: true, retry: attempt > 0), options: Self.options).content
            },
            decode: { try Self.reading(Ladder.decode(DayOut.self, from: $0)) },
            guided: { [shown] attempt in
                let out = try await LanguageModelSession(model: base, instructions: Self.dayInstructions)
                    .respond(to: Self.dayTask(kept, shown, json: false, retry: attempt > 0), generating: DayOut.self,
                             options: Self.options).content
                return try Self.reading(out)
            },
            validate: { Self.grounded($0, in: indexes) && validate($0) },
            fallback: fallback)
        return (result.value, provenance(result.rung, result.calls, tokensIn, Self.dayPromptVersion, start))
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

    static func dayTask(_ digests: [EntryDigest], _ candidates: [Candidate], json: Bool, retry: Bool) -> String {
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
        do {
            var n = try await base.tokenCount(for: Instructions(instructions))
            n += try await base.tokenCount(for: prompt)
            if let schema { n += try await base.tokenCount(for: schema) }
            return n
        } catch {
            // ponytail: 3 chars/token is the BRD's conservative knob, used only if tokenCount itself fails.
            return (instructions.count + prompt.count) / 3 + (schema == nil ? 0 : 350)
        }
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

    private func provenance(_ rung: Rung, _ calls: Int, _ tokensIn: Int?, _ promptVersion: String,
                            _ start: ContinuousClock.Instant) -> Provenance {
        Provenance(executor: rung == .heuristic ? "heuristic" : "on_device", rung: rung,
                   guardrails: rung == .permissiveJSON ? "permissive" : rung == .guided ? "default" : nil,
                   variant: variant, osBuild: Self.osBuild, contextSize: contextSize, promptVersion: promptVersion,
                   tokensIn: tokensIn, modelCalls: calls, latencyMs: Int((ContinuousClock.now - start) / .milliseconds(1)))
    }
}
