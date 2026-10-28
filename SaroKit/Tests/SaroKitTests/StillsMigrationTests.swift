import Foundation
import Testing
@testable import SaroKit

/// A journal as it stood before the stills migration (every earlier migration run), with a still, a page and a reading.
@Test func stillsMigrationAddsTagsAndQueuesEarlierStills() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "saro-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let db = try SQLite(path: root.appending(path: "saro.sqlite").path)
    let at = try #require(Schema.migrations.firstIndex(of: Schema.stills))
    for (i, sql) in Schema.migrations.prefix(at).enumerated() {
        try db.exec(sql)
        try db.exec("PRAGMA user_version = \(i + 1)")
    }
    let now = Date.now.iso
    try db.run("INSERT INTO media_asset (id, file_name, kind, origin, state, created_at, updated_at) VALUES ('m1','s.heic','image','dropped','ready',?,?)",
               [.text(now), .text(now)])
    for (id, media) in [("still", SQLValue.text("m1")), ("page", .null)] {
        try db.run("""
            INSERT INTO entry (id, kind, media_id, processing_status, captured_at, tz_id, local_day, updated_at)
            VALUES (?,?,?,'done',?,'UTC','2026-10-27',?)
            """, [.text(id), .text(id == "still" ? "still" : "reflection"), media, .text(now), .text(now)])
    }
    try db.run("INSERT INTO ai_run (id, feature, executor, status, created_at) VALUES ('r1','entry_reading','heuristic','ok',?)", [.text(now)])
    try db.run("INSERT INTO entry_annotation (id, entry_id, ai_run_id, generator, title, created_at) VALUES ('a1','page','r1','heuristic','Kept',?)",
               [.text(now)])

    let l = try Ledger(rootURL: root)
    #expect(try await l.schemaVersion() == Schema.migrations.count)
    #expect(try await l.run("PRAGMA table_info(entry_annotation)").contains { $0["name"]?.string == "tags" })
    #expect(try await l.entry("still")?.processingStatus == ProcessingStatus.pending)
    #expect(try await l.entry("page")?.processingStatus == "done")
    let kept = try #require(try await l.run("SELECT title, tags FROM entry_annotation").first)
    #expect(kept["title"]?.string == "Kept" && kept["tags"]?.string == nil)
}
