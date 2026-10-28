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
