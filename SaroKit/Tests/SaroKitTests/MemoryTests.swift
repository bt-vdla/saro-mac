import Foundation
import Testing
@testable import SaroKit

// MARK: Fixtures

private let day: TimeInterval = 86_400
private func ago(_ days: Double, hour: Double = 0) -> Date { Date.now.addingTimeInterval(-days * day + hour * 3600) }

/// Gate and read without the model: the phrase gate clears (`unavailable_clear`) and the heuristic twin reads.
private func offline(_ l: Ledger) -> Pipeline { Pipeline(ledger: l, ai: SaroAI(stub: { _ in "" }, status: .unavailable(reason: "test"))) }

@discardableResult
private func write(_ l: Ledger, _ p: Pipeline, _ text: String, at: Date = .now) async throws -> Entry {
    let e = Entry(kind: .reflection, body: text, capturedAt: at)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    await p.learn(entryId: e.id)
    return e
}

private func memories(_ l: Ledger, now: Date = .now) async throws -> [Memory] {
    MemoryList.derive(try await l.activeObservations(), starter: try await l.latestStarter(), commitments: try await l.openCommitments(),
                      tombstones: try await l.tombstoneHashes(), forgotAllAt: try await l.forgotAllAt(), pauses: try await l.pauses(), now: now)
}

private func texts(_ m: [Memory]) -> [String] { m.map(\.text) }

/// Derive straight from texts, one entry per text, a day apart (memory.test.ts's deriveMemories cases).
private func derived(_ entries: [String], now: Date = .now) -> [Memory] {
    let rows = entries.enumerated().flatMap { i, t in
        MemoryRules.observe(entryId: "e\(i)", field: "body", text: t, localDay: "d\(i)").map { o in
            var o = o
            o.capturedAt = now.addingTimeInterval(Double(i - entries.count) * day)
            return o
        }
    }
    return MemoryList.derive(rows, now: now)
}

private func people(_ entries: [String]) -> [String] { texts(derived(entries).filter { $0.group == .people }) }

// MARK: The view's exclusions

@Test func activeObservationHidesHeldDaysTrashTombstonesAndRetractions() async throws {
    let l = try tempLedger()
    let p = offline(l)
    let a = try await write(l, p, "Dinner with my sister Maya was lovely. Work was a lot.", at: ago(2))
    let b = try await write(l, p, "Long walk in the park after work.", at: ago(1))
    let keys = { Set(try await l.activeObservations().map(\.key)) }
    #expect(try await keys().isSuperset(of: ["person:maya", "theme:work", "theme:nature"]))

    // A held entry on the same day hides every row of that day; a re-gate that clears it brings them back.
    let held = Entry(kind: .reflection, body: "x", capturedAt: a.capturedAt)
    try await l.insertEntry(held)
    let hold = SafetyVerdictRow(entryId: held.id, textSha256: sha256("x"), safetyVersion: SafetyGate.version, layer: 1, verdict: "safety_hold", reasonCode: "t")
    try await l.insertVerdict(hold)
    #expect(try await !keys().contains("person:maya"))
    try await l.insertVerdict(SafetyVerdictRow(entryId: held.id, textSha256: sha256("x"), safetyVersion: SafetyGate.version, layer: 2, verdict: "clear", reasonCode: "t"))
    #expect(try await keys().contains("person:maya"))

    // So does a held answer or mood note, the person's words outside an entry (SR-13); checked again and cleared, they're back.
    let turn = ReflectionTurn(kind: .dailyQuestion, question: "What stood out?", generator: "heuristic", localDay: a.localDay)
    try await l.insertTurn(turn)
    try await l.setTurnAnswer(id: turn.id, answer: "x", verdict: "safety_hold")
    #expect(try await !keys().contains("person:maya"))
    try await l.setTurnAnswer(id: turn.id, answer: "x", verdict: "clear")
    #expect(try await keys().contains("person:maya"))
    try await l.setUserMood(day: a.localDay, label: .calm, note: "x", verdict: "safety_hold")
    #expect(try await !keys().contains("person:maya"))
    #expect(try await keys().contains("theme:nature"))
    try await l.setUserMood(day: a.localDay, label: .calm, note: "x", verdict: "clear")
    #expect(try await keys().contains("person:maya"))

    // Trash hides, restore brings back, with no write to observations.
    let batch = try await l.trash([b.id])
    #expect(try await !keys().contains("theme:nature"))
    try await l.restore(batch: batch)
    #expect(try await keys().contains("theme:nature"))

    // Forgetting a key tombstones it (only its hash is kept) and deletes its rows, words and all.
    try await l.forget(keys: ["theme:nature"])
    #expect(try await !keys().contains("theme:nature"))
    #expect(try await l.run("SELECT * FROM memory_tombstone").allSatisfy { $0["key_sha256"] != .text("theme:nature") })
    #expect(try await l.run("SELECT 1 FROM observation WHERE key='theme:nature'").isEmpty)
}

@Test func aHoldAfterLearningDropsWhatWasLearnedAndClearingAgainLearnsAgain() async throws {
    let l = try tempLedger()
    let p = offline(l)
    let e = try await write(l, p, "Dinner with my sister Maya was lovely. Work was a lot.", at: ago(1))
    // An edit leaves the first text's rows behind, retracted.
    let text = "Dinner with my sister Maya was lovely. Maya stayed late."
    try await l.updateEntryText(id: e.id, body: text, titleUser: nil)
    await p.process(entryId: e.id) {}
    #expect(await p.learn(entryId: e.id))
    let count = { (sql: String) in try await l.run(sql, [.text(e.id)]).first?["n"] }
    let rows = "SELECT COUNT(*) AS n FROM observation WHERE entry_id=?"
    let retractions = "SELECT COUNT(*) AS n FROM observation_retraction r JOIN observation o ON o.id = r.observation_id WHERE o.entry_id=?"
    let inputs = "SELECT COUNT(*) AS n FROM ai_run_input i JOIN ai_run r ON r.id = i.ai_run_id WHERE r.feature='memory' AND i.entry_id=?"
    #expect(try await count(retractions) != .int(0))

    // The same text held later (a gate version bump, the classifier once the model is back, or layer 3 on the day's
    // reading): nothing learned from it stays on disk, retracted or not, so Export can't write it out.
    try await l.insertVerdict(SafetyVerdictRow(entryId: e.id, textSha256: sha256(text), safetyVersion: SafetyGate.version, layer: 3,
                                               verdict: "safety_hold", reasonCode: "output_gate"))
    #expect(try await count(rows) == .int(0))
    #expect(try await count(retractions) == .int(0))
    #expect(try await count(inputs) == .int(0))
    #expect(try await l.run("SELECT 1 FROM ai_run WHERE feature='memory'").isEmpty)
    let url = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString).json")
    try await l.exportJSON(to: url)
    let obj = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect((obj["observation"] as? [Any])?.isEmpty == true)
    #expect((obj["memories"] as? [Any])?.isEmpty == true)

    // Cleared again, the text is learned afresh, by the next pass or the launch backfill.
    try await l.insertVerdict(SafetyVerdictRow(entryId: e.id, textSha256: sha256(text), safetyVersion: SafetyGate.version, layer: 2,
                                               verdict: "clear", reasonCode: "t"))
    #expect(try await l.unlearnedEntryIDs(extractor: MemoryRules.extractorVersion) == [e.id])
    #expect(await p.learn(entryId: e.id))
    #expect(try await l.standingObservations(entryId: e.id).contains { $0.key == "person:maya" })

    // An unchecked verdict drops it too: unchecked text never feeds memory.
    try await l.insertVerdict(SafetyVerdictRow(entryId: e.id, textSha256: sha256(text), safetyVersion: SafetyGate.version, layer: 1,
                                               verdict: "unavailable_caution", reasonCode: "caution_hit"))
    #expect(try await count(rows) == .int(0))
}

// MARK: Extraction

@Test func observationsQuoteWholeSentencesVerbatim() throws {
    let text = "Long day at work. Dinner with my sister Maya was lovely.\nI need to call Mum this week, and pay the rent."
    let rows = MemoryRules.observe(entryId: "e", field: "body", text: text, localDay: "d")
    let ns = text as NSString
    for o in rows {
        #expect(o.quote == ns.substring(with: NSRange(location: o.spanStart!, length: o.spanEnd! - o.spanStart!)))
        #expect(o.textSha256 == sha256(text))
    }
    #expect(rows.first { $0.key == "person:maya" }?.kind == .person)
    #expect(rows.first { $0.key == "person:maya" }?.quote == "Dinner with my sister Maya was lovely.")
    #expect(rows.first { $0.key == "theme:work" }?.quote == "Long day at work.")
    let intent = try #require(rows.first { $0.kind == .intention })
    #expect(intent.label == "call Mum this week")
    #expect(intent.quote == "I need to call Mum this week, and pay the rent.")
    #expect(MemoryRules.intention(in: "I'll be honest")?.label == "be honest")
    #expect(MemoryRules.intention(in: "I want to be") == nil)
    #expect(MemoryRules.intention(in: "Tomorrow I start the new job.")?.label == "start the new job")
    #expect(MemoryRules.intention(in: "Tomorrow I will book the restaurant.")?.label == "book the restaurant")
    #expect(MemoryRules.intention(in: "Tomorrow I'll call Mum.")?.label == "call Mum")
    #expect(MemoryRules.intention(in: "Tomorrow I want to rest.")?.label == "rest")
    let plan = { (t: String) in MemoryRules.observe(entryId: "e", field: "body", text: t, localDay: "d").filter { $0.kind == .intention }.map(\.key) }
    #expect(plan("Tomorrow I will book the restaurant.") == plan("I will book the restaurant."), "one plan, one key")
    #expect(MemoryRules.intention(in: "If I have to sit through one more meeting I'll scream.") == nil, "a condition, not a plan")
}

@Test func aNameInTwoEntriesIsAPersonWithTheNewestSentenceAsEvidence() throws {
    let out = derived([
        "Dinner with my sister Maya was lovely. We talked for hours.",
        "Lunch with Priya from the office.",
        "I miss Maya's laugh already. The house is quiet.",
    ])
    let maya = try #require(out.first { $0.key == "person:maya" })
    #expect(maya.text == "Maya comes up often.")
    #expect(maya.count == 2)
    #expect(maya.evidence == "I miss Maya's laugh already.")
    #expect(maya.sightings.count == 2)
    #expect(!out.contains { $0.key == "person:priya" })
}

@Test func brandsPlacesAndCompaniesAreNotPeople() {
    #expect(people(["Flat hunting in London, then we watched Netflix and I fixed a bug in Python. The Zoom call ran long.",
                    "Back in London. Too much Netflix on the sofa, a Zoom call, more Python.",
                    "Called Sam about the weekend.", "Lunch with Sam, and Sam said the job is his."]) == ["Sam comes up often."])
    for pair in [["Spent the evening with Netflix.", "Ended up with Netflix and noodles."],
                 ["Called Vodafone about the bill, on hold for ages.", "Called Vodafone again."],
                 ["Weekend with London friends.", "Missed London already."],
                 ["Met with Berlin team.", "Met with Berlin team again."],
                 ["Called Barclays about my card.", "Barclays said the payment bounced."],
                 ["Interview at Deloitte.", "Met with Deloitte people."],
                 ["Called British Gas about the boiler.", "British Gas said Monday."],
                 ["Christmas with the family.", "Missed Christmas with Mum."],
                 ["Zapco said my bill went up again this month.", "Told Zapco I would switch if it keeps going up."],
                 ["Drove to Hebden. She slept most of the way.", "Back to Hebden. He was quiet."],
                 ["Someone said hi.", "Everyone said so. He said it too."]] {
        #expect(people(pair) == [], "\(pair[0])")
    }
    #expect(people(["Sam texted me.", "Dinner with Sam."]) == ["Sam comes up often."])
    #expect(people(["Dana thinks I should rest.", "My therapist Dana asked about sleep."]) == ["Dana comes up often."])
    #expect(people(["Raj and I went running.", "Raj and I went running again."]) == ["Raj comes up often."])
    #expect(people(["Called Jo. She was upset.", "Saw Jo, she looked tired."]) == ["Jo comes up often."])
    #expect(people(["Me and Tom went out.", "Tom and I cooked."]) == ["Tom comes up often."])
}

@Test func themesNeedTwoEntriesMoodsThreeRecentAndAForgottenThemeFreesItsSlot() {
    let out = derived(["Awake at 3am again, anxious about the deadline.", "Slept badly. So anxious and worried.",
                       "Anxious before the meeting, then fine."])
    #expect(texts(out).contains("Sleep has been on your mind."))
    #expect(texts(out).contains("Work has been on your mind."))
    #expect(texts(out).contains("You’ve often felt anxious lately."))
    #expect(out.first { $0.key == "mood:anxious" }?.count == 3)

    // Six themes tie on count; the oldest (work) is sixth until another is forgotten.
    let words = ["the office", "insomnia", "rent", "the park", "a book", "my cousin"]
    let entries = words.flatMap { ["Thinking about \($0).", "More \($0) today."] }
    // The view leaves a forgotten key's rows out before the top five are chosen.
    let mind = { (gone: Set<String>) in
        MemoryList.derive(rows(entries).filter { !gone.contains($0.key) }).filter { $0.group == .mind }.map(\.key)
    }
    #expect(mind([]) == ["theme:family", "theme:learning", "theme:nature", "theme:money", "theme:sleep"])
    #expect(mind(["theme:family"]) == ["theme:learning", "theme:nature", "theme:money", "theme:sleep", "theme:work"])
}

private func rows(_ entries: [String], now: Date = .now) -> [MemoryObservation] {
    entries.enumerated().flatMap { i, t in
        MemoryRules.observe(entryId: "e\(i)", field: "body", text: t, localDay: "d\(i)").map { o in
            var o = o
            o.capturedAt = now.addingTimeInterval(Double(i - entries.count) * day)
            return o
        }
    }
}

@Test func feelingsNeverMixLineagesOrCountOldEntries() {
    var r = rows(["So anxious.", "Anxious again.", "Anxious all day."])
    #expect(MemoryList.derive(r).contains { $0.key == "mood:anxious" })
    r[0].lineage = "on_device"
    #expect(!MemoryList.derive(r).contains { $0.key == "mood:anxious" }, "two heuristic and one model sighting are not three")
    let old = rows(["So anxious.", "Anxious again.", "Anxious all day."], now: ago(40))
    #expect(!MemoryList.derive(old).contains { $0.key == "mood:anxious" })
}

@Test func carriedCommitmentsAreOneAndAboutYouReadsAsSentences() {
    let c = [OpenCommitment(text: "Call Maya back about the weekend", createdAt: ago(3)),
             OpenCommitment(text: "Call Maya back about the weekend.", createdAt: ago(1))]
    var starter = StarterContext(version: 1)
    starter.answers = [1: "hi im sam", 2: "The launch, and work in general. My sister Maya.", 3: "Late, usually around 10pm, before bed.",
                       4: "I want to sleep better this month", 5: "Straight, please."]
    starter.picks = [Pick(kind: .name, text: "im sam", value: "im sam", start: 3, end: 9, q: 1),
                     Pick(kind: .theme, text: "work", value: "work", start: 16, end: 20, q: 2),
                     Pick(kind: .person, text: "My sister Maya", value: "Maya", start: 33, end: 47, q: 2),
                     Pick(kind: .time, text: "Late", value: "late", start: 0, end: 4, q: 3),
                     Pick(kind: .time, text: "10pm", value: "22:00", start: 21, end: 25, q: 3),
                     Pick(kind: .goal, text: "to sleep better", value: "to sleep better", start: 7, end: 22, q: 4),
                     Pick(kind: .tone, text: "Straight", value: "direct", start: 0, end: 8, q: 5)]
    let out = MemoryList.derive([], starter: starter, commitments: c)
    let work = out.filter { $0.group == .work }
    #expect(texts(work) == ["You’re working on “Call Maya back about the weekend”."])
    #expect(work.first?.count == 2)
    #expect(Set(texts(out.filter { $0.group == .about })) == ["You go by Sam.", "Work is on your mind.", "Your sister Maya matters to you.",
                                                             "You like to reflect around 10:00 pm.", "You want to sleep better this month.",
                                                             "You’d like Saro to be direct with you."])
    #expect(out.first { $0.key == "starter:name" }?.told == "hi im sam")
    // Learned from entries wins over the onboarding line with the same meaning.
    let both = MemoryList.derive(rows(["Worked late on the launch again.", "Another meeting about work."]), starter: starter)
    #expect(texts(both.filter { $0.key == "theme:work" }) == ["Work has been on your mind."])
    #expect(MemoryRules.goalLine("I want to be kinder to me", answer: nil) == "You want to be kinder to yourself.")
    #expect(MemoryRules.goalLine("More sleep", answer: nil) == "You want more sleep.")
    #expect(MemoryRules.goalLine("I want to be the kind of person who", answer: nil) == nil)
    #expect(MemoryRules.nameOf("שמי נועה", answer: nil) == "נועה")
}

@Test func clipMetaAndSearch() {
    let long = "You’re working on getting the whole team to agree on a launch date before the end of the month"
    #expect(MemoryList.clip(long, 60).count <= 60)
    #expect(MemoryList.clip(long, 60).hasSuffix("…"))
    #expect(MemoryList.clip("  short  ", 60) == "short")
    #expect(MemoryList.oneLine("I work nights as a nurse \n and sleep in the day") == "I work nights as a nurse and sleep in the day")
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let sep24 = cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12))!
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 28))!
    #expect(MemoryList.day(sep24, now: now, calendar: cal) == "Sep 24")
    #expect(MemoryList.day(sep24, now: cal.date(byAdding: .year, value: 1, to: now)!, calendar: cal) == "Sep 24, 2026")
    let m = Memory(key: "person:maya", text: "Maya comes up often.", group: .people, source: .entries, count: 6, lastSeen: sep24,
                   updatedAt: sep24, label: "Maya", sightings: [], told: nil)
    #expect(MemoryList.meta(m, now: now, calendar: cal) == "From 6 entries · last Sep 24")
    var edited = m
    edited.source = .user
    #expect(MemoryList.meta(edited, now: now, calendar: cal) == "Edited by you · Sep 24")
    #expect(MemoryList.matches(m, "MAYA"))
    #expect(!MemoryList.matches(m, "Priya"))
    let cafe = Memory(key: "user:1", text: "I love the café on Elm", group: .about, source: .user, count: 0, lastSeen: sep24,
                      updatedAt: sep24, label: "", sightings: [], told: nil)
    #expect(MemoryList.matches(cafe, "cafe"), "diacritic-insensitive")
    #expect(MemoryList.meta(cafe, now: now, calendar: cal) == "Added by you · Sep 24")
    #expect(MemoryList.knownLabels([m, cafe], called: "Bharat") == ["Bharat", "Maya"])
}

// MARK: Learning

@Test func learningReadsOnlyClearedTextAndRetractsOnEdit() async throws {
    let l = try tempLedger()
    let p = offline(l)
    let a = try await write(l, p, "Dinner with my sister Maya. Work was long.", at: ago(1))
    let first = try await l.standingObservations(entryId: a.id)
    #expect(first.contains { $0.key == "person:maya" })
    let run = try await l.run("SELECT * FROM ai_run WHERE feature='memory'")
    #expect(run.count == 1 && run[0]["extractor_version"] == .text(MemoryRules.extractorVersion))
    #expect(await !p.learn(entryId: a.id), "the same text isn't read twice")

    // An edit retracts the old rows, pointing at their replacements, and learns again.
    try await l.updateEntryText(id: a.id, body: "Dinner with my sister Maya. The garden was quiet.", titleUser: nil)
    await p.process(entryId: a.id) {}
    #expect(await p.learn(entryId: a.id))
    let now = try await l.standingObservations(entryId: a.id)
    #expect(now.allSatisfy { $0.textSha256 == sha256("Dinner with my sister Maya. The garden was quiet.") })
    #expect(!now.contains { $0.key == "theme:work" })
    let maya = try #require(now.first { $0.key == "person:maya" })
    #expect(try await l.run("SELECT replaced_by FROM observation_retraction WHERE reason='source_edited'").contains { $0["replaced_by"] == .text(maya.id) })

    // A held entry gives nothing, and an unchecked edit gives nothing until it is gated.
    let held = try await write(l, p, "I want to kill myself")
    #expect(try await l.standingObservations(entryId: held.id).isEmpty)
    let unchecked = Entry(kind: .reflection, body: "Lunch with Priya at the office.")
    try await l.insertEntry(unchecked)
    #expect(await !p.learn(entryId: unchecked.id))
    #expect(try await l.unlearnedEntryIDs(extractor: MemoryRules.extractorVersion).isEmpty)
}

@Test func nothingWrittenInAPauseOrBeforeForgetEverythingIsLearned() async throws {
    let l = try tempLedger()
    let p = offline(l)
    try await l.openPause(at: ago(5))
    try await l.closePause(at: ago(3))
    let inPause = try await write(l, p, "Rent is due again. Money is tight.", at: ago(4))
    #expect(try await l.standingObservations(entryId: inPause.id).isEmpty)
    #expect(try await l.run("SELECT status FROM ai_run WHERE feature='memory'").first?["status"] == .text("paused"))
    #expect(try await l.unlearnedEntryIDs(extractor: MemoryRules.extractorVersion).isEmpty, "a passed-over text isn't asked about again")

    // Paused right now: nothing new is learned, and what was written before is learned once memory is back on.
    let old = Entry(kind: .reflection, body: "Long day at the office.", capturedAt: ago(10))
    try await l.insertEntry(old)
    await p.process(entryId: old.id) {}
    try await Task.sleep(for: .milliseconds(5)) // the pause opens after the gate, not in the same millisecond
    var profile = try await l.profile()
    profile.memoryPaused = true
    try await l.saveProfile(profile)
    #expect(await !p.learn(entryId: old.id))
    #expect(try await l.unlearnedEntryIDs(extractor: MemoryRules.extractorVersion) == [old.id])
    profile.memoryPaused = false
    try await l.saveProfile(profile)
    #expect(await p.learn(entryId: old.id))

    // Forget everything: every row goes, every key is tombstoned, and older text is never read again.
    _ = try await write(l, p, "Another long meeting at work.", at: ago(2))
    #expect(try await memories(l).contains { $0.key == "theme:work" })
    #expect(try await l.forgetAll() >= 1)
    #expect(try await l.run("SELECT COUNT(*) AS n FROM observation").first?["n"] == .int(0))
    #expect(try await memories(l).isEmpty)
    let before = Entry(kind: .reflection, body: "My cousin visited. My cousin stayed late.", capturedAt: ago(1))
    try await l.insertEntry(before)
    await p.process(entryId: before.id) {}
    await p.learn(entryId: before.id)
    #expect(try await l.standingObservations(entryId: before.id).isEmpty)
    _ = try await write(l, p, "Saw my cousin today.")
    _ = try await write(l, p, "My cousin again.")
    #expect(try await memories(l).filter { $0.group == .mind }.map(\.key) == ["theme:family"])
    #expect(try await !memories(l).contains { $0.key == "theme:work" }, "a forgotten key never comes back")
}

@Test func editedAndAddedLinesOutrankExtractionAndDeleteForgetsTheWords() async throws {
    let l = try tempLedger()
    let p = offline(l)
    _ = try await write(l, p, "Cooked for Maya tonight and we talked about work.", at: ago(2))
    _ = try await write(l, p, "Then Maya called and we laughed about the launch at work.", at: ago(1))
    var list = try await memories(l)
    #expect(texts(list).contains("Work has been on your mind."))
    try await l.addUserMemory(MemoryObservation(entryId: nil, source: .user, kind: .line, key: "theme:work", label: "Work is a lot right now.", localDay: "d"))
    try await l.addUserMemory(MemoryObservation(entryId: nil, source: .user, kind: .line, key: "theme:work", label: "Work is calmer now.", localDay: "d"))
    try await l.addUserMemory(MemoryObservation(entryId: nil, source: .user, kind: .line, key: "user:1", label: "I work nights.", localDay: "d"))
    _ = try await write(l, p, "Work again, a long meeting.")
    list = try await memories(l)
    let work = try #require(list.first { $0.key == "theme:work" })
    #expect(work.text == "Work is calmer now." && work.source == .user && work.count == 3)
    #expect(list.first { $0.key == "user:1" }?.group == .about)
    #expect(try await l.run("SELECT COUNT(*) AS n FROM observation_retraction WHERE reason='user_edited'").first?["n"] == .int(1))

    try await l.forget(keys: ["user:1", "person:maya"])
    #expect(try await l.run("SELECT * FROM observation WHERE label='I work nights.'").isEmpty, "what the person wrote is deleted, not kept")
    #expect(try await l.run("SELECT * FROM observation WHERE key='person:maya'").isEmpty, "nor are the entry quotes behind a forgotten key")

    // Export carries the lines as the pane shows them, with their sightings; a forgotten key only as its hash.
    let url = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString).json")
    try await l.exportJSON(to: url)
    let obj = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let exported = try #require(obj["memories"] as? [[String: Any]])
    let line = try #require(exported.first { $0["key"] as? String == "theme:work" })
    #expect(line["text"] as? String == "Work is calmer now." && line["group"] as? String == "On your mind" && line["entries"] as? Int == 3)
    #expect((line["sightings"] as? [[String: Any]])?.first?["quote"] as? String == "Work again, a long meeting.")
    let raw = String(decoding: try Data(contentsOf: url), as: UTF8.self)
    #expect(!raw.contains("I work nights") && !raw.contains("person:maya"))
    _ = try await write(l, p, "Maya came over. Maya stayed for dinner.")
    #expect(try await !memories(l).contains { $0.key == "person:maya" })
}

@Test func aQuoteInATranscriptPlaysFromItsWord() {
    let words = [TranscriptWord(text: "I", startMs: 0, durMs: 100, confidence: nil), TranscriptWord(text: " walked", startMs: 200, durMs: 300, confidence: nil),
                 TranscriptWord(text: "home.", startMs: 600, durMs: 300, confidence: nil), TranscriptWord(text: "Maya", startMs: 1500, durMs: 300, confidence: nil)]
    let text = Pipeline.join(words)
    #expect(text == "I walked home. Maya")
    #expect(Pipeline.startMs(atUTF16: (text as NSString).range(of: "Maya").location, in: words) == 1500)
    #expect(Pipeline.startMs(atUTF16: (text as NSString).range(of: "home").location, in: words) == 600)
    #expect(Pipeline.startMs(atUTF16: 0, in: words) == 0)
}

// MARK: The model rung

private func memoryAI(_ reply: String) -> SaroAI {
    SaroAI(stub: { p in
        if p.hasSuffix("Label:") { return "NONE" }
        if p.contains("List the people the writer names") { return reply }
        return p.hasPrefix("Notes on today's entries") ? cleanDay : cleanEntry
    })
}

@Test func theModelPicksByPhraseAndAnInventedNameFallsBack() async throws {
    let text = "Had chai with Ravi after work. I want to call Mum this week."
    let candidates = Heuristics.candidates(entryId: "e", field: "body", text: text)
    let ravi = try #require(candidates.first { $0.text.contains("Ravi") })
    let mum = try #require(candidates.first { $0.text.contains("call Mum") })
    let good = #"{"people": [{"name": "Ravi", "phrase": \#(ravi.index)}], "themes": [{"theme": "work", "phrase": \#(ravi.index)}], "intentions": [\#(mum.index)]}"#
    let (picks, prov) = await memoryAI(good).extractMemory(text: text, candidates: candidates)
    #expect(prov.executor == "on_device" && prov.rung == .guided && prov.guardrails == "default")
    #expect(picks?.count == 3)

    let invented = #"{"people": [{"name": "Priya", "phrase": \#(ravi.index)}], "themes": [], "intentions": []}"#
    let (none, fallback) = await memoryAI(invented).extractMemory(text: text, candidates: candidates)
    #expect(none == nil && fallback.rung == .heuristic && fallback.modelCalls == 2)

    // Learned through the pipeline: the model's people, the reading's feeling, a content-free on-device run.
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: memoryAI(good))
    let e = Entry(kind: .reflection, body: text)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    await p.learn(entryId: e.id)
    let rows = try await l.activeObservations()
    #expect(rows.first { $0.key == "person:ravi" }?.lineage == "on_device")
    #expect(rows.first { $0.kind == .intention }?.label == "call Mum this week")
    #expect(rows.allSatisfy { text.contains($0.quote ?? "∅") })
    #expect(try await l.run("SELECT executor FROM ai_run WHERE feature='memory'").first?["executor"] == .text("on_device"))
}

@Test func aFeelingNeverTakesTheModelsLineageWithoutTheModelsReading() async throws {
    let text = "Had chai with Ravi after work. So anxious about the launch all evening."
    let candidates = Heuristics.candidates(entryId: "e", field: "body", text: text)
    let ravi = try #require(candidates.first { $0.text.contains("Ravi") })
    let reply = #"{"people": [{"name": "Ravi", "phrase": \#(ravi.index)}], "themes": [], "intentions": []}"#
    // Cleared, but its reading hasn't run yet (deferred): the model's people, and no heuristic feeling under its name.
    let l = try tempLedger()
    let e = Entry(kind: .reflection, body: text)
    try await l.insertEntry(e)
    try await l.insertVerdict(SafetyVerdictRow(entryId: e.id, textSha256: sha256(text), safetyVersion: SafetyGate.version, layer: 2,
                                               verdict: "clear", reasonCode: "t"))
    await Pipeline(ledger: l, ai: memoryAI(reply)).learn(entryId: e.id)
    let rows = try await l.activeObservations()
    #expect(rows.first { $0.key == "person:ravi" }?.lineage == "on_device")
    #expect(!rows.contains { $0.kind == .emotion })

    // The heuristic twin alone keeps its own feeling.
    let h = try tempLedger()
    _ = try await write(h, offline(h), text)
    #expect(try await h.activeObservations().first { $0.kind == .emotion }.map { $0.lineage == "heuristic" && $0.key == "mood:anxious" } == true)
}

// MARK: The graph

@Test func graphNodesEdgesAndALayoutThatSettlesTheSameWayEveryTime() throws {
    let r = rows(["Dinner with Maya. Work was long.", "Maya and I walked in the park.", "Work, work, work. I need to sleep more.",
                  "Lunch with Sam at the office.", "Sam texted me about Maya."])
    let g = KnowledgeGraph.build(r)
    #expect(g.nodes.contains { $0.id == "person:maya" && $0.kind == .person && $0.mentions.count == 3 })
    #expect(g.nodes.contains { $0.id == "theme:work" && $0.label == "Work" })
    #expect(g.nodes.contains { $0.kind == .intention })
    let maya = try #require(g.neighbours(of: "person:maya").first { $0.node.id == "theme:work" })
    #expect(maya.weight >= 1)
    #expect(KnowledgeGraph.build(r, since: Date.now.addingTimeInterval(-2.5 * day)).nodes.allSatisfy { $0.mentions.allSatisfy { $0.at >= Date.now.addingTimeInterval(-2.5 * day) } })

    let a = g.layout(), b = g.layout()
    #expect(a == b)
    #expect(a.count == g.nodes.count)
    #expect(a.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    // Converged: a few more steps from the result barely move anything.
    let again = g.layout(iterations: 20, from: a)
    let drift = a.keys.map { k in let d = a[k]! - again[k]!; return (d * d).sum().squareRoot() }.max() ?? 0
    #expect(drift < 0.5)
    // Linked nodes sit closer than the average pair.
    let dist = { (x: String, y: String) in let d = a[x]! - a[y]!; return (d * d).sum().squareRoot() }
    let all = a.keys.flatMap { x in a.keys.filter { $0 > x }.map { dist(x, $0) } }
    #expect(dist("person:maya", "theme:work") < all.reduce(0, +) / Double(all.count))
    #expect(KnowledgeGraph.weekly(g.nodes[0].mentions).reduce(0, +) == g.nodes[0].mentions.count)
    // With label boxes, no two boxes overlap.
    let box = SIMD2(0.6, 0.25)
    let spaced = g.layout(extents: Dictionary(uniqueKeysWithValues: g.nodes.map { ($0.id, box) }))
    for x in spaced.keys { for y in spaced.keys where y > x {
        let d = spaced[x]! - spaced[y]!
        #expect(abs(d.x) >= 2 * box.x - 1e-6 || abs(d.y) >= 2 * box.y - 1e-6, "\(x) overlaps \(y)")
    } }
}

