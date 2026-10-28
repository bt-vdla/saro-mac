import Foundation

/// What Settings → Your data shows of the journal's weight (exportBook.ts summarizeStorage): by kind, each shared file
/// counted once, Trash's share said apart, plus the database and backups.
public struct StorageSummary: Sendable, Hashable {
    public struct Item: Sendable, Hashable {
        public var entryId: String
        public var kind: EntryKind
        public var day: String
        public var bytes: Int64
        /// The media file; entries sharing one (a duplicate) weigh it once.
        public var file: String?
        public var inTrash = false
        /// A copy from Duplicate To, which isn't counted (FR-DAY-07).
        public var duplicate = false

        public init(entryId: String, kind: EntryKind, day: String, bytes: Int64, file: String? = nil, inTrash: Bool = false, duplicate: Bool = false) {
            self.entryId = entryId
            self.kind = kind
            self.day = day
            self.bytes = bytes
            self.file = file
            self.inTrash = inTrash
            self.duplicate = duplicate
        }
    }

    public struct Kind: Sendable, Hashable {
        public var kind: EntryKind
        public var count: Int
        public var bytes: Int64
    }

    public static let order: [EntryKind] = [.moment, .voice, .still, .reflection, .music]

    public var kinds: [Kind]
    public var totalBytes: Int64
    public var trashBytes: Int64
    public var databaseBytes: Int64 = 0
    public var backupsBytes: Int64 = 0
    /// The heaviest live entries, heaviest first: where a space saver starts.
    public var largest: [Item] = []

    public init(items: [Item]) {
        var kinds = Self.order.map { Kind(kind: $0, count: 0, bytes: 0) }
        var seen = Set<String>()
        var trash: Int64 = 0
        // Live entries first, so a file shared with a trashed copy counts as live.
        for item in items.sorted(by: { !$0.inTrash && $1.inTrash }) {
            guard let i = kinds.firstIndex(where: { $0.kind == item.kind }) else { continue }
            if !item.inTrash && !item.duplicate { kinds[i].count += 1 }
            if let file = item.file, !seen.insert(file).inserted { continue }
            let bytes = max(0, item.bytes)
            kinds[i].bytes += bytes
            if item.inTrash { trash += bytes }
        }
        self.kinds = kinds
        totalBytes = kinds.reduce(0) { $0 + $1.bytes }
        trashBytes = trash
        largest = Array(items.filter { !$0.inTrash && $0.file != nil }.sorted { $0.bytes > $1.bytes }.prefix(5))
    }
}

/// What an import added.
public struct ImportSummary: Sendable, Hashable {
    public var rows = 0
    public var files = 0
}

public struct ImportError: Error, LocalizedError {
    public let errorDescription: String?
}

extension Ledger {
    public nonisolated var backupsURL: URL { rootURL.appending(path: "Backups", directoryHint: .isDirectory) }

    // MARK: Storage

    public func storageSummary() throws -> StorageSummary {
        let rows = try db.run("""
            SELECT e.id, e.kind, e.local_day, e.trashed_at, e.duplicated_from_id, e.title_user, e.body, e.caption_user, m.file_name, m.bytes,
                   m.poster_file
            FROM entry e LEFT JOIN media_asset m ON m.id = e.media_id
            """)
        let items = rows.map { r -> StorageSummary.Item in
            let kind = EntryKind(rawValue: r.str("kind") ?? "") ?? .reflection
            let text = Int64(((r.str("title_user") ?? "") + (r.str("body") ?? "") + (r.str("caption_user") ?? "")).utf8.count)
            var bytes = text
            if let file = r.str("file_name") {
                bytes += Self.size(of: mediaURL.appending(path: file)) ?? Int64(r.int("bytes") ?? 0)
                if let poster = r.str("poster_file") { bytes += Self.size(of: mediaURL.appending(path: poster)) ?? 0 }
            }
            return .init(entryId: r.str("id") ?? "", kind: kind, day: r.str("local_day") ?? "", bytes: bytes, file: r.str("file_name"),
                         inTrash: r.str("trashed_at") != nil, duplicate: r.str("duplicated_from_id") != nil)
        }
        var summary = StorageSummary(items: items)
        summary.databaseBytes = ["saro.sqlite", "saro.sqlite-wal", "saro.sqlite-shm"].compactMap { Self.size(of: rootURL.appending(path: $0)) }.reduce(0, +)
        summary.backupsBytes = Self.treeSize(backupsURL)
        return summary
    }

    static func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    static func treeSize(_ dir: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }.reduce(0) { $0 + Int64($1) }
    }

    // MARK: Rhythm

    /// When the person wrote or recorded on each of the last `days` local days (not music: that isn't a reflection; nor a
    /// duplicate, which wasn't written then).
    public func entryTimes(days: Int = Rhythm.windowDays, today: String = LocalDay.today()) throws -> [Rhythm.EntryTime] {
        try db.run("""
            SELECT local_day, captured_at, tz_id FROM live_entry
            WHERE kind IN ('moment','voice','reflection','still') AND duplicated_from_id IS NULL AND local_day >= ?
            """, [.text(LocalDay.adding(-(days - 1), to: today))])
            .compactMap { r in
                guard let day = r.str("local_day"), let at = r.date("captured_at") else { return nil }
                return Rhythm.EntryTime(localDay: day, capturedAt: at, tzId: r.str("tz_id") ?? TimeZone.current.identifier)
            }
    }

    // MARK: What Saro read

    /// Every ai_run, newest first, with how many entries and characters it read; never the text.
    public func aiLog(offset: Int = 0, limit: Int = 20) throws -> [AILog.Row] {
        try db.run("""
            SELECT r.id, r.feature, r.executor, r.ladder_rung, r.status, r.latency_ms, r.local_day, r.created_at,
              (SELECT group_concat(entry_id) FROM (SELECT DISTINCT entry_id FROM ai_run_input WHERE ai_run_id = r.id)) AS entry_ids,
              (SELECT COALESCE(SUM(utf16_to - utf16_from), 0) FROM ai_run_input WHERE ai_run_id = r.id) AS chars
            FROM ai_run r ORDER BY r.created_at DESC, r.rowid DESC LIMIT ? OFFSET ?
            """, [.int(Int64(limit)), .int(Int64(offset))])
            .map { r in
                AILog.Row(id: r.str("id") ?? "", at: r.date("created_at") ?? .distantPast, feature: r.str("feature") ?? "",
                          executor: r.str("executor") ?? "heuristic", rung: r.str("ladder_rung"), status: r.str("status") ?? "ok",
                          latencyMs: r.int("latency_ms"), localDay: r.str("local_day"),
                          entryIds: (r.str("entry_ids") ?? "").split(separator: ",").map(String.init), chars: r.int("chars") ?? 0)
            }
    }

    public func aiRunCount() throws -> Int { try db.run("SELECT COUNT(*) AS n FROM ai_run").first?.int("n") ?? 0 }

    // MARK: Book

    /// The person's words for one year, by day, and the letters they kept on days that were never held (SR-13).
    /// Titles are only the person's own; Saro's titles and summaries never appear.
    public func bookDays(year: Int) throws -> [Book.Day] {
        let prefix = "\(year)-"
        var days: [String: [Book.Piece]] = [:]
        for e in try db.run("SELECT * FROM live_entry WHERE local_day LIKE ? ORDER BY captured_at", [.text(prefix + "%")]).map(Entry.init) {
            let minutes = Rhythm.EntryTime(localDay: e.localDay, capturedAt: e.capturedAt, tzId: e.tzId).minutes
            let piece: Book.Piece? = switch e.kind {
            case .reflection: Book.Piece(kind: .reflection, minutes: minutes, title: e.titleUser, body: Book.paragraphs(e.body))
            case .still: Book.Piece(kind: .still, minutes: minutes, title: e.titleUser, body: Book.paragraphs(e.captionUser))
            case .moment, .voice:
                Book.Piece(kind: e.kind == .moment ? .moment : .echo, minutes: minutes, title: e.titleUser,
                           prompt: try db.run("SELECT question FROM reflection_turn WHERE entry_id=? AND kind='prompt' LIMIT 1", [.text(e.id)]).first?.str("question"),
                           body: Book.paragraphs(try e.mediaId.map { Pipeline.join(try transcript(mediaId: $0)) }))
            case .music: nil
            }
            if let piece { days[e.localDay, default: []].append(piece) }
        }
        let held = Set(try db.run("""
            SELECT e.local_day AS d FROM safety_verdict v JOIN live_entry e ON e.id = v.entry_id
            WHERE v.rowid = (SELECT MAX(rowid) FROM safety_verdict WHERE entry_id = v.entry_id) AND v.verdict = 'safety_hold'
            UNION SELECT local_day AS d FROM reflection_turn WHERE answer_verdict = 'safety_hold'
            UNION SELECT local_day AS d FROM day_state WHERE mood_note_verdict = 'safety_hold'
            """).compactMap { $0.str("d") })
        // The letter the day keeps now (a rewrite unkeeps the old one), as Reflection kept it.
        for s in try db.run("""
            SELECT s.* FROM insight_snapshot s JOIN day_state d ON d.letter_kept_snapshot_id = s.id WHERE s.kind='letter' AND d.local_day LIKE ?
            """, [.text(prefix + "%")]).map(InsightSnapshot.init) where !held.contains(s.fromDay) {
            guard let letter = try? JSONDecoder().decode(Letter.self, from: Data(s.payload.utf8)) else { continue }
            days[s.fromDay, default: []].append(Book.Piece(kind: .letter, minutes: nil, body: letter.paragraphs + [letter.question].compactMap { $0 }))
        }
        return days.map { Book.Day(day: $0.key, pieces: $0.value) }
    }

    // MARK: Export and import (DR-20, FR-EXP-02)

    /// Every row of every table as JSON (`saro.json`, with this Mac's prefs beside them), and every media file, into
    /// `dir`. `progress` hears the share of media bytes copied. The copy runs off the actor, so the journal stays usable.
    public func exportEverything(to dir: URL, prefs: Data?, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [String: Any] = ["export_version": 1, "schema_version": try schemaVersion(), "exported_at": Date.now.iso]
        for t in try tableNames() { out[t] = try db.run("SELECT * FROM \(t)").map { $0.mapValues(\.json) } }
        // What Saro knows, readable (import skips it: it's derived from the rows above).
        out["memories"] = try memoriesForExport()
        if let prefs, let block = try? JSONSerialization.jsonObject(with: prefs) { out["prefs"] = block }
        try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]).write(to: dir.appending(path: "saro.json"), options: .atomic)
        try await Self.copyTreeDetached(from: mediaURL, to: dir.appending(path: "Media", directoryHint: .isDirectory), progress: progress)
    }

    /// Adds an export's rows and files to this journal. Idempotent: a row whose id is already here is kept as it is,
    /// and importing the same export twice adds nothing. A blank profile takes the export's. Media copies off the actor.
    @discardableResult
    public func importExport(from url: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> ImportSummary {
        let folder = url.pathExtension == "json" ? url.deletingLastPathComponent() : url
        let json = url.pathExtension == "json" ? url : folder.appending(path: "saro.json")
        guard let data = try? Data(contentsOf: json),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError(errorDescription: "That folder doesn’t hold a Saro export (saro.json is missing or unreadable).")
        }
        if let v = top["schema_version"] as? Int, v > (try schemaVersion()) {
            throw ImportError(errorDescription: "This export was made by a newer Saro. Update Saro, then import it.")
        }
        var summary = ImportSummary()
        let tables = try tableNames()
        try db.transaction {
            try db.exec("PRAGMA defer_foreign_keys=ON")
            try db.run("DELETE FROM profile WHERE id=1 AND name IS NULL AND called IS NULL AND onboarding_done_at IS NULL")
            for t in tables {
                guard let rows = top[t] as? [[String: Any]], !rows.isEmpty else { continue }
                let columns = Set(try db.run("PRAGMA table_info(\(t))").compactMap { $0.str("name") })
                let keyed = try !db.run("PRAGMA table_info(\(t))").filter { ($0.int("pk") ?? 0) > 0 }.isEmpty
                for row in rows {
                    let pairs = row.filter { columns.contains($0.key) }.sorted { $0.key < $1.key }.map { ($0.key, Self.sql($0.value)) }
                    guard !pairs.isEmpty else { continue }
                    let names = pairs.map(\.0)
                    // A table without a key (ai_run_input) is matched on every column instead.
                    if !keyed, try !db.run("SELECT 1 FROM \(t) WHERE " + names.map { "\($0) IS ?" }.joined(separator: " AND "), pairs.map(\.1)).isEmpty {
                        continue
                    }
                    try db.run("INSERT OR IGNORE INTO \(t) (\(names.joined(separator: ","))) VALUES (\(names.map { _ in "?" }.joined(separator: ",")))",
                               pairs.map(\.1))
                    summary.rows += try db.run("SELECT changes() AS n").first?.int("n") ?? 0
                }
            }
            // An empty profile row, so the profile reads back even when the export had none.
            try db.run("INSERT OR IGNORE INTO profile (id, created_at, updated_at) VALUES (1, ?, ?)", [.text(Date.now.iso), .text(Date.now.iso)])
            try purgeAgain()
        }
        summary.files = try await Self.copyTreeDetached(from: folder.appending(path: "Media", directoryHint: .isDirectory), to: mediaURL, progress: progress)
        return summary
    }

    /// An export can be older than this journal's holds and forgetting, and its rows come back under their own ids, so
    /// what those deleted is deleted again (SR-15, FR-MEM-03), as `insertVerdict`, `setTurnAnswer`, `setUserMood` and
    /// `forget` did.
    func purgeAgain() throws {
        let unclear = try db.run("""
            SELECT v.entry_id, v.verdict, v.created_at, e.local_day, e.trashed_at FROM safety_verdict v JOIN entry e ON e.id = v.entry_id
            WHERE v.rowid = (SELECT MAX(rowid) FROM safety_verdict WHERE entry_id = v.entry_id) AND v.verdict NOT IN ('clear','unavailable_clear')
            """)
        for r in unclear {
            guard let id = r.str("entry_id"), let day = r.str("local_day") else { continue }
            try dropMemory(entryId: id)
            guard r.str("verdict") == "safety_hold" else { continue }
            try db.run("DELETE FROM entry_annotation WHERE entry_id=?", [.text(id)])
            if r.str("trashed_at") == nil { try dropDayReadings(day); continue }
            // Its day may have been read again since it went to Trash: only what drew on it goes.
            try db.run("DELETE FROM insight_snapshot WHERE kind IN ('day_reading','letter') AND from_day=? AND created_at <= ?",
                       [.text(day), .text(r.str("created_at") ?? "")])
            try db.run("DELETE FROM insight_snapshot WHERE kind IN ('pattern','week_letter') AND EXISTS (SELECT 1 FROM json_each(payload, '$.sources') WHERE value=?)",
                       [.text(id)])
        }
        for r in try db.run("""
            SELECT local_day FROM reflection_turn WHERE answer_verdict = 'safety_hold'
            UNION SELECT local_day FROM day_state WHERE mood_note_verdict = 'safety_hold'
            """) {
            if let day = r.str("local_day") { try dropDayReadings(day) }
        }
        let forgotten = """
            SELECT id FROM observation WHERE key_sha256 IN (SELECT key_sha256 FROM memory_tombstone)
              OR created_at <= COALESCE((SELECT at FROM memory_tombstone WHERE key_sha256 = 'all'), '')
            """
        try db.run("DELETE FROM observation_retraction WHERE observation_id IN (\(forgotten))")
        try db.run("DELETE FROM observation WHERE id IN (\(forgotten))")
    }

    static func sql(_ v: Any) -> SQLValue {
        switch v {
        case let s as String: .text(s)
        case let n as NSNumber: CFNumberIsFloatType(n) ? .real(n.doubleValue) : .int(n.int64Value)
        default: .null
        }
    }

    func tableNames() throws -> [String] {
        try db.run("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").compactMap { $0.str("name") }
    }

    /// `copyTree` on a detached task: a large Media folder never holds up canvas loads or the pipeline meanwhile.
    @discardableResult
    static func copyTreeDetached(from source: URL, to dest: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> Int {
        try await Task.detached(priority: .utility) { try copyTree(from: source, to: dest, progress: progress) }.value
    }

    /// Copies every file under `source` that `dest` doesn't have yet, keeping relative paths; returns how many.
    @discardableResult
    static func copyTree(from source: URL, to dest: URL, progress: @Sendable (Double) -> Void) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        guard let walk = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        let files = walk.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        let total = max(1, files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +))
        let base = source.standardizedFileURL.path
        var done = 0, copied = 0
        for file in files {
            let relative = String(file.standardizedFileURL.path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let target = dest.appending(path: relative)
            if !fm.fileExists(atPath: target.path) {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: file, to: target)
                copied += 1
            }
            done += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            progress(Double(done) / Double(total))
        }
        progress(1)
        return copied
    }

    // MARK: Erase (DR-16)

    /// Every row of every table, every media file and every backup, gone. The database overwrites what it deletes
    /// (secure_delete) and is compacted, so nothing of the journal is left in the file either.
    public func eraseAll() throws {
        let tables = try tableNames()
        try db.transaction {
            try db.exec("PRAGMA defer_foreign_keys=ON")
            for t in tables { try db.run("DELETE FROM \(t)") }
        }
        try db.exec("PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")
        let fm = FileManager.default
        for item in (try? fm.contentsOfDirectory(at: mediaURL, includingPropertiesForKeys: nil)) ?? [] { try fm.removeItem(at: item) }
        if fm.fileExists(atPath: backupsURL.path) { try fm.removeItem(at: backupsURL) }
    }
}
