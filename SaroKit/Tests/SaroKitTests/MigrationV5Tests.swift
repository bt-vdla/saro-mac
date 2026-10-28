import Foundation
import Testing
@testable import SaroKit

// MARK: Migration v5

@Test func v5RebuildsObservationKeepingRowsAndRetractions() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "saro-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let db = try SQLite(path: root.appending(path: "saro.sqlite").path)
    let v5 = try #require(Schema.migrations.firstIndex(of: Schema.v5))
    for (i, sql) in Schema.migrations.prefix(v5).enumerated() {
        try db.exec(sql)
        try db.exec("PRAGMA user_version = \(i + 1)")
    }
    let now = Date.now.iso
    try db.run("INSERT INTO entry (id, kind, captured_at, tz_id, local_day, updated_at) VALUES ('e1','reflection',?,?,?,?)",
               [.text(now), .text("UTC"), .text("2026-10-26"), .text(now)])
    try db.run("""
        INSERT INTO observation (id, entry_id, source, kind, key, label, quote, local_day, created_at)
        VALUES ('o1','e1','extractor','theme','theme:work','work','Long day at work.','2026-10-26',?)
        """, [.text(now)])
    try db.run("INSERT INTO observation_retraction (observation_id, reason, created_at) VALUES ('o1','source_edited',?)", [.text(now)])

    let l = try Ledger(rootURL: root)
    #expect(try await l.schemaVersion() == Schema.migrations.count)
    #expect(try await l.run("SELECT key_sha256 FROM observation WHERE id='o1'").first?["key_sha256"] == .text(""))
    #expect(try await l.run("SELECT COUNT(*) AS n FROM observation_retraction").first?["n"] == .int(1))
    #expect(try await l.activeObservations().isEmpty)
    #expect(try await l.run("PRAGMA foreign_key_check").isEmpty)
    // Still append-only; a user row needs no entry; an extractor row still does.
    await #expect(throws: (any Error).self) { try await l.run("UPDATE observation SET label='x'") }
    try await l.addUserMemory(MemoryObservation(entryId: nil, source: .user, kind: .line, key: "user:1", label: "I work nights.", localDay: "2026-10-26"))
    await #expect(throws: (any Error).self) {
        try await l.insertObservations([MemoryObservation(entryId: nil, kind: .theme, key: "theme:x", label: "x", quote: "x", localDay: "d")],
                                       run: AIRun(feature: "memory", executor: "heuristic", status: "ok"), inputs: [])
    }
    try await l.forget(keys: ["theme:x"])
    await #expect(throws: (any Error).self) { try await l.run("UPDATE memory_tombstone SET at='x'") }
}
