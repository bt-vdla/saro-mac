import Foundation
import Testing
@testable import SaroKit

// Synthetic text only (SR-28). Found by the app's scenario run (Saro/Dev/Scenarios.swift).

/// Trashing a day's held page frees the day to be read; putting it back must hold the day again with nothing read
/// meanwhile left stored, which Export would otherwise write out (SR-13, SR-15).
@Test(arguments: [true, false])
func restoringAHeldEntryDropsItsDaysReadings(byBatch: Bool) async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: answers())
    let clear = Entry(kind: .reflection, body: chai)
    let held = Entry(kind: .reflection, body: "Some nights I just want to die and not wake up.")
    try await l.insertEntry(clear)
    try await l.insertEntry(held)
    await p.process(entryId: clear.id) {}
    await p.process(entryId: held.id) {}
    #expect(await p.dayStatus(clear.localDay) == .held)

    let batch = try await l.trash([held.id])
    #expect(await p.dayStatus(clear.localDay) == .ready)
    #expect(await p.readDay(clear.localDay) != nil)

    if byBatch {
        #expect(try await l.restore(batch: batch) == [held.id])
    } else {
        try await l.restore(ids: [held.id])
    }
    #expect(await p.dayStatus(clear.localDay) == .held)
    #expect(try await l.run("SELECT COUNT(*) AS n FROM insight_snapshot WHERE from_day=?", [.text(clear.localDay)]).first?["n"]?.int == 0)
}

/// A clear page coming back keeps its day's reading.
@Test func restoringAClearEntryKeepsItsDaysReading() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: answers())
    let a = Entry(kind: .reflection, body: chai)
    let b = Entry(kind: .reflection, body: "Walked to the lake and back.")
    try await l.insertEntry(a)
    try await l.insertEntry(b)
    await p.process(entryId: a.id) {}
    await p.process(entryId: b.id) {}
    let batch = try await l.trash([b.id])
    #expect(await p.readDay(a.localDay) != nil)
    try await l.restore(batch: batch)
    #expect(try await l.run("SELECT COUNT(*) AS n FROM insight_snapshot WHERE from_day=?", [.text(a.localDay)]).first?["n"]?.int == 1)
}

/// Delete for good (FR-DAY-05, DR-15): the entry, every row derived from it, the questions asked of it, the readings that
/// quote it and its file go; the person's commitment stays, unlinked. A live entry and a file another entry shares stay.
@Test func purgeDeletesATrashedEntryAndEverythingDerivedFromIt() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: answers())
    let gone = Entry(kind: .reflection, body: chai)
    let kept = Entry(kind: .reflection, body: "Walked to the lake and back.")
    for e in [gone, kept] { try await l.insertEntry(e) }
    for e in [gone, kept] { await p.process(entryId: e.id) {} }
    #expect(await p.readDay(gone.localDay) != nil)
    let day = gone.localDay, now = Date.now.iso
    try await l.run("""
        INSERT INTO observation (id, entry_id, source, kind, key, key_sha256, label, quote, local_day, created_at)
        VALUES ('o1', ?, 'extractor', 'person', 'ravi', 'h', 'Ravi', 'Ravi', ?, ?)
        """, [.text(gone.id), .text(day), .text(now)])
    try await l.run("INSERT INTO observation_retraction (observation_id, reason, created_at) VALUES ('o1', 'test', ?)", [.text(now)])
    try await l.setLayouts([CardLayout(entryId: gone.id, x: 0, y: 0)])
    try await l.insertTurn(ReflectionTurn(kind: .prompt, question: "What stood out?", generator: "heuristic", localDay: day, entryId: gone.id))
    let answered = ReflectionTurn(kind: .reflectDeeper, question: "Why chai?", generator: "heuristic", localDay: day, entryId: gone.id)
    try await l.insertTurn(answered)
    try await l.setTurnAnswer(id: answered.id, answer: "Synthetic answer.", verdict: "clear")
    let promise = try #require(try await l.addCommitment("Call Ravi", day: day, sourceEntryId: gone.id))
    let copy = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(copy)
    try await l.run("UPDATE entry SET duplicated_from_id=? WHERE id=?", [.text(gone.id), .text(copy.id)])
    // Two stills share one file; a third has its own.
    let shared = MediaAsset(fileName: "\(day)/stills/shared.heic", kind: .image, origin: "test", state: "ready")
    let own = MediaAsset(fileName: "\(day)/stills/own.heic", kind: .image, origin: "test", state: "ready")
    for m in [shared, own] {
        try await l.insertMedia(m)
        try FileManager.default.createDirectory(at: l.url(for: m).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic".utf8).write(to: l.url(for: m))
    }
    let twin = Entry(kind: .still, mediaId: shared.id), twinKept = Entry(kind: .still, mediaId: shared.id)
    let still = Entry(kind: .still, mediaId: own.id)
    for e in [twin, twinKept, still] { try await l.insertEntry(e) }

    try await l.trash([gone.id, twin.id, still.id])
    #expect(try await l.hardDelete(ids: [gone.id, twin.id, still.id, kept.id]) == 3)
    func count(_ sql: String) async throws -> Int? { try await l.run(sql).first?["n"]?.int }
    for table in ["observation", "entry_annotation", "ai_run_input", "safety_verdict", "card_layout"] {
        #expect(try await count("SELECT COUNT(*) AS n FROM \(table) WHERE entry_id='\(gone.id)'") == 0, "\(table)")
    }
    #expect(try await count("SELECT COUNT(*) AS n FROM observation_retraction") == 0)
    #expect(try await count("SELECT COUNT(*) AS n FROM insight_snapshot WHERE instr(payload, '\(gone.id)') > 0") == 0)
    #expect(try await count("SELECT COUNT(*) AS n FROM reflection_turn") == 0)
    #expect(try await l.run("SELECT source_entry_id FROM commitment WHERE id=?", [.text(promise.id)]).first?.str("source_entry_id") == nil)
    #expect(try await l.run("SELECT duplicated_from_id FROM entry WHERE id=?", [.text(copy.id)]).first?.str("duplicated_from_id") == nil)
    #expect(Set(try await l.allEntries(includeTrashed: true).map(\.id)) == [kept.id, copy.id, twinKept.id])
    #expect(try await l.annotations(day: day)[kept.id] != nil)
    #expect(FileManager.default.fileExists(atPath: l.url(for: shared).path))
    #expect(!FileManager.default.fileExists(atPath: l.url(for: own).path))
    #expect(try await l.media(own.id) == nil)
    #expect(try await l.media(shared.id) != nil)
}

/// The 30-day purge (DR-15) takes only what has waited 30 days.
@Test func purgeTrashTakesOnlyEntriesTrashedBeforeTheCutoff() async throws {
    let l = try tempLedger()
    let old = Entry(kind: .reflection, body: chai), recent = Entry(kind: .reflection, body: "Walked to the lake and back.")
    for e in [old, recent] { try await l.insertEntry(e) }
    try await l.trash([old.id, recent.id])
    try await l.run("UPDATE entry SET trashed_at=? WHERE id=?", [.text(Date.now.addingTimeInterval(-31 * 86_400).iso), .text(old.id)])
    #expect(try await l.purgeTrash(now: .now) == 1)
    #expect(try await l.trashed().map(\.id) == [recent.id])
}
