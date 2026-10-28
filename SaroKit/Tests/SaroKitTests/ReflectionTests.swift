import Foundation
import Testing
@testable import SaroKit

// Synthetic text only (SR-28).

/// The model can't run, so the gate clears typed text as unavailable_clear and every reading is the heuristic twin's.
private func offline(_ l: Ledger) -> Pipeline { Pipeline(ledger: l, ai: SaroAI(stub: { _ in "" }, status: .unavailable(reason: "test"))) }

private func count(_ l: Ledger, _ sql: String) async throws -> Int? { try await l.run(sql).first?["n"]?.int }

// MARK: Commitment rows

@Test func commitmentRowsAreCheckedAndEventsAppendOnly() async throws {
    let l = try tempLedger()
    let c = try #require(try await l.addCommitment("Call Ravi", day: "2026-10-26"))
    await #expect(throws: (any Error).self) { try await l.run("UPDATE commitment_event SET event='edited'") }
    await #expect(throws: (any Error).self) {
        try await l.run("UPDATE commitment SET text=? WHERE id=?", [.text(String(repeating: "a", count: 281)), .text(c.id)])
    }
    await #expect(throws: (any Error).self) {
        try await l.run("INSERT INTO commitment_event (id, commitment_id, event, local_day, created_at) VALUES ('x',?,'renamed','d','t')", [.text(c.id)])
    }
    try await l.setUserMood(day: "2026-10-26", label: .calm, note: nil, verdict: nil)
    await #expect(throws: (any Error).self) { try await l.run("UPDATE day_state SET mood_note_verdict='fine'") }
}

// MARK: Day state

@Test func theUsersMoodIsLockedAndAHeldNoteHoldsTheDay() async throws {
    let l = try tempLedger()
    let p = offline(l)
    let e = Entry(kind: .reflection, body: "Long day at work. Shipped the launch with the team.")
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    #expect(await p.readDay(e.localDay) != nil)
    #expect(await p.dayMood(e.localDay) != .grateful)

    try await l.setUserMood(day: e.localDay, label: .grateful, note: "A good one.", verdict: "clear")
    #expect(await p.dayMood(e.localDay) == .grateful)
    // No re-read replaces it.
    await p.readDay(e.localDay, force: true, seed: 7)
    #expect(try await l.dayState(e.localDay).lockedMood == .grateful)
    #expect(await p.dayMood(e.localDay) == .grateful)

    try await l.setUserMood(day: e.localDay, label: .tender, note: "x", verdict: "safety_hold")
    #expect(await p.dayStatus(e.localDay) == .held)
    #expect(await p.dayMood(e.localDay) == nil)
    #expect(await p.readDay(e.localDay) == nil)
    #expect(try await count(l, "SELECT COUNT(*) AS n FROM insight_snapshot") == 0)
}

@Test func letterIsOpenedKeptAndCleared() async throws {
    let l = try tempLedger()
    let day = "2026-10-26"
    #expect(try await l.dayState(day).letterOpenedAt == nil)
    try await l.markLetterOpened(day: day)
    let opened = try #require(try await l.dayState(day).letterOpenedAt)
    try await l.markLetterOpened(day: day)
    #expect(try await l.dayState(day).letterOpenedAt == opened)
    let s = InsightSnapshot(kind: "letter", day: day, aiRunId: nil, generator: "heuristic", inputHash: nil, payload: "{}")
    try await l.keepLetter(day: day, snapshot: s)
    #expect(try await l.keptLetter(day: day)?.id == s.id)
    try await l.clearKept(day: day)
    #expect(try await l.keptLetter(day: day) == nil)
}

// MARK: Commitments

@Test func commitmentsCapClipEditAndLogEveryChange() async throws {
    let l = try tempLedger()
    let day = "2026-10-26"
    #expect(try await l.addCommitment("   ", day: day) == nil)
    let long = String(repeating: "é", count: 300)
    let c = try #require(try await l.addCommitment(long, day: day))
    #expect(c.text.count == 280)
    for i in 1..<Commitment.maxCount { try await l.addCommitment("Thing \(i)", day: day) }
    #expect(try await l.addCommitment("One too many", day: day) == nil)
    #expect(try await l.commitments(day: day).count == 20)

    try await l.edit(c.id, text: "Walk home the long way")
    try await l.setDone(c.id, true)
    #expect(try await l.commitments(day: day).first?.done == true)
    try await l.setDone(c.id, false)
    try await l.delete(c.id)
    #expect(try await l.commitments(day: day).count == 19)
    try await l.restoreCommitment(c.id)
    #expect(try await l.commitments(day: day).first?.text == "Walk home the long way")
    #expect(try await l.commitmentEvents(c.id) == ["created", "edited", "completed", "uncompleted", "deleted", "restored"])
    // A combining mark counts as SQLite counts it: the cut never splits a character or overruns the column.
    let clipped = Commitment.clipped(String(repeating: "e\u{301}", count: 200))
    #expect(clipped.unicodeScalars.count <= 280 && clipped.count == 140)
}

@Test func carryOverAsksOnceAndLettingGoStopsIt() async throws {
    let l = try tempLedger()
    let (yesterday, today) = ("2026-10-25", "2026-10-26")
    let a = try #require(try await l.addCommitment("Call Ravi.", day: yesterday))
    let b = try #require(try await l.addCommitment("Book the dentist", day: yesterday))
    let done = try #require(try await l.addCommitment("Water the plants", day: yesterday))
    try await l.setDone(done.id, true)
    #expect(try await l.openCommitments(from: yesterday).map(\.id) == [a.id, b.id])

    // Already on today's list by the same words: not asked again.
    let typed = try #require(try await l.addCommitment("  call ravi. ", day: today))
    #expect(Commitment.pending(try await l.openCommitments(from: yesterday), today: try await l.commitments(day: today)).map(\.id) == [b.id])
    try await l.delete(typed.id)

    let carried = try await l.carry([a.id], to: today)
    #expect(carried.first?.carriedFromId == a.id && carried.first?.text == "Call Ravi.")
    #expect(try await l.commitmentEvents(carried[0].id) == ["carried"])
    try await l.letGo([b.id], day: today)
    #expect(try await l.openCommitments(from: yesterday).isEmpty)
    #expect(try await l.commitmentEvents(b.id) == ["created", "let_go"])
    // Undo of a let-go.
    try await l.restoreCommitment(b.id)
    #expect(try await l.openCommitments(from: yesterday).map(\.id) == [b.id])
    #expect(try await l.openCommitments().map(\.id) == [b.id, carried[0].id])
}

// MARK: Questions

@Test func questionsAreChosenAvoidingTheLastWeekAndByTone() {
    let work = Lexicon.questions[.work]!
    #expect(Heuristics.pickQuestion(themes: [.work], seed: 0) == work[0])
    #expect(Heuristics.pickQuestion(themes: [.work], seed: 0, exclude: [work[0]]) == work[1])
    // Every work question used: the next theme's pool, then the general one, then a repeat rather than an invention.
    #expect(Heuristics.pickQuestion(themes: [.work, .family], seed: 0, exclude: work) == Lexicon.questions[.family]![0])
    let all = Lexicon.questions.values.flatMap { $0 }
    #expect(Lexicon.questions[nil]!.contains(Heuristics.pickQuestion(themes: [.work], seed: 3, exclude: all)))
    #expect(Heuristics.pickQuestion(themes: [.work], seed: 0, tone: .direct) == work.min { $0.count < $1.count })
    #expect(Heuristics.pickQuestion(themes: [.work], seed: 0, tone: .contemplative) == work.max { $0.count < $1.count })
}

@Test func anAnsweredQuestionStaysAndARefreshArchivesIt() async throws {
    let l = try tempLedger()
    let p = offline(l)
    let e = Entry(kind: .reflection, body: "Long day at work. The deadline moved again.")
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    let asked = try #require(await p.readDay(e.localDay)?.reading.question)
    var turn = ReflectionTurn(kind: .dailyQuestion, question: asked, generator: "heuristic", localDay: e.localDay)
    try await l.insertTurn(turn)
    try await l.setTurnAnswer(id: turn.id, answer: "More room to think.", verdict: "clear")

    // A new entry changes the day's inputs; the answered question stays.
    let more = Entry(kind: .reflection, body: "Called my sister about the family dinner.")
    try await l.insertEntry(more)
    await p.process(entryId: more.id) {}
    #expect(await p.readDay(e.localDay)?.reading.question == asked)

    let refreshed = try #require(await p.refreshQuestion(e.localDay)?.reading.question)
    #expect(refreshed != asked)
    #expect(await p.latestDayReading(e.localDay)?.payload.reading.question == refreshed)
    turn = try #require(try await l.turns(day: e.localDay, includeArchived: true).first)
    #expect(turn.archivedAt != nil && turn.answer == "More room to think.")
    #expect(try await l.turns(day: e.localDay, kind: .dailyQuestion).isEmpty)
    #expect(try await l.recentQuestions(day: e.localDay, includingDay: true).contains(asked))
}

@Test func aHeldAnswerHoldsTheWholeDay() async throws {
    let l = try tempLedger()
    let p = offline(l)
    let e = Entry(kind: .reflection, body: "Walked home through the park.")
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    let q = try #require(await p.readDay(e.localDay)?.reading.question)
    let verdict = try #require(await p.check("Some nights I just want to die."))
    #expect(verdict.verdict == "safety_hold")
    let turn = ReflectionTurn(kind: .dailyQuestion, question: q, generator: "heuristic", localDay: e.localDay)
    try await l.insertTurn(turn)
    try await l.setTurnAnswer(id: turn.id, answer: "Some nights I just want to die.", verdict: verdict.verdict)
    #expect(await p.dayStatus(e.localDay) == .held)
    #expect(await p.readDay(e.localDay) == nil)
    #expect(await p.latestDayReading(e.localDay) == nil)
}

// MARK: Narrative

private func n(_ kind: EntryKind, _ text: String = "", day: String = "2026-10-26", label: String? = nil) -> NarrativeEntry {
    NarrativeEntry(id: UUID().uuidString, kind: kind, day: day, text: text, label: label)
}

@Test func theNarrativeCountsQuotesAndRecalls() throws {
    let today = [n(.reflection, "Long day at work. The launch meeting ran over."), n(.voice, "Work again, and a call with my sister about the family dinner.")]
    let recent = [n(.reflection, "Slept badly before the launch.", day: "2026-10-20"), n(.moment, "Back at work early.", day: "2026-10-22")]
    let a = try #require(DayNarrative.draft(day: "2026-10-26", entries: today, recent: recent))
    #expect(["A day of work and family.", "Work and family, side by side.", "Moving between work and family."].contains(a.title))
    #expect(a.body.contains("Work came up 4 times, family twice."))
    #expect(a.body.contains("Work has come up on 3 of the last 14 days, most recently Thu 22 Oct."))
    let q = try #require(a.quote)
    #expect(today.contains { $0.text.contains(q.text) } && a.subtitle.contains("\"\(q.text)\""))
    #expect(a.subtitle.contains("Thu 22 Oct"))
    // Refresh rotates past the title it had.
    #expect(DayNarrative.draft(day: "2026-10-26", entries: today, recent: recent, avoidTitle: a.title)?.title != a.title)

    let first = try #require(DayNarrative.draft(day: "2026-10-26", entries: today, recent: []))
    #expect(first.body.last == "This is the first time work has come up in the last two weeks.")

    let quiet = try #require(DayNarrative.draft(day: "2026-10-26", entries: [n(.still), n(.music, label: "Holocene"), n(.still)], recent: []))
    #expect(["A day in three moments.", "Three moments, kept.", "What you kept: 2 stills and a song."].contains(quiet.title))
    #expect(quiet.subtitle == "You added 2 stills and a song." && quiet.body.isEmpty && quiet.quote == nil)
    #expect(DayNarrative.draft(day: "2026-10-26", entries: [], recent: []) == nil)
}

@Test func theLastInferredLineQuotesOnlyStoredWords() {
    let id = "e1"
    let quote = Candidate(index: 3, entryId: id, field: "body", text: "the sky was pink", utf16From: 4, utf16To: 20)
    func line(_ kind: EntryKind, _ q: Candidate? = nil, label: String? = nil) -> String {
        DayNarrative.lastInferred(NarrativeEntry(id: id, kind: kind, day: "d", text: "x", quote: q, label: label)).message
    }
    #expect(line(.reflection, quote) == "You wrote \"the sky was pink\".")
    #expect(line(.moment, quote) == "You said \"the sky was pink\" on camera.")
    #expect(line(.voice, quote) == "You said \"the sky was pink\".")
    #expect(line(.voice) == "You left yourself an echo.")
    #expect(line(.moment) == "You recorded a moment.")
    #expect(line(.still, label: "Mum's garden") == "You kept a still: \"Mum's garden\"")
    #expect(line(.still) == "You kept a still.")
    #expect(line(.music, label: "Holocene") == "You added \"Holocene\".")
    let long = Candidate(index: 0, entryId: id, field: "body", text: String(repeating: "word ", count: 40), utf16From: 0, utf16To: 200)
    let cut = line(.reflection, long)
    #expect(cut.count == 149 && cut.hasSuffix("…"))
}

@Test func theDayReadingCarriesItsNarrativeAndTheLetterPlacesItsQuotes() async throws {
    let l = try tempLedger()
    let p = offline(l)
    let e = Entry(kind: .reflection, body: "Long day at work. Shipped the onboarding flow finally. Feeling tired but good.")
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    let payload = try #require(await p.readDay(e.localDay))
    let narrative = try #require(payload.narrative)
    #expect(narrative.lastInferred?.kind == .reflection && narrative.lastInferred?.entryId == e.id)
    #expect(!SafetyGate.phraseHit(narrative.prose))

    let letter = try #require(Letter(reading: payload.reading, candidates: payload.quotes, narrative: narrative, mood: .grateful))
    #expect(letter.paragraphs.first == "\(narrative.title) \(narrative.subtitle)")
    #expect(letter.paragraphs.count <= 3 && letter.mood == .grateful)
    // Quotes already in the paragraphs aren't repeated under "In your words".
    for q in letter.unplacedQuotes { #expect(!letter.paragraphs.contains { $0.contains(q.text) }) }
    if let q = narrative.quote { #expect(!letter.unplacedQuotes.contains(q)) }

    // A forced re-read is a new snapshot.
    await p.readDay(e.localDay, force: true, avoid: narrative.title, seed: 1)
    #expect(try await count(l, "SELECT COUNT(*) AS n FROM insight_snapshot WHERE kind='day_reading'") == 2)
    #expect(await p.latestDayReading(e.localDay)?.payload.narrative?.title != narrative.title)
}

@Test func theLetterNotificationWaitsForAReadyUnreadDay() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let later = now.addingTimeInterval(3600)
    #expect(Letter.notice(status: .ready, hasLetter: true, opened: false, letterAt: later, now: now) == .schedule(later))
    #expect(Letter.notice(status: .ready, hasLetter: true, opened: false, letterAt: now.addingTimeInterval(-60), now: now) == .none)
    #expect(Letter.notice(status: .ready, hasLetter: true, opened: true, letterAt: later, now: now) == .cancel)
    #expect(Letter.notice(status: .ready, hasLetter: false, opened: false, letterAt: later, now: now) == .none)
    // A held day, and a voice note not yet transcribed (awaiting its check), never get one.
    #expect(Letter.notice(status: .held, hasLetter: true, opened: false, letterAt: later, now: now) == .cancel)
    #expect(Letter.notice(status: .awaitingCheck, hasLetter: true, opened: false, letterAt: later, now: now) == .cancel)
    #expect(Letter.notice(status: .working, hasLetter: true, opened: false, letterAt: later, now: now) == .none)
}

@Test func anUntranscribedVoiceNoteHoldsTheLetter() async throws {
    let l = try tempLedger()
    let p = offline(l)
    let page = Entry(kind: .reflection, body: "Walked home through the park.")
    try await l.insertEntry(page)
    await p.process(entryId: page.id) {}
    var voice = Entry(kind: .voice)
    voice.processingStatus = ProcessingStatus.transcriptUnavailable
    try await l.insertEntry(voice)
    let status = await p.dayStatus(page.localDay)
    #expect(status == .awaitingCheck)
    #expect(Letter.notice(status: status, hasLetter: true, opened: false, letterAt: .distantFuture) == .cancel)
}

// MARK: Personalisation

@Test func personalisationShapesThePromptButNeverItsQuotes() async {
    let ai = SaroAI(stub: { _ in "" }, status: .unavailable(reason: "test"))
    #expect(await ai.personalization.isEmpty)
    #expect(await ai.personalTag.isEmpty)
    await ai.setPersonalization(name: " Asha ", tone: .gentle, focus: [.clarity], known: ["Asha Rao", ""])
    let lines = await ai.personalization
    #expect(lines.contains("Lean gentle: soft wording, no pushing."))
    #expect(lines.contains("You may address the user as Asha, sparingly."))
    #expect(lines.contains("Areas the user cares about: Clarity for decisions. Connect to them only when an entry does."))
    #expect(await ai.personalTag == "+gentle+name+focus1")
    #expect(await ai.known == ["Asha Rao"])
    #expect(await ai.tone == .gentle)
    #expect(await ai.dayInstructions.hasPrefix(SaroAI.dayInstructions))
    #expect(Pipeline.quotesName("You said “Asha, slow down”.", "Asha"))
    #expect(!Pipeline.quotesName("Asha, you said “slow down”.", "Asha"))
    #expect(SaroAI.dayPromptVersion == "day-2" && SaroAI.entryPromptVersion == "entry-2")
}

// MARK: First week (weekMilestones.test.ts)

private let cal = Calendar.current
private func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 26 + day, hour: h, minute: m))! }
/// As stored: the reading's words and its verbatim quote.
private func week(_ day: Int, _ h: Int, _ text: String, _ m: Int = 0) -> WeekEntry {
    WeekEntry(at: at(day, h, m), words: text, quote: Heuristics.extractPhrase(text, focus: Heuristics.analyzeText(text).focus))
}

private let work = [
    week(0, 21, "The launch slipped again and the team is tired.", 30),
    week(1, 21, "Slept badly, then the launch meeting ran over.", 45),
    week(2, 22, "Walked by the river after work. Felt lighter."),
]

@Test func aFirstPatternNeedsThreeMoments() throws {
    #expect(WeekMilestones.firstPattern(Array(work.prefix(2))) == nil)
    let note = try #require(WeekMilestones.firstPattern(work))
    #expect(note.title == "A first pattern")
    #expect(note.lines[0] == "Work came up in all three of your first moments.")
    let said = try #require(note.lines[1].firstMatch(of: /^You said “(.+)”\.$/)?.1)
    #expect(work.contains { $0.words.contains(said) })
    #expect(note.lines[2] == "All three came around 9:45 pm.")
    #expect(WeekMilestones.firstPattern([week(0, 8, "Coffee."), week(1, 13, "Bus."), week(2, 23, "Rain.")])?.lines
        == ["Three moments, each about something different. I’ll keep watching."])
    #expect(WeekMilestones.firstPattern(Array(work.prefix(2)) + [week(2, 22, "I want to kill myself")]) == nil)
}

@Test func theFirstWeeklyLetterCountsAndQuotes() throws {
    let letter = WeekMilestones.firstLetter(name: "Alex", week: work + [week(5, 21, "Quiet day. The launch is finally out.", 30)], carriesPattern: false)
    #expect(letter.title == "Dear Alex,")
    #expect(letter.lines[0] == "You came back four times this week, on Saturday, Sunday, Monday and Thursday.")
    #expect(letter.lines[1] == "Most came around 9:45 pm.")
    #expect(letter.lines[2] == "Work came up most, in four of them.")
    #expect(letter.lines[3].firstMatch(of: /^One line I kept: “.+”\.$/) != nil)
    #expect(WeekMilestones.firstLetter(name: nil, week: [], carriesPattern: true)
        == WeekNote(kind: .letter, title: "Dear you,", lines: ["No moments this week, and that’s all right.", "Tonight’s minute is still yours."]))
}

@Test func whatTheFirstWeekHasDueDayByDay() throws {
    let now = { (day: Int) in at(day, 12) }
    #expect(WeekMilestones.dueNote(startedOn: "2026-09-26", entries: Array(work.prefix(2)), now: now(3), name: nil) == nil)
    #expect(WeekMilestones.dueNote(startedOn: "2026-09-26", entries: work, now: now(3), name: nil)?.kind == .pattern)
    #expect(WeekMilestones.dueNote(startedOn: "2026-09-26", entries: work, now: now(6), name: "Alex")?.title == "Dear Alex,")
    #expect(WeekMilestones.dueNote(startedOn: "2026-09-26", entries: work, now: now(14), name: nil) == nil)
    #expect(WeekMilestones.dueNote(startedOn: "2026-09-26", entries: work, now: now(-1), name: nil) == nil)
    #expect(WeekMilestones.dueNote(startedOn: "not a day", entries: work, now: now(3), name: nil) == nil)
    let late = try #require(WeekMilestones.dueNote(startedOn: "2026-09-26", entries: [week(6, 21, "Work again."), week(6, 22, "More work."),
                                                                                       week(6, 23, "Still work.")], now: now(6), name: nil))
    #expect(late.lines.last?.hasPrefix("And a first pattern: ") == true)
    #expect(WeekMilestones.weekDay(startedOn: "2026-09-26", now: now(4)) == 4)
    #expect(WeekMilestones.checkIn(goal: "sleep more.").lines == ["How’s “sleep more” going?"])
    #expect(WeekMilestones.checkIn(goal: String(repeating: "a", count: 60)).lines == ["How’s the week sitting?"])
    #expect(WeekMilestones.clockLabel(0) == "12:00 am" && WeekMilestones.clockLabel(1290) == "9:30 pm")
}

@Test func theWeekIsReadFromStoredClearEntriesOnly() async throws {
    let l = try tempLedger()
    let p = offline(l)
    let start = LocalDay.today()
    let clear = Entry(kind: .reflection, body: "Long day at work. The launch meeting ran over.")
    let held = Entry(kind: .reflection, body: "Some nights I just want to die.", localDay: LocalDay.adding(1, to: start))
    try await l.insertEntry(clear)
    try await l.insertEntry(held)
    await p.process(entryId: clear.id) {}
    await p.process(entryId: held.id) {}
    let entries = await p.weekEntries(from: start)
    #expect(entries.count == 1)
    let quote = try #require(entries.first?.quote)
    #expect(clear.body!.contains(quote))
}

@Test func theWeekSkipsDaysAwaitingACheckOrStillBeingRead() async throws {
    let l = try tempLedger()
    let p = offline(l)
    let start = LocalDay.today()
    let (d1, d2) = (LocalDay.adding(1, to: start), LocalDay.adding(2, to: start))
    let ready = Entry(kind: .reflection, body: "Long day at work. The launch meeting ran over.")
    let waiting = Entry(kind: .reflection, body: "Work again, the launch is close.", localDay: d1)
    var voice = Entry(kind: .voice, localDay: d1)
    voice.processingStatus = ProcessingStatus.transcriptUnavailable
    let reading = Entry(kind: .reflection, body: "More work on the launch today.", localDay: d2)
    let unread = Entry(kind: .reflection, body: "Still the launch.", localDay: d2)
    for e in [ready, waiting, voice, reading, unread] { try await l.insertEntry(e) }
    for e in [ready, waiting, reading] { await p.process(entryId: e.id) {} }
    #expect(await p.dayStatus(d1) == .awaitingCheck)
    #expect(await p.dayStatus(d2) == .working)
    // SR-14: the clear entries of a day awaiting a check, or still being read, feed neither note.
    #expect(await p.weekEntries(from: start).map(\.id) == [ready.id])
}

@Test func aStoredWeekNoteFollowsTheWholeDayRule() async throws {
    let l = try tempLedger()
    let p = offline(l)
    let (d0, d1) = ("2026-09-26", "2026-09-27")
    let a = Entry(kind: .reflection, body: "Long day at work. The launch slipped.", localDay: d0)
    let b = Entry(kind: .reflection, body: "Walked by the river after work.", localDay: d1)
    for e in [a, b] {
        try await l.insertEntry(e)
        await p.process(entryId: e.id) {}
    }
    let note = WeekNote(kind: .pattern, title: "A first pattern", lines: ["You said “the launch slipped”."], sources: [a.id, b.id])
    #expect(await p.weekNoteStatus(note) == .ready)

    // A day waiting on a check hides it for now.
    var voice = Entry(kind: .voice, localDay: d1)
    voice.processingStatus = ProcessingStatus.transcriptUnavailable
    try await l.insertEntry(voice)
    #expect(await p.weekNoteStatus(note) == .awaitingCheck)
    _ = try await l.trash([voice.id])
    #expect(await p.weekNoteStatus(note) == .ready)

    // Held through a different entry, a held answer or a held mood note: the note goes (SR-13).
    let other = Entry(kind: .reflection, body: "Some nights I just want to die.", localDay: d1)
    try await l.insertEntry(other)
    await p.process(entryId: other.id) {}
    #expect(await p.weekNoteStatus(note) == .held)
    _ = try await l.trash([other.id])
    #expect(await p.weekNoteStatus(note) == .ready)
    try await l.setUserMood(day: d0, label: .tender, note: "x", verdict: "safety_hold")
    #expect(await p.weekNoteStatus(note) == .held)

    // A moment since trashed takes the note with it.
    #expect(await p.weekNoteStatus(WeekNote(kind: .pattern, title: "", lines: [], sources: [b.id])) == .ready)
    _ = try await l.trash([b.id])
    #expect(await p.weekNoteStatus(WeekNote(kind: .pattern, title: "", lines: [], sources: [b.id])) == .held)
}

@Test func anAnswerAloneLeavesNothingToRead() async throws {
    let l = try tempLedger()
    let p = offline(l)
    var still = Entry(kind: .still)
    still.processingStatus = ProcessingStatus.done
    try await l.insertEntry(still)
    let turn = ReflectionTurn(kind: .dailyQuestion, question: "What helped?", generator: "heuristic", localDay: still.localDay)
    try await l.insertTurn(turn)
    try await l.setTurnAnswer(id: turn.id, answer: "A walk.", verdict: "clear")
    try await l.setUserMood(day: still.localDay, label: .calm, note: "Fine.", verdict: "clear")
    // A bare still with a clear answer and note: nothing to read, so not ready (no panel or letter left loading).
    #expect(await p.dayStatus(still.localDay) == .empty)
    try await l.setTurnAnswer(id: turn.id, answer: "A walk.", verdict: "safety_hold")
    #expect(await p.dayStatus(still.localDay) == .held)
}

@Test func aCuratedQuestionAndAHeuristicRefreshKeepHonestProvenance() async throws {
    let l = try tempLedger()
    let p = offline(l)
    let e = Entry(kind: .reflection, body: "Long day at work. The deadline moved again.")
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    #expect(await p.readDay(e.localDay, force: true, seed: 42)?.questionGenerator == nil)
    // The heuristic twin sampled nothing, though the refresh asked with a seed.
    let run = try #require(try await l.run("SELECT sampling FROM ai_run WHERE feature='day_reading' ORDER BY created_at DESC LIMIT 1").first)
    #expect(run.str("sampling") == nil)

    let refreshed = try #require(await p.refreshQuestion(e.localDay))
    #expect(refreshed.questionGenerator == "curated")
    let q = try #require(refreshed.reading.question)
    let turn = ReflectionTurn(kind: .dailyQuestion, question: q, generator: "curated", localDay: e.localDay)
    try await l.insertTurn(turn)
    try await l.setTurnAnswer(id: turn.id, answer: "More room.", verdict: "clear")
    // A later reading keeps the answered question, and says it was Saro's list's.
    let more = Entry(kind: .reflection, body: "Called my sister about the family dinner.")
    try await l.insertEntry(more)
    await p.process(entryId: more.id) {}
    let next = try #require(await p.readDay(e.localDay))
    #expect(next.reading.question == q && next.questionGenerator == "curated")
}

@Test func carryOverNeverVoicesAHeldDayOrWordsThatTripTheGate() async throws {
    let l = try tempLedger()
    let p = offline(l)
    let (yesterday, today) = ("2026-10-25", "2026-10-26")
    let call = try #require(try await l.addCommitment("Call Ravi", day: yesterday))
    try await l.addCommitment("Kill myself tomorrow", day: yesterday)
    #expect(await p.carryOvers(to: today, list: []).map(\.id) == [call.id])
    let held = Entry(kind: .reflection, body: "Some nights I just want to die.", localDay: yesterday)
    try await l.insertEntry(held)
    await p.process(entryId: held.id) {}
    #expect(await p.dayStatus(yesterday) == .held)
    #expect(await p.carryOvers(to: today, list: []).isEmpty)
}
