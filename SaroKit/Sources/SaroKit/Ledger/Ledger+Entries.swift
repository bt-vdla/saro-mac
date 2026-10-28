import Foundation

public enum DuplicateError: Error, Equatable {
    case missing
    /// Future days aren't shown on the canvas, so a copy there would be invisible.
    case futureDay
}

extension Ledger {
    /// A voice note's summary in the person's own words (DR-04).
    public func summaryUser(id: String) throws -> String? {
        try db.run("SELECT summary_user FROM entry WHERE id=?", [.text(id)]).first?.str("summary_user")
    }

    /// A user edit, as `updateEntryText`: a changed summary is the person's words, so it goes back to pending for the gate.
    public func updateSummary(id: String, _ summary: String?) throws {
        guard let old = try entry(id) else { return }
        let status = Self.statusAfterEdit(old, body: old.body, titleUser: old.titleUser, captionUser: old.captionUser, summaryUser: summary)
            ?? old.processingStatus
        try db.run("UPDATE entry SET summary_user=?, processing_status=?, updated_at=? WHERE id=?",
                   [summary.sql, .text(status), .text(Date.now.iso), .text(id)])
    }

    /// The entry this one was copied from, nil for an original.
    public func duplicatedFrom(id: String) throws -> String? {
        try db.run("SELECT duplicated_from_id FROM entry WHERE id=?", [.text(id)]).first?.str("duplicated_from_id")
    }

    /// A copy on another day (FR-DAY-07): the person's words and the same media file, backdated, at the source's time of
    /// day (never later than now), pointing at the original, which a copy of a copy points at too. It inherits the
    /// source's newest verdict, so it is never read before it is checked, and a held copy holds its new day at once,
    /// dropping what was read there (SR-13, SR-15). Engine counts leave it out (active_observation).
    public func duplicate(id: String, toDay day: String, now: Date = .now) throws -> Entry {
        guard let source = try entry(id) else { throw DuplicateError.missing }
        guard day <= LocalDay.string(for: now) else { throw DuplicateError.futureDay }
        let tz = TimeZone(identifier: source.tzId) ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var at = cal.dateComponents([.hour, .minute, .second], from: source.capturedAt)
        let p = day.split(separator: "-").compactMap { Int($0) }
        (at.year, at.month, at.day) = (p.first, p.dropFirst().first, p.last)
        let captured = min(cal.date(from: at) ?? now, now)
        let copy = UUID().uuidString
        try db.transaction {
            try db.run("""
                INSERT INTO entry (id, kind, title_user, caption_user, summary_user, body, captured_at, tz_id, local_day, backdated,
                                   duplicated_from_id, media_id, processing_status, updated_at)
                SELECT ?, kind, title_user, caption_user, summary_user, body, ?, tz_id, ?, 1, COALESCE(duplicated_from_id, id), media_id,
                       'pending', ? FROM entry WHERE id=?
                """, [.text(copy), .text(captured.iso), .text(day), .text(now.iso), .text(id)])
            try db.run("""
                INSERT INTO safety_verdict (id, entry_id, text_sha256, safety_version, layer, verdict, reason_code, created_at)
                SELECT ?, ?, text_sha256, safety_version, layer, verdict, reason_code, ? FROM safety_verdict WHERE entry_id=?
                ORDER BY rowid DESC LIMIT 1
                """, [.text(UUID().uuidString), .text(copy), .text(now.iso), .text(id)])
            if try !db.run("SELECT 1 FROM safety_verdict WHERE entry_id=? AND verdict='safety_hold'", [.text(copy)]).isEmpty {
                try db.run("DELETE FROM insight_snapshot WHERE kind IN ('day_reading','letter') AND from_day=?", [.text(day)])
            }
        }
        guard let made = try entry(copy) else { throw DuplicateError.missing }
        return made
    }
}
