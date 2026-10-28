import Foundation

/// A daily copy of the database in `Backups/` (DR-18).
public struct LedgerSnapshot: Sendable, Hashable, Identifiable {
    public var url: URL
    /// The local day it was taken, YYYY-MM-DD.
    public var day: String
    public var bytes: Int64
    public var id: String { day }
}

extension Ledger {
    /// Trash keeps an entry this long (DR-15).
    public static let trashDays = 30
    /// Daily snapshots kept (DR-18).
    public static let snapshotsKept = 7

    // MARK: Delete for good

    /// Deletes the entries and everything derived from them: layout, verdicts, readings, memories, questions asked of
    /// them and the day readings that quote them. A media file goes only when no entry left, live or trashed, duplicates
    /// included, still uses it (DR-12). A copy whose source goes keeps its own life as an original; a commitment made
    /// from an entry stays the person's, unlinked. Returns how many entries went.
    @discardableResult
    public func hardDelete(ids: [String]) throws -> Int {
        let ids = Array(Set(ids))
        guard !ids.isEmpty else { return 0 }
        let marks = ids.map { _ in "?" }.joined(separator: ",")
        let args = ids.map { SQLValue.text($0) }
        let doomed = try db.run("SELECT id, local_day, media_id FROM entry WHERE id IN (\(marks))", args)
        guard !doomed.isEmpty else { return 0 }
        var files: [URL] = []
        try db.transaction {
            try db.exec("PRAGMA defer_foreign_keys=ON")
            for r in doomed {
                guard let id = r.str("id"), let day = r.str("local_day") else { continue }
                try db.run("DELETE FROM insight_snapshot WHERE kind IN ('day_reading','letter') AND from_day=? AND payload LIKE ?",
                           [.text(day), .text("%\"\(id)\"%")])
            }
            try db.run("DELETE FROM observation_retraction WHERE observation_id IN (SELECT id FROM observation WHERE entry_id IN (\(marks)))", args)
            for table in ["observation", "ai_run_input", "entry_annotation", "safety_verdict", "card_layout", "reflection_turn"] {
                try db.run("DELETE FROM \(table) WHERE entry_id IN (\(marks))", args)
            }
            try db.run("UPDATE commitment SET source_entry_id=NULL, updated_at=? WHERE source_entry_id IN (\(marks))", [.text(Date.now.iso)] + args)
            try db.run("UPDATE entry SET duplicated_from_id=NULL WHERE duplicated_from_id IN (\(marks)) AND id NOT IN (\(marks))", args + args)
            try db.run("DELETE FROM entry WHERE id IN (\(marks))", args)
            for media in Set(doomed.compactMap { $0.str("media_id") }) {
                guard try db.run("SELECT 1 FROM entry WHERE media_id=? LIMIT 1", [.text(media)]).isEmpty,
                      let m = try db.run("SELECT file_name, poster_file FROM media_asset WHERE id=?", [.text(media)]).first else { continue }
                try db.run("DELETE FROM transcript_word WHERE media_id=?", [.text(media)])
                try db.run("DELETE FROM media_asset WHERE id=?", [.text(media)])
                files += [m.str("file_name"), m.str("poster_file")].compactMap { $0 }.map { mediaURL.appending(path: $0) }
            }
        }
        // After the commit: a file is never gone while its row could still roll back.
        for f in files { try? FileManager.default.removeItem(at: f) }
        return doomed.count
    }

    /// Deletes for good what has been in Trash for 30 days (DR-15).
    @discardableResult
    public func purgeTrash(now: Date) throws -> Int {
        let cutoff = now.addingTimeInterval(-Double(Self.trashDays) * 86_400)
        let ids = try trashed().filter { ($0.trashedAt ?? .distantFuture) <= cutoff }.map(\.id)
        return try hardDelete(ids: ids)
    }

    /// When a trashed entry leaves for good.
    public static func expiry(trashedAt: Date) -> Date { trashedAt.addingTimeInterval(Double(trashDays) * 86_400) }

    // MARK: Snapshots (DR-18)

    /// Once per local day, a compacted copy of the database as `Backups/saro-YYYY-MM-DD.sqlite`, keeping the newest 7.
    /// Returns the new snapshot, or nil when today's is already there.
    @discardableResult
    public func dailySnapshot(now: Date) throws -> URL? {
        let fm = FileManager.default
        try fm.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        let url = backupsURL.appending(path: "saro-\(LocalDay.string(for: now)).sqlite")
        defer { for old in Self.snapshots(in: backupsURL).dropFirst(Self.snapshotsKept) { try? fm.removeItem(at: old.url) } }
        guard !fm.fileExists(atPath: url.path) else { return nil }
        // Written beside it and moved in, so a half-written copy never looks like a snapshot.
        let partial = backupsURL.appending(path: ".partial-\(UUID().uuidString).sqlite")
        try db.exec("VACUUM INTO '\(partial.path.replacingOccurrences(of: "'", with: "''"))'")
        try fm.moveItem(at: partial, to: url)
        return url
    }

    /// This journal's snapshots, newest first.
    public nonisolated func snapshots() -> [LedgerSnapshot] { Self.snapshots(in: backupsURL) }

    /// The snapshots under a journal folder that may not open, newest first.
    public static func snapshots(root: URL = defaultRoot) -> [LedgerSnapshot] {
        snapshots(in: root.appending(path: "Backups", directoryHint: .isDirectory))
    }

    static func snapshots(in dir: URL) -> [LedgerSnapshot] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.compactMap { name -> LedgerSnapshot? in
            guard name.hasPrefix("saro-"), name.hasSuffix(".sqlite") else { return nil }
            let day = String(name.dropFirst(5).dropLast(7))
            guard LocalDay.isValid(day) else { return nil }
            let url = dir.appending(path: name)
            return LedgerSnapshot(url: url, day: day, bytes: size(of: url) ?? 0)
        }
        .sorted { $0.day > $1.day }
    }

    /// Puts a snapshot in place of the journal's database, before a Ledger opens it. The database it replaces, with its
    /// write-ahead log, is kept in `Backups/replaced-<time>/`, so a restore never loses anything. Media files stay.
    public static func restore(snapshot: URL, root: URL = defaultRoot) throws {
        let fm = FileManager.default
        let aside = root.appending(path: "Backups/replaced-\(Int(Date.now.timeIntervalSince1970))", directoryHint: .isDirectory)
        try fm.createDirectory(at: aside, withIntermediateDirectories: true)
        for name in ["saro.sqlite", "saro.sqlite-wal", "saro.sqlite-shm"] {
            let file = root.appending(path: name)
            if fm.fileExists(atPath: file.path) { try fm.moveItem(at: file, to: aside.appending(path: name)) }
        }
        try fm.copyItem(at: snapshot, to: root.appending(path: "saro.sqlite"))
    }
}
