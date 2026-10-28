import Foundation
import Testing
@testable import SaroKit

// Scenarios through the LENS pipeline with a model stand-in that logs every prompt. Synthetic text only (SR-28).

actor Prompts {
    private(set) var log: [(ask: Ask, prompt: String)] = []
    func add(_ ask: Ask, _ prompt: String) { log.append((ask, prompt)) }
    func count(_ ask: Ask) -> Int { log.filter { $0.ask == ask }.count }
    func prompts(_ ask: Ask) -> [String] { log.filter { $0.ask == ask }.map(\.prompt) }
}

func logged(_ log: Prompts, status: SaroAI.Status = .available,
            _ answer: @escaping @Sendable (Ask, String) async throws -> String = echo) -> SaroAI {
    SaroAI(stub: { prompt in
        let ask: Ask = prompt.hasSuffix("Label:") ? .classify : prompt.hasPrefix("Notes on today's entries") ? .day : .entry
        await log.add(ask, prompt)
        return try await answer(ask, prompt)
    }, status: status)
}

/// Grounded replies for any text: the entry's own words back, and the day's first, middle and last listed phrases.
/// The classifier calls anything with "vanish" in it PASSIVE.
func echo(_ ask: Ask, _ prompt: String) -> String {
    switch ask {
    case .classify:
        return prompt.contains("vanish") ? "PASSIVE" : "NONE"
    case .entry:
        let text = prompt.components(separatedBy: "Entry:\n")[1].components(separatedBy: "\n\n")[0]
        let words = text.split(separator: " ").prefix(4).joined(separator: " ")
        return json(["title": words, "summary": "You wrote: \(text)", "mood": "Reflective", "moodBasis": words, "quoteIndex": 0])
    case .day:
        let listed = listedPhrases(prompt)
        let picks = [listed.first!, listed[listed.count / 2], listed.last!]
        return json(["mood": "Calm", "moodBasis": picks[0].text, "quoteIndexes": picks.map(\.index), "question": "What stayed with you?",
                     "narrative": NSNull()])
    }
}

func json(_ object: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

/// The numbered phrases a prompt lists, as `Ladder.numbered` writes them.
func listedPhrases(_ prompt: String) -> [(index: Int, text: String)] {
    prompt.split(separator: "\n").compactMap { line in
        guard let m = line.wholeMatch(of: /\[(\d+)\] "(.*)"/) else { return nil }
        return (Int(m.1)!, String(m.2))
    }
}

func rowCount(_ l: Ledger, _ table: String, _ condition: String = "1") async throws -> Int? {
    try await l.run("SELECT COUNT(*) AS n FROM \(table) WHERE \(condition)").first?["n"]?.int
}

/// Every quote sits at its span in its entry's current text, from an entry the reading drew on.
func expectVerbatim(_ payload: DayPayload, _ l: Ledger) async throws {
    for q in payload.quotes {
        let e = try #require(try await l.entry(q.entryId))
        let text = (q.field == "caption_user" ? e.captionUser : e.body) ?? ""
        #expect(payload.entryIds.contains(q.entryId))
        #expect(q.utf16To <= text.utf16.count
                && (text as NSString).substring(with: NSRange(location: q.utf16From, length: q.utf16To - q.utf16From)) == q.text,
                "\(q.text)")
    }
}

let vanishing = "Lately I keep picturing myself just vanishing and nobody noticing."

@Test func anEntryIsGatedThenRead() async throws {
    let l = try tempLedger()
    let log = Prompts()
    let p = Pipeline(ledger: l, ai: logged(log))
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}

    let v = try #require(try await l.verdicts(day: e.localDay)[e.id])
    #expect(v.verdict == "clear" && v.layer == 2 && v.reasonCode == "clear")
    #expect(v.textSha256 == sha256(chai) && v.safetyVersion == SafetyGate.version)
    let a = try #require(try await l.annotations(day: e.localDay)[e.id])
    let first = try #require(Heuristics.candidates(entryId: e.id, field: "body", text: chai).first)
    #expect(a.generator == "on_device" && a.title == "Had chai with Ravi" && a.moodLabel == "Reflective")
    #expect(a.quote == first.text && a.quoteField == "body" && a.quoteFrom == first.utf16From && a.quoteTo == first.utf16To)
    let run = try #require(try await l.run("SELECT * FROM ai_run WHERE feature='entry_reading'").first)
    #expect(run.str("executor") == "on_device" && run.str("ladder_rung") == "permissive_json" && run.str("guardrails") == "permissive")
    #expect(run.int("model_calls") == 1 && run.str("status") == "ok" && run.str("input_hash") == sha256(chai))
    #expect(run.str("prompt_version") == SaroAI.entryPromptVersion && run.str("sampling") == "greedy" && run.str("local_day") == e.localDay)
    let inputs = try await l.run("SELECT * FROM ai_run_input WHERE ai_run_id=?", [.text(run.str("id") ?? "")])
    #expect(inputs.map { $0.str("entry_id") } == [e.id] && inputs.first?.str("text_sha256") == sha256(chai))
    #expect(try await l.entry(e.id)?.processingStatus == ProcessingStatus.done)

    #expect(await p.dayStatus(e.localDay) == .ready)
    let payload = try #require(await p.readDay(e.localDay))
    #expect(payload.entryIds == [e.id] && payload.reading.question == "What stayed with you?")
    try await expectVerbatim(payload, l)
    // The gate ran before any model read the entry, and the day was read from the entry's reading.
    #expect(await log.log.map { $0.ask } == [.classify, .entry, .day])
    #expect(await log.prompts(.day).allSatisfy { $0.contains("\"Had chai with Ravi\". You wrote: \(chai)") })
}

@Test func editsAreGatedAgainAndAnEditBackReusesItsVerdict() async throws {
    let l = try tempLedger()
    let log = Prompts()
    let p = Pipeline(ledger: l, ai: logged(log))
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    #expect(await p.readDay(e.localDay) != nil)

    // An edit is unchecked until gated; layer 2 then holds it, and what was generated from the entry and its day goes (SR-15).
    try await l.updateEntryText(id: e.id, body: vanishing, titleUser: nil, captionUser: nil)
    #expect(await p.dayStatus(e.localDay) == .working)
    await p.process(entryId: e.id) {}
    let held = try await l.verdicts(day: e.localDay)[e.id]
    #expect(held?.verdict == "safety_hold" && held?.reasonCode == "classifier_passive" && held?.textSha256 == sha256(vanishing))
    #expect(try await l.annotations(day: e.localDay).isEmpty)
    #expect(await p.latestDayReading(e.localDay) == nil)
    #expect(await p.dayStatus(e.localDay) == .held)

    // Back to the first text: its cached verdict stands again with no new classifier call (SR-17), and it is read again.
    try await l.updateEntryText(id: e.id, body: chai, titleUser: nil, captionUser: nil)
    await p.process(entryId: e.id) {}
    #expect(await log.count(.classify) == 2)
    #expect(try await l.verdicts(day: e.localDay)[e.id]?.verdict == "clear")
    #expect(await p.dayStatus(e.localDay) == .ready)
    #expect(try await l.annotations(day: e.localDay)[e.id]?.generator == "on_device")
    #expect(await p.readDay(e.localDay) != nil)

    // Saving the same text again changes nothing.
    try await l.updateEntryText(id: e.id, body: chai, titleUser: nil, captionUser: nil)
    await p.process(entryId: e.id) {}
    #expect(await log.count(.classify) == 2)
    #expect(await log.count(.entry) == 2)
}

@Test func anEditBackToHeldTextIsHeldAgain() async throws {
    let l = try tempLedger()
    let log = Prompts()
    let p = Pipeline(ledger: l, ai: logged(log))
    let e = Entry(kind: .reflection, body: vanishing)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    try await l.updateEntryText(id: e.id, body: chai, titleUser: nil, captionUser: nil)
    await p.process(entryId: e.id) {}
    #expect(await p.dayStatus(e.localDay) == .ready)
    #expect(await p.readDay(e.localDay) != nil)

    // The held words come back: the hold made for them is the entry's verdict again, so the day is held, not waiting.
    try await l.updateEntryText(id: e.id, body: vanishing, titleUser: nil, captionUser: nil)
    await p.process(entryId: e.id) {}
    #expect(await log.count(.classify) == 2)
    #expect(try await l.verdicts(day: e.localDay)[e.id]?.verdict == "safety_hold")
    #expect(try await l.annotations(day: e.localDay).isEmpty)
    #expect(await p.dayStatus(e.localDay) == .held)
    #expect(await p.latestDayReading(e.localDay) == nil)
}

@Test func aVerdictFromAnOlderGateIsGatedAgain() async throws {
    let l = try tempLedger()
    let log = Prompts()
    let p = Pipeline(ledger: l, ai: logged(log))
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    try await l.insertVerdict(SafetyVerdictRow(entryId: e.id, textSha256: sha256(chai), safetyVersion: "safety-0", layer: 2,
                                               verdict: "safety_hold", reasonCode: "classifier_uncertain"))
    #expect(try await l.entryIDs(withLatestVerdictNotAt: SafetyGate.version) == [e.id])
    // SR-18: the launch sweep queues it, and this gate's verdict replaces the old one (here lifting the hold).
    await p.process(entryId: e.id) {}
    #expect(await log.count(.classify) == 1)
    let v = try await l.verdicts(day: e.localDay)[e.id]
    #expect(v?.verdict == "clear" && v?.safetyVersion == SafetyGate.version)
    #expect(try await l.entryIDs(withLatestVerdictNotAt: SafetyGate.version).isEmpty)
    #expect(await p.dayStatus(e.localDay) == .ready)
}

@Test func aHeldEntryHoldsItsDayAndNothingIsGeneratedFromIt() async throws {
    let l = try tempLedger()
    let log = Prompts()
    let p = Pipeline(ledger: l, ai: logged(log))
    let a = Entry(kind: .reflection, body: chai)
    let b = Entry(kind: .reflection, body: vanishing)
    try await l.insertEntry(a)
    await p.process(entryId: a.id) {}
    #expect(await p.readDay(a.localDay) != nil)
    try await l.insertEntry(b)
    await p.process(entryId: b.id) {}

    #expect(try await l.verdicts(day: a.localDay)[b.id]?.reasonCode == "classifier_passive")
    #expect(try await l.annotations(day: a.localDay)[b.id] == nil)
    #expect(await log.count(.entry) == 1)
    #expect(await log.log.allSatisfy { $0.ask == .classify || !$0.prompt.contains("vanishing") })
    #expect(try await rowCount(l, "ai_run_input", "entry_id='\(b.id)'") == 0)
    #expect(try await rowCount(l, "insight_snapshot") == 0)
    #expect(await p.dayStatus(a.localDay) == .held)
    #expect(await p.readDay(a.localDay) == nil)
    #expect(await p.latestDayReading(a.localDay) == nil)
    #expect(await log.count(.day) == 1)
}

@Test func withoutTheModelReadingsAreInYourWords() async throws {
    let l = try tempLedger()
    let log = Prompts()
    let off = Pipeline(ledger: l, ai: logged(log, status: .unavailable(reason: "appleIntelligenceNotEnabled")))
    let a = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(a)
    await off.process(entryId: a.id) {}
    let v = try await l.verdicts(day: a.localDay)[a.id]
    #expect(v?.verdict == "unavailable_clear" && v?.layer == 1 && v?.reasonCode == "model_unavailable")
    #expect(try await l.annotations(day: a.localDay)[a.id]?.generator == "heuristic")
    let run = try #require(try await l.run("SELECT * FROM ai_run WHERE feature='entry_reading'").first)
    #expect(run.str("executor") == "heuristic" && run.str("ladder_rung") == "heuristic" && run.str("guardrails") == nil)
    #expect(run.int("model_calls") == 0 && run.str("input_hash") == sha256(chai))
    #expect(await off.dayStatus(a.localDay) == .ready)
    let day = try #require(await off.readDay(a.localDay))
    #expect(day.reading.narrative == nil)
    try await expectVerbatim(day, l)
    #expect(await off.latestDayReading(a.localDay)?.generator == "heuristic")

    // A caution hit with no layer 2 waits for a check: nothing is read, and the day gets no reading (SR-06, SR-14).
    let b = Entry(kind: .reflection, body: "Some days everything feels hopeless and I just want to sleep.")
    try await l.insertEntry(b)
    await off.process(entryId: b.id) {}
    #expect(try await l.verdicts(day: a.localDay)[b.id]?.verdict == "unavailable_caution")
    #expect(try await l.annotations(day: a.localDay)[b.id] == nil)
    #expect(await off.dayStatus(a.localDay) == .awaitingCheck)
    #expect(await off.readDay(a.localDay) == nil)
    #expect(await log.log.isEmpty)

    // The model comes back: both re-gate through layer 2 before anything is generated, and the day is read on-device.
    let on = Pipeline(ledger: l, ai: logged(log))
    for id in [a.id, b.id] { await on.process(entryId: id) {} }
    #expect(await log.log.map { $0.ask } == [.classify, .entry, .classify, .entry])
    #expect(try await l.verdicts(day: a.localDay).values.map(\.verdict) == ["clear", "clear"])
    #expect(await on.readDay(a.localDay) != nil)
    #expect(await on.latestDayReading(a.localDay)?.generator == "on_device")
}

@Test func theSameTextIsReadOnce() async throws {
    let l = try tempLedger()
    let log = Prompts()
    let p = Pipeline(ledger: l, ai: logged(log))
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    for _ in 0..<3 {
        await p.process(entryId: e.id) {}
        await p.readDay(e.localDay)
    }
    #expect(await log.count(.classify) == 1)
    #expect(await log.count(.entry) == 1)
    #expect(await log.count(.day) == 1)
    for (table, n) in [("safety_verdict", 1), ("entry_annotation", 1), ("ai_run", 2), ("insight_snapshot", 1)] {
        #expect(try await rowCount(l, table) == n, "\(table)")
    }
}

@Test func aLadderThatRanOutIsNotAskedAgain() async throws {
    let l = try tempLedger()
    let log = Prompts()
    // Every reading names someone the entry never mentions, so each reply fails the drift check.
    let p = Pipeline(ledger: l, ai: logged(log) { ask, _ in
        switch ask {
        case .classify: "NONE"
        case .entry: cleanEntry.replacingOccurrences(of: "Ravi", with: "Priya")
        case .day: cleanDay.replacingOccurrences(of: "Ravi", with: "Priya")
        }
    })
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    for _ in 0..<2 {
        await p.process(entryId: e.id) {}
        await p.readDay(e.localDay)
    }
    // At most 4 calls per touchpoint (SR-10), two per rung: the permissive pair asks for JSON, each retry adds the correction.
    #expect(await log.count(.classify) == 1)
    #expect(await log.count(.entry) == 4)
    #expect(await log.count(.day) == 4)
    for ask in [Ask.entry, .day] {
        let prompts = await log.prompts(ask)
        #expect(prompts.map { $0.contains("Reply with only a JSON object") } == [true, true, false, false])
        #expect(prompts.map { $0.hasSuffix(SaroAI.correction) } == [false, true, false, true])
    }
    let runs = try await l.run("SELECT * FROM ai_run ORDER BY rowid")
    #expect(runs.map { $0.str("feature") } == ["entry_reading", "day_reading"])
    #expect(runs.allSatisfy { $0.int("model_calls") == 4 && $0.str("executor") == "heuristic" && $0.str("status") == "ok" })
    #expect(try await l.annotations(day: e.localDay)[e.id]?.title != "Chai with Priya")
}

@Test func aRefusedEntrysDayMakesAtMostTwoCalls() async throws {
    let l = try tempLedger()
    let log = Prompts()
    let p = Pipeline(ledger: l, ai: logged(log) { ask, _ in
        switch ask {
        case .classify: return "NONE"
        case .entry: throw guardrail
        case .day: return cleanDay.replacingOccurrences(of: "Ravi", with: "Priya")
        }
    })
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    await p.readDay(e.localDay)
    #expect(await log.count(.entry) == 1)
    #expect(await log.prompts(.day).map { $0.contains("Reply with only a JSON object") } == [false, false])
}

@Test func aDayReadsOnlyItsClearCheckedEntries() async throws {
    let l = try tempLedger()
    let log = Prompts()
    let p = Pipeline(ledger: l, ai: logged(log))
    let clear = Entry(kind: .reflection, body: chai)
    // A voice note heard too faintly: layer 2 finds nothing, so layer 0 makes it a technical hold.
    let media = MediaAsset(fileName: "x/voice.m4a", kind: .audio, origin: "recorded", state: "ready")
    try await l.insertMedia(media)
    let words = "Mumbled something about the garden shed".split(separator: " ").enumerated().map { i, w in
        TranscriptWord(text: String(w), startMs: i * 300, durMs: 250, confidence: 0.1)
    }
    try await l.setTranscript(mediaId: media.id, words: words, extractorVersion: "test")
    let faint = Entry(kind: .voice, mediaId: media.id)
    let bare = Entry(kind: .still, processingStatus: ProcessingStatus.done)
    let emptied = Entry(kind: .reflection, body: "Picked up marigolds at the market.")
    let trashed = Entry(kind: .reflection, body: "Watched the cricket with Kabir.")
    for e in [clear, faint, bare, emptied, trashed] {
        try await l.insertEntry(e)
        await p.process(entryId: e.id) {}
    }
    try await l.updateEntryText(id: emptied.id, body: "", titleUser: nil, captionUser: nil)
    _ = try await l.trash([trashed.id])
    #expect(try await l.verdicts(day: clear.localDay)[faint.id]?.verdict == "technical_hold")
    #expect(try await l.verdicts(day: clear.localDay)[bare.id] == nil)

    let payload = try #require(await p.readDay(clear.localDay))
    #expect(payload.entryIds == [clear.id])
    try await expectVerbatim(payload, l)
    let run = try #require(try await l.run("SELECT id FROM ai_run WHERE feature='day_reading'").first?.str("id"))
    #expect(try await l.run("SELECT entry_id FROM ai_run_input WHERE ai_run_id=?", [.text(run)]).map { $0.str("entry_id") } == [clear.id])
    for word in ["garden", "marigolds", "Kabir"] {
        #expect(await log.prompts(.day).allSatisfy { !$0.contains(word) }, "\(word)")
    }

    // Unchecked text keeps the day from being read at all.
    let pending = Entry(kind: .reflection, body: "Fixed the leaking tap.")
    try await l.insertEntry(pending)
    #expect(await p.dayStatus(clear.localDay) == .working)
    #expect(await p.readDay(clear.localDay) == nil)
    await p.process(entryId: pending.id) {}
    #expect(try #require(await p.readDay(clear.localDay)).entryIds == [clear.id, pending.id])
}

@Test func dayQuotesAreVerbatimFromTheEntries() async throws {
    let texts = [chai, "Walked home in the rain and called my sister. We laughed about the old flat.",
                 "Finally fixed the bike chain. Rode to the lake and back before dinner."]
    let outOfList = cleanDay.replacingOccurrences(of: "[0]", with: "[0, 99]")
    for ai in [logged(Prompts()), logged(Prompts(), status: .unavailable(reason: "test")), answers(day: outOfList)] {
        let l = try tempLedger()
        let p = Pipeline(ledger: l, ai: ai)
        let entries = texts.map { Entry(kind: .reflection, body: $0) }
        for e in entries {
            try await l.insertEntry(e)
            await p.process(entryId: e.id) {}
        }
        let payload = try #require(await p.readDay(entries[0].localDay))
        #expect(payload.entryIds.count == 3)
        #expect(!payload.quotes.isEmpty && !payload.quotes.contains { $0.index == 99 })
        try await expectVerbatim(payload, l)
    }
}

@Test func anOlderDayReadingKeepsOnlyQuotesStillInTheText() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: logged(Prompts()))
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    let before = try #require(await p.readDay(e.localDay))
    #expect(!before.quotes.isEmpty)

    // An edit is gated, but its reading and the day's are rate-limited: the older day reading is still the newest.
    try await l.updateEntryText(id: e.id, body: "Rain all afternoon, so I stayed in.", titleUser: nil, captionUser: nil)
    let limited = Pipeline(ledger: l, ai: stubAI { ask in
        guard ask == .classify else { throw rateLimited }
        return "NONE"
    })
    await limited.process(entryId: e.id) {}
    #expect(await limited.readDay(e.localDay) == nil)
    let after = try #require(await p.latestDayReading(e.localDay))
    #expect(after.payload.quotes.isEmpty)
    try await expectVerbatim(after.payload, l)
}

@Test func rateLimitsDeferReadingsMidLadder() async throws {
    let l = try tempLedger()
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    // Limited after two replies that didn't parse: the guided rung stops the ladder and nothing is stored (§11.7).
    let log = Prompts()
    await Pipeline(ledger: l, ai: logged(log) { ask, _ in
        if ask == .classify { return "NONE" }
        if await log.count(ask) <= 2 { return "not json" }
        throw rateLimited
    }).process(entryId: e.id) {}
    #expect(await log.count(.entry) == 3)
    #expect(try await l.verdicts(day: e.localDay)[e.id]?.verdict == "clear")
    #expect(try await l.annotations(day: e.localDay).isEmpty)
    #expect(try await rowCount(l, "ai_run") == 0)
    #expect(try await l.entry(e.id)?.processingStatus == ProcessingStatus.pending)

    let p = Pipeline(ledger: l, ai: answers())
    await p.process(entryId: e.id) {}
    #expect(try await l.annotations(day: e.localDay)[e.id]?.generator == "on_device")
    // The day reading the same way: deferred, nothing stored, and asked again on the next pass.
    let dayLog = Prompts()
    let limited = Pipeline(ledger: l, ai: logged(dayLog) { ask, _ in
        if await dayLog.count(ask) <= 1 { return "not json" }
        throw rateLimited
    })
    #expect(await limited.readDay(e.localDay) == nil)
    #expect(await dayLog.count(.day) == 2)
    #expect(try await rowCount(l, "insight_snapshot") == 0)
    #expect(try await rowCount(l, "ai_run", "feature='day_reading'") == 0)
    #expect(await p.readDay(e.localDay)?.reading.question == "What did Ravi say?")
}

@Test func noOfferedQuoteTripsThePhraseGate() {
    // Each text passes layer 1 whole; a window cut from it must not drop the guard that made it pass.
    for text in ["Honestly at the office today I want to die of boredom in every single meeting we have",
                 "Sitting in that queue for three hours I was ready to die of old age before the counter opened"] {
        #expect(!SafetyGate.phraseHit(text))
        for c in Heuristics.candidates(entryId: "e", field: "body", text: text) {
            #expect(!SafetyGate.phraseHit(c.text), "\(c.text)")
        }
    }
}
