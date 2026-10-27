import Foundation

/// Shared value types between the safety gate, the heuristic twin and SaroAI. Kept in one file so each side
/// can be built and tested on its own.

/// The 12 mood labels (EMOTION_CATALOGUE in `saro/frontend/lib/demo/ai.ts`).
public enum Mood: String, Sendable, Codable, CaseIterable {
    case calm = "Calm", reflective = "Reflective", grateful = "Grateful", frustrated = "Frustrated", tender = "Tender",
         anxious = "Anxious", energised = "Energised", neutral = "Neutral", bittersweet = "Bittersweet",
         surprised = "Surprised", overwhelmed = "Overwhelmed", inspired = "Inspired"

    public var summary: String {
        switch self {
        case .calm: "Settled and present, without the noise."
        case .reflective: "Turning inward, sitting with what matters."
        case .grateful: "Noticing the good, small as it may be."
        case .frustrated: "Something resisted you today, and you felt it."
        case .tender: "Soft and a little raw at the edges."
        case .anxious: "The mind running faster than the moment."
        case .energised: "Something lit you up and you're still running on it."
        case .neutral: "Moving through the day without a strong pull."
        case .bittersweet: "Happy and a little sad at the same time."
        case .surprised: "The day handed you something unexpected."
        case .overwhelmed: "Too many things pulling at once."
        case .inspired: "Ideas or feelings arriving with unexpected clarity."
        }
    }
}

/// A verbatim phrase built by code from an entry; models refer to it by `index` and never copy text (§11.6).
public struct Candidate: Sendable, Hashable, Codable {
    public let index: Int
    public let entryId: String
    public let field: String
    public let text: String
    public let utf16From: Int
    public let utf16To: Int

    public init(index: Int, entryId: String, field: String, text: String, utf16From: Int, utf16To: Int) {
        self.index = index
        self.entryId = entryId
        self.field = field
        self.text = text
        self.utf16From = utf16From
        self.utf16To = utf16To
    }
}

/// Per-entry reading: title, summary, mood and one quote by candidate index.
public struct EntryReading: Sendable, Hashable, Codable {
    public var title: String
    public var summary: String
    public var mood: Mood
    public var moodBasis: String?
    public var quoteIndex: Int?

    public init(title: String, summary: String, mood: Mood, moodBasis: String? = nil, quoteIndex: Int? = nil) {
        self.title = title
        self.summary = summary
        self.mood = mood
        self.moodBasis = moodBasis
        self.quoteIndex = quoteIndex
    }
}

/// One entry as the day reading sees it: its stored annotation, never raw history.
public struct EntryDigest: Sendable, Hashable, Codable {
    public var entryId: String
    public var kind: String
    public var time: String
    public var title: String
    public var summary: String
    public var mood: Mood?

    public init(entryId: String, kind: String, time: String, title: String, summary: String, mood: Mood?) {
        self.entryId = entryId
        self.kind = kind
        self.time = time
        self.title = title
        self.summary = summary
        self.mood = mood
    }
}

/// The day reading behind "What Saro noticed" and the evening letter.
public struct DayReading: Sendable, Hashable, Codable {
    public var mood: Mood
    public var moodBasis: String?
    /// 1-3 candidate indexes.
    public var quoteIndexes: [Int]
    public var question: String?
    /// 1-2 sentences, or nil when it failed grounding (a template is shown instead).
    public var narrative: String?

    public init(mood: Mood, moodBasis: String? = nil, quoteIndexes: [Int], question: String? = nil, narrative: String? = nil) {
        self.mood = mood
        self.moodBasis = moodBasis
        self.quoteIndexes = quoteIndexes
        self.question = question
        self.narrative = narrative
    }
}

/// Layer-2 classifier labels (SR-07).
public enum ClassifierLabel: String, Sendable, Codable {
    case none = "NONE", passive = "PASSIVE", active = "ACTIVE"
}

/// Anything but `.label(.none)` keeps an entry from being cleared; `.unavailable` means layer 2 couldn't run.
public enum ClassifierOutcome: Sendable, Hashable {
    case label(ClassifierLabel)
    /// Refusal, guardrail, unparseable reply or timeout: an uncertain result, so a safety hold (SR-02).
    case uncertain(reason: String)
    /// deviceNotEligible, appleIntelligenceNotEnabled, modelNotReady, unsupported locale.
    case unavailable(reason: String)
}

/// Where a ladder result came from (§11.3).
public enum Rung: String, Sendable, Codable {
    case permissiveJSON = "permissive_json"
    case guided = "guided"
    case heuristic = "heuristic"
}

/// Provenance recorded on every AI artifact (§11.8). Content-free.
public struct Provenance: Sendable, Hashable, Codable {
    public var executor: String
    public var rung: Rung
    public var guardrails: String?
    public var variant: String?
    public var osBuild: String
    public var contextSize: Int?
    public var promptVersion: String
    public var tokensIn: Int?
    public var modelCalls: Int
    public var latencyMs: Int

    public init(executor: String, rung: Rung, guardrails: String?, variant: String?, osBuild: String, contextSize: Int?,
                promptVersion: String, tokensIn: Int?, modelCalls: Int, latencyMs: Int) {
        self.executor = executor
        self.rung = rung
        self.guardrails = guardrails
        self.variant = variant
        self.osBuild = osBuild
        self.contextSize = contextSize
        self.promptVersion = promptVersion
        self.tokensIn = tokensIn
        self.modelCalls = modelCalls
        self.latencyMs = latencyMs
    }
}
