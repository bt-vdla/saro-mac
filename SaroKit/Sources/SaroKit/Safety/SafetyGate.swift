import Foundation

/// The one entry state (§13.2), derived from a stored `SafetyVerdictRow.verdict`.
public enum EntryState: Sendable, Hashable {
    case clear, technicalHold, safetyHold, modelUnavailable, awaitingCheck

    /// No verdict yet is awaiting a check; an unknown verdict string is unclear, so a safety hold.
    public init(verdict: String?) {
        switch verdict {
        case nil, "unavailable_caution": self = .awaitingCheck
        case "clear": self = .clear
        case "technical_hold": self = .technicalHold
        case "unavailable_clear": self = .modelUnavailable
        default: self = .safetyHold
        }
    }
}

/// What a whole local day may get (SR-13, SR-14).
public enum DayGate: Sendable, Hashable {
    case allowed, safetyHeld, awaitingCheck
}

/// One gate decision. Content-free: safe to store and log (SR-33).
public struct GateResult: Sendable, Hashable {
    /// `clear`, `technical_hold`, `safety_hold`, `unavailable_clear` or `unavailable_caution`.
    public let verdict: String
    public let layer: Int
    /// `phrase_hit`, `classifier_active`, `classifier_passive`, `classifier_uncertain`, `low_confidence`, `caution_hit`,
    /// `model_unavailable` or `clear`.
    public let reasonCode: String
    public var state: EntryState { EntryState(verdict: verdict) }

    public init(verdict: String, layer: Int, reasonCode: String) {
        self.verdict = verdict
        self.layer = layer
        self.reasonCode = reasonCode
    }
}

/// SR-01: every path's text passes this gate before any model or heuristic reads it.
public actor SafetyGate {
    /// SAFETY_VERSION (SR-18). Bump on any change to patterns, lexicon, prompt or rules.
    public static let version = "safety-1"
    /// Layer 0 floor on mean transcription confidence. // calibration knob: Spike A sets it from Bharat's 10 recordings.
    public static let confidenceFloor = 0.35
    /// About 3,000 tokens at 4.1 characters per token (§11.5).
    public static let chunkLimit = 12_000

    private let classify: (@Sendable (String) async -> ClassifierOutcome)?
    private let timeout: Duration

    /// `classify` is layer 2: it gets one chunk of entry text, sends `classifierPrompt(for:)` under `classifierInstructions`
    /// and returns `parseLabel` of the reply. nil means the model is unavailable. A call outliving `timeout` is uncertain (SR-02).
    public init(classify: (@Sendable (String) async -> ClassifierOutcome)?, timeout: Duration = .seconds(10)) {
        self.classify = classify
        self.timeout = timeout
    }

    /// Layers 0-2 in §13.2 order: safety hold > model unavailable > technical hold > clear.
    /// `transcriptConfidence` is nil for typed text.
    public func gate(text: String, transcriptConfidence: Double?) async -> GateResult {
        if Self.phraseHit(text) { return GateResult(verdict: "safety_hold", layer: 1, reasonCode: "phrase_hit") }
        switch await classifyChunks(text) {
        case .label(.active): return GateResult(verdict: "safety_hold", layer: 2, reasonCode: "classifier_active")
        case .label(.passive): return GateResult(verdict: "safety_hold", layer: 2, reasonCode: "classifier_passive")
        case .uncertain: return GateResult(verdict: "safety_hold", layer: 2, reasonCode: "classifier_uncertain")
        case .unavailable:
            return Self.cautionHit(text)
                ? GateResult(verdict: "unavailable_caution", layer: 1, reasonCode: "caution_hit")
                : GateResult(verdict: "unavailable_clear", layer: 1, reasonCode: "model_unavailable")
        case .label(.none):
            if let c = transcriptConfidence, c < Self.confidenceFloor {
                return GateResult(verdict: "technical_hold", layer: 0, reasonCode: "low_confidence")
            }
            return GateResult(verdict: "clear", layer: 2, reasonCode: "clear")
        }
    }

    /// Layer 3 (SR-08): the phrase gate over generated text. A hit suppresses the output and holds the entry.
    public nonisolated func outputGateHit(_ generated: String) -> Bool { Self.phraseHit(generated) }

    /// SR-13, SR-14: a safety hold anywhere holds the whole day; an entry awaiting a check holds the reading and letter.
    /// Technical holds are simply left out of the reading.
    public static func dayGate(_ states: [EntryState]) -> DayGate {
        if states.contains(.safetyHold) { return .safetyHeld }
        if states.contains(.awaitingCheck) { return .awaitingCheck }
        return .allowed
    }

    private func classifyChunks(_ text: String) async -> ClassifierOutcome {
        guard let classify else { return .unavailable(reason: "no_model") }
        if text.allSatisfy(\.isWhitespace) { return .label(.none) }
        for chunk in Self.chunks(text) {
            let outcome = await withTaskGroup(of: ClassifierOutcome.self) { [timeout] group in
                group.addTask { await classify(chunk) }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return .uncertain(reason: "timeout")
                }
                // ponytail: relies on `classify` honouring cancellation, as FoundationModels calls do.
                let first = await group.next() ?? .uncertain(reason: "timeout")
                group.cancelAll()
                return Task.isCancelled ? .uncertain(reason: "cancelled") : first
            }
            if outcome != .label(.none) { return outcome }
        }
        return .label(.none)
    }

    /// Splits at sentence boundaries into pieces of at most `chunkLimit` characters.
    static func chunks(_ text: String) -> [String] {
        guard text.count > chunkLimit else { return [text] }
        var out: [String] = []
        var current = ""
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, enclosing, _ in
            guard sentence != nil else { return }
            let s = text[enclosing]
            if count + s.count > chunkLimit, !current.isEmpty {
                out.append(current)
                current = ""
                count = 0
            }
            current += s
            count += s.count
        }
        if !current.isEmpty { out.append(current) }
        // ponytail: an unpunctuated run longer than the limit is cut by length; the phrase gate still saw it whole.
        return out.flatMap { piece -> [String] in
            let chars = Array(piece)
            return stride(from: 0, to: chars.count, by: chunkLimit).map { String(chars[$0..<min($0 + chunkLimit, chars.count)]) }
        }
    }
}
