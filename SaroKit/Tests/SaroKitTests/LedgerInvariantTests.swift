import Foundation
import Testing
@testable import SaroKit

private func page(_ l: Ledger, _ body: String?, day: String? = nil, title: String? = nil) async throws -> Entry {
    let e = Entry(kind: .reflection, titleUser: title, body: body, localDay: day)
    try await l.insertEntry(e)
    return e
}

private func reading(_ l: Ledger, _ e: Entry, hash: String?, title: String? = nil) async throws {
    var run = AIRun(feature: "entry_reading", executor: "heuristic", status: "ok")
    run.inputHash = hash
    try await l.insertRun(run, inputs: e.body.map { [AIRunInput(entryId: e.id, field: "body", text: $0)] } ?? [])
    var a = EntryAnnotation(entryId: e.id, aiRunId: run.id, generator: "heuristic")
    a.title = title
    try await l.insertAnnotation(a)
}

private func verdict(_ l: Ledger, _ e: Entry, _ v: String, sha: String = "h", version: String = "1") async throws {
    try await l.insertVerdict(SafetyVerdictRow(entryId: e.id, textSha256: sha, safetyVersion: version, layer: 2, verdict: v, reasonCode: "t"))
}

private func count(_ l: Ledger, _ table: String) async throws -> Int {
    try await l.run("SELECT COUNT(*) AS n FROM \(table)").first?["n"]?.int ?? -1
}

/// One row in every table, so each append-only trigger has something to refuse.
private func fillEveryTable(_ l: Ledger) async throws -> Entry {
    let m = MediaAsset(fileName: "2026-01-05/v/part-1.mov", kind: .audio, origin: "recorded", state: "ready")
    try await l.insertMedia(m)
    try await l.setTranscript(mediaId: m.id, words: [TranscriptWord(text: "Kettle", startMs: 0, durMs: 200, confidence: 0.8)], extractorVersion: "sa-1")
    let voice = Entry(kind: .voice, localDay: "2026-01-05", mediaId: m.id)
    try await l.insertEntry(voice)
    let e = try await page(l, "The kettle sang while the plants got water.", day: "2026-01-05")
    try await reading(l, e, hash: sha256(e.body!), title: "Plants")
    try await verdict(l, e, "clear")
    try await l.setLayouts([CardLayout(entryId: e.id, x: 1, y: 2)])
    let runId = try #require(try await l.runs().first?.str("id"))
    try await l.insertSnapshot(InsightSnapshot(kind: "day_reading", day: e.localDay, aiRunId: runId, generator: "heuristic", inputHash: "d", payload: "{}"))
    try await l.appendDecisionEvent(DecisionEvent(decisionId: "D-01", choice: "a", note: nil, screenId: nil, appVersion: "0.1.0"))
    try await l.appendScreenNote(ScreenNote(screenId: "canvas", note: "spacing", appVersion: "0.1.0"))
    let now = SQLValue.text(Date.now.iso)
    try await l.run("""
        INSERT INTO observation (id, entry_id, ai_run_id, source, kind, key, label, quote, field, span_start, span_end, text_sha256, local_day, created_at)
        VALUES ('o1', ?, ?, 'extractor', 'theme', 'plants', 'Plants', 'the plants got water', 'body', 22, 42, 'x', ?, ?)
        """, [.text(e.id), .text(runId), .text(e.localDay), now])
    try await l.run("INSERT INTO observation_retraction (observation_id, reason, created_at) VALUES ('o1', 'user_edited', ?)", [now])
    try await l.run("INSERT INTO day_state (local_day, updated_at) VALUES (?, ?)", [.text(e.localDay), now])
    try await l.run("INSERT INTO model_fingerprint (os_build, created_at) VALUES ('26A1', ?)", [now])
    return e
}

// MARK: Append-only (DR-05)

@Test func everyAppendOnlyTableRejectsUpdates() async throws {
    let l = try tempLedger()
    _ = try await fillEveryTable(l)
    let triggers = try await l.run("SELECT tbl_name FROM sqlite_master WHERE type='trigger' AND name LIKE '%_append_only'")
        .compactMap { $0.str("tbl_name") }
    #expect(Set(triggers) == Set(Schema.appendOnly))
    #expect(Set(["observation", "entry_annotation", "insight_snapshot", "ai_run"]).isSubset(of: Schema.appendOnly))
    for table in Schema.appendOnly {
        let before = try await l.run("SELECT * FROM \(table)")
        #expect(!before.isEmpty, "\(table) needs a row for its trigger to fire")
        do {
            try await l.run("UPDATE \(table) SET rowid = rowid")
            Issue.record("\(table) accepted an UPDATE")
        } catch {
            #expect("\(error)".contains("\(table) is append-only"))
        }
        #expect(try await l.run("SELECT * FROM \(table)") == before)
    }
    for table in ["entry", "media_asset", "card_layout", "transcript_word", "day_state", "model_fingerprint"] {
        try await l.run("UPDATE \(table) SET rowid = rowid")
    }
}

// MARK: Foreign keys

@Test func foreignKeysRejectOrphans() async throws {
    let l = try tempLedger()
    let e = try await page(l, "A slow walk by the canal.")
    let run = AIRun(feature: "entry_reading", executor: "heuristic", status: "ok")
    try await l.insertRun(run)
    let ghost = UUID().uuidString
    await #expect(throws: (any Error).self) { try await l.insertAnnotation(EntryAnnotation(entryId: ghost, aiRunId: run.id, generator: "heuristic")) }
    await #expect(throws: (any Error).self) { try await l.insertAnnotation(EntryAnnotation(entryId: e.id, aiRunId: ghost, generator: "heuristic")) }
    await #expect(throws: (any Error).self) {
        try await l.insertVerdict(SafetyVerdictRow(entryId: ghost, textSha256: "h", safetyVersion: "1", layer: 1, verdict: "clear", reasonCode: "t"))
    }
    await #expect(throws: (any Error).self) { try await l.insertEntry(Entry(kind: .voice, mediaId: ghost)) }
    await #expect(throws: (any Error).self) { try await l.setLayouts([CardLayout(entryId: ghost, x: 0, y: 0)]) }
    await #expect(throws: (any Error).self) {
        try await l.setTranscript(mediaId: ghost, words: [TranscriptWord(text: "hi", startMs: 0, durMs: 1, confidence: nil)], extractorVersion: "sa-1")
    }
    await #expect(throws: (any Error).self) {
        try await l.run("UPDATE entry SET duplicated_from_id=? WHERE id=?", [.text(ghost), .text(e.id)])
    }
    // A run whose input names a missing entry is rolled back whole.
    let orphanRun = AIRun(feature: "entry_reading", executor: "heuristic", status: "ok")
    await #expect(throws: (any Error).self) {
        try await l.insertRun(orphanRun, inputs: [AIRunInput(entryId: ghost, field: "body", text: "x")])
    }
    #expect(try await l.runs().map { $0.str("id") } == [run.id])
    #expect(try await l.run("PRAGMA foreign_key_check").isEmpty)
    #expect(try await count(l, "entry_annotation") == 0)
    #expect(try await count(l, "safety_verdict") == 0)
    #expect(try await count(l, "card_layout") == 0)
    #expect(try await count(l, "transcript_word") == 0)
}

// MARK: Trash (DR-15)

@Test func trashingTwiceKeepsTheFirstBatch() async throws {
    let l = try tempLedger()
    let a = try await page(l, "Bread rose overnight."), b = try await page(l, "Bus was late again.")
    let first = try await l.trash([a.id])
    let second = try await l.trash([a.id, b.id])
    #expect(try await l.entry(a.id)?.trashBatchId == first)
    #expect(try await l.entry(b.id)?.trashBatchId == second)
    try await l.restore(batch: second)
    #expect(try await l.allEntries().map(\.id) == [b.id])
    #expect(try await l.trashed().map(\.id) == [a.id])
    try await l.restore(batch: first)
    #expect(try await Set(l.allEntries().map(\.id)) == [a.id, b.id])
    #expect(try await l.trashed().isEmpty)
    #expect(try await l.allEntries().allSatisfy { $0.trashedAt == nil && $0.trashBatchId == nil })
}

@Test func restoringOneIdLeavesTheRestOfItsBatchInTrash() async throws {
    let l = try tempLedger()
    let a = try await page(l, "Rain on the skylight."), b = try await page(l, "Fixed the bike chain.")
    let batch = try await l.trash([a.id, b.id])
    try await l.restore(ids: [a.id])
    #expect(try await l.allEntries().map(\.id) == [a.id])
    #expect(try await l.entry(a.id)?.trashBatchId == nil)
    try await l.restore(batch: batch)
    #expect(try await l.allEntries().count == 2)
    _ = try await l.trash([])
    try await l.restore(batch: "no-such-batch")
    #expect(try await l.allEntries().count == 2)
}

@Test func trashedEntriesLeaveEveryLiveQuery() async throws {
    let l = try tempLedger()
    let day = "2026-02-03"
    let e = try await page(l, "Planted basil on the sill.", day: day)
    try await verdict(l, e, "unavailable_clear")
    #expect(try await l.unfinishedEntries().map(\.id) == [e.id])
    #expect(try await l.entryIDs(withLatestVerdictIn: ["unavailable_clear"]) == [e.id])
    try await l.trash([e.id])
    #expect(try await l.entries(day: day).isEmpty)
    #expect(try await l.allEntries().isEmpty)
    #expect(try await l.allEntries(includeTrashed: true).map(\.id) == [e.id])
    #expect(try await l.unfinishedEntries().isEmpty)
    #expect(try await l.entryIDs(withLatestVerdictIn: ["unavailable_clear"]).isEmpty)
    #expect(try await l.days().isEmpty)
    #expect(try await l.run("SELECT * FROM live_entry WHERE trashed_at IS NOT NULL").isEmpty)
}

@Test func discardKeepsAnythingWithContent() async throws {
    let l = try tempLedger()
    let blank = try await page(l, " \t\r\n"), none = try await page(l, nil)
    let gated = try await page(l, ""), read = try await page(l, "")
    try await verdict(l, gated, "clear")
    try await reading(l, read, hash: nil)
    let titled = try await page(l, "", title: "Thursday")
    let m = MediaAsset(fileName: "voice/x.mov", kind: .audio, origin: "recorded")
    try await l.insertMedia(m)
    let voice = Entry(kind: .voice, mediaId: m.id)
    try await l.insertEntry(voice)
    try await l.setLayouts([blank, none, voice].map { CardLayout(entryId: $0.id, x: 0, y: 0) })
    for e in [blank, none, gated, read, titled, voice] { try await l.discardIfEmpty(e.id) }
    try await l.discardIfEmpty(UUID().uuidString)
    #expect(try await Set(l.allEntries(includeTrashed: true).map(\.id)) == [gated.id, read.id, titled.id, voice.id])
    #expect(try await count(l, "card_layout") == 1)
    #expect(try await l.run("PRAGMA foreign_key_check").isEmpty)
}

// MARK: Transcripts

@Test func transcriptsReplacePerExtractor() async throws {
    let l = try tempLedger()
    let m = MediaAsset(fileName: "voice/t.mov", kind: .audio, origin: "recorded", state: "ready")
    try await l.insertMedia(m)
    func words(_ s: String) -> [TranscriptWord] {
        s.split(separator: " ").enumerated().map { TranscriptWord(text: String($1), startMs: $0 * 100, durMs: 90, confidence: $0 == 0 ? nil : 0.5) }
    }
    func text() async throws -> String { try await l.transcript(mediaId: m.id).map(\.text).joined(separator: " ") }
    try await l.setTranscript(mediaId: m.id, words: words("one two three"), extractorVersion: "sa-1")
    try await l.setTranscript(mediaId: m.id, words: words("uno"), extractorVersion: "sa-1")
    #expect(try await text() == "uno")
    let twelve = "a b c d e f g h i j k l"
    try await l.setTranscript(mediaId: m.id, words: words(twelve), extractorVersion: "sa-2")
    #expect(try await text() == twelve)
    #expect(try await l.transcript(mediaId: m.id).first?.confidence == nil)
    #expect(try await l.transcript(mediaId: m.id).last?.startMs == 1100)
    try await l.setTranscript(mediaId: m.id, words: words("again"), extractorVersion: "sa-1")
    #expect(try await text() == "again")
    #expect(try await count(l, "transcript_word") == 13)
    try await l.clearTranscript(mediaId: m.id)
    #expect(try await l.transcript(mediaId: m.id).isEmpty)
}

// MARK: Layouts

@Test func layoutsUpsertPerEntryAndDay() async throws {
    let l = try tempLedger()
    let a = try await page(l, "Morning pages.", day: "2026-03-01"), b = try await page(l, "Evening pages.", day: "2026-03-01")
    let other = try await page(l, "Elsewhere.", day: "2026-03-02")
    try await l.setLayouts([CardLayout(entryId: a.id, x: 1, y: 1, z: 3, stackId: "s"), CardLayout(entryId: b.id, x: 2, y: 2),
                            CardLayout(entryId: other.id, x: 9, y: 9)])
    try await l.setLayouts([CardLayout(entryId: a.id, x: -5.5, y: 7.25, z: 0, stackId: nil, userPlaced: true)])
    let got = try await l.layouts(day: "2026-03-01")
    #expect(Set(got.keys) == [a.id, b.id])
    #expect(got[a.id] == CardLayout(entryId: a.id, x: -5.5, y: 7.25, z: 0, stackId: nil, userPlaced: true))
    #expect(got[b.id] == CardLayout(entryId: b.id, x: 2, y: 2))
    #expect(try await count(l, "card_layout") == 3)
}

@Test func nonFinitePositionsAreRefusedSoExportCanRun() async throws {
    let l = try tempLedger()
    let a = try await page(l, "Lamp by the window."), b = try await page(l, "Tea gone cold.")
    try await l.setLayouts([CardLayout(entryId: a.id, x: 4, y: 4)])
    for bad in [Double.infinity, -.infinity, .nan] {
        await #expect(throws: (any Error).self) {
            try await l.setLayouts([CardLayout(entryId: a.id, x: 8, y: 8), CardLayout(entryId: b.id, x: bad, y: 0)])
        }
    }
    #expect(try await l.layouts(day: a.localDay) == [a.id: CardLayout(entryId: a.id, x: 4, y: 4)])
    let url = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString).json")
    try await l.exportJSON(to: url)
}

// MARK: Newest wins, matched by text hash

@Test func newestRowWinsEvenWhenItsClockIsBehind() async throws {
    let l = try tempLedger()
    let e = try await page(l, "Cycled to the market.")
    let run = AIRun(feature: "entry_reading", executor: "heuristic", status: "ok")
    try await l.insertRun(run)
    for (title, offset) in [("newer clock", 60.0), ("older clock", -60.0)] {
        var a = EntryAnnotation(entryId: e.id, aiRunId: run.id, generator: "heuristic")
        a.title = title
        a.createdAt = .now.addingTimeInterval(offset)
        try await l.insertAnnotation(a)
        var v = SafetyVerdictRow(entryId: e.id, textSha256: "h", safetyVersion: "1", layer: 2, verdict: offset > 0 ? "clear" : "unavailable_clear", reasonCode: title)
        v.createdAt = a.createdAt
        try await l.insertVerdict(v)
    }
    #expect(try await l.annotations(day: e.localDay)[e.id]?.title == "older clock")
    #expect(try await l.verdicts(day: e.localDay)[e.id]?.reasonCode == "older clock")
    #expect(try await l.cachedVerdict(entryId: e.id, textSha256: "h", safetyVersion: "1")?.reasonCode == "older clock")
    #expect(try await l.entryIDs(withLatestVerdictIn: ["unavailable_clear"]) == [e.id])
    #expect(try await l.entryIDs(withLatestVerdictIn: ["clear"]).isEmpty)
}

@Test func cachedVerdictMatchesEntryTextAndVersion() async throws {
    let l = try tempLedger()
    let a = try await page(l, "Watered the fern."), b = try await page(l, "Watered the fern.")
    try await verdict(l, a, "clear", sha: "s1", version: "1")
    try await verdict(l, a, "technical_hold", sha: "s2", version: "1")
    try await verdict(l, a, "unavailable_caution", sha: "s1", version: "2")
    // An older verdict for the same text still counts as cached (SR-17); the pipeline restates it as the newest.
    #expect(try await l.cachedVerdict(entryId: a.id, textSha256: "s1", safetyVersion: "1")?.verdict == "clear")
    #expect(try await l.cachedVerdict(entryId: a.id, textSha256: "s2", safetyVersion: "1")?.verdict == "technical_hold")
    #expect(try await l.cachedVerdict(entryId: a.id, textSha256: "s1", safetyVersion: "2")?.verdict == "unavailable_caution")
    #expect(try await l.cachedVerdict(entryId: a.id, textSha256: "s2", safetyVersion: "2") == nil)
    #expect(try await l.cachedVerdict(entryId: b.id, textSha256: "s1", safetyVersion: "1") == nil)
    #expect(try await l.verdicts(day: a.localDay)[a.id]?.verdict == "unavailable_caution")
    #expect(try await l.verdicts(day: a.localDay)[b.id] == nil)
}

@Test func textEditedBackToAGatedVersionDoesNotStrandTheDay() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: answers())
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    #expect(await p.dayStatus(e.localDay) == .ready)
    try await l.updateEntryText(id: e.id, body: chai + " Then the bus home.", titleUser: nil)
    await p.process(entryId: e.id) {}
    #expect(await p.dayStatus(e.localDay) == .ready)
    // Undo, back to text gated two verdicts ago.
    try await l.updateEntryText(id: e.id, body: chai, titleUser: nil)
    await p.process(entryId: e.id) {}
    #expect(try await l.verdicts(day: e.localDay)[e.id]?.textSha256 == sha256(chai))
    #expect(await p.dayStatus(e.localDay) == .ready)
    #expect(await p.readDay(e.localDay) != nil)
}

@Test func latestVerdictLookupIsPerEntry() async throws {
    let l = try tempLedger()
    let moved = try await page(l, "Notes from the train."), stuck = try await page(l, "Notes from the ferry.")
    let other = try await page(l, "Notes from the tram.")
    try await verdict(l, moved, "unavailable_clear")
    try await verdict(l, moved, "clear")
    try await verdict(l, stuck, "clear")
    try await verdict(l, stuck, "unavailable_caution")
    try await verdict(l, other, "unavailable_clear")
    let waiting = ["unavailable_clear", "unavailable_caution"]
    #expect(try await Set(l.entryIDs(withLatestVerdictIn: waiting)) == [stuck.id, other.id])
    #expect(try await l.entryIDs(withLatestVerdictIn: waiting).count == 2)
    #expect(try await l.entryIDs(withLatestVerdictIn: []).isEmpty)
    #expect(try await l.entryIDs(withLatestVerdictIn: ["safety_hold"]).isEmpty)
}

@Test func hasAnnotationLooksOnlyAtTheNewestReading() async throws {
    let l = try tempLedger()
    let e = try await page(l, "Learnt three chords."), other = try await page(l, "Learnt three chords.")
    #expect(try await !l.hasAnnotation(entryId: e.id, inputHash: "h1"))
    try await reading(l, e, hash: "h1")
    try await reading(l, e, hash: "h2")
    #expect(try await l.hasAnnotation(entryId: e.id, inputHash: "h2"))
    #expect(try await !l.hasAnnotation(entryId: e.id, inputHash: "h1"))
    #expect(try await !l.hasAnnotation(entryId: other.id, inputHash: "h2"))
    try await reading(l, e, hash: nil)
    #expect(try await !l.hasAnnotation(entryId: e.id, inputHash: "h2"))
}

@Test func safetyHoldDropsOnlyItsOwnEntryAndDay() async throws {
    let l = try tempLedger()
    let held = try await page(l, "Synthetic held text.", day: "2026-04-01")
    let sameDay = try await page(l, "Picked up groceries.", day: "2026-04-01")
    let otherDay = try await page(l, "Painted the fence.", day: "2026-04-02")
    for e in [held, sameDay, otherDay] { try await reading(l, e, hash: sha256(e.body!)) }
    for day in ["2026-04-01", "2026-04-02"] {
        try await l.insertSnapshot(InsightSnapshot(kind: "day_reading", day: day, aiRunId: nil, generator: "heuristic", inputHash: nil, payload: "{}"))
    }
    try await verdict(l, held, "safety_hold", sha: sha256(held.body!))
    #expect(try await !l.hasAnnotation(entryId: held.id, inputHash: sha256(held.body!)))
    #expect(try await l.hasAnnotation(entryId: sameDay.id, inputHash: sha256(sameDay.body!)))
    #expect(try await l.annotations(day: "2026-04-02")[otherDay.id] != nil)
    #expect(try await l.latestSnapshot(kind: "day_reading", day: "2026-04-01") == nil)
    #expect(try await l.latestSnapshot(kind: "day_reading", day: "2026-04-02") != nil)
    #expect(try await l.verdicts(day: "2026-04-01")[held.id]?.verdict == "safety_hold")
    #expect(try await l.run("SELECT * FROM safety_verdict").allSatisfy { $0.str("text_sha256")?.count == 64 })
}

@Test func annotationStoresTheQuotesHash() async throws {
    let l = try tempLedger()
    let e = try await page(l, "The bus driver waved.")
    let run = AIRun(feature: "entry_reading", executor: "heuristic", status: "ok")
    try await l.insertRun(run)
    var a = EntryAnnotation(entryId: e.id, aiRunId: run.id, generator: "heuristic")
    a.quote = "driver waved"
    try await l.insertAnnotation(a)
    try await l.insertAnnotation(EntryAnnotation(entryId: e.id, aiRunId: run.id, generator: "heuristic"))
    let rows = try await l.run("SELECT quote_sha256 FROM entry_annotation ORDER BY rowid")
    #expect(rows.map { $0.str("quote_sha256") } == [sha256("driver waved"), nil])
}

// MARK: Text and dates round-trip

@Test func entriesRoundTrip() async throws {
    let l = try tempLedger()
    let tz = try #require(TimeZone(identifier: "Asia/Kolkata"))
    let captured = Date(timeIntervalSince1970: 1_767_225_600.123)
    var originals: [Entry] = []
    for kind in EntryKind.allCases {
        let e = Entry(kind: kind, sessionId: "s", turnNumber: 2, titleUser: "Tītle ✓", captionUser: "café", body: "line one\nline two 👋🏽",
                      capturedAt: captured, timeZone: tz, localDay: "2026-01-01", processingStatus: ProcessingStatus.gating)
        try await l.insertEntry(e)
        originals.append(e)
    }
    for e in originals {
        let got = try #require(try await l.entry(e.id))
        #expect(got.kind == e.kind && got.body == e.body && got.titleUser == e.titleUser && got.captionUser == e.captionUser)
        #expect(got.tzId == "Asia/Kolkata" && got.localDay == "2026-01-01" && got.backdated == e.backdated)
        #expect(got.sessionId == "s" && got.turnNumber == 2 && got.processingStatus == ProcessingStatus.gating)
        #expect(abs(got.capturedAt.timeIntervalSince(captured)) < 0.001)
    }
}

@Test func textWithANulCharacterIsNotCut() async throws {
    let l = try tempLedger()
    let body = "before\u{0}after"
    let e = try await page(l, body)
    #expect(try await l.entry(e.id)?.body == body)
    try await l.updateEntryText(id: e.id, body: body + "\u{0}", titleUser: "a\u{0}b")
    #expect(try await l.entry(e.id)?.body == body + "\u{0}")
    #expect(try await l.entry(e.id)?.titleUser == "a\u{0}b")
    #expect(try await l.run("SELECT length(CAST(body AS BLOB)) AS n FROM entry").first?["n"]?.int == body.utf8.count + 1)
}

// MARK: Export (DR-20)

@Test func exportHasEveryTableAndEveryRow() async throws {
    let l = try tempLedger()
    let e = try await fillEveryTable(l)
    try await l.trash([e.id])
    let url = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString).json")
    try await l.exportJSON(to: url)
    let obj = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect(obj["export_version"] as? Int == 1)
    #expect(obj["schema_version"] as? Int == Schema.migrations.count)
    #expect((obj["exported_at"] as? String).flatMap { Date(iso: $0) } != nil)
    let tables = try await l.run("SELECT name FROM sqlite_master WHERE type='table'").compactMap { $0.str("name") }
    let v1 = ["media_asset", "entry", "transcript_word", "ai_run", "ai_run_input", "entry_annotation", "observation", "observation_retraction",
              "insight_snapshot", "day_state", "safety_verdict", "model_fingerprint", "card_layout", "decision_event", "screen_note"]
    #expect(Set(v1).isSubset(of: tables))
    for t in tables {
        let rows = try #require(obj[t] as? [[String: Any]], "\(t) missing from export")
        #expect(rows.count == (try await count(l, t)), "\(t)")
        #expect(!v1.contains(t) || rows.count > 0, "\(t) was filled")
    }
    let entries = try #require(obj["entry"] as? [[String: Any]])
    #expect(entries.contains { $0["id"] as? String == e.id && $0["body"] as? String == e.body && $0["trashed_at"] is String })
    #expect(entries.contains { $0["body"] is NSNull })
    #expect(!obj.keys.contains("live_entry"))
}

// MARK: Migration (DR-02)

@Test func migratesAnEmptyFileAndReopensIdempotently() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "saro-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    #expect(FileManager.default.createFile(atPath: root.appending(path: "saro.sqlite").path, contents: Data()))
    let first = try Ledger(rootURL: root)
    #expect(try await first.schemaVersion() == Schema.migrations.count)
    #expect(FileManager.default.fileExists(atPath: first.mediaURL.path))
    let e = try await fillEveryTable(first)
    func shape(_ l: Ledger) async throws -> [Row] {
        try await l.run("SELECT type, name, sql FROM sqlite_master ORDER BY type, name")
    }
    let schema = try await shape(first)
    let rows = try await first.run("SELECT COUNT(*) AS n FROM entry")
    for _ in 0..<3 {
        let again = try Ledger(rootURL: root)
        #expect(try await again.schemaVersion() == Schema.migrations.count)
        #expect(try await shape(again) == schema)
        #expect(try await again.run("SELECT COUNT(*) AS n FROM entry") == rows)
        #expect(try await again.pragma("foreign_keys") == "1")
        #expect(try await again.entry(e.id)?.body == e.body)
    }
}
