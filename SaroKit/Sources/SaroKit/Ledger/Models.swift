import CryptoKit
import Foundation

public enum EntryKind: String, Sendable, Codable, CaseIterable {
    case moment, voice, reflection, still, music
}

public struct Entry: Sendable, Identifiable, Hashable, Codable {
    public var id: String
    public var kind: EntryKind
    public var sessionId: String?
    public var turnNumber: Int?
    public var titleUser: String?
    public var captionUser: String?
    public var body: String?
    public var capturedAt: Date
    public var tzId: String
    public var localDay: String
    public var backdated: Bool
    public var mediaId: String?
    public var processingStatus: String
    public var trashedAt: Date?
    public var trashBatchId: String?

    public init(id: String = UUID().uuidString, kind: EntryKind, sessionId: String? = nil, turnNumber: Int? = nil,
                titleUser: String? = nil, captionUser: String? = nil, body: String? = nil, capturedAt: Date = .now,
                timeZone: TimeZone = .current, localDay: String? = nil, mediaId: String? = nil,
                processingStatus: String = ProcessingStatus.pending) {
        self.id = id
        self.kind = kind
        self.sessionId = sessionId
        self.turnNumber = turnNumber
        self.titleUser = titleUser
        self.captionUser = captionUser
        self.body = body
        self.capturedAt = capturedAt
        self.tzId = timeZone.identifier
        let today = LocalDay.string(for: capturedAt, in: timeZone)
        self.localDay = localDay ?? today
        self.backdated = (localDay ?? today) != today
        self.mediaId = mediaId
        self.processingStatus = processingStatus
    }

    init(row: Row) {
        id = row.str("id") ?? ""
        kind = EntryKind(rawValue: row.str("kind") ?? "") ?? .reflection
        sessionId = row.str("session_id")
        turnNumber = row.int("turn_number")
        titleUser = row.str("title_user")
        captionUser = row.str("caption_user")
        body = row.str("body")
        capturedAt = row.date("captured_at") ?? .distantPast
        tzId = row.str("tz_id") ?? TimeZone.current.identifier
        localDay = row.str("local_day") ?? ""
        backdated = row.int("backdated") == 1
        mediaId = row.str("media_id")
        processingStatus = row.str("processing_status") ?? ProcessingStatus.pending
        trashedAt = row.date("trashed_at")
        trashBatchId = row.str("trash_batch_id")
    }
}

public enum ProcessingStatus {
    public static let recording = "recording"
    public static let pending = "pending"
    public static let transcribing = "transcribing"
    public static let transcriptUnavailable = "transcript_unavailable"
    public static let gating = "gating"
    public static let reading = "reading"
    public static let done = "done"
    public static let failed = "failed"
}

public enum MediaKind: String, Sendable, Codable { case video, audio, image }

public struct MediaAsset: Sendable, Identifiable, Hashable, Codable {
    public var id: String
    /// Relative to `Ledger.mediaURL`.
    public var fileName: String
    public var kind: MediaKind
    public var origin: String
    public var state: String
    public var durationMs: Int?
    public var bytes: Int?

    public init(id: String = UUID().uuidString, fileName: String, kind: MediaKind, origin: String,
                state: String = "recording", durationMs: Int? = nil, bytes: Int? = nil) {
        self.id = id
        self.fileName = fileName
        self.kind = kind
        self.origin = origin
        self.state = state
        self.durationMs = durationMs
        self.bytes = bytes
    }

    init(row: Row) {
        id = row.str("id") ?? ""
        fileName = row.str("file_name") ?? ""
        kind = MediaKind(rawValue: row.str("kind") ?? "") ?? .video
        origin = row.str("origin") ?? ""
        state = row.str("state") ?? "missing"
        durationMs = row.int("duration_ms")
        bytes = row.int("bytes")
    }
}

public struct TranscriptWord: Sendable, Hashable, Codable {
    public var text: String
    public var startMs: Int
    public var durMs: Int
    public var confidence: Double?

    public init(text: String, startMs: Int, durMs: Int, confidence: Double?) {
        self.text = text
        self.startMs = startMs
        self.durMs = durMs
        self.confidence = confidence
    }
}

public struct CardLayout: Sendable, Hashable, Codable {
    public var entryId: String
    public var x: Double
    public var y: Double
    public var z: Int
    public var stackId: String?
    public var userPlaced: Bool
    /// Set by resizing; nil is the type's default (a nil height follows the width where the card keeps proportions).
    public var w: Double?
    public var h: Double?

    public init(entryId: String, x: Double, y: Double, z: Int = 0, stackId: String? = nil, userPlaced: Bool = false,
                w: Double? = nil, h: Double? = nil) {
        self.entryId = entryId
        self.x = x
        self.y = y
        self.z = z
        self.stackId = stackId
        self.userPlaced = userPlaced
        self.w = w
        self.h = h
    }
}

/// Content-free provenance of one model or heuristic run (§11.8).
public struct AIRun: Sendable, Hashable, Codable {
    public var id = UUID().uuidString
    public var feature: String
    public var executor: String
    public var guardrails: String?
    public var ladderRung: String?
    public var osBuild: String?
    public var variant: String?
    public var modelFingerprint: String?
    public var contextSize: Int?
    public var sampling: String?
    public var promptVersion: String?
    public var schemaVersion: String?
    public var extractorVersion: String?
    public var inputHash: String?
    public var tokensIn: Int?
    public var tokensOut: Int?
    public var modelCalls: Int?
    public var latencyMs: Int?
    public var status: String
    public var localDay: String?
    public var createdAt = Date.now

    public init(feature: String, executor: String, status: String) {
        self.feature = feature
        self.executor = executor
        self.status = status
    }
}

public struct AIRunInput: Sendable, Hashable, Codable {
    public var entryId: String
    public var field: String
    public var utf16From: Int
    public var utf16To: Int
    public var textSha256: String

    public init(entryId: String, field: String, text: String) {
        self.entryId = entryId
        self.field = field
        utf16From = 0
        utf16To = text.utf16.count
        textSha256 = sha256(text)
    }
}

public struct EntryAnnotation: Sendable, Hashable, Codable {
    public var id = UUID().uuidString
    public var entryId: String
    public var aiRunId: String
    /// `on_device`, `heuristic`, …; heuristic output is labelled "In your words".
    public var generator: String
    public var title: String?
    public var summary: String?
    public var caption: String?
    public var moodLabel: String?
    public var moodBasis: String?
    public var quote: String?
    public var quoteField: String?
    public var quoteFrom: Int?
    public var quoteTo: Int?
    public var createdAt = Date.now

    public init(entryId: String, aiRunId: String, generator: String) {
        self.entryId = entryId
        self.aiRunId = aiRunId
        self.generator = generator
    }

    init(row: Row) {
        id = row.str("id") ?? ""
        entryId = row.str("entry_id") ?? ""
        aiRunId = row.str("ai_run_id") ?? ""
        generator = row.str("generator") ?? ""
        title = row.str("title")
        summary = row.str("summary")
        caption = row.str("caption")
        moodLabel = row.str("mood_label")
        moodBasis = row.str("mood_basis")
        quote = row.str("quote")
        quoteField = row.str("quote_field")
        quoteFrom = row.int("quote_from")
        quoteTo = row.int("quote_to")
        createdAt = row.date("created_at") ?? .distantPast
    }
}

/// One content-free gate result (SR-33). `verdict` is one of `clear`, `technical_hold`, `safety_hold`,
/// `unavailable_clear`, `unavailable_caution`.
public struct SafetyVerdictRow: Sendable, Hashable, Codable {
    public var id = UUID().uuidString
    public var entryId: String
    public var textSha256: String
    public var safetyVersion: String
    public var layer: Int
    public var verdict: String
    public var reasonCode: String
    public var createdAt = Date.now

    public init(entryId: String, textSha256: String, safetyVersion: String, layer: Int, verdict: String, reasonCode: String) {
        self.entryId = entryId
        self.textSha256 = textSha256
        self.safetyVersion = safetyVersion
        self.layer = layer
        self.verdict = verdict
        self.reasonCode = reasonCode
    }

    init(row: Row) {
        id = row.str("id") ?? ""
        entryId = row.str("entry_id") ?? ""
        textSha256 = row.str("text_sha256") ?? ""
        safetyVersion = row.str("safety_version") ?? ""
        layer = row.int("layer") ?? 0
        verdict = row.str("verdict") ?? "safety_hold"
        reasonCode = row.str("reason_code") ?? ""
        createdAt = row.date("created_at") ?? .distantPast
    }
}

public struct InsightSnapshot: Sendable, Hashable, Codable {
    public var id = UUID().uuidString
    public var kind: String
    public var fromDay: String
    public var toDay: String
    public var aiRunId: String?
    public var generator: String
    public var inputHash: String?
    /// JSON.
    public var payload: String
    public var createdAt = Date.now

    public init(kind: String, day: String, aiRunId: String?, generator: String, inputHash: String?, payload: String) {
        self.kind = kind
        fromDay = day
        toDay = day
        self.aiRunId = aiRunId
        self.generator = generator
        self.inputHash = inputHash
        self.payload = payload
    }

    init(row: Row) {
        id = row.str("id") ?? ""
        kind = row.str("kind") ?? ""
        fromDay = row.str("from_day") ?? ""
        toDay = row.str("to_day") ?? ""
        aiRunId = row.str("ai_run_id")
        generator = row.str("generator") ?? ""
        inputHash = row.str("input_hash")
        payload = row.str("payload") ?? "{}"
        createdAt = row.date("created_at") ?? .distantPast
    }
}

public struct DecisionEvent: Sendable, Hashable, Codable {
    public var id = UUID().uuidString
    public var decisionId: String
    public var choice: String?
    public var note: String?
    public var screenId: String?
    public var appVersion: String
    public var createdAt = Date.now

    public init(decisionId: String, choice: String?, note: String?, screenId: String?, appVersion: String) {
        self.decisionId = decisionId
        self.choice = choice
        self.note = note
        self.screenId = screenId
        self.appVersion = appVersion
    }

    init(row: Row) {
        id = row.str("id") ?? ""
        decisionId = row.str("decision_id") ?? ""
        choice = row.str("choice")
        note = row.str("note")
        screenId = row.str("screen_id")
        appVersion = row.str("app_version") ?? ""
        createdAt = row.date("created_at") ?? .distantPast
    }
}

public struct ScreenNote: Sendable, Hashable, Codable {
    public var id = UUID().uuidString
    public var screenId: String
    public var note: String
    public var appVersion: String
    public var createdAt = Date.now

    public init(screenId: String, note: String, appVersion: String) {
        self.screenId = screenId
        self.note = note
        self.appVersion = appVersion
    }

    init(row: Row) {
        id = row.str("id") ?? ""
        screenId = row.str("screen_id") ?? ""
        note = row.str("note") ?? ""
        appVersion = row.str("app_version") ?? ""
        createdAt = row.date("created_at") ?? .distantPast
    }
}

public enum LocalDay {
    /// `YYYY-MM-DD` in the given time zone (DR-10: frozen at capture).
    public static func string(for date: Date, in tz: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func today() -> String { string(for: .now) }

    /// Noon on that day, in the current time zone.
    public static func date(_ day: String) -> Date? {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }

    public static func adding(_ days: Int, to day: String) -> String {
        guard let d = date(day), let n = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: d) else { return day }
        return string(for: n)
    }
}

public func sha256(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

extension Date {
    static let isoStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    var iso: String { formatted(Self.isoStyle) }
    init?(iso: String) {
        guard let d = (try? Self.isoStyle.parse(iso)) ?? (try? Date(iso, strategy: .iso8601)) else { return nil }
        self = d
    }
}
