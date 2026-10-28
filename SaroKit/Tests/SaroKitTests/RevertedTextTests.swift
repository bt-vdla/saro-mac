import Foundation
import Testing
@testable import SaroKit

// Synthetic text only (SR-28). Found by the app's scenario run (Saro/Dev/Scenarios.swift): a page or still note edited
// back to text gated earlier reused that verdict from the cache, but the newest verdict, which every reader takes,
// stayed the one for the text in between.

/// Clear, then held, then the held line taken out: the day reads again, and nothing is stored under a stale hold.
@Test func textEditedBackToAClearVersionIsClearAgain() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: answers())
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    try await l.updateEntryText(id: e.id, body: chai + " Some nights I just want to die.", titleUser: nil)
    await p.process(entryId: e.id) {}
    #expect(await p.dayStatus(e.localDay) == .held)

    try await l.updateEntryText(id: e.id, body: chai, titleUser: nil)
    await p.process(entryId: e.id) {}
    let v = try await l.verdicts(day: e.localDay)[e.id]
    #expect(v?.verdict == "clear" && v?.textSha256 == sha256(chai))
    #expect(try await l.hasAnnotation(entryId: e.id, inputHash: sha256(chai)))
    #expect(await p.dayStatus(e.localDay) == .ready)
}

/// Held, then rewritten clear and read, then the held text put back: held again, and the clear reading goes (SR-15).
@Test func textEditedBackToAHeldVersionIsHeldAgain() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: answers())
    let held = "Some nights I just want to die."
    let e = Entry(kind: .still, captionUser: held, processingStatus: ProcessingStatus.done)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    try await l.updateEntryText(id: e.id, body: nil, titleUser: nil, captionUser: chai)
    await p.process(entryId: e.id) {}
    #expect(await p.readDay(e.localDay) != nil)

    try await l.updateEntryText(id: e.id, body: nil, titleUser: nil, captionUser: held)
    await p.process(entryId: e.id) {}
    #expect(try await l.verdicts(day: e.localDay)[e.id]?.verdict == "safety_hold")
    #expect(try await l.annotations(day: e.localDay).isEmpty)
    #expect(await p.dayStatus(e.localDay) == .held)
    #expect(try await l.run("SELECT COUNT(*) AS n FROM insight_snapshot").first?["n"]?.int == 0)
}
