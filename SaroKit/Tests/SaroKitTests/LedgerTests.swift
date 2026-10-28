import Foundation
import Testing
@testable import SaroKit

func tempLedger() throws -> Ledger {
    try Ledger(rootURL: FileManager.default.temporaryDirectory.appending(path: "saro-test-\(UUID().uuidString)"))
}

@Test func pragmasAndSchema() async throws {
    let l = try tempLedger()
    #expect(try await l.schemaVersion() == Schema.migrations.count)
    #expect(try await l.pragma("journal_mode") == "wal")
    #expect(try await l.pragma("foreign_keys") == "1")
    #expect(try await l.pragma("secure_delete") == "1")
}

@Test func reopenDoesNotRemigrate() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "saro-test-\(UUID().uuidString)")
    let a = try Ledger(rootURL: root)
    try await a.insertEntry(Entry(kind: .reflection, body: "hello"))
    let b = try Ledger(rootURL: root)
    #expect(try await b.allEntries().count == 1)
}

@Test func appendOnlyTablesRejectUpdates() async throws {
    let l = try tempLedger()
    let e = Entry(kind: .reflection, body: "Tea with Ravi.")
    try await l.insertEntry(e)
    let run = AIRun(feature: "entry", executor: "heuristic", status: "ok")
    try await l.insertRun(run, inputs: [AIRunInput(entryId: e.id, field: "body", text: e.body!)])
    var a = EntryAnnotation(entryId: e.id, aiRunId: run.id, generator: "heuristic")
    a.title = "Tea with Ravi"
    try await l.insertAnnotation(a)
    for table in Schema.appendOnly where ["ai_run", "entry_annotation"].contains(table) {
        await #expect(throws: (any Error).self) { try await l.run("UPDATE \(table) SET id = id") }
    }
    #expect(try await l.annotations(day: e.localDay)[e.id]?.title == "Tea with Ravi")
    var hashed = AIRun(feature: "entry", executor: "heuristic", status: "ok")
    hashed.inputHash = "h1"
    try await l.insertRun(hashed)
    try await l.insertAnnotation(EntryAnnotation(entryId: e.id, aiRunId: hashed.id, generator: "heuristic"))
    #expect(try await l.hasAnnotation(entryId: e.id, inputHash: "h1"))
    #expect(try await !l.hasAnnotation(entryId: e.id, inputHash: "h2"))
}

@Test func newestAnnotationAndVerdictWin() async throws {
    let l = try tempLedger()
    let e = Entry(kind: .reflection, body: "x")
    try await l.insertEntry(e)
    let run = AIRun(feature: "entry", executor: "heuristic", status: "ok")
    try await l.insertRun(run)
    for t in ["first", "second"] {
        var a = EntryAnnotation(entryId: e.id, aiRunId: run.id, generator: "heuristic")
        a.title = t
        try await l.insertAnnotation(a)
        try await l.insertVerdict(SafetyVerdictRow(entryId: e.id, textSha256: "h", safetyVersion: "1", layer: 1, verdict: t == "first" ? "clear" : "safety_hold", reasonCode: t))
    }
    #expect(try await l.annotations(day: e.localDay)[e.id]?.title == "second")
    #expect(try await l.verdicts(day: e.localDay)[e.id]?.verdict == "safety_hold")
}

@Test func trashAndRestoreByBatch() async throws {
    let l = try tempLedger()
    let a = Entry(kind: .reflection, body: "a"), b = Entry(kind: .reflection, body: "b")
    try await l.insertEntry(a)
    try await l.insertEntry(b)
    let batch = try await l.trash([a.id, b.id])
    #expect(try await l.entries(day: a.localDay).isEmpty)
    #expect(try await l.trashed().count == 2)
    try await l.restore(batch: batch)
    #expect(try await l.entries(day: a.localDay).count == 2)
}

@Test func layoutsUpsert() async throws {
    let l = try tempLedger()
    let e = Entry(kind: .reflection, body: "a")
    try await l.insertEntry(e)
    try await l.setLayouts([CardLayout(entryId: e.id, x: 10, y: 20)])
    try await l.setLayouts([CardLayout(entryId: e.id, x: 30, y: 40, stackId: "s", userPlaced: true)])
    let got = try await l.layouts(day: e.localDay)[e.id]
    #expect(got?.x == 30 && got?.stackId == "s" && got?.userPlaced == true)
}

@Test func transcriptRoundTrip() async throws {
    let l = try tempLedger()
    let m = MediaAsset(fileName: "d/p.mov", kind: .video, origin: "recorded")
    try await l.insertMedia(m)
    try await l.setTranscript(mediaId: m.id, words: [TranscriptWord(text: "Hi", startMs: 0, durMs: 300, confidence: 0.9)], extractorVersion: "sa-1")
    #expect(try await l.transcript(mediaId: m.id).map(\.text) == ["Hi"])
}

@Test func backdatedCapture() {
    let e = Entry(kind: .reflection, localDay: "2020-01-01")
    #expect(e.backdated)
    #expect(!Entry(kind: .reflection).backdated)
    #expect(LocalDay.adding(1, to: "2026-12-31") == "2027-01-01")
}

@Test func exportIsJSON() async throws {
    let l = try tempLedger()
    try await l.insertEntry(Entry(kind: .reflection, body: "a"))
    let url = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString).json")
    try await l.exportJSON(to: url)
    let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    #expect((obj?["entry"] as? [Any])?.count == 1)
}

@Test func editedTextGoesBackToPending() async throws {
    let l = try tempLedger()
    let page = Entry(kind: .reflection, body: "Tea with Ravi.", processingStatus: ProcessingStatus.done)
    let still = Entry(kind: .still, processingStatus: ProcessingStatus.done)
    let moment = Entry(kind: .moment, processingStatus: ProcessingStatus.transcriptUnavailable)
    for e in [page, still, moment] { try await l.insertEntry(e) }
    func status(_ e: Entry) async throws -> String? { try await l.entry(e.id)?.processingStatus }
    // A title alone isn't gated text.
    try await l.updateEntryText(id: page.id, body: "Tea with Ravi.", titleUser: "Tea")
    #expect(try await status(page) == ProcessingStatus.done)
    try await l.updateEntryText(id: page.id, body: "Tea with Ravi, then rain.", titleUser: "Tea")
    #expect(try await status(page) == ProcessingStatus.pending)
    try await l.updateEntryText(id: page.id, body: " \n", titleUser: "Tea")
    #expect(try await status(page) == ProcessingStatus.done)
    try await l.updateEntryText(id: still.id, body: nil, titleUser: nil, captionUser: "The river")
    #expect(try await status(still) == ProcessingStatus.pending)
    try await l.updateEntryText(id: moment.id, body: nil, titleUser: "Walk", captionUser: "x")
    #expect(try await status(moment) == ProcessingStatus.transcriptUnavailable)
}

@Test func onlyEmptyPagesAreDiscarded() async throws {
    let l = try tempLedger()
    let empty = Entry(kind: .reflection, body: " \n"), full = Entry(kind: .reflection, body: "words")
    try await l.insertEntry(empty)
    try await l.insertEntry(full)
    try await l.setLayouts([CardLayout(entryId: empty.id, x: 0, y: 0)])
    try await l.discardIfEmpty(empty.id)
    try await l.discardIfEmpty(full.id)
    #expect(try await l.allEntries(includeTrashed: true).map(\.id) == [full.id])
}
