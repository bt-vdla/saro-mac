import Foundation

/// One thing Saro picked up, or that the person told it (BRD §13 `observation`). An extractor row always carries the
/// person's own words verbatim (DR-09): `quote` is `field`'s text at UTF-16 [spanStart, spanEnd).
public struct MemoryObservation: Sendable, Hashable, Codable, Identifiable {
    public enum Source: String, Sendable, Codable { case extractor, user, onboarding }

    public enum Kind: String, Sendable, Codable {
        /// A capitalised name, by how the sentence treats it (memory.ts personCue): as a person, in the way companies are
        /// talked about too, as a thing, or with no cue. All four share the key `person:<name>`.
        case person, personTalks = "person.talks", personThing = "person.thing", personName = "person.name"
        case place, org, theme, emotion, intention
        /// The person's own sentence for a memory: one they added (key `user:<id>`), or an edit of one Saro wrote.
        case line
        /// The person's correction of a name in the graph.
        case label
    }

    public var id = UUID().uuidString
    public var entryId: String?
    public var aiRunId: String?
    public var source: Source
    public var kind: Kind
    public var key: String
    public var label: String
    public var quote: String?
    public var field: String?
    public var spanStart: Int?
    public var spanEnd: Int?
    public var textSha256: String?
    public var localDay: String
    public var createdAt = Date.now
    /// Read back only: the entry's capture time, and the executor of the run that made the row (its lineage, DR-13).
    public var capturedAt: Date?
    public var lineage: String?

    public init(entryId: String?, source: Source = .extractor, kind: Kind, key: String, label: String, quote: String? = nil,
                field: String? = nil, spanStart: Int? = nil, spanEnd: Int? = nil, textSha256: String? = nil, localDay: String) {
        self.entryId = entryId
        self.source = source
        self.kind = kind
        self.key = key
        self.label = label
        self.quote = quote
        self.field = field
        self.spanStart = spanStart
        self.spanEnd = spanEnd
        self.textSha256 = textSha256
        self.localDay = localDay
    }

    init(row: Row) {
        id = row.str("id") ?? ""
        entryId = row.str("entry_id")
        aiRunId = row.str("ai_run_id")
        source = Source(rawValue: row.str("source") ?? "") ?? .extractor
        kind = Kind(rawValue: row.str("kind") ?? "") ?? .personName
        key = row.str("key") ?? ""
        label = row.str("label") ?? ""
        quote = row.str("quote")
        field = row.str("field")
        spanStart = row.int("span_start")
        spanEnd = row.int("span_end")
        textSha256 = row.str("text_sha256")
        localDay = row.str("local_day") ?? ""
        createdAt = row.date("created_at") ?? .distantPast
        capturedAt = row.date("entry_at")
        lineage = row.str("executor")
    }

    /// When it was said: the entry's capture time, or when the person wrote it here.
    public var at: Date { capturedAt ?? createdAt }
}

/// An open commitment from reflection's v4 table, as memory reads it.
public struct OpenCommitment: Sendable, Hashable {
    public let text: String
    public let createdAt: Date

    public init(text: String, createdAt: Date) {
        self.text = text
        self.createdAt = createdAt
    }
}

extension Ledger {
    public static let memoryFeature = "memory"

    /// Every row the engine may read (the `active_observation` view), oldest first.
    public func activeObservations() throws -> [MemoryObservation] {
        try db.run("""
            SELECT o.*, e.captured_at AS entry_at, r.executor AS executor FROM active_observation o
            LEFT JOIN entry e ON e.id = o.entry_id LEFT JOIN ai_run r ON r.id = o.ai_run_id
            ORDER BY COALESCE(e.captured_at, o.created_at), o.created_at
            """).map(MemoryObservation.init)
    }

    /// An entry's extractor rows that nothing retracted yet, whatever hides them.
    public func standingObservations(entryId: String) throws -> [MemoryObservation] {
        try db.run("""
            SELECT * FROM observation o WHERE entry_id=? AND source='extractor'
              AND NOT EXISTS (SELECT 1 FROM observation_retraction r WHERE r.observation_id = o.id)
            """, [.text(entryId)]).map(MemoryObservation.init)
    }

    /// One learning pass in one transaction (FR-MEM-01): its run and inputs, its rows, and the retraction of what the
    /// entry's earlier text gave (FR-MEM-02, `source_edited`, pointing at the new row with the same key when there is one).
    /// A row without an `aiRunId` belongs to `run`.
    public func insertObservations(_ observations: [MemoryObservation], run: AIRun, inputs: [AIRunInput], retracting stale: [MemoryObservation] = []) throws {
        try db.transaction {
            try insertRunRow(run, inputs: inputs)
            for var o in observations {
                if o.aiRunId == nil { o.aiRunId = run.id }
                try insertRow(o)
            }
            for s in stale {
                try retractRow(s.id, reason: "source_edited", replacedBy: observations.first { $0.key == s.key }?.id)
            }
        }
    }

    public func retract(_ ids: [String], reason: String, replacedBy: String? = nil) throws {
        try db.transaction { for id in ids { try retractRow(id, reason: reason, replacedBy: replacedBy) } }
    }

    /// The person's own line or name for `key` (FR-MEM-09): it replaces their earlier one of the same kind (`user_edited`),
    /// and extraction never writes over it because it outranks every extractor row with that key.
    public func addUserMemory(_ o: MemoryObservation) throws {
        try db.transaction {
            let earlier = try db.run("""
                SELECT id FROM observation o WHERE key=? AND kind=? AND source='user'
                  AND NOT EXISTS (SELECT 1 FROM observation_retraction r WHERE r.observation_id = o.id)
                """, [.text(o.key), .text(o.kind.rawValue)]).compactMap { $0.str("id") }
            try insertRow(o)
            for id in earlier { try retractRow(id, reason: "user_edited", replacedBy: o.id) }
        }
    }

    /// Delete (FR-MEM-03): every row with the key goes for good (secure_delete overwrites its words) and a tombstone keeps
    /// only the key's hash, so the key never comes back. The entry's runs stay, so its text isn't read again for it.
    public func forget(keys: [String]) throws {
        let now = Date.now.iso
        try db.transaction {
            for key in keys {
                try db.run("DELETE FROM observation_retraction WHERE observation_id IN (SELECT id FROM observation WHERE key=?)", [.text(key)])
                try db.run("DELETE FROM observation WHERE key=?", [.text(key)])
                try db.run("INSERT OR IGNORE INTO memory_tombstone (key_sha256, at) VALUES (?, ?)", [.text(sha256(key)), .text(now)])
            }
        }
    }

    /// A gate that no longer clears an entry takes back everything memory learned from it, retracted rows included
    /// (SR-15: nothing generated is kept for a held entry), and its memory runs, so text cleared again is learned afresh.
    /// Called inside `insertVerdict`'s transaction.
    func dropMemory(entryId: String) throws {
        let runs = try db.run("""
            SELECT DISTINCT r.id FROM ai_run r JOIN ai_run_input i ON i.ai_run_id = r.id WHERE r.feature=? AND i.entry_id=?
            """, [.text(Self.memoryFeature), .text(entryId)]).compactMap { $0.str("id") }
        try db.run("DELETE FROM observation_retraction WHERE observation_id IN (SELECT id FROM observation WHERE entry_id=?)", [.text(entryId)])
        try db.run("DELETE FROM observation WHERE entry_id=?", [.text(entryId)])
        for id in runs {
            try db.run("DELETE FROM ai_run_input WHERE ai_run_id=?", [.text(id)])
            try db.run("DELETE FROM ai_run WHERE id=? AND NOT EXISTS (SELECT 1 FROM observation WHERE ai_run_id=?)", [.text(id), .text(id)])
        }
    }

    /// What Saro knows, as readable lines for Export (FR-MEM feeding): what the pane shows, with every dated sighting.
    /// Forgotten keys are left out; the tombstone table carries only their hashes.
    func memoriesForExport() throws -> [[String: Any]] {
        let memories = MemoryList.derive(try activeObservations(), starter: try latestStarter(), commitments: try openCommitments(),
                                         tombstones: try tombstoneHashes(), forgotAllAt: try forgotAllAt(), pauses: try pauses())
        return MemoryList.group(memories).flatMap { g in
            g.items.map { m -> [String: Any] in
                var out: [String: Any] = ["key": m.key, "text": m.text, "group": g.group.label, "source": "\(m.source)", "entries": m.count,
                                          "last_seen": m.lastSeen.iso, "updated_at": m.updatedAt.iso,
                                          "sightings": m.sightings.map { ["day": $0.day, "quote": $0.quote, "entry_id": $0.entryId as Any] }]
                if let told = m.told { out["told"] = told }
                return out
            }
        }
    }

    /// Forget everything (FR-MEM-04, as decided for v0: memories only, readings and letters stay). One transaction
    /// hard-deletes every observation and retraction (secure_delete overwrites them), tombstones every key, `extra`
    /// included, and records the cutoff, so nothing written before `at` is read again. Backups/ goes too, so the next
    /// snapshot is fresh (DR-16). Returns how many keys were forgotten.
    @discardableResult
    public func forgetAll(extra: [String] = [], at: Date = .now) throws -> Int {
        let n = try db.transaction {
            let keys = Set(try db.run("SELECT DISTINCT key FROM observation").compactMap { $0.str("key") } + extra)
            try db.run("DELETE FROM observation_retraction")
            try db.run("DELETE FROM observation")
            for key in keys {
                try db.run("INSERT OR IGNORE INTO memory_tombstone (key_sha256, at) VALUES (?, ?)", [.text(sha256(key)), .text(at.iso)])
            }
            // REPLACE deletes and inserts, so the append-only trigger (UPDATE only) lets the cutoff move on.
            try db.run("INSERT OR REPLACE INTO memory_tombstone (key_sha256, at) VALUES ('all', ?)", [.text(at.iso)])
            return keys.count
        }
        try? FileManager.default.removeItem(at: rootURL.appending(path: "Backups", directoryHint: .isDirectory))
        return n
    }

    /// The hash of every forgotten key.
    public func tombstoneHashes() throws -> Set<String> {
        Set(try db.run("SELECT key_sha256 FROM memory_tombstone WHERE key_sha256 <> 'all'").compactMap { $0.str("key_sha256") })
    }

    public func forgotAllAt() throws -> Date? {
        try db.run("SELECT at FROM memory_tombstone WHERE key_sha256='all'").first?.date("at")
    }

    /// Whether this text of the entry was learned from, or deliberately passed over, by this extractor version.
    public func memoryLearned(entryId: String, textSha256: String, extractor: String) throws -> Bool {
        try !db.run("""
            SELECT 1 FROM ai_run r JOIN ai_run_input i ON i.ai_run_id = r.id
            WHERE r.feature=? AND r.extractor_version=? AND r.input_hash=? AND i.entry_id=? LIMIT 1
            """, [.text(Self.memoryFeature), .text(extractor), .text(textSha256), .text(entryId)]).isEmpty
    }

    /// Live, cleared entries whose current text this extractor version hasn't seen (the launch backfill, FR-MEM-06).
    public func unlearnedEntryIDs(extractor: String) throws -> [String] {
        try db.run("""
            SELECT v.entry_id FROM safety_verdict v JOIN live_entry e ON e.id = v.entry_id
            WHERE v.rowid = (SELECT MAX(rowid) FROM safety_verdict WHERE entry_id = v.entry_id) AND v.verdict IN ('clear','unavailable_clear')
              AND NOT EXISTS (SELECT 1 FROM ai_run r JOIN ai_run_input i ON i.ai_run_id = r.id
                              WHERE r.feature=? AND r.extractor_version=? AND r.input_hash = v.text_sha256 AND i.entry_id = v.entry_id)
            ORDER BY e.captured_at
            """, [.text(Self.memoryFeature), .text(extractor)]).compactMap { $0.str("entry_id") }
    }

    /// Whether this text of the entry ever gave a row, retracted or not.
    public func observedEver(entryId: String, textSha256: String) throws -> Bool {
        try !db.run("SELECT 1 FROM observation WHERE entry_id=? AND text_sha256=? LIMIT 1", [.text(entryId), .text(textSha256)]).isEmpty
    }

    /// When this text was first gated: a typed entry's edit time, near enough, since saving queues the gate.
    public func firstVerdictAt(entryId: String, textSha256: String) throws -> Date? {
        try db.run("SELECT MIN(created_at) AS at FROM safety_verdict WHERE entry_id=? AND text_sha256=?",
                   [.text(entryId), .text(textSha256)]).first?.date("at")
    }

    /// Open commitments from reflection's v4 table, a carried one on each day it was carried to. None set on a held day or
    /// carried from one (SR-13, SR-16), by `active_observation`'s three holds, since memory says them in Saro's voice.
    public func openCommitments() throws -> [OpenCommitment] {
        try db.run("""
            WITH RECURSIVE line(id, day, up) AS (
              SELECT id, for_day, carried_from_id FROM commitment
              UNION ALL SELECT l.id, c.for_day, c.carried_from_id FROM line l JOIN commitment c ON c.id = l.up)
            SELECT c.text, c.created_at FROM commitment c
            WHERE c.completed_at IS NULL AND c.let_go_on_day IS NULL AND c.deleted_at IS NULL
              AND NOT EXISTS (SELECT 1 FROM line l WHERE l.id = c.id AND (
                EXISTS (SELECT 1 FROM live_entry h JOIN safety_verdict v ON v.entry_id = h.id
                        WHERE h.local_day = l.day AND v.verdict = 'safety_hold'
                          AND v.rowid = (SELECT MAX(rowid) FROM safety_verdict WHERE entry_id = h.id))
                OR EXISTS (SELECT 1 FROM reflection_turn t WHERE t.local_day = l.day AND t.answer_verdict = 'safety_hold')
                OR EXISTS (SELECT 1 FROM day_state d WHERE d.local_day = l.day AND d.mood_note_verdict = 'safety_hold')))
            ORDER BY c.created_at
            """).compactMap { r in r.str("text").map { OpenCommitment(text: $0, createdAt: r.date("created_at") ?? .distantPast) } }
    }

    /// How many live entries have cleared text, for the empty state's count (R-14).
    public func clearedEntryCount() throws -> Int {
        try db.run("""
            SELECT COUNT(*) AS n FROM live_entry e JOIN safety_verdict v ON v.entry_id = e.id
            WHERE v.rowid = (SELECT MAX(rowid) FROM safety_verdict WHERE entry_id = e.id) AND v.verdict IN ('clear','unavailable_clear')
            """).first?.int("n") ?? 0
    }

    // MARK: Rows

    private func insertRow(_ o: MemoryObservation) throws {
        try db.run("""
            INSERT INTO observation (id, entry_id, ai_run_id, source, kind, key, key_sha256, label, quote, field, span_start, span_end,
              text_sha256, local_day, created_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, [.text(o.id), o.entryId.sql, o.aiRunId.sql, .text(o.source.rawValue), .text(o.kind.rawValue), .text(o.key),
                  .text(sha256(o.key)), .text(o.label), o.quote.sql, o.field.sql, o.spanStart.sql, o.spanEnd.sql, o.textSha256.sql,
                  .text(o.localDay), .text(o.createdAt.iso)])
    }

    private func retractRow(_ id: String, reason: String, replacedBy: String?) throws {
        try db.run("INSERT INTO observation_retraction (observation_id, reason, replaced_by, created_at) VALUES (?,?,?,?)",
                   [.text(id), .text(reason), replacedBy.sql, .text(Date.now.iso)])
    }

    // ponytail: insertRun's statement again, because it opens its own transaction and this one must hold the rows too;
    // fold the two together if insertRun ever takes a caller's transaction.
    private func insertRunRow(_ r: AIRun, inputs: [AIRunInput]) throws {
        try db.run("""
            INSERT INTO ai_run (id, feature, executor, guardrails, ladder_rung, os_build, variant, model_fingerprint, context_size,
              sampling, prompt_version, schema_version, extractor_version, input_hash, tokens_in, tokens_out, model_calls,
              latency_ms, status, local_day, created_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, [.text(r.id), .text(r.feature), .text(r.executor), r.guardrails.sql, r.ladderRung.sql, r.osBuild.sql, r.variant.sql,
                  r.modelFingerprint.sql, r.contextSize.sql, r.sampling.sql, r.promptVersion.sql, r.schemaVersion.sql,
                  r.extractorVersion.sql, r.inputHash.sql, r.tokensIn.sql, r.tokensOut.sql, r.modelCalls.sql, r.latencyMs.sql,
                  .text(r.status), r.localDay.sql, .text(r.createdAt.iso)])
        for i in inputs {
            try db.run("INSERT INTO ai_run_input (ai_run_id, entry_id, field, utf16_from, utf16_to, text_sha256) VALUES (?,?,?,?,?,?)",
                       [.text(r.id), .text(i.entryId), .text(i.field), .int(Int64(i.utf16From)), .int(Int64(i.utf16To)), .text(i.textSha256)])
        }
    }
}
