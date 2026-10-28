import Foundation
import Testing
@testable import SaroKit

// Synthetic text only (SR-28). These cases resolve at layer 1 or before the gate, so no model call runs.

@Test func phraseHitHoldsEntryAndDay() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: SaroAI())
    let e = Entry(kind: .reflection, body: "Some nights I just want to die and not wake up.")
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    let v = try await l.verdicts(day: e.localDay)[e.id]
    #expect(v?.verdict == "safety_hold" && v?.layer == 1)
    #expect(try await l.annotations(day: e.localDay).isEmpty)
    #expect(try await l.entry(e.id)?.processingStatus == ProcessingStatus.done)
    #expect(await p.dayStatus(e.localDay) == .held)
    #expect(await p.readDay(e.localDay) == nil)
    #expect(try await l.run("SELECT COUNT(*) AS n FROM insight_snapshot").first?["n"]?.int == 0)
}

@Test func verdictIsCachedByTextHash() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: SaroAI())
    let e = Entry(kind: .reflection, body: "I want to kill myself.")
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    await p.process(entryId: e.id) {}
    #expect(try await l.run("SELECT COUNT(*) AS n FROM safety_verdict").first?["n"]?.int == 1)
}

@Test func emptyAndTrashedEntriesAreSkipped() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: SaroAI())
    let empty = Entry(kind: .reflection, body: "  ")
    let trashed = Entry(kind: .reflection, body: "I want to die.")
    try await l.insertEntry(empty)
    try await l.insertEntry(trashed)
    try await l.trash([trashed.id])
    await p.process(entryId: empty.id) {}
    await p.process(entryId: trashed.id) {}
    #expect(try await l.run("SELECT COUNT(*) AS n FROM safety_verdict").first?["n"]?.int == 0)
    #expect(try await l.entry(empty.id)?.processingStatus == ProcessingStatus.done)
}

@Test func unfinishedTranscriptHoldsTheDay() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: SaroAI())
    var e = Entry(kind: .moment)
    e.processingStatus = ProcessingStatus.transcriptUnavailable
    try await l.insertEntry(e)
    #expect(await p.dayStatus(e.localDay) == .awaitingCheck)
    try await l.setProcessingStatus(id: e.id, ProcessingStatus.transcribing)
    #expect(await p.dayStatus(e.localDay) == .working)
}

@Test func editedTextHoldsTheDayUntilRegated() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: SaroAI())
    let e = Entry(kind: .reflection, body: "I want to die.")
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    // The newest verdict was made for other text; editing the body must not count as checked.
    try await l.updateEntryText(id: e.id, body: "A quiet walk home.", titleUser: nil)
    #expect(await p.dayStatus(e.localDay) == .working)
    #expect(await p.readDay(e.localDay) == nil)
}

@Test func missingMediaFailsInsteadOfWaiting() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: SaroAI())
    let m = MediaAsset(fileName: "x/part-1.mov", kind: .video, origin: "recorded", state: "missing")
    try await l.insertMedia(m)
    var e = Entry(kind: .moment, mediaId: m.id)
    e.processingStatus = ProcessingStatus.pending
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    #expect(try await l.entry(e.id)?.processingStatus == ProcessingStatus.failed)
    #expect(await p.dayStatus(e.localDay) == .empty)
}
