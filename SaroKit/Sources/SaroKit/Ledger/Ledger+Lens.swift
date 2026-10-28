import Foundation

/// One day as the time lens draws it (useDaySummaries.ts): what was captured, by kind, with a stack or a recording's
/// parts counted once as on the canvas, and the day's key frame. `mood` is filled in from the day's reading, only
/// when the day is ready (so never on a held day).
public struct DaySummary: Sendable, Hashable {
    public let day: String
    public var counts: [EntryKind: Int] = [:]
    public var total = 0
    /// The day's latest moment, else its latest still.
    public var keyMediaId: String?
    public var mood: Mood?

    public init(day: String) { self.day = day }
}

/// One card of a week, for the lens's week replay: when it was captured and, for an entry the gate cleared on a day
/// that isn't held, the mood Saro read in it.
public struct LensEntry: Sendable, Hashable {
    public let day: String
    public let kind: EntryKind
    public let capturedAt: Date
    public let mood: Mood?
}

extension Ledger {
    /// Every day from `from` through `to` that has a live entry, from one GROUP BY (the web runs five range queries).
    public func daySummaries(from: String, to: String) throws -> [DaySummary] {
        var out: [String: DaySummary] = [:]
        for r in try db.run("""
            SELECT e.local_day AS day, e.kind, COUNT(DISTINCT COALESCE(l.stack_id, e.session_id, e.id)) AS n
            FROM live_entry e LEFT JOIN card_layout l ON l.entry_id = e.id
            WHERE e.local_day BETWEEN ? AND ?
            GROUP BY e.local_day, e.kind
            """, [.text(from), .text(to)]) {
            guard let day = r.str("day"), let kind = EntryKind(rawValue: r.str("kind") ?? ""), let n = r.int("n") else { continue }
            out[day, default: DaySummary(day: day)].counts[kind] = n
        }
        // A stack of mixed kinds is one card, though each kind's dot counts it.
        for r in try db.run("""
            SELECT e.local_day AS day, COUNT(DISTINCT COALESCE(l.stack_id, e.session_id, e.id)) AS n
            FROM live_entry e LEFT JOIN card_layout l ON l.entry_id = e.id
            WHERE e.local_day BETWEEN ? AND ?
            GROUP BY e.local_day
            """, [.text(from), .text(to)]) {
            if let day = r.str("day") { out[day]?.total = r.int("n") ?? 0 }
        }
        // The newest picture wins, a moment over a still.
        for r in try db.run("""
            SELECT e.local_day AS day, e.media_id FROM live_entry e JOIN media_asset m ON m.id = e.media_id AND m.state = 'ready'
            WHERE e.kind IN ('moment','still') AND e.local_day BETWEEN ? AND ?
            ORDER BY e.kind = 'moment', e.captured_at
            """, [.text(from), .text(to)]) {
            if let day = r.str("day") { out[day]?.keyMediaId = r.str("media_id") }
        }
        return out.values.sorted { $0.day < $1.day }
    }

    /// The live entries of `from` through `to` in capture order, a stack once at its first capture, with the mood of each
    /// entry cleared for its current text on a day that isn't held.
    public func lensEntries(from: String, to: String) throws -> [LensEntry] {
        let held = try heldDays()
        var seen: Set<String> = []
        return try db.run("""
            SELECT e.id, e.kind, e.local_day, e.captured_at, e.body, e.caption_user, e.title_user, e.summary_user,
              COALESCE(l.stack_id, e.session_id, e.id) AS card,
              v.verdict, v.text_sha256, r.input_hash, a.mood_label
            FROM live_entry e
            LEFT JOIN card_layout l ON l.entry_id = e.id
            LEFT JOIN entry_annotation a ON a.rowid = (SELECT MAX(rowid) FROM entry_annotation WHERE entry_id = e.id)
            LEFT JOIN ai_run r ON r.id = a.ai_run_id
            LEFT JOIN safety_verdict v ON v.rowid = (SELECT MAX(rowid) FROM safety_verdict WHERE entry_id = e.id)
            WHERE e.local_day BETWEEN ? AND ?
            ORDER BY e.captured_at
            """, [.text(from), .text(to)]).compactMap { r in
            guard let card = r.str("card"), seen.insert(card).inserted, let day = r.str("local_day"),
                  let kind = EntryKind(rawValue: r.str("kind") ?? "") else { return nil }
            let mood = Self.cleared(r, kind, held: held) ? r.str("mood_label").flatMap(Mood.init(rawValue:)) : nil
            return LensEntry(day: day, kind: kind, capturedAt: r.date("captured_at") ?? .distantPast, mood: mood)
        }
    }

    /// Saro's text for an entry may show (§13.2): its newest verdict clears its current words with any typed text (SR-01),
    /// its newest reading was made from those words, and its day isn't held. The row carries kind, local_day, body,
    /// caption_user, title_user, summary_user, verdict, text_sha256 and input_hash.
    static func cleared(_ r: Row, _ kind: EntryKind, held: Set<String>) -> Bool {
        let words: String? = switch kind {
        case .reflection, .music: r.str("body") ?? ""
        case .still: r.str("caption_user").flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        case .moment, .voice: nil
        }
        let typed = { (words: String) in
            Pipeline.titled(words, title: r.str("title_user"), caption: r.str("caption_user"), summary: r.str("summary_user"), kind: kind)
        }
        guard let sha = r.str("text_sha256"), ["clear", "unavailable_clear"].contains(r.str("verdict") ?? ""),
              !held.contains(r.str("local_day") ?? "") else { return false }
        // A recording's words (or an uncaptioned still's description) aren't in the row: with nothing typed, its verdict and
        // reading share one hash. ponytail: titled, it shows no Saro text here; join the transcript in if that's ever missed.
        guard let words else { return typed("").isEmpty && r.str("input_hash") == sha }
        return sha256(typed(words)) == sha && r.str("input_hash") == sha256(words)
    }

    /// A media file's key frame, relative to `mediaURL` (Media/<day>/<id>.poster.jpg), once one is made.
    public func poster(mediaId: String) throws -> String? {
        try db.run("SELECT poster_file FROM media_asset WHERE id=?", [.text(mediaId)]).first?.str("poster_file")
    }

    public func setPoster(mediaId: String, file: String) throws {
        try db.run("UPDATE media_asset SET poster_file=?, updated_at=? WHERE id=?", [.text(file), .text(Date.now.iso), .text(mediaId)])
    }
}
