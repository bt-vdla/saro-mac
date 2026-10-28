import Foundation

/// A day's own record (BRD §14.2): the mood the person set for it, which no re-read overwrites, and whether its letter
/// was opened or kept.
public struct DayState: Sendable, Hashable {
    public var day: String
    public var moodUser: Mood?
    public var moodLocked = false
    public var moodNote: String?
    /// The gate's verdict on `moodNote`; a safety hold holds the whole day.
    public var moodNoteVerdict: String?
    public var letterOpenedAt: Date?
    public var keptSnapshotId: String?

    public init(day: String) { self.day = day }

    /// The person's mood for the day, when they set one.
    public var lockedMood: Mood? { moodLocked ? moodUser : nil }
}

/// Something the person said they'd do (FR-REF-12). Their own words: never sent to a model.
public struct Commitment: Sendable, Hashable, Identifiable {
    public static let maxCount = 20
    public static let maxChars = 280

    public var id = UUID().uuidString
    public var text: String
    public var forDay: String
    public var completedAt: Date?
    public var letGoOnDay: String?
    public var carriedFromId: String?
    public var sourceEntryId: String?
    public var createdAt = Date.now

    public var done: Bool { completedAt != nil }

    public init(text: String, forDay: String) {
        self.text = text
        self.forDay = forDay
    }

    /// Cut to what the column holds (280 characters, as SQLite counts them), never inside a character.
    public static func clipped(_ text: String) -> String {
        var scalars = 0
        return String(text.prefix { c in
            scalars += c.unicodeScalars.count
            return scalars <= maxChars
        })
    }

    /// The same commitment, compared at the stored length (DailyInsightBar sameText).
    public static func sameText(_ a: String, _ b: String) -> Bool {
        let key = { (s: String) in clipped(s).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return key(a) == key(b)
    }

    /// Yesterday's open commitments still to ask about: none already on today's list by the same words.
    public static func pending(_ open: [Commitment], today: [Commitment]) -> [Commitment] {
        open.filter { o in !today.contains { sameText($0.text, o.text) } }
    }
}

extension Ledger {
    // MARK: Day state

    public func dayState(_ day: String) throws -> DayState {
        var s = DayState(day: day)
        guard let r = try db.run("SELECT * FROM day_state WHERE local_day=?", [.text(day)]).first else { return s }
        s.moodUser = r.str("mood_label_user").flatMap(Mood.init(rawValue:))
        s.moodLocked = r.int("mood_locked") == 1
        s.moodNote = r.str("mood_note")
        s.moodNoteVerdict = r.str("mood_note_verdict")
        s.letterOpenedAt = r.date("letter_opened_at")
        s.keptSnapshotId = r.str("letter_kept_snapshot_id")
        return s
    }

    /// The person's own mood for the day, locked so no re-read replaces it, with their note and the gate's verdict on it.
    /// A safety hold on the note drops the day's readings and letters, as an entry's hold does (SR-13, SR-15).
    public func setUserMood(day: String, label: Mood, note: String?, verdict: String?) throws {
        try db.transaction {
            try db.run("""
                INSERT INTO day_state (local_day, mood_label_user, mood_source, mood_locked, mood_note, mood_note_verdict, updated_at)
                VALUES (?,?,'user',1,?,?,?)
                ON CONFLICT(local_day) DO UPDATE SET mood_label_user=excluded.mood_label_user, mood_source='user', mood_locked=1,
                  mood_note=excluded.mood_note, mood_note_verdict=excluded.mood_note_verdict, updated_at=excluded.updated_at
                """, [.text(day), .text(label.rawValue), note.sql, verdict.sql, .text(Date.now.iso)])
            if verdict == "safety_hold" { try dropDayReadings(day) }
        }
    }

    /// Opening the letter marks it read; the first time is kept.
    public func markLetterOpened(day: String) throws {
        try db.run("""
            INSERT INTO day_state (local_day, letter_opened_at, updated_at) VALUES (?,?,?)
            ON CONFLICT(local_day) DO UPDATE SET letter_opened_at=COALESCE(letter_opened_at, excluded.letter_opened_at),
              updated_at=excluded.updated_at
            """, [.text(day), .text(Date.now.iso), .text(Date.now.iso)])
    }

    /// Stores the letter as it reads now (a 'letter' snapshot) and keeps it with the day, read.
    public func keepLetter(day: String, snapshot: InsightSnapshot) throws {
        try db.transaction {
            try insertSnapshot(snapshot)
            let now = Date.now.iso
            try db.run("""
                INSERT INTO day_state (local_day, letter_opened_at, letter_kept_snapshot_id, updated_at) VALUES (?,?,?,?)
                ON CONFLICT(local_day) DO UPDATE SET letter_kept_snapshot_id=excluded.letter_kept_snapshot_id,
                  letter_opened_at=COALESCE(letter_opened_at, excluded.letter_opened_at), updated_at=excluded.updated_at
                """, [.text(day), .text(now), .text(snapshot.id), .text(now)])
        }
    }

    public func clearKept(day: String) throws {
        try db.run("UPDATE day_state SET letter_kept_snapshot_id=NULL, updated_at=? WHERE local_day=?", [.text(Date.now.iso), .text(day)])
    }

    public func keptLetter(day: String) throws -> InsightSnapshot? {
        try db.run("SELECT s.* FROM insight_snapshot s JOIN day_state d ON d.letter_kept_snapshot_id = s.id WHERE d.local_day=?",
                   [.text(day)]).first.map(InsightSnapshot.init)
    }

    /// The newest snapshot of a kind on any day (the first week's notes come once).
    public func latestSnapshot(kind: String) throws -> InsightSnapshot? {
        try db.run("SELECT * FROM insight_snapshot WHERE kind=? ORDER BY rowid DESC LIMIT 1", [.text(kind)]).first.map(InsightSnapshot.init)
    }

    /// Drops generated text that drew on an entry since held (SR-15 outranks DR-05's append-only rule here).
    public func deleteSnapshot(id: String) throws {
        try db.run("DELETE FROM insight_snapshot WHERE id=?", [.text(id)])
    }

    func dropDayReadings(_ day: String) throws {
        try db.run("DELETE FROM insight_snapshot WHERE kind IN ('day_reading','letter') AND from_day=?", [.text(day)])
    }

    // MARK: Daily question

    /// Refresh question (CONTRACT §4): the answered pair stays, archived, and a new question starts unanswered.
    public func archiveTurn(id: String) throws {
        try db.run("UPDATE reflection_turn SET archived_at=?, updated_at=? WHERE id=?", [.text(Date.now.iso), .text(Date.now.iso), .text(id)])
    }

    /// Every question asked in the 7 days up to `day` (ai.ts recentQuestions): the day readings', before `day` unless
    /// `includingDay`, and every reflection turn's.
    public func recentQuestions(day: String, includingDay: Bool) throws -> [String] {
        let from = LocalDay.adding(-7, to: day)
        return try db.run("""
            SELECT json_extract(payload, '$.reading.question') AS q FROM insight_snapshot
            WHERE kind='day_reading' AND from_day >= ? AND (from_day < ? OR (? AND from_day = ?))
            UNION SELECT question AS q FROM reflection_turn WHERE local_day >= ? AND local_day <= ?
            """, [.text(from), .text(day), .int(includingDay ? 1 : 0), .text(day), .text(from), .text(day)])
            .compactMap { $0.str("q") }.filter { !$0.isEmpty }
    }

    // MARK: Commitments

    public func commitments(day: String) throws -> [Commitment] {
        try db.run("SELECT * FROM commitment WHERE for_day=? AND deleted_at IS NULL ORDER BY created_at, rowid", [.text(day)])
            .map(Commitment.init)
    }

    /// Adds one to the day's list, cut to 280 characters; nil when the text is empty or the day already holds 20.
    @discardableResult
    public func addCommitment(_ text: String, day: String, carriedFrom: String? = nil, sourceEntryId: String? = nil) throws -> Commitment? {
        try db.transaction { try insertCommitment(text, day: day, carriedFrom: carriedFrom, sourceEntryId: sourceEntryId) }
    }

    public func setDone(_ id: String, _ done: Bool) throws {
        try change(id, done ? "completed" : "uncompleted", "completed_at=?", [done ? .text(Date.now.iso) : .null])
    }

    public func edit(_ id: String, text: String) throws {
        try change(id, "edited", "text=?", [.text(Commitment.clipped(text))])
    }

    /// A tombstone (DR-03); `restoreCommitment` is its undo.
    public func delete(_ id: String) throws {
        try change(id, "deleted", "deleted_at=?", [.text(Date.now.iso)])
    }

    /// Undoes a delete or a let-go.
    public func restoreCommitment(_ id: String) throws {
        try change(id, "restored", "deleted_at=NULL, let_go_on_day=NULL", [])
    }

    /// The same words on `day`, linked to where they came from, in order and within the day's 20. Returns the carried copies.
    @discardableResult
    public func carry(_ ids: [String], to day: String) throws -> [Commitment] {
        try db.transaction {
            try ids.compactMap { id in
                guard let c = try db.run("SELECT * FROM commitment WHERE id=?", [.text(id)]).first.map(Commitment.init) else { return nil }
                return try insertCommitment(c.text, day: day, carriedFrom: id, sourceEntryId: c.sourceEntryId, event: "carried")
            }
        }
    }

    /// Yesterday's stays unfinished there, and Saro stops asking about it.
    public func letGo(_ ids: [String], day: String) throws {
        try db.transaction {
            for id in ids { try changed(id, "let_go", "let_go_on_day=?", [.text(day)]) }
        }
    }

    /// Commitments still open: not done, let go, deleted, or carried on to a later day. Only `from` that day, when given.
    public func openCommitments(from day: String? = nil) throws -> [Commitment] {
        try db.run("""
            SELECT c.* FROM commitment c
            WHERE c.deleted_at IS NULL AND c.completed_at IS NULL AND c.let_go_on_day IS NULL AND (? IS NULL OR c.for_day = ?)
              AND NOT EXISTS (SELECT 1 FROM commitment n WHERE n.carried_from_id = c.id AND n.deleted_at IS NULL)
            ORDER BY c.for_day, c.created_at, c.rowid
            """, [day.sql, day.sql]).map(Commitment.init)
    }

    /// Every change to a commitment, oldest first.
    public func commitmentEvents(_ id: String) throws -> [String] {
        try db.run("SELECT event FROM commitment_event WHERE commitment_id=? ORDER BY rowid", [.text(id)]).compactMap { $0.str("event") }
    }

    private func insertCommitment(_ text: String, day: String, carriedFrom: String?, sourceEntryId: String?,
                                  event: String = "created") throws -> Commitment? {
        let text = Commitment.clipped(text.trimmingCharacters(in: .whitespacesAndNewlines))
        let count = try db.run("SELECT COUNT(*) AS n FROM commitment WHERE for_day=? AND deleted_at IS NULL", [.text(day)]).first?.int("n") ?? 0
        guard !text.isEmpty, count < Commitment.maxCount else { return nil }
        var c = Commitment(text: text, forDay: day)
        c.carriedFromId = carriedFrom
        c.sourceEntryId = sourceEntryId
        try db.run("""
            INSERT INTO commitment (id, text, for_day, carried_from_id, source_entry_id, created_at, updated_at) VALUES (?,?,?,?,?,?,?)
            """, [.text(c.id), .text(c.text), .text(day), carriedFrom.sql, sourceEntryId.sql, .text(c.createdAt.iso), .text(c.createdAt.iso)])
        try appendEvent(c.id, event)
        return c
    }

    private func change(_ id: String, _ event: String, _ set: String, _ args: [SQLValue]) throws {
        try db.transaction { try changed(id, event, set, args) }
    }

    private func changed(_ id: String, _ event: String, _ set: String, _ args: [SQLValue]) throws {
        try db.run("UPDATE commitment SET \(set), updated_at=? WHERE id=?", args + [.text(Date.now.iso), .text(id)])
        try appendEvent(id, event)
    }

    private func appendEvent(_ id: String, _ event: String) throws {
        try db.run("INSERT INTO commitment_event (id, commitment_id, event, local_day, created_at) VALUES (?,?,?,?,?)",
                   [.text(UUID().uuidString), .text(id), .text(event), .text(LocalDay.today()), .text(Date.now.iso)])
    }
}

extension Commitment {
    init(row: Row) {
        id = row.str("id") ?? ""
        text = row.str("text") ?? ""
        forDay = row.str("for_day") ?? ""
        completedAt = row.date("completed_at")
        letGoOnDay = row.str("let_go_on_day")
        carriedFromId = row.str("carried_from_id")
        sourceEntryId = row.str("source_entry_id")
        createdAt = row.date("created_at") ?? .distantPast
    }
}
