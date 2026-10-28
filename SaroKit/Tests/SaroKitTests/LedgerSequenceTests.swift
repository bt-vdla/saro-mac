import Foundation
import Testing
@testable import SaroKit

/// SplitMix64, so a seed replays the same operation sequence.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let days = ["2026-05-01", "2026-05-02", "2026-05-03"]
private let vocabulary = ["kettle", "rain", "bus", "fern", "chai", "river", "bread", "lamp", "market", "train", "Ravi", "café"]
private let blanks = ["", " ", "\n\t", "\r\n "]
private let verdictKinds = ["clear", "technical_hold", "safety_hold", "unavailable_clear", "unavailable_caution"]
private let statuses = [ProcessingStatus.recording, ProcessingStatus.pending, ProcessingStatus.transcribing, ProcessingStatus.transcriptUnavailable,
                        ProcessingStatus.gating, ProcessingStatus.reading, ProcessingStatus.done, ProcessingStatus.failed]

/// What the ledger should hold, kept alongside it.
private struct Model {
    var order: [String] = []
    var entries: [String: Entry] = [:]
    var batchOf: [String: String] = [:]
    var batches: [String] = []
    var verdicts: [String: [(verdict: String, sha: String, version: String)]] = [:]
    /// Input hashes of the entry's readings, oldest first; a safety hold empties it.
    var readings: [String: [String]] = [:]
    var layouts: Set<String> = []
    var undo: [String: String?] = [:]
    /// Per media: words per extractor, and extractors in the order last written (newest last).
    var transcripts: [String: (words: [String: [String]], written: [String])] = [:]

    var live: [String] { order.filter { batchOf[$0] == nil } }

    func text(_ id: String) -> String {
        guard let e = entries[id] else { return "" }
        guard let m = e.mediaId else { return e.body ?? "" }
        guard let t = transcripts[m], let newest = t.written.last else { return "" }
        return t.words[newest, default: []].joined(separator: " ")
    }

    mutating func remove(_ id: String) {
        order.removeAll { $0 == id }
        entries[id] = nil
        batchOf[id] = nil
        layouts.remove(id)
    }
}

private func phrase(_ rng: inout SplitMix64) -> String? {
    switch Int.random(in: 0..<10, using: &rng) {
    case 0: nil
    case 1, 2: blanks.randomElement(using: &rng)
    default: (0..<Int.random(in: 1...6, using: &rng)).map { _ in vocabulary.randomElement(using: &rng)! }.joined(separator: " ")
    }
}

/// Mostly one of the newest few, so single entries see long edit, gate, read and trash histories.
private func pick(_ ids: [String], _ rng: inout SplitMix64) -> String? {
    (Int.random(in: 0..<5, using: &rng) == 0 ? ids[...] : ids.suffix(6)).randomElement(using: &rng)
}

private func blank(_ s: String?) -> Bool { (s ?? "").trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r")).isEmpty }

@Test(arguments: [1, 7, 42, 2026] as [UInt64])
func randomOperationSequencesKeepTheLedgerConsistent(seed: UInt64) async throws {
    let l = try tempLedger()
    var rng = SplitMix64(state: seed)
    var m = Model()
    for step in 0..<500 {
        let roll = m.order.isEmpty ? 0 : Int.random(in: 0..<100, using: &rng)
        let op: String
        switch roll {
        case 0..<14:
            op = "insert page"
            let title = Int.random(in: 0..<4, using: &rng) == 0 ? phrase(&rng) : nil
            let e = Entry(id: "e\(step)", kind: .reflection, titleUser: title, body: phrase(&rng), localDay: days.randomElement(using: &rng))
            try await l.insertEntry(e)
            m.order.append(e.id)
            m.entries[e.id] = e
        case 14..<20:
            op = "insert voice"
            let media = MediaAsset(id: "m\(step)", fileName: "voice/m\(step).mov", kind: .audio, origin: "recorded", state: "ready")
            try await l.insertMedia(media)
            let e = Entry(id: "e\(step)", kind: .voice, localDay: days.randomElement(using: &rng), mediaId: media.id)
            try await l.insertEntry(e)
            m.order.append(e.id)
            m.entries[e.id] = e
            m.transcripts[media.id] = ([:], [])
        case 20..<32:
            op = "edit"
            let id = pick(m.order, &rng)!
            let before = try #require(try await l.entry(id))
            // Now and then an Undo, back to the text before the last edit.
            let body = before.kind == .voice ? before.body : Int.random(in: 0..<3, using: &rng) == 0 ? m.undo[id] ?? before.body : phrase(&rng)
            let title = Int.random(in: 0..<3, using: &rng) == 0 ? phrase(&rng) : before.titleUser
            try await l.updateEntryText(id: id, body: body, titleUser: title, captionUser: before.captionUser)
            m.undo[id] = before.body
            m.entries[id]?.body = body
            m.entries[id]?.titleUser = title
            let expected = before.kind == .voice || before.body == body ? before.processingStatus
                : (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ProcessingStatus.done : ProcessingStatus.pending
            #expect(try await l.entry(id)?.processingStatus == expected, "seed \(seed) step \(step): edit status")
        case 32..<40:
            op = "trash"
            let ids = (0..<Int.random(in: 1...3, using: &rng)).map { _ in pick(m.order, &rng)! }
            let batch = try await l.trash(ids)
            m.batches.append(batch)
            for id in ids where m.batchOf[id] == nil { m.batchOf[id] = batch }
        case 40..<46:
            op = "restore batch"
            guard let batch = m.batches.randomElement(using: &rng) else { continue }
            try await l.restore(batch: batch)
            for (id, b) in m.batchOf where b == batch { m.batchOf[id] = nil }
        case 46..<50:
            op = "restore ids"
            let ids = (0..<Int.random(in: 1...2, using: &rng)).map { _ in pick(m.order, &rng)! }
            try await l.restore(ids: ids)
            for id in ids { m.batchOf[id] = nil }
        case 50..<62:
            op = "verdict"
            let id = pick(m.order, &rng)!
            let sha = Int.random(in: 0..<4, using: &rng) == 0 ? "stale-\(step)" : sha256(m.text(id))
            let version = Int.random(in: 0..<5, using: &rng) == 0 ? "2" : "1"
            try await gate(l, &m, id, sha: sha, version: version, verdictKinds.randomElement(using: &rng)!, at: "seed \(seed) step \(step)")
        case 62..<74:
            // As the pipeline does: gate unless a cached verdict covers this text (restating it if an older one), then read
            // what the verdict lets through.
            op = "process"
            guard let id = pick(m.live, &rng) else { continue }
            let text = m.text(id), sha = sha256(text)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let cached = try await l.cachedVerdict(entryId: id, textSha256: sha, safetyVersion: "1")
            var v = cached?.verdict
            if let cached, try await l.verdicts(day: m.entries[id]!.localDay)[id]?.id != cached.id {
                // Text edited back to a version gated before: the pipeline restates that verdict as the newest.
                try await gate(l, &m, id, sha: sha, version: "1", cached.verdict, at: "seed \(seed) step \(step)")
            }
            if v == nil {
                let gated = Int.random(in: 0..<3, using: &rng) == 0 ? verdictKinds.randomElement(using: &rng)! : "clear"
                try await gate(l, &m, id, sha: sha, version: "1", gated, at: "seed \(seed) step \(step)")
                v = gated
            }
            // The day's state reads the newest verdict, so it has to be this text's (dayStatus compares the hash).
            #expect(try await l.verdicts(day: m.entries[id]!.localDay)[id]?.textSha256 == sha, "seed \(seed) step \(step): newest verdict is for the gated text")
            guard v == "clear" || v == "unavailable_clear", try await !l.hasAnnotation(entryId: id, inputHash: sha) else { break }
            var run = AIRun(feature: "entry_reading", executor: "heuristic", status: "ok")
            run.id = "r\(step)"
            run.inputHash = sha
            try await l.insertRun(run, inputs: [AIRunInput(entryId: id, field: m.entries[id]!.kind == .voice ? "transcript" : "body", text: text)])
            var a = EntryAnnotation(entryId: id, aiRunId: run.id, generator: "heuristic")
            a.title = "Reading \(step)"
            try await l.insertAnnotation(a)
            m.readings[id, default: []].append(sha)
        case 74..<82:
            op = "discard"
            let id = pick(m.order, &rng)!
            try await l.discardIfEmpty(id)
            let e = m.entries[id]!
            if e.mediaId == nil, blank((e.body ?? "") + (e.titleUser ?? "") + (e.captionUser ?? "")),
               m.verdicts[id, default: []].isEmpty, m.readings[id, default: []].isEmpty {
                m.remove(id)
            }
        case 82..<88:
            op = "layout"
            let ids = Array(Set((0..<Int.random(in: 1...3, using: &rng)).map { _ in pick(m.order, &rng)! })).sorted()
            try await l.setLayouts(ids.map {
                CardLayout(entryId: $0, x: Double(Int.random(in: -500...500, using: &rng)), y: Double(Int.random(in: -500...500, using: &rng)),
                           z: Int.random(in: 0...9, using: &rng), userPlaced: Bool.random(using: &rng))
            })
            m.layouts.formUnion(ids)
        case 88..<94:
            // A pass finishing for text that may have been edited since it began.
            op = "pass status"
            let id = pick(m.order, &rng)!
            let pass = try #require(try await l.entry(id))
            let editedSince = pass.kind == .reflection && Bool.random(using: &rng)
            if editedSince {
                let body = (pass.body ?? "") + " " + vocabulary.randomElement(using: &rng)!
                try await l.updateEntryText(id: id, body: body, titleUser: pass.titleUser, captionUser: nil)
                m.entries[id]?.body = body
            }
            let status = statuses.randomElement(using: &rng)!
            try await l.setProcessingStatus(status, startedFrom: pass)
            #expect(try await l.entry(id)?.processingStatus == (editedSince ? ProcessingStatus.pending : status), "seed \(seed) step \(step): pass status")
        case 94..<97:
            op = "transcript"
            guard let id = pick(m.order.filter { m.entries[$0]?.mediaId != nil }, &rng), let media = m.entries[id]?.mediaId else { continue }
            if Int.random(in: 0..<4, using: &rng) == 0 {
                try await l.clearTranscript(mediaId: media)
                m.transcripts[media] = ([:], [])
            } else {
                let version = ["sa-1", "sa-2"].randomElement(using: &rng)!
                let said = (phrase(&rng) ?? "").split(separator: " ").map(String.init)
                try await l.setTranscript(mediaId: media, words: said.enumerated().map { TranscriptWord(text: $1, startMs: $0 * 300, durMs: 250, confidence: 0.9) },
                                          extractorVersion: version)
                m.transcripts[media]!.words[version] = said
                m.transcripts[media]!.written.removeAll { $0 == version }
                if !said.isEmpty { m.transcripts[media]!.written.append(version) }
            }
            #expect(try await l.transcript(mediaId: media).map(\.text).joined(separator: " ") == m.text(id), "seed \(seed) step \(step): transcript")
        default:
            op = "snapshot"
            let day = days.randomElement(using: &rng)!
            let kind = Bool.random(using: &rng) ? "day_reading" : "letter"
            try await l.insertSnapshot(InsightSnapshot(kind: kind, day: day, aiRunId: nil, generator: "heuristic", inputHash: "\(step)", payload: "{}"))
        }
        try await expectInvariants(l, m, "seed \(seed) step \(step) after \(op)")
    }
    let url = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString).json")
    try await l.exportJSON(to: url)
    let obj = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect((obj["entry"] as? [[String: Any]])?.compactMap { $0["id"] as? String }.sorted() == m.order.sorted(), "seed \(seed): export")
}

private func gate(_ l: Ledger, _ m: inout Model, _ id: String, sha: String, version: String, _ verdict: String, at: String) async throws {
    try await l.insertVerdict(SafetyVerdictRow(entryId: id, textSha256: sha, safetyVersion: version, layer: 2, verdict: verdict, reasonCode: "fuzz"))
    m.verdicts[id, default: []].append((verdict, sha, version))
    guard verdict == "safety_hold" else { return }
    m.readings[id] = []
    let day = m.entries[id]!.localDay
    #expect(try await l.latestSnapshot(kind: "day_reading", day: day) == nil, "\(at): a hold drops its day's reading")
    #expect(try await l.latestSnapshot(kind: "letter", day: day) == nil, "\(at): a hold drops its day's letter")
}

private func expectInvariants(_ l: Ledger, _ m: Model, _ at: String) async throws {
    func scalar(_ sql: String) async throws -> Int { try await l.run(sql).first?["n"]?.int ?? -1 }
    // Trash: the live set, the trashed set and their batches are exactly what the operations left.
    #expect(try await l.allEntries().map(\.id).sorted() == m.live.sorted(), "\(at): live entries")
    let trashed = try await l.trashed()
    #expect(Dictionary(uniqueKeysWithValues: trashed.map { ($0.id, $0.trashBatchId ?? "") }) == m.batchOf, "\(at): trashed entries")
    #expect(try await scalar("SELECT COUNT(*) AS n FROM live_entry WHERE trashed_at IS NOT NULL OR trash_batch_id IS NOT NULL") == 0, "\(at): live_entry")
    #expect(try await scalar("SELECT COUNT(*) AS n FROM entry WHERE (trashed_at IS NULL) != (trash_batch_id IS NULL)") == 0, "\(at): trash columns")
    #expect(try await Set(l.days().map(\.day)) == Set(m.live.compactMap { m.entries[$0]?.localDay }), "\(at): days")
    // Keys: nothing points at a row that isn't there.
    #expect(try await l.run("PRAGMA foreign_key_check").isEmpty, "\(at): foreign keys")
    #expect(try await scalar("""
        SELECT COUNT(*) AS n FROM entry_annotation a LEFT JOIN entry e ON e.id = a.entry_id LEFT JOIN ai_run r ON r.id = a.ai_run_id
        WHERE e.id IS NULL OR r.id IS NULL
        """) == 0, "\(at): orphan annotations")
    #expect(try await Set(l.run("SELECT entry_id FROM card_layout").compactMap { $0.str("entry_id") }) == m.layouts, "\(at): layouts")
    let known = Set(statuses)
    let rows = try await l.allEntries(includeTrashed: true)
    #expect(rows.allSatisfy { known.contains($0.processingStatus) }, "\(at): processing_status")
    #expect(try await l.unfinishedEntries().map(\.id).sorted()
        == rows.filter { $0.trashedAt == nil && ![ProcessingStatus.done, ProcessingStatus.failed].contains($0.processingStatus) }.map(\.id).sorted(),
        "\(at): unfinished entries")
    // SR-15: an entry whose newest verdict is a safety hold keeps no reading.
    #expect(try await scalar("""
        SELECT COUNT(*) AS n FROM entry_annotation a JOIN safety_verdict v ON v.entry_id = a.entry_id
        WHERE v.rowid = (SELECT MAX(rowid) FROM safety_verdict WHERE entry_id = a.entry_id) AND v.verdict = 'safety_hold'
        """) == 0, "\(at): reading kept under a safety hold")
    // Newest wins, matched by text hash.
    var waiting: [String] = []
    for day in days {
        let verdicts = try await l.verdicts(day: day)
        let annotations = try await l.annotations(day: day)
        for id in m.order where m.entries[id]?.localDay == day {
            let newest = m.verdicts[id]?.last
            #expect(verdicts[id]?.verdict == newest?.verdict && verdicts[id]?.textSha256 == newest?.sha, "\(at): newest verdict of \(id)")
            #expect((annotations[id] != nil) == !(m.readings[id] ?? []).isEmpty, "\(at): newest reading of \(id)")
            let sha = sha256(m.text(id))
            #expect(try await l.hasAnnotation(entryId: id, inputHash: sha) == (m.readings[id]?.last == sha), "\(at): hasAnnotation \(id)")
            if let newest {
                let cached = try await l.cachedVerdict(entryId: id, textSha256: newest.sha, safetyVersion: newest.version)
                #expect(cached?.verdict == newest.verdict, "\(at): cachedVerdict of \(id)")
                if m.batchOf[id] == nil, newest.verdict.hasPrefix("unavailable") { waiting.append(id) }
            }
        }
    }
    #expect(try await l.entryIDs(withLatestVerdictIn: ["unavailable_clear", "unavailable_caution"]).sorted() == waiting.sorted(), "\(at): waiting entries")
}
