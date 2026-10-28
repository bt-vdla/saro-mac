import Foundation

/// The one local ledger (DR-01): a single SQLite file in WAL mode, written only through this actor.
/// Media live as files under `mediaURL`; rows store relative paths.
public actor Ledger {
    public nonisolated let rootURL: URL
    public nonisolated var mediaURL: URL { rootURL.appending(path: "Media", directoryHint: .isDirectory) }
    let db: SQLite

    /// `Application Support/Saro` inside the app container.
    public static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Saro", directoryHint: .isDirectory)
    }

    public init(rootURL: URL = Ledger.defaultRoot) throws {
        self.rootURL = rootURL
        try FileManager.default.createDirectory(at: rootURL.appending(path: "Media"), withIntermediateDirectories: true)
        db = try SQLite(path: rootURL.appending(path: "saro.sqlite").path)
        try db.exec("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA secure_delete=ON; PRAGMA synchronous=NORMAL;")
        try Self.migrate(db)
    }

    static func migrate(_ db: SQLite) throws {
        let current = try db.run("PRAGMA user_version").first?.int("user_version") ?? 0
        for (i, sql) in Schema.migrations.enumerated() where i >= current {
            try db.transaction {
                try db.exec(sql)
                try db.exec("PRAGMA user_version = \(i + 1)")
            }
        }
    }

    public func schemaVersion() throws -> Int { try db.run("PRAGMA user_version").first?.int("user_version") ?? 0 }

    public func pragma(_ name: String) throws -> String? {
        try db.run("PRAGMA \(name)").first?.values.first.map { "\($0.json)" }
    }

    /// Raw access for tests and one-off reads.
    @discardableResult
    public func run(_ sql: String, _ args: [SQLValue] = []) throws -> [Row] { try db.run(sql, args) }

    // MARK: Media

    public func insertMedia(_ m: MediaAsset) throws {
        let now = Date.now.iso
        try db.run("""
            INSERT INTO media_asset (id, file_name, kind, origin, state, duration_ms, bytes, created_at, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?)
            """, [.text(m.id), .text(m.fileName), .text(m.kind.rawValue), .text(m.origin), .text(m.state),
                  m.durationMs.sql, m.bytes.sql, .text(now), .text(now)])
    }

    public func updateMedia(id: String, state: String, durationMs: Int?, bytes: Int?) throws {
        try db.run("UPDATE media_asset SET state=?, duration_ms=COALESCE(?, duration_ms), bytes=COALESCE(?, bytes), updated_at=? WHERE id=?",
                   [.text(state), durationMs.sql, bytes.sql, .text(Date.now.iso), .text(id)])
    }

    public func media(_ id: String) throws -> MediaAsset? {
        try db.run("SELECT * FROM media_asset WHERE id=?", [.text(id)]).first.map(MediaAsset.init)
    }

    public func allMedia() throws -> [MediaAsset] { try db.run("SELECT * FROM media_asset").map(MediaAsset.init) }

    public nonisolated func url(for media: MediaAsset) -> URL { mediaURL.appending(path: media.fileName) }

    // MARK: Entries

    public func insertEntry(_ e: Entry) throws {
        try db.run("""
            INSERT INTO entry (id, kind, session_id, turn_number, title_user, caption_user, body, captured_at, tz_id, local_day,
                               backdated, media_id, processing_status, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, [.text(e.id), .text(e.kind.rawValue), e.sessionId.sql, e.turnNumber.sql, e.titleUser.sql, e.captionUser.sql,
                  e.body.sql, .text(e.capturedAt.iso), .text(e.tzId), .text(e.localDay), .int(e.backdated ? 1 : 0),
                  e.mediaId.sql, .text(e.processingStatus), .text(Date.now.iso)])
    }

    /// User edits only (DR-04): no AI path calls this.
    public func updateEntryText(id: String, body: String?, titleUser: String?, captionUser: String? = nil) throws {
        try db.run("UPDATE entry SET body=?, title_user=?, caption_user=?, updated_at=? WHERE id=?",
                   [body.sql, titleUser.sql, captionUser.sql, .text(Date.now.iso), .text(id)])
    }

    public func setProcessingStatus(id: String, _ status: String) throws {
        try db.run("UPDATE entry SET processing_status=?, updated_at=? WHERE id=?", [.text(status), .text(Date.now.iso), .text(id)])
    }

    public func entry(_ id: String) throws -> Entry? {
        try db.run("SELECT * FROM entry WHERE id=?", [.text(id)]).first.map(Entry.init)
    }

    public func entries(day: String) throws -> [Entry] {
        try db.run("SELECT * FROM live_entry WHERE local_day=? ORDER BY captured_at, turn_number", [.text(day)]).map(Entry.init)
    }

    public func allEntries(includeTrashed: Bool = false) throws -> [Entry] {
        try db.run("SELECT * FROM \(includeTrashed ? "entry" : "live_entry") ORDER BY captured_at").map(Entry.init)
    }

    /// Entries whose processing did not finish (crash, quit mid-transcription) or whose transcript wasn't ready,
    /// for the launch sweep to try again.
    public func unfinishedEntries() throws -> [Entry] {
        try db.run("SELECT * FROM live_entry WHERE processing_status NOT IN ('done','failed') ORDER BY captured_at")
            .map(Entry.init)
    }

    /// Live entries whose newest verdict is one of `verdicts`.
    public func entryIDs(withLatestVerdictIn verdicts: [String]) throws -> [String] {
        let marks = verdicts.map { _ in "?" }.joined(separator: ",")
        return try db.run("""
            SELECT v.entry_id FROM safety_verdict v JOIN live_entry e ON e.id = v.entry_id
            WHERE v.rowid = (SELECT MAX(rowid) FROM safety_verdict WHERE entry_id = v.entry_id) AND v.verdict IN (\(marks))
            """, verdicts.map { .text($0) }).compactMap { $0.str("entry_id") }
    }

    /// Drops a media file's transcript so the next pass transcribes it again (Try again on a technical hold).
    public func clearTranscript(mediaId: String) throws {
        try db.run("DELETE FROM transcript_word WHERE media_id=?", [.text(mediaId)])
    }

    /// Days that have at least one live entry, newest first.
    public func days() throws -> [(day: String, count: Int)] {
        try db.run("SELECT local_day, COUNT(*) AS n FROM live_entry GROUP BY local_day ORDER BY local_day DESC")
            .map { ($0.str("local_day") ?? "", $0.int("n") ?? 0) }
    }

    // MARK: Trash (DR-15)

    /// Soft-deletes the entries as one user action and returns the batch id for undo.
    @discardableResult
    public func trash(_ ids: [String]) throws -> String {
        let batch = UUID().uuidString
        let now = Date.now.iso
        try db.transaction {
            for id in ids {
                try db.run("UPDATE entry SET trashed_at=?, trash_batch_id=?, updated_at=? WHERE id=? AND trashed_at IS NULL",
                           [.text(now), .text(batch), .text(now), .text(id)])
            }
        }
        return batch
    }

    /// Removes a never-written page (no text, no media, nothing derived). Anything with content goes to Trash instead.
    public func discardIfEmpty(_ id: String) throws {
        try db.transaction {
            let empty = try db.run("""
                SELECT 1 FROM entry WHERE id=? AND trim(COALESCE(body,''), ' '||char(9)||char(10)||char(13))='' AND media_id IS NULL
                  AND NOT EXISTS (SELECT 1 FROM safety_verdict WHERE entry_id=entry.id)
                  AND NOT EXISTS (SELECT 1 FROM entry_annotation WHERE entry_id=entry.id)
                """, [.text(id)])
            guard !empty.isEmpty else { return }
            try db.run("DELETE FROM card_layout WHERE entry_id=?", [.text(id)])
            try db.run("DELETE FROM entry WHERE id=?", [.text(id)])
        }
    }

    public func restore(batch: String) throws {
        try db.run("UPDATE entry SET trashed_at=NULL, trash_batch_id=NULL, updated_at=? WHERE trash_batch_id=?",
                   [.text(Date.now.iso), .text(batch)])
    }

    public func restore(ids: [String]) throws {
        try db.transaction {
            for id in ids {
                try db.run("UPDATE entry SET trashed_at=NULL, trash_batch_id=NULL, updated_at=? WHERE id=?", [.text(Date.now.iso), .text(id)])
            }
        }
    }

    public func trashed() throws -> [Entry] {
        try db.run("SELECT * FROM entry WHERE trashed_at IS NOT NULL ORDER BY trashed_at DESC").map(Entry.init)
    }

    // MARK: Canvas layout

    public func setLayouts(_ layouts: [CardLayout]) throws {
        try db.transaction {
            for l in layouts {
                try db.run("""
                    INSERT INTO card_layout (entry_id, x, y, z, stack_id, user_placed, updated_at) VALUES (?,?,?,?,?,?,?)
                    ON CONFLICT(entry_id) DO UPDATE SET x=excluded.x, y=excluded.y, z=excluded.z, stack_id=excluded.stack_id,
                      user_placed=excluded.user_placed, updated_at=excluded.updated_at
                    """, [.text(l.entryId), .real(l.x), .real(l.y), .int(Int64(l.z)), l.stackId.sql, .int(l.userPlaced ? 1 : 0), .text(Date.now.iso)])
            }
        }
    }

    public func layouts(day: String) throws -> [String: CardLayout] {
        let rows = try db.run("SELECT c.* FROM card_layout c JOIN entry e ON e.id = c.entry_id WHERE e.local_day=?", [.text(day)])
        var out: [String: CardLayout] = [:]
        for r in rows {
            let id = r.str("entry_id") ?? ""
            out[id] = CardLayout(entryId: id, x: r.dbl("x") ?? 0, y: r.dbl("y") ?? 0, z: r.int("z") ?? 0,
                                 stackId: r.str("stack_id"), userPlaced: r.int("user_placed") == 1)
        }
        return out
    }

    // MARK: Transcripts

    public func setTranscript(mediaId: String, words: [TranscriptWord], extractorVersion: String) throws {
        try db.transaction {
            try db.run("DELETE FROM transcript_word WHERE media_id=? AND extractor_version=?", [.text(mediaId), .text(extractorVersion)])
            for (i, w) in words.enumerated() {
                try db.run("INSERT INTO transcript_word (media_id, extractor_version, idx, text, start_ms, dur_ms, confidence) VALUES (?,?,?,?,?,?,?)",
                           [.text(mediaId), .text(extractorVersion), .int(Int64(i)), .text(w.text), .int(Int64(w.startMs)),
                            .int(Int64(w.durMs)), w.confidence.map { .real($0) } ?? .null])
            }
        }
    }

    /// The newest extractor's words for this media.
    public func transcript(mediaId: String) throws -> [TranscriptWord] {
        try db.run("""
            SELECT * FROM transcript_word WHERE media_id=? AND extractor_version =
              (SELECT extractor_version FROM transcript_word WHERE media_id=? ORDER BY rowid DESC LIMIT 1) ORDER BY idx
            """, [.text(mediaId), .text(mediaId)])
            .map { TranscriptWord(text: $0.str("text") ?? "", startMs: $0.int("start_ms") ?? 0, durMs: $0.int("dur_ms") ?? 0, confidence: $0.dbl("confidence")) }
    }

    // MARK: AI layer (append-only)

    public func insertRun(_ r: AIRun, inputs: [AIRunInput] = []) throws {
        try db.transaction {
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

    public func runs(limit: Int = 200) throws -> [Row] {
        try db.run("SELECT * FROM ai_run ORDER BY rowid DESC LIMIT ?", [.int(Int64(limit))])
    }

    public func insertAnnotation(_ a: EntryAnnotation) throws {
        try db.run("""
            INSERT INTO entry_annotation (id, entry_id, ai_run_id, generator, title, summary, caption, mood_label, mood_basis, quote,
              quote_field, quote_from, quote_to, quote_sha256, created_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, [.text(a.id), .text(a.entryId), .text(a.aiRunId), .text(a.generator), a.title.sql, a.summary.sql, a.caption.sql,
                  a.moodLabel.sql, a.moodBasis.sql, a.quote.sql, a.quoteField.sql, a.quoteFrom.sql, a.quoteTo.sql,
                  a.quote.map { .text(sha256($0)) } ?? .null, .text(a.createdAt.iso)])
    }

    /// Whether this entry already has a reading made from exactly this text. With `needsModel`, a heuristic reading
    /// made without any model call doesn't count, so text read while the model couldn't run is read again once it can.
    public func hasAnnotation(entryId: String, inputHash: String, needsModel: Bool = false) throws -> Bool {
        try !db.run("""
            SELECT 1 FROM entry_annotation a JOIN ai_run r ON r.id = a.ai_run_id
            WHERE a.entry_id=? AND r.input_hash=? AND a.rowid = (SELECT MAX(rowid) FROM entry_annotation WHERE entry_id=?)
              AND NOT (? AND r.executor='heuristic' AND COALESCE(r.model_calls, 0)=0)
            """, [.text(entryId), .text(inputHash), .text(entryId), .int(needsModel ? 1 : 0)]).isEmpty
    }

    /// The newest annotation per entry for a day (DR-05: newest is current).
    public func annotations(day: String) throws -> [String: EntryAnnotation] {
        let rows = try db.run("""
            SELECT a.* FROM entry_annotation a JOIN entry e ON e.id = a.entry_id
            WHERE e.local_day=? AND a.rowid = (SELECT MAX(rowid) FROM entry_annotation WHERE entry_id = a.entry_id)
            """, [.text(day)])
        return Dictionary(rows.map(EntryAnnotation.init).map { ($0.entryId, $0) }, uniquingKeysWith: { $1 })
    }

    public func insertVerdict(_ v: SafetyVerdictRow) throws {
        try db.run("""
            INSERT INTO safety_verdict (id, entry_id, text_sha256, safety_version, layer, verdict, reason_code, created_at)
            VALUES (?,?,?,?,?,?,?,?)
            """, [.text(v.id), .text(v.entryId), .text(v.textSha256), .text(v.safetyVersion), .int(Int64(v.layer)),
                  .text(v.verdict), .text(v.reasonCode), .text(v.createdAt.iso)])
    }

    /// The newest verdict per entry for a day.
    public func verdicts(day: String) throws -> [String: SafetyVerdictRow] {
        let rows = try db.run("""
            SELECT v.* FROM safety_verdict v JOIN entry e ON e.id = v.entry_id
            WHERE e.local_day=? AND v.rowid = (SELECT MAX(rowid) FROM safety_verdict WHERE entry_id = v.entry_id)
            """, [.text(day)])
        return Dictionary(rows.map(SafetyVerdictRow.init).map { ($0.entryId, $0) }, uniquingKeysWith: { $1 })
    }

    /// A cached verdict for exactly this text and gate version (SR-17, SR-18).
    public func cachedVerdict(entryId: String, textSha256: String, safetyVersion: String) throws -> SafetyVerdictRow? {
        try db.run("SELECT * FROM safety_verdict WHERE entry_id=? AND text_sha256=? AND safety_version=? ORDER BY rowid DESC LIMIT 1",
                   [.text(entryId), .text(textSha256), .text(safetyVersion)]).first.map(SafetyVerdictRow.init)
    }

    public func insertSnapshot(_ s: InsightSnapshot) throws {
        try db.run("""
            INSERT INTO insight_snapshot (id, kind, from_day, to_day, ai_run_id, generator, input_hash, payload, created_at)
            VALUES (?,?,?,?,?,?,?,?,?)
            """, [.text(s.id), .text(s.kind), .text(s.fromDay), .text(s.toDay), s.aiRunId.sql, .text(s.generator), s.inputHash.sql,
                  .text(s.payload), .text(s.createdAt.iso)])
    }

    public func latestSnapshot(kind: String, day: String) throws -> InsightSnapshot? {
        try db.run("SELECT * FROM insight_snapshot WHERE kind=? AND from_day=? ORDER BY rowid DESC LIMIT 1", [.text(kind), .text(day)])
            .first.map(InsightSnapshot.init)
    }

    // MARK: Dev mode (append-only events)

    public func appendDecisionEvent(_ e: DecisionEvent) throws {
        try db.run("INSERT INTO decision_event (id, decision_id, choice, note, screen_id, app_version, created_at) VALUES (?,?,?,?,?,?,?)",
                   [.text(e.id), .text(e.decisionId), e.choice.sql, e.note.sql, e.screenId.sql, .text(e.appVersion), .text(e.createdAt.iso)])
    }

    public func decisionEvents() throws -> [DecisionEvent] {
        try db.run("SELECT * FROM decision_event ORDER BY rowid").map(DecisionEvent.init)
    }

    public func appendScreenNote(_ n: ScreenNote) throws {
        try db.run("INSERT INTO screen_note (id, screen_id, note, app_version, created_at) VALUES (?,?,?,?,?)",
                   [.text(n.id), .text(n.screenId), .text(n.note), .text(n.appVersion), .text(n.createdAt.iso)])
    }

    public func screenNotes() throws -> [ScreenNote] {
        try db.run("SELECT * FROM screen_note ORDER BY rowid").map(ScreenNote.init)
    }

    // MARK: Export

    /// Every row of every table as one JSON object keyed by table name (DR-20). The ledger holds no secrets.
    public func exportJSON(to url: URL) throws {
        let tables = try db.run("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").compactMap { $0.str("name") }
        var out: [String: Any] = ["export_version": 1, "schema_version": try schemaVersion(), "exported_at": Date.now.iso]
        for t in tables { out[t] = try db.run("SELECT * FROM \(t)").map { $0.mapValues(\.json) } }
        try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
}

extension Optional where Wrapped == String {
    var sql: SQLValue { map { .text($0) } ?? .null }
}

extension Optional where Wrapped == Int {
    var sql: SQLValue { map { .int(Int64($0)) } ?? .null }
}
