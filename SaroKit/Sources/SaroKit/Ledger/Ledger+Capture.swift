import Foundation

extension Ledger {
    /// Discard of a take that was never kept (the recorder's two-step discard, the voice pill's ✕ and Record again): its
    /// entries, every row made from them and their files, gone for good. Kept entries go to Trash instead, never here.
    public func discardTake(entryIds: [String]) throws {
        var files: [URL] = []
        try db.transaction {
            try db.exec("PRAGMA defer_foreign_keys=ON")
            for id in entryIds {
                guard let e = try entry(id) else { continue }
                let key: [SQLValue] = [.text(id)]
                try db.run("DELETE FROM observation_retraction WHERE observation_id IN (SELECT id FROM observation WHERE entry_id=?)", key)
                for table in ["observation", "entry_annotation", "ai_run_input", "safety_verdict", "card_layout", "reflection_turn"] {
                    try db.run("DELETE FROM \(table) WHERE entry_id=?", key)
                }
                try db.run("UPDATE commitment SET source_entry_id=NULL WHERE source_entry_id=?", key)
                try db.run("UPDATE entry SET duplicated_from_id=NULL WHERE duplicated_from_id=?", key)
                try db.run("DELETE FROM entry WHERE id=?", key)
                guard let mid = e.mediaId, try db.run("SELECT 1 FROM entry WHERE media_id=?", [.text(mid)]).isEmpty,
                      let m = try media(mid) else { continue }
                files.append(url(for: m))
                // Its key frame too, once the card or the lens made one.
                if let poster = try poster(mediaId: mid) { files.append(mediaURL.appending(path: poster)) }
                try db.run("DELETE FROM transcript_word WHERE media_id=?", [.text(mid)])
                try db.run("DELETE FROM media_asset WHERE id=?", [.text(mid)])
            }
        }
        for f in files { try? FileManager.default.removeItem(at: f) }
    }

    /// A question left unanswered goes with nothing kept of it: Another question swaps it, and closing the page lets it go.
    public func dropUnanswered(turnId: String) throws {
        try db.run("DELETE FROM reflection_turn WHERE id=? AND answer IS NULL", [.text(turnId)])
    }

    /// When the page's words were last changed after they were first checked, for the reading page's "Edited 4:20 PM": the
    /// newest check of words other than the first ones. A re-check of the same words (a launch re-gate) isn't an edit.
    // ponytail: the time of the check, seconds after the edit; an edited_at column if that ever reads wrong.
    public func editedAt(entryId: String) throws -> Date? {
        let checks = try db.run("SELECT text_sha256, created_at FROM safety_verdict WHERE entry_id=? ORDER BY rowid", [.text(entryId)])
        guard let first = checks.first?.str("text_sha256") else { return nil }
        return checks.last { $0.str("text_sha256") != first }?.date("created_at")
    }

    /// A follow-up asked from an entry's words, once that entry is held, is generated text from a held entry (SR-15): the
    /// question goes. A row the person answered keeps their answer, with the question emptied; one never answered goes.
    public func dropFollowUps(heldFrom entryId: String) throws {
        let held = try db.run("""
            SELECT 1 FROM safety_verdict WHERE entry_id=? AND verdict='safety_hold'
              AND rowid = (SELECT MAX(rowid) FROM safety_verdict WHERE entry_id=?)
            """, [.text(entryId), .text(entryId)])
        guard !held.isEmpty else { return }
        // Only capture's own questions: the day's question is the reflection pipeline's to keep or drop.
        let derived = "kind IN ('prompt','reflect_deeper','reflect_further') AND ai_run_id IN (SELECT ai_run_id FROM ai_run_input WHERE entry_id=?)"
        try db.transaction {
            try db.run("DELETE FROM reflection_turn WHERE answer IS NULL AND \(derived)", [.text(entryId)])
            try db.run("UPDATE reflection_turn SET question='', updated_at=? WHERE \(derived)", [.text(Date.now.iso), .text(entryId)])
        }
    }
}
