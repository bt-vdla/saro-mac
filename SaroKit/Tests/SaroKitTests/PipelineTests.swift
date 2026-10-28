import Foundation
import FoundationModels
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
    // The newest verdict was made for other text; editing the body must not count as checked, and the hold stands.
    try await l.updateEntryText(id: e.id, body: "A quiet walk home.", titleUser: nil, captionUser: nil)
    #expect(await p.dayStatus(e.localDay) == .held)
    #expect(await p.readDay(e.localDay) == nil)
}

@Test func emptiedTextDoesNotStrandTheDay() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: SaroAI())
    let page = Entry(kind: .reflection, body: "I want to die.")
    let still = Entry(kind: .still, captionUser: "I want to die.", processingStatus: ProcessingStatus.done)
    try await l.insertEntry(page)
    try await l.insertEntry(still)
    await p.process(entryId: page.id) {}
    await p.process(entryId: still.id) {}
    #expect(await p.dayStatus(page.localDay) == .held)
    // Cleared with no further pass (the editor discards an empty page instead of processing it), then with one.
    try await l.updateEntryText(id: page.id, body: "", titleUser: nil, captionUser: nil)
    try await l.updateEntryText(id: still.id, body: nil, titleUser: nil, captionUser: nil)
    #expect(await p.dayStatus(page.localDay) == .empty)
    await p.process(entryId: page.id) {}
    #expect(await p.dayStatus(page.localDay) == .empty)
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

// MARK: With a model stand-in (synthetic replies; no real model call runs)

enum Ask { case classify, entry, day }

/// Routes each prompt by kind: the classifier's ends in "Label:", the day's opens with its notes.
func stubAI(_ answer: @escaping @Sendable (Ask) async throws -> String) -> SaroAI {
    SaroAI(stub: { prompt in
        try await answer(prompt.hasSuffix("Label:") ? .classify : prompt.hasPrefix("Notes on today's entries") ? .day : .entry)
    })
}

let chai = "Had chai with Ravi after work."
let cleanEntry = #"{"title": "Chai with Ravi", "summary": "You had chai with Ravi.", "mood": "Calm", "moodBasis": "chai", "quoteIndex": null}"#
let cleanDay = #"{"mood": "Calm", "moodBasis": "chai", "quoteIndexes": [0], "question": "What did Ravi say?", "narrative": null}"#

func answers(entry: String = cleanEntry, day: String = cleanDay) -> SaroAI {
    stubAI { ask in
        switch ask {
        case .classify: "NONE"
        case .entry: entry
        case .day: day
        }
    }
}

@Test func cleanRepliesAreStoredAsOnDeviceReadings() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: answers())
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    #expect(try await l.annotations(day: e.localDay)[e.id]?.generator == "on_device")
    #expect(await p.dayStatus(e.localDay) == .ready)
    #expect(await p.readDay(e.localDay)?.reading.question == "What did Ravi say?")
    #expect(await p.latestDayReading(e.localDay)?.generator == "on_device")
}

@Test func anEditSavedDuringAPassStaysPending() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: answers())
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    // The editor reopened and autosaved new text while the pass for the old text ran, then the app quit.
    await p.process(entryId: e.id) { try? await l.updateEntryText(id: e.id, body: "I want to die.", titleUser: nil, captionUser: nil) }
    #expect(try await l.entry(e.id)?.processingStatus == ProcessingStatus.pending)
    #expect(try await l.unfinishedEntries().map(\.id) == [e.id])
    #expect(await p.dayStatus(e.localDay) == .working)
    // The launch sweep's pass gates the edit.
    await p.process(entryId: e.id) {}
    #expect(await p.dayStatus(e.localDay) == .held)
}

@Test func anEditWrittenAtQuitIsKeptAndGatedAtTheNextLaunch() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: answers())
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    // ⌘Q before the editor's autosave: the words are written before the call returns, and left for the sweep.
    #expect(await MainActor.run { l.updateEntryTextBeforeQuit(id: e.id, body: chai + " I want to die.", titleUser: nil) })
    #expect(try await l.entry(e.id)?.body == chai + " I want to die.")
    #expect(try await l.unfinishedEntries().map(\.id) == [e.id])
    await p.process(entryId: e.id) {}
    #expect(await p.dayStatus(e.localDay) == .held)
}

@Test func dayQuestionAndMoodBasisAreDriftChecked() async throws {
    let drifted = [cleanDay.replacingOccurrences(of: "What did Ravi say?", with: "How is your sister settling in?"),
                   cleanDay.replacingOccurrences(of: #""moodBasis": "chai""#, with: #""moodBasis": "the move to Pune""#)]
    for day in drifted {
        let l = try tempLedger()
        let p = Pipeline(ledger: l, ai: answers(day: day))
        let e = Entry(kind: .reflection, body: chai)
        try await l.insertEntry(e)
        await p.process(entryId: e.id) {}
        let r = await p.readDay(e.localDay)?.reading
        #expect(r != nil && r?.question != "How is your sister settling in?" && r?.moodBasis != "the move to Pune")
        #expect(await p.latestDayReading(e.localDay)?.generator == "heuristic")
    }
}

@Test func rateLimitedDefersTheGateAndTheReading() async throws {
    let l = try tempLedger()
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    // The classifier: no verdict, so the entry is neither held nor cleared; it waits, pending, for the next pass.
    let p = Pipeline(ledger: l, ai: stubAI { _ in throw rateLimited })
    await p.process(entryId: e.id) {}
    #expect(try await l.run("SELECT COUNT(*) AS n FROM safety_verdict").first?["n"]?.int == 0)
    #expect(try await l.entry(e.id)?.processingStatus == ProcessingStatus.pending)
    #expect(await p.dayStatus(e.localDay) == .working)
    // What the app's activation, wake and midnight pass picks up again (it has no verdict to re-gate by).
    #expect(try await l.unfinishedEntries().map(\.id) == [e.id])
    // The reading: the clear verdict stays, nothing generated is stored, and the model is asked once.
    let asked = CallLog()
    await Pipeline(ledger: l, ai: stubAI { ask in
        guard ask == .classify else { await asked.hitPermissive(); throw rateLimited }
        return "NONE"
    }).process(entryId: e.id) {}
    #expect(try await l.verdicts(day: e.localDay)[e.id]?.verdict == "clear")
    #expect(try await l.annotations(day: e.localDay).isEmpty)
    #expect(try await l.entry(e.id)?.processingStatus == ProcessingStatus.pending)
    #expect(try await l.unfinishedEntries().map(\.id) == [e.id])
    #expect(await asked.permissive == 1)
    // Once the limit lifts, the next pass reads it.
    await Pipeline(ledger: l, ai: answers()).process(entryId: e.id) {}
    #expect(try await l.annotations(day: e.localDay)[e.id]?.generator == "on_device")
}

/// A model call that never answers is given up once, and deferred like a rate limit (§11.7), so it can't hold the queue.
@Test func aTimedOutCallIsDeferredLikeARateLimit() async throws {
    let l = try tempLedger()
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    let asked = CallLog()
    let p = Pipeline(ledger: l, ai: stubAI { ask in
        guard ask == .classify else { await asked.hitPermissive(); throw Ladder.Timeout() }
        return "NONE"
    })
    await p.process(entryId: e.id) {}
    #expect(try await l.verdicts(day: e.localDay)[e.id]?.verdict == "clear")
    #expect(try await l.annotations(day: e.localDay).isEmpty)
    #expect(try await l.entry(e.id)?.processingStatus == ProcessingStatus.pending)
    #expect(await asked.permissive == 1)
    #expect(await !p.learn(entryId: e.id))
    #expect(try await l.unlearnedEntryIDs(extractor: MemoryRules.extractorVersion) == [e.id])

    await Pipeline(ledger: l, ai: answers()).process(entryId: e.id) {}
    #expect(await p.readDay(e.localDay) == nil)
    #expect(try await l.latestSnapshot(kind: "day_reading", day: e.localDay) == nil)
}

/// Text the model runs but can't read (its language) is gated once: the model being available can't change that, so no
/// later pass or activation asks again or adds a verdict (SR-17); only a new gate does (SR-18).
@Test func textInAnUnsupportedLanguageIsGatedOnce() async throws {
    let l = try tempLedger()
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    let asked = CallLog()
    let p = Pipeline(ledger: l, ai: stubAI { ask in
        guard ask == .classify else { return cleanEntry }
        await asked.hitPermissive()
        throw LanguageModelError.unsupportedLanguageOrLocale(.init(languageCode: .init("xx"), debugDescription: "test"))
    })
    for _ in 0..<3 { await p.process(entryId: e.id) {} }
    #expect(await asked.permissive == 1)
    #expect(try await l.run("SELECT COUNT(*) AS n FROM safety_verdict").first?["n"]?.int == 1)
    let v = try await l.verdicts(day: e.localDay)[e.id]
    #expect(v?.verdict == "unavailable_clear" && v?.reasonCode == "unsupported_language")
    #expect(try await l.entryIDs(withLatestVerdictIn: ["unavailable_clear"]) == [e.id])
    #expect(try await l.entryIDs(withLatestVerdictIn: ["unavailable_clear"], except: "unsupported_language").isEmpty)
    // A caution hit still waits for a check, for the same reason.
    let r = await SafetyGate(classify: { _ in .unavailable(reason: SafetyGate.unsupportedLanguage) })
        .gate(text: "Some days everything feels hopeless and I just want to sleep.", transcriptConfidence: nil)
    #expect(r?.verdict == "unavailable_caution" && r?.reasonCode == "unsupported_language")
}

/// The person's own answers and mood notes in a language the model can't read are asked about once a launch, not again
/// on every activation's re-gate: the verdict can't change while the model stays the same (SR-17).
@Test func answersInAnUnsupportedLanguageAreCheckedOnceALaunch() async throws {
    let l = try tempLedger()
    let day = "2026-10-20"
    let turn = ReflectionTurn(kind: .dailyQuestion, question: "What stayed with you?", generator: "heuristic", localDay: day)
    try await l.insertTurn(turn)
    try await l.setTurnAnswer(id: turn.id, answer: chai, verdict: "unavailable_clear")
    try await l.setUserMood(day: day, label: .calm, note: "Slow tea in the garden.", verdict: "unavailable_clear")
    let asked = CallLog()
    let p = Pipeline(ledger: l, ai: stubAI { _ in
        await asked.hitPermissive()
        throw LanguageModelError.unsupportedLanguageOrLocale(.init(languageCode: .init("xx"), debugDescription: "test"))
    })
    for _ in 0..<3 { #expect(await p.regateReflections(all: false)) }
    #expect(await asked.permissive == 2)
    #expect(try await l.turns(day: day).first?.answerVerdict == "unavailable_clear")
    #expect(try await l.dayState(day).moodNoteVerdict == "unavailable_clear")
}

@Test func heuristicReadingGivesWayOnceTheModelCanRun() async throws {
    let l = try tempLedger()
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    // What a pass made while Apple Intelligence was off: unavailable_clear and an "In your words" reading.
    try await l.insertVerdict(SafetyVerdictRow(entryId: e.id, textSha256: sha256(chai), safetyVersion: SafetyGate.version, layer: 1,
                                               verdict: "unavailable_clear", reasonCode: "model_unavailable"))
    let words = Heuristics.heuristicReading(text: chai, candidates: Heuristics.candidates(entryId: e.id, field: "body", text: chai))
    var run = AIRun(feature: "entry_reading", executor: "heuristic", status: "ok")
    run.inputHash = sha256(chai)
    run.modelCalls = 0
    var a = EntryAnnotation(entryId: e.id, aiRunId: run.id, generator: "heuristic")
    (a.title, a.summary, a.moodLabel) = (words.title, words.summary, words.mood.rawValue)
    try await l.insertRun(run)
    try await l.insertAnnotation(a)
    // Every entry reply drifts (Priya), so the model's reading falls back to that same "In your words" digest.
    let asked = CallLog()
    let p = Pipeline(ledger: l, ai: stubAI { ask in
        switch ask {
        case .classify: return "NONE"
        case .entry: await asked.hitPermissive(); return cleanEntry.replacingOccurrences(of: "Ravi", with: "Priya")
        case .day: await asked.hitGuided(); return cleanDay
        }
    })
    await p.readDay(e.localDay)
    #expect(await p.latestDayReading(e.localDay)?.generator == "heuristic")
    #expect(await asked.guided == 0)
    // Re-gated clear, then read by the model although a heuristic reading of this text exists.
    await p.process(entryId: e.id) {}
    #expect(try await l.verdicts(day: e.localDay)[e.id]?.verdict == "clear")
    #expect(await asked.permissive == 4)
    // The model's own fallback counts as read: no second round of calls.
    await p.process(entryId: e.id) {}
    #expect(await asked.permissive == 4)
    // Same digests as the heuristic day, but the model can run now.
    await p.readDay(e.localDay)
    #expect(await p.latestDayReading(e.localDay)?.generator == "on_device")
}

@Test func theModelsDayReadingStandsWhileItCantRun() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: answers())
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    await p.readDay(e.localDay)
    // Apple Intelligence goes off for a while: the cached clear verdict keeps the day ready, and the model's reading stands.
    let off = Pipeline(ledger: l, ai: SaroAI(stub: { _ in "" }, status: .unavailable(reason: "test")))
    #expect(await off.dayStatus(e.localDay) == .ready)
    #expect(await off.readDay(e.localDay)?.reading.question == "What did Ravi say?")
    await p.readDay(e.localDay)
    #expect(try await l.run("SELECT COUNT(*) AS n FROM insight_snapshot").first?["n"]?.int == 1)
}

@Test func readingsLeftByMissingModelAssetsGiveWay() async throws {
    let l = try tempLedger()
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    // The assets go missing mid-ladder: one call, then "In your words".
    func missing(at stage: Ask) -> SaroAI {
        stubAI { ask in
            if ask == stage { throw assetsMissing }
            return ask == .classify ? "NONE" : ask == .entry ? cleanEntry : cleanDay
        }
    }
    await Pipeline(ledger: l, ai: missing(at: .entry)).process(entryId: e.id) {}
    #expect(try await l.annotations(day: e.localDay)[e.id]?.generator == "heuristic")
    let p = Pipeline(ledger: l, ai: answers())
    await p.process(entryId: e.id) {}
    #expect(try await l.annotations(day: e.localDay)[e.id]?.generator == "on_device")
    // The day's inputs are the same both times, so only the stop tells the two readings apart.
    await Pipeline(ledger: l, ai: missing(at: .day)).readDay(e.localDay)
    #expect(await p.latestDayReading(e.localDay)?.generator == "heuristic")
    await p.readDay(e.localDay)
    #expect(await p.latestDayReading(e.localDay)?.generator == "on_device")
}

@Test func refusedEntryNeverReachesThePermissiveDayRung() async throws {
    let l = try tempLedger()
    let permissiveDay = CallLog()
    let p = Pipeline(ledger: l, ai: SaroAI(stub: { prompt in
        if prompt.hasSuffix("Label:") { return "NONE" }
        guard prompt.hasPrefix("Notes on today's entries") else { throw guardrail }
        if prompt.contains("Reply with only a JSON object") { await permissiveDay.hitPermissive() }
        return cleanDay
    }))
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    #expect(try await l.run("SELECT status FROM ai_run WHERE feature='entry_reading'").first?.str("status") == "guardrail")
    #expect(try await l.annotations(day: e.localDay)[e.id]?.generator == "heuristic")
    #expect(await p.readDay(e.localDay) != nil)
    #expect(await permissiveDay.permissive == 0)
    #expect(try await l.run("SELECT ladder_rung FROM ai_run WHERE feature='day_reading'").first?.str("ladder_rung") == "guided")
}

@Test func outputGateHitOnAnEntryReadingHoldsIt() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: answers(entry: cleanEntry.replacingOccurrences(of: "You had chai with Ravi.", with: "You said you want to end it all.")))
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    let v = try await l.verdicts(day: e.localDay)[e.id]
    #expect(v?.verdict == "safety_hold" && v?.layer == 3 && v?.reasonCode == "output_gate")
    #expect(try await l.annotations(day: e.localDay).isEmpty)
    #expect(await p.dayStatus(e.localDay) == .held)
    #expect(await p.readDay(e.localDay) == nil)
}

@Test func outputGateHitOnTheDayReadingHoldsTheDay() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: answers(day: cleanDay.replacingOccurrences(of: "What did Ravi say?", with: "Do you want to end it all?")))
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    #expect(await p.readDay(e.localDay) == nil)
    let v = try await l.verdicts(day: e.localDay)[e.id]
    #expect(v?.verdict == "safety_hold" && v?.layer == 3 && v?.reasonCode == "output_gate")
    #expect(await p.dayStatus(e.localDay) == .held)
    #expect(try await l.run("SELECT COUNT(*) AS n FROM insight_snapshot").first?["n"]?.int == 0)
    await p.process(entryId: e.id) {}
    #expect(await p.dayStatus(e.localDay) == .held)
}
