import Foundation

/// How Saro talks (focus-data.ts). The tone's preview line is also the first recording prompt, so the tone picked is
/// the voice heard first.
public enum Tone: String, Sendable, Codable, CaseIterable {
    case gentle, neutral, direct, contemplative

    public var label: String { rawValue.capitalized }

    public func previewLine(name: String?) -> String {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let named = !name.isEmpty
        return switch self {
        case .gentle: named ? "\(name), what moment still lingers?" : "What moment still lingers?"
        case .neutral: named ? "\(name), which moment from today stands out?" : "Which moment from today stands out?"
        case .direct: named ? "\(name). One second you’d keep from today. Go." : "One second you’d keep from today. Go."
        case .contemplative: named ? "\(name), which moment felt still inside?" : "Which moment felt still inside?"
        }
    }
}

/// What the lens is aimed at (focus-data.ts focusOptions and focusIcons, as SF Symbols).
public enum FocusArea: String, Sendable, Codable, CaseIterable {
    case clarity, steadiness, creative, relationships, habits, confidence, energy, purpose

    public var label: String {
        switch self {
        case .clarity: "Clarity for decisions"
        case .steadiness: "Emotional steadiness"
        case .creative: "Creative momentum"
        case .relationships: "Relationships"
        case .habits: "Habits / consistency"
        case .confidence: "Confidence / agency"
        case .energy: "Energy / health"
        case .purpose: "Purpose / direction"
        }
    }

    public var symbol: String {
        switch self {
        case .clarity: "scope"
        case .steadiness: "waveform.path.ecg"
        case .creative: "bolt"
        case .relationships: "heart"
        case .habits: "repeat"
        case .confidence: "shield"
        case .energy: "sun.max"
        case .purpose: "location.north"
        }
    }
}

/// The one local profile row (BRD §14.2). No email or avatar: those were account fields.
public struct Profile: Sendable, Hashable, Codable {
    public var name: String?
    /// What Saro calls you.
    public var called: String?
    public var tone: Tone = .neutral
    public var focusAreas: [FocusArea] = []
    public var memoryPaused = false
    public var onboardingDoneAt: Date?
    public var createdAt = Date.now
    public var updatedAt = Date.now

    public init(name: String? = nil, called: String? = nil, tone: Tone = .neutral) {
        self.name = name
        self.called = called
        self.tone = tone
    }

    /// The name a line addresses: what Saro calls you, else your first name (VideoReflectionScreen.tsx promptFor).
    public var address: String? {
        let called = called?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !called.isEmpty { return called }
        return name?.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }
}

/// A span Saro picked up from an About you answer. `text` is the answer's exact substring at UTF-16 [start, end).
public struct Pick: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Codable { case name, person, theme, time, goal, tone }

    public var kind: Kind
    public var text: String
    /// The normalised meaning: a name, a theme id or mood label, "HH:MM", a tone key, or the text itself.
    public var value: String
    public var start: Int
    public var end: Int
    /// The question it answers, 1 to 5.
    public var q: Int

    public init(kind: Kind, text: String, value: String, start: Int, end: Int, q: Int) {
        self.kind = kind
        self.text = text
        self.value = value
        self.start = start
        self.end = end
        self.q = q
    }

    /// The key a pick the person left out is remembered by (extract.ts dropKey).
    public var dropKey: String { "\(kind.rawValue)|\(text.lowercased())" }
}

/// What the person told Saro in About you, one row per onboarding pass; the newest pass is current.
public struct StarterContext: Sendable, Hashable, Codable, Identifiable {
    public enum Source: String, Sendable, Codable { case local, ai }

    public var id = UUID().uuidString
    /// The onboarding pass this row belongs to (Ledger.newStarterVersion).
    public var version: Int
    public var answers: [Int: String] = [:]
    public var picks: [Pick] = []
    /// `dropKey`s of picks the person left out.
    public var dropped: Set<String> = []
    /// Questions whose answer the SafetyGate held. Question numbers only, so the set is content-free.
    public var held: Set<Int> = []
    /// "HH:MM", the most specific time they mentioned.
    public var reflectTime: String?
    public var firstPrompt: String?
    public var source: Source = .local
    public var createdAt = Date.now
    public var updatedAt = Date.now

    public init(version: Int) { self.version = version }

    /// What may be stored (SR-13): nothing derived from a held answer, nor a pick the person left out. A held answer
    /// also means About you shows the SafetyCard instead of a personal prompt, so no first prompt is kept.
    public var storable: StarterContext {
        var s = self
        s.picks.removeAll { s.held.contains($0.q) || s.dropped.contains($0.dropKey) }
        if !s.held.isEmpty { s.firstPrompt = nil }
        if let t = s.reflectTime, !s.picks.contains(where: { $0.kind == .time && $0.value == t }) { s.reflectTime = nil }
        return s
    }
}

/// A question Saro asked and, once given, the answer. The answer updates the question's row and always carries the
/// gate's verdict on it.
public struct ReflectionTurn: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        case prompt
        case dailyQuestion = "daily_question"
        case reflectDeeper = "reflect_deeper"
        case reflectFurther = "reflect_further"
    }

    public var id = UUID().uuidString
    public var kind: Kind
    public var entryId: String?
    public var sessionId: String?
    public var turnNumber: Int?
    public var question: String
    public var answer: String?
    /// A safety_verdict value; set whenever `answer` is.
    public var answerVerdict: String?
    /// `on_device`, `heuristic`, `curated`, …
    public var generator: String
    public var aiRunId: String?
    public var localDay: String
    public var archivedAt: Date?
    public var createdAt = Date.now
    public var updatedAt = Date.now

    public init(kind: Kind, question: String, generator: String, localDay: String = LocalDay.today(), entryId: String? = nil,
                sessionId: String? = nil, turnNumber: Int? = nil, aiRunId: String? = nil) {
        self.kind = kind
        self.question = question
        self.generator = generator
        self.localDay = localDay
        self.entryId = entryId
        self.sessionId = sessionId
        self.turnNumber = turnNumber
        self.aiRunId = aiRunId
    }
}

/// A window in which memory was paused; `to` is nil while it still is. Nothing written inside one is ever learned.
public struct MemoryPause: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var from: Date
    public var to: Date?

    public func contains(_ date: Date) -> Bool { date >= from && to.map { date < $0 } ?? true }
}
