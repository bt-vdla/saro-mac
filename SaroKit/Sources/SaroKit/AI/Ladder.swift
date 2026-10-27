import Foundation
import FoundationModels

/// The model-free half of SaroAI: rung walking, reply parsing and input trimming (§11.3, §11.5).
enum Ladder {
    /// Permissive JSON (two tries), then guided (two tries), then the caller's fallback. A guardrail or refusal on
    /// any rung goes straight to the fallback and is never re-asked (SR-09). `attempt` is 0 or 1; 1 means "add the
    /// correction line". At most 4 calls (SR-10).
    static func walk<T: Sendable>(
        permissive: @Sendable (Int) async throws -> String,
        decode: @Sendable (String) throws -> T,
        guided: @Sendable (Int) async throws -> T,
        validate: @Sendable (T) -> Bool,
        fallback: T
    ) async -> (value: T, rung: Rung, calls: Int) {
        var calls = 0
        for attempt in 0..<2 {
            calls += 1
            do {
                let raw = try await permissive(attempt)
                if let value = try? decode(raw), validate(value) { return (value, .permissiveJSON, calls) }
            } catch let error where isStop(error) {
                return (fallback, .heuristic, calls)
            } catch {}
        }
        for attempt in 0..<2 {
            calls += 1
            do {
                let value = try await guided(attempt)
                if validate(value) { return (value, .guided, calls) }
            } catch let error where isStop(error) {
                return (fallback, .heuristic, calls)
            } catch {}
        }
        return (fallback, .heuristic, calls)
    }

    /// Errors where another call can't help or must not happen: guardrail and refusal (SR-09), an over-long input
    /// (never retried, §11.5), an unsupported language, missing assets.
    static func isStop(_ error: any Error) -> Bool {
        if error is SystemLanguageModel.Error { return true }
        guard let error = error as? LanguageModelError else { return false }
        switch error {
        case .guardrailViolation, .refusal, .contextSizeExceeded, .unsupportedLanguageOrLocale: return true
        default: return false
        }
    }

    static func reason(_ error: any Error) -> String {
        if error is SystemLanguageModel.Error { return "assetsUnavailable" }
        guard let error = error as? LanguageModelError else { return "error" }
        switch error {
        case .guardrailViolation: return "guardrail"
        case .refusal: return "refusal"
        case .contextSizeExceeded: return "too_long"
        case .unsupportedLanguageOrLocale: return "unsupportedLanguageOrLocale"
        case .timeout: return "timeout"
        case .rateLimited: return "rate_limited"
        default: return "error"
        }
    }

    /// The JSON object inside a reply: drops ``` fences and any prose around the outermost braces.
    static func jsonObject(in raw: String) -> String? {
        guard let open = raw.firstIndex(of: "{"), let close = raw.lastIndex(of: "}"), open < close else { return nil }
        return String(raw[open...close])
    }

    static func decode<T: Generable>(_ type: T.Type, from raw: String) throws -> T {
        guard let json = jsonObject(in: raw) else { throw GeneratedContent.ParsingError(rawContent: raw, debugDescription: "no JSON object") }
        return try T(GeneratedContent(json: json))
    }

    struct UnknownMood: Error {}

    static func mood(_ label: String) throws -> Mood {
        let key = label.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
            .replacingOccurrences(of: "energized", with: "energised")
        guard let mood = Mood.allCases.first(where: { $0.rawValue.lowercased() == key }) else { throw UnknownMood() }
        return mood
    }

    /// First classifier label among the reply's first three words; anything else is uncertain.
    // ponytail: three words, so a chatty refusal that later says "none" can't clear an entry.
    static func label(_ reply: String) -> ClassifierOutcome {
        for word in reply.uppercased().split(whereSeparator: { !$0.isLetter }).prefix(3) {
            if let label = ClassifierLabel(rawValue: String(word)) { return .label(label) }
        }
        return .uncertain(reason: "unparsed")
    }

    /// Cuts to `maxChars`, ending on a sentence boundary when that keeps at least half, else on a word boundary.
    static func truncated(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let head = text.prefix(max(0, maxChars))
        let half = head.index(head.startIndex, offsetBy: head.count / 2)
        if let end = head.lastIndex(where: { ".!?\n".contains($0) }), end >= half {
            return String(head[...end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let space = head.lastIndex(where: \.isWhitespace), space >= half { return String(head[..<space]) }
        return String(head)
    }

    static func numbered(_ candidates: [Candidate]) -> String {
        candidates.map { "[\($0.index)] \"\($0.text)\"" }.joined(separator: "\n")
    }
}
