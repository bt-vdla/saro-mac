import Foundation
import Testing
@testable import SaroKit

// MARK: Migration v4

@Test func v4MigratesAJournalAndKeepsItsDayState() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "saro-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let db = try SQLite(path: root.appending(path: "saro.sqlite").path)
    let v4 = try #require(Schema.migrations.firstIndex(of: Schema.v4))
    for (i, sql) in Schema.migrations.prefix(v4).enumerated() {
        try db.exec(sql)
        try db.exec("PRAGMA user_version = \(i + 1)")
    }
    try db.run("INSERT INTO day_state (local_day, mood_label_user, letter_opened_at, updated_at) VALUES ('2026-10-26','Calm',?,?)",
               [.text(Date.now.iso), .text(Date.now.iso)])
    let l = try Ledger(rootURL: root)
    #expect(try await l.schemaVersion() == Schema.migrations.count)
    let s = try await l.dayState("2026-10-26")
    #expect(s.moodUser == .calm && !s.moodLocked && s.lockedMood == nil && s.letterOpenedAt != nil && s.moodNote == nil)
    #expect(try await l.commitments(day: "2026-10-26").isEmpty)
}
