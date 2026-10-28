import Foundation
import Testing
@testable import SaroKit

// The web suites, ported: onboarding.test.ts, firstWeek.test.ts, firstWeekLight.test.ts and light-check.test.ts.

private func picks(_ text: String, _ q: Int, dropped: Set<String> = [], own: String = "Bharat") -> [String] {
    Onboarding.extract(answer: text, question: q, knownName: own, dropped: dropped).map { "\($0.kind.rawValue):\($0.text)=\($0.value)" }
}

// MARK: onboarding.test.ts

@Test func nameStripsGreetingsAndKeepsAtMostTwoWords() {
    #expect(picks("I'm Bharat", 1) == ["name:Bharat=Bharat"])
    #expect(picks("I'm called Bee", 1) == ["name:Bee=Bee"])
    #expect(picks("My nickname is Bee", 1) == ["name:Bee=Bee"])
    #expect(picks("Sam here", 1) == ["name:Sam=Sam"])
    #expect(picks("hi, I’m محمد", 1) == ["name:محمد=محمد"])
    #expect(picks("Hey, my name is Bea Lin!", 1) == ["name:Bea Lin=Bea Lin"])
    #expect(picks("just Sam and co", 1) == ["name:Sam=Sam"])
    #expect(picks("I'm not sure", 1) == [])
    #expect(picks("I don’t know", 1) == [])
}

@Test func personTakesMyJoinsAFollowingNameAndIgnoresTheirOwn() {
    #expect(picks("Bharat and my sister Maya", 2) == ["person:my sister Maya=Maya"])
    #expect(picks("Mostly our team", 2) == ["person:our team=team"])
    #expect(picks("Talked to Priya again", 2) == ["person:Priya=Priya"])
    // A name standing alone at a sentence start counts; a common noun standing alone doesn't.
    #expect(picks("Maya", 2) == ["person:Maya=Maya"])
    #expect(picks("Mark and the launch.", 2) == ["person:Mark=Mark", "theme:the launch=work"])
    #expect(picks("Life. Christmas. Moving.", 2) == [])
    #expect(picks("Bharat.", 2) == [])
    #expect(picks("Help.", 2) == [])
    #expect(picks("Supercalifragilisticexpialidocious.", 2) == [])
    #expect(["Paris.", "London.", "Netflix.", "Chemo."].flatMap { picks($0, 2) } == [])
    #expect(picks("Konstantinos.", 2) == ["person:Konstantinos=Konstantinos"])
}

@Test func themesTakeTheirDeterminerAndMoodsAreWorriesOnQ2Only() {
    #expect(picks("The launch, mostly", 2) == ["theme:The launch=work"])
    #expect(picks("I feel anxious", 2) == ["theme:anxious=Anxious"])
    #expect(picks("I feel anxious", 4) == [])
}

@Test func timesArePeriodsRelativeTimesAndClockTimes() {
    #expect(picks("Late night, usually", 3) == ["time:Late night=23:00"])
    #expect(picks("after dinner", 3) == ["time:after dinner=20:30"])
    #expect(picks("around 10:40", 3) == ["time:around 10:40=22:40"])
    #expect(picks("at 7 in the morning", 3) == ["time:at 7=07:00", "time:morning=08:00"])
    #expect(picks("by 6am", 3) == ["time:by 6am=06:00"])
    #expect(picks("at 10.30pm", 3) == ["time:at 10.30pm=22:30"])
    #expect(picks("late at night", 3) == ["time:late at night=23:00"])
    // A clock time needs no lead word when it can only be a time; a bare number can be anything.
    #expect(picks("Usually 10:30pm, once the kids are asleep", 3) == ["time:10:30pm=22:30", "person:kids=kids"])
    #expect(picks("Usually 10pm", 3) == ["time:10pm=22:00"])
    #expect(picks("10 pm", 3) == ["time:10 pm=22:00"])
    #expect(picks("10:30ish", 3) == ["time:10:30ish=22:30"])
    #expect(picks("I have 2 kids", 3) == ["person:kids=kids"])
    #expect(picks("It’s never late enough", 3) == [])
    // A counted noun makes the number a count, even after a lead word; a number standing alone is a time.
    #expect(picks("After 2 kids, never", 3) == ["person:kids=kids"])
    #expect(picks("about 3 hours", 3) == [])
    #expect(picks("Late. 11.", 3) == ["time:Late=23:00", "time:11=23:00"])
    #expect(picks("between 10 and 11", 3) == ["time:between 10=22:00"])
    // A bare 12 is midnight unless the words say midday.
    #expect(picks("at 12", 3) == ["time:at 12=00:00"])
    #expect(picks("at 12, lunch", 3) == ["time:at 12=12:00", "time:lunch=12:30"])
}

@Test func goalRunsFromTheTriggerToTheEndOfTheClause() {
    #expect(picks("More sleep, less rehearsing", 4) == ["goal:More sleep=More sleep", "goal:less rehearsing=less rehearsing"])
    #expect(picks("I want to run and read", 4) == ["goal:I want to run=I want to run", "theme:read=learning"])
    #expect(Onboarding.extract(answer: "I want to finally find a quiet hour every single day", question: 4)[0].text == "I want to finally find a quiet hour")
    // Cut at the cap, it drops the dangling "to".
    #expect(Onboarding.extract(answer: "I want to finally find a way to sleep", question: 4)[0].text == "I want to finally find a way")
    #expect(picks("More.", 4) == [])
    // "Between work and life" is one goal, and spending time isn't money.
    #expect(picks("More balance between work and life", 2) == ["goal:More balance between work and life=More balance between work and life"])
    #expect(picks("spend more time with my kids", 4) == ["goal:more time with my kids=more time with my kids"])
}

@Test func theFirstUnnegatedToneWordWins() {
    #expect(picks("Not too soft. Straight, but kind.", 5) == ["tone:Straight=direct"])
    #expect(picks("Don't be soft", 5) == [])
    #expect(picks("Plainly", 5) == ["tone:Plainly=neutral"])
    #expect(picks("kind of blunt", 5) == ["tone:blunt=direct"])
    #expect(picks("I don’t know, calm?", 5) == ["tone:calm=contemplative"])
}

@Test func overlapsLongerWinsThenKindPriority() {
    // "my sister" is both a person and a family theme word; person wins the tie.
    #expect(picks("my sister", 2) == ["person:my sister=sister"])
    // "More sleep" (goal) beats the theme word "sleep" inside it.
    #expect(picks("More sleep", 4) == ["goal:More sleep=More sleep"])
}

@Test func droppedPicksAreNeverReturned() {
    let kept = Onboarding.extract(answer: "my sister Maya", question: 2)
    #expect(kept.count == 1)
    #expect(Onboarding.extract(answer: "my sister Maya", question: 2, dropped: [kept[0].dropKey]).isEmpty)
}

@Test func picksAreExactUTF16SubstringsOfTheAnswer() {
    for text in ["The launch. My sister Maya. I need to sleep more, honestly.", "Ma sœur 👩🏽‍🦱 Maya. I need to sleep more 😴 honestly."] {
        let ns = text as NSString
        for p in Onboarding.extract(answer: text, question: 2) {
            #expect(ns.substring(with: NSRange(location: p.start, length: p.end - p.start)) == p.text)
        }
    }
}

private let answers: [Int: String] = [
    1: "Bharat",
    2: "The launch. My sister.",
    3: "Late, usually. Around 10:40",
    4: "More sleep, less rehearsing conversations",
    5: "Straight to it",
]

@Test func profileFieldsComeFromThePicks() {
    let all = Onboarding.picks(answers: answers, knownName: "Bharat")
    #expect(Onboarding.focusAreas(all) == [.clarity, .relationships, .energy])
    #expect(Onboarding.tone(all) == .direct)
    #expect(Onboarding.name(all) == "Bharat")
    // A clock time beats the vaguer "Late" before it.
    #expect(Onboarding.reflectTime(all) == "22:40")
    #expect(Onboarding.reflectTime(Onboarding.picks(answers: [3: "Late, usually. After the kids are down … around 10:40"])) == "22:40")
    #expect(Onboarding.reflectTime(Onboarding.picks(answers: [3: "Late, usually"])) == "23:00")
    #expect(Onboarding.reflectTime(Onboarding.picks(answers: [3: "late at night, maybe 11:30pm"])) == "23:30")
    // Between two clock times the later one is when the day goes quiet.
    #expect(Onboarding.reflectTime(Onboarding.picks(answers: [3: "I get home at 7 then 9:30 is quiet"])) == "21:30")
    #expect(Onboarding.reflectTime(Onboarding.picks(answers: [3: "Late. 11."])) == "23:00")
    #expect(Onboarding.picks(answers: [3: "Late. 11."]).first { $0.kind == .time }?.text == "11")
    // First week takes the first time pick, so the most specific one is stored first.
    let q3 = Onboarding.picks(answers: [3: "Late, usually. After the kids are down … around 10:40"])
    #expect(q3.map(\.text) == ["around 10:40", "kids", "Late"])
}

@Test func firstPromptThemeInTheChosenToneWithTheSlotOnTheirWords() throws {
    let all = Onboarding.picks(answers: answers, knownName: "Bharat")
    let out = FirstPrompt.compose(answers: answers, picks: all, name: "Bharat", tone: .direct, fallback: "Fallback?")
    #expect(out[0].text == "Bharat. The launch. What actually happened with it today?")
    let slot = try #require(out[0].slot)
    #expect((out[0].text as NSString).substring(with: NSRange(location: slot.start, length: slot.end - slot.start)) == "The launch")
    #expect(out[1].text == "Bharat, you want more sleep. What’s one small sign of that from today?")
}

@Test func firstPromptDropsTheNamePast90CharactersThenSkips() {
    let long = [4: "I want to sleep through a whole night"]
    let name = "Maximilianussss"
    let goal = FirstPrompt.compose(answers: long, picks: Onboarding.picks(answers: long), name: name, tone: .gentle, fallback: "Fallback?")
    #expect(goal[0].text == "You want to sleep through a whole night. What’s one small sign of that from today?")
    let longer = [4: "I want to stop rehearsing conversations with everyone"]
    let out = FirstPrompt.compose(answers: longer, picks: Onboarding.picks(answers: longer), name: name, tone: .gentle, fallback: "Fallback?")
    #expect(out == [FirstPrompt.Candidate(text: "Fallback?")])
}

@Test func aGoalIsSaidBackAsAWholeSentenceInTheSecondPerson() throws {
    func prompt(_ answer: String) -> String {
        let a = [4: answer]
        return FirstPrompt.compose(answers: a, picks: Onboarding.picks(answers: a), name: "Bee", tone: .gentle, fallback: "Fallback?")[0].text
    }
    let sign = ". What’s one small sign of that from today?"
    #expect(prompt("To be more present for my kids and stop snapping at them") == "Bee, you want to be more present for your kids\(sign)")
    #expect(prompt("I need to accept who I am") == "Bee, you want to accept who you are\(sign)")
    #expect(prompt("spend more time with my kids") == "Bee, you want to spend more time with your kids\(sign)")
    #expect(prompt("I’d love to feel less tired and more like me") == "Bee, you want to feel less tired\(sign)")
    #expect(prompt("I want to be kinder to me") == "Bee, you want to be kinder to yourself\(sign)")
    #expect(prompt("More me time") == "Bee, you want more time for yourself\(sign)")
    #expect(prompt("I want to feel like I’m enough") == "Bee, you want to feel like you’re enough\(sign)")
    #expect(prompt("We want to travel more as a family") == "Bee, you want to travel more as a family\(sign)")
    // Nothing whole to say back: no goal prompt.
    #expect(prompt("I want to be more") == "Fallback?")
    #expect(prompt("Less about work, more about life") == "Fallback?")
    // The slot is on their words, said back.
    let a = [4: "To be more present for my kids"]
    let goal = FirstPrompt.compose(answers: a, picks: Onboarding.picks(answers: a), name: "Bee", tone: .gentle, fallback: "Fallback?")[0]
    let slot = try #require(goal.slot)
    #expect((goal.text as NSString).substring(with: NSRange(location: slot.start, length: slot.end - slot.start)) == "to be more present for your kids")
}

@Test func aThemeIsSaidBackAsTheWholePhraseItCameIn() {
    let fallback = "Bee, what moment still lingers?"
    func prompt(_ answer: String, _ tone: Tone = .gentle) -> String {
        let a = [2: answer]
        return FirstPrompt.compose(answers: a, picks: Onboarding.picks(answers: a, knownName: "Bee"), name: "Bee", tone: tone, fallback: fallback)[0].text
    }
    func room(_ words: String, _ verb: String = "has") -> String {
        "Bee, \(words) \(verb) been taking up a lot of room. How are you holding up today?"
    }
    // Illness, work stress, money, a single noun.
    #expect(prompt("My mum is ill") == room("your mum being ill"))
    #expect(prompt("My mum’s ill and I’m worried about her") == room("your mum being ill"))
    #expect(prompt("Work stress, mostly") == room("work stress"))
    #expect(prompt("Money is tight") == room("money being tight"))
    #expect(prompt("Work") == room("work"))
    #expect(prompt("Deadlines at work") == room("deadlines at work", "have"))
    #expect(prompt("So tired lately") == room("being so tired lately"))
    // Longer phrases keep the name with the shorter line, or drop it; past 90 characters there's no theme prompt.
    #expect(prompt("Work is stressing me out") == "Bee, work stressing you out has been taking up a lot of room. How are you holding up?")
    #expect(prompt("I can’t sleep") == "Bee, not being able to sleep has been taking up a lot of room. How are you holding up?")
    // A breakup, and a move.
    #expect(prompt("My relationship ended") == "Bee, your relationship ending has been taking up a lot of room. How are you holding up?")
    #expect(prompt("We’re moving for my partner’s job") == "Moving for your partner’s job has been taking up a lot of room. How are you holding up?")
    #expect(prompt("Deadlines at work", .direct) == "Bee. Deadlines at work. What actually happened with them today?")
    // A clause it can't turn into a phrase: the prompt from the name alone.
    #expect(prompt("Everything at work feels like it’s on fire") == fallback)
    #expect(prompt("Work never stops") == fallback)
}

@Test func aSelfHarmAnswerLeavesOnlyTheFallback() {
    let a = [2: "I want to kill myself", 4: "More sleep"]
    #expect(FirstPrompt.compose(answers: a, picks: Onboarding.picks(answers: a), name: "Bharat", tone: .gentle, fallback: "Fallback?")
        == [FirstPrompt.Candidate(text: "Fallback?")])
}

@Test func aHeldStarterGetsOnlyItsTonesLine() {
    var s = StarterContext(version: 1)
    s.answers = [2: "The launch, mostly."]
    s.picks = Onboarding.picks(answers: s.answers)
    #expect(FirstPrompt.compose(starter: s, name: "Bee", tone: .gentle).count == 2)
    s.held = [2]
    #expect(FirstPrompt.compose(starter: s, name: "Bee", tone: .gentle) == [FirstPrompt.Candidate(text: "Bee, what moment still lingers?")])
}

@Test func onlyGatedAnswersAreStoredOrComposedFrom() {
    var s = StarterContext(version: 1)
    s.answers = [1: "Bee", 2: "The launch, mostly.", 4: "More sleep"]
    let clear = { (t: String) in AnswerVerdict(text: t, verdict: "clear") }
    // Q4 is still at the gate: nothing yet, and it isn't stored.
    var v: [Int: AnswerVerdict] = [1: clear("Bee"), 2: clear("The launch, mostly.")]
    #expect(FirstPrompt.state(s, verdicts: v, name: "Bee", tone: .gentle) == .waiting)
    #expect(s.gated(v, knownName: "Bee").answers.keys.sorted() == [1, 2])
    // A verdict for older text doesn't count for the text there now.
    v[4] = clear("More sleep and less")
    #expect(FirstPrompt.state(s, verdicts: v, name: "Bee", tone: .gentle) == .waiting)
    v[4] = clear("More sleep")
    guard case .ready(let all) = FirstPrompt.state(s, verdicts: v, name: "Bee", tone: .gentle) else { Issue.record("not ready"); return }
    #expect(all.count == 3 && all[0].text.contains("the launch"))
    // A deferred verdict: only their tone's line.
    v[4] = AnswerVerdict(text: "More sleep", verdict: nil)
    #expect(FirstPrompt.state(s, verdicts: v, name: "Bee", tone: .gentle) == .ready([FirstPrompt.Candidate(text: "Bee, what moment still lingers?")]))
    // A held answer: the SafetyCard, and nothing derived from it is stored.
    v[2] = AnswerVerdict(text: "The launch, mostly.", verdict: "safety_hold")
    #expect(FirstPrompt.state(s, verdicts: v, name: "Bee", tone: .gentle) == .held)
    let stored = s.gated(v, knownName: "Bee").storable
    #expect(stored.held == [2] && !stored.picks.contains { $0.q == 2 } && stored.firstPrompt == nil)
}

@Test func anAnswerAwaitingACheckIsKeptButNothingIsLearnedFromIt() {
    var s = StarterContext(version: 1)
    s.answers = [1: "Bee", 3: "Around 9:30, after dinner", 4: "More sleep, less rehearsing conversations", 5: "Straight to it"]
    let v = { (q: Int, verdict: String?) in AnswerVerdict(text: s.answers[q]!, verdict: verdict) }
    var verdicts = [1: v(1, "clear"), 3: v(3, "unavailable_clear"), 4: v(4, "unavailable_caution"), 5: v(5, nil)]
    let gated = s.gated(verdicts, knownName: "Bee").storable
    // Their words stay; the caution hit and the deferred answer give no goal, focus or tone, and no ritual span.
    #expect(gated.answers.keys.sorted() == [1, 3, 4, 5])
    #expect(Set(gated.picks.map(\.q)) == [1, 3])
    #expect(Onboarding.focusAreas(gated.picks).isEmpty && Onboarding.tone(gated.picks) == nil)
    #expect(FirstWeek.ritualFromSpans(gated.picks).span?.text == "Around 9:30")
    #expect(FirstWeek.plan(on: allOn, goal: gated.picks.first { $0.kind == .goal }?.text)[4].milestone?.note == "How’s the week sitting?")
    #expect(FirstPrompt.state(s, verdicts: verdicts, name: "Bee", tone: .gentle) == .ready([FirstPrompt.Candidate(text: "Bee, what moment still lingers?")]))
    // Only the caution hit offers someone to talk to; the gate is asked again for the deferred one, and for both once
    // the model can run.
    #expect(verdicts.values.filter(\.caution).count == 1)
    #expect(verdicts.filter { $0.value.needsRegate(modelAvailable: false) }.keys.sorted() == [5])
    #expect(verdicts.filter { $0.value.needsRegate(modelAvailable: true) }.keys.sorted() == [3, 4, 5])
    // Cleared later, it counts.
    verdicts[4] = v(4, "clear")
    #expect(s.gated(verdicts, knownName: "Bee").storable.picks.contains { $0.q == 4 && $0.kind == .goal })
}

@Test func emptyAnswersGateClearWithoutTheModel() async throws {
    let ledger = try Ledger(rootURL: URL.temporaryDirectory.appending(path: "onb-\(UUID().uuidString)"))
    let pipeline = Pipeline(ledger: ledger, ai: SaroAI())
    #expect(await pipeline.gate(answer: "  ")?.verdict == "clear")
    #expect(await pipeline.gate(answer: "I want to kill myself")?.verdict == "safety_hold")
}

@Test func anEmptyFirstPageWithItsPromptStillDiscards() async throws {
    let ledger = try Ledger(rootURL: URL.temporaryDirectory.appending(path: "onb-\(UUID().uuidString)"))
    let page = Entry(kind: .reflection, body: "")
    try await ledger.insertEntry(page)
    try await ledger.insertTurn(ReflectionTurn(kind: .prompt, question: "Bee, what moment still lingers?", generator: "curated",
                                               localDay: page.localDay, entryId: page.id))
    try await ledger.discardIfEmpty(page.id)
    #expect(try await ledger.entry(page.id) == nil)
    #expect(try await ledger.turns(entryId: page.id).isEmpty)
}

// MARK: firstWeek.test.ts

private let allOn = [Bool](repeating: true, count: 7)
private func at(_ plan: [FirstWeek.DayPlan]) -> [String] { plan.compactMap { d in d.milestone.map { "\(d.index):\($0.kind.rawValue)" } } }
private func time(_ text: String) -> FirstWeek.RitualSuggestion {
    FirstWeek.ritualFromSpans([Pick(kind: .time, text: text, value: text, start: 0, end: (text as NSString).length, q: 3)])
}

@Test func allDaysOnMilestonesFallOn0246() {
    #expect(at(FirstWeek.plan(on: allOn)) == ["0:baseline", "2:pattern", "4:checkin", "6:letter"])
}

@Test func day2OffMovesThePatternTo3() {
    var on = allOn
    on[2] = false
    #expect(at(FirstWeek.plan(on: on)) == ["0:baseline", "3:pattern", "4:checkin", "6:letter"])
}

@Test func twoOnDaysNoPatternAndTheLetterBringsIt() {
    let plan = FirstWeek.plan(on: [true, false, false, true, false, false, false])
    #expect(!plan.contains { $0.milestone?.kind == .pattern })
    #expect(plan[6].milestone?.note == "Your first weekly letter, and a first pattern. It still comes.")
}

@Test func day6OffTheLetterStillComes() {
    var on = allOn
    on[6] = false
    #expect(FirstWeek.plan(on: on)[6].milestone?.note == "Your first weekly letter. It still comes.")
    #expect(FirstWeek.plan(on: allOn)[6].milestone?.note == "Your first weekly letter.")
}

@Test func todayIsAlwaysOnAndTheLetterIsAddressed() {
    let plan = FirstWeek.plan(on: [false, true, true, true, true, true, true], name: "Alex", goal: "Phone stays in the kitchen.")
    #expect(plan[0].on)
    #expect(plan[6].milestone?.title == "Dear Alex,")
    #expect(plan[4].milestone?.note == "How’s “phone stays in the kitchen” going?")
    #expect(FirstWeek.plan(on: allOn)[6].milestone?.title == "Dear you,")
    #expect(FirstWeek.checkInNote(goal: String(repeating: "x", count: 49)) == "How’s the week sitting?")
}

@Test func theRitualTimeTable() {
    let cases: [(String, Int)] = [
        ("in the morning", 450), ("over breakfast", 450), ("when I wake up", 450), ("at lunch", 750), ("in the afternoon", 960),
        ("after dinner, on the sofa", 1290), ("evenings", 1290), ("late at night", 1290), ("before bed", 1290),
        ("around 10 pm", 1320), ("after dinner, around 10:30pm", 1350), ("22:15", 1335),
    ]
    for (text, minutes) in cases { #expect(time(text).minutes == minutes, "\(text)") }
    #expect(time("at lunch or in the evening").minutes == 750, "the earliest word wins")
    #expect(time("over breakfast").span?.text == "over breakfast")
    #expect(FirstWeek.ritualFromSpans([]) == FirstWeek.RitualSuggestion(minutes: 1290, source: .default))
    #expect(FirstWeek.ritualFromSpans([Pick(kind: .goal, text: "sleep by 10 pm", value: "sleep by 10 pm", start: 0, end: 14, q: 4)]).source == .default)
    #expect(time("whenever").source == .default)
}

@Test func hourCopyBoundaries() {
    let copy = { (h: Double) in let c = FirstWeek.hourCopy(h); return "\(c.part.rawValue)|\(c.day0)" }
    #expect(copy(11.99) == "Mornings|TODAY")
    #expect(copy(12) == "Afternoons|TODAY")
    #expect(copy(16.99) == "Afternoons|TODAY")
    #expect(copy(17) == "Evenings|TONIGHT")
    #expect(copy(21.99) == "Evenings|TONIGHT")
    #expect(copy(22) == "Late evenings|TONIGHT")
    #expect(copy(1) == "Late evenings|TONIGHT")
    #expect(copy(4) == "Mornings|TODAY")
}

@Test func hourDeltaTakesTheShortWayRound() {
    #expect(FirstWeek.hourDelta(from: 23, to: 7.5) == 8.5)
    #expect(FirstWeek.hourDelta(from: 7.5, to: 23) == -8.5)
    #expect(FirstWeek.hourDelta(from: 14, to: 21.5) == 7.5)
    #expect(FirstWeek.hourDelta(from: 31.5, to: 21.5) == -10)
}

@Test func dayGlowBuildsTowardTheLetter() {
    #expect((0..<7).map { WeekLight.dayGlow($0, on: true) } == [0.7, 0.74, 0.78, 0.82, 0.86, 0.9, 1])
    #expect(WeekLight.dayGlow(3, on: false) == 0.12)
}

@Test func theLightRunsFromTheHoursLightRoundTheHueWheelToTheVoice() {
    let lights = WeekLight.dayLights(hour: 21.5)
    #expect(lights.count == 7)
    #expect(lights[6].night == SIMD3(242, 160, 120))
    #expect(lights[6].day == SIMD3(242, 160, 120))
    let b0 = lights[0].night, b3 = lights[3].night
    #expect(b0.z > b0.x && b0.z > b0.y, "9:30 pm starts blue \(b0)")
    #expect(b3.x > b3.y && b3.z > b3.y, "and passes through rose \(b3)")
    // Even a grey hour's light gives every day a colour of its own.
    for c in WeekLight.dayLights(hour: 12.5).map(\.night) { #expect(max(c.x, c.y, c.z) - min(c.x, c.y, c.z) > 30, "noon \(c)") }
}

@Test func theCheckInQuotesTheGoalNotTheWanting() {
    #expect(FirstWeek.checkInNote(goal: "More sleep") == "How’s “more sleep” going?")
    #expect(FirstWeek.checkInNote(goal: "I want to keep the phone") == "How’s “keep the phone” going?")
    #expect(FirstWeek.checkInNote(goal: nil) == "How’s the week sitting?")
}

@Test func weekdaysMapOntoTheComingWeek() {
    // Starting on a Wednesday (3): index 4 is Sunday (bit 0).
    let mask = FirstWeek.toggleWeekday(Prefs.everyDay, startDay: 3, index: 4)
    #expect(mask == Prefs.everyDay & ~1)
    #expect(FirstWeek.weekOn(mask, startDay: 3) == [true, true, true, true, false, true, true])
    #expect(FirstWeek.weekOn(0, startDay: 3)[0])
}

@Test func aSwitchedDayIsAnnouncedWithWhatMoved() {
    let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    var on = allOn
    on[2] = false
    #expect(FirstWeek.weekChange(before: FirstWeek.plan(on: allOn), after: FirstWeek.plan(on: on), index: 2, dayNames: names)
        == "Wednesday off. The first pattern moves to Thursday.")
    on[6] = false
    let before = FirstWeek.plan(on: on.enumerated().map { $0.offset == 6 ? true : $0.element })
    #expect(FirstWeek.weekChange(before: before, after: FirstWeek.plan(on: on), index: 6, dayNames: names) == "Sunday off. The letter still comes.")
}

@Test func theStarterContextsPicksReachTheWeek() {
    let a = [2: "The launch, mostly.", 3: "Around 9:30, after dinner, on the sofa", 4: "More sleep, less rehearsing conversations"]
    let spans = Onboarding.picks(answers: a)
    let ritual = FirstWeek.ritualFromSpans(spans)
    #expect(ritual.source == .answer)
    #expect(ritual.minutes == 21 * 60 + 30, "About you reads a bare 9:30 as evening, and so does the week")
    #expect(ritual.span?.text == "Around 9:30")
    #expect(FirstWeek.checkInNote(goal: spans.first { $0.kind == .goal }?.text) == "How’s “more sleep” going?")
    let ritual3 = { (s: String) in FirstWeek.ritualFromSpans(Onboarding.picks(answers: [3: s])) }
    #expect(ritual3("in bed at 10:30").minutes == 22 * 60 + 30)
    #expect(ritual3("Late, usually.").minutes == 23 * 60)
    #expect(ritual3("around midnight").minutes == 0)
    #expect(ritual3("After the kids are down").source == .default)
}

@Test func spansAreReadDefensively() {
    // The kit's picks are typed, so what's left to be defensive about is a pick with nothing usable in it.
    let blank = Pick(kind: .time, text: "  ", value: "", start: 0, end: 2, q: 3)
    let goal = Pick(kind: .goal, text: "", value: "", start: 0, end: 0, q: 4)
    #expect(FirstWeek.ritualFromSpans([blank, goal]).source == .default)
    #expect(FirstWeek.ritualFromSpans([blank, Pick(kind: .time, text: " evenings ", value: "evenings", start: 0, end: 10, q: 3)]).source == .answer)
    #expect(FirstWeek.ritualFromSpans([]).minutes == FirstWeek.defaultMinutes)
    #expect(FirstWeek.checkInNote(goal: "") == "How’s the week sitting?")
}

@Test func aStoredRitualIsCheckedBeforeItIsTrusted() {
    let good = #"{"ritualMinutes": 450, "ritualWeekdays": 127, "ritualSource": "answer", "weekStartedOn": "2026-09-28""#
    let ritual = { (json: String) in Prefs.decode(Data(json.utf8)) }
    let p = ritual(good + "}")
    #expect(p.ritualMinutes == 450 && p.ritualWeekdays == 127 && p.ritualSource == .answer && p.weekStartedOn == "2026-09-28")
    #expect(ritual(good.replacingOccurrences(of: "450", with: "1440") + "}").ritualMinutes == Prefs().ritualMinutes)
    #expect(ritual(good + #", "ritualSuggested": 1290}"#).ritualSuggested == 1290)
    #expect(ritual(good + #", "ritualSuggested": "soon"}"#).ritualSuggested == nil)
    #expect(ritual(good.replacingOccurrences(of: "2026-09-28", with: "Monday") + "}").weekStartedOn == nil)
    #expect(ritual("{") == Prefs() && Prefs.decode(nil) == Prefs())
}

@Test func withoutANormalisedValueEveningAndMorningWordsDecideABareClock() {
    #expect(time("Around 9:30, after dinner").minutes == 21 * 60 + 30)
    #expect(time("in bed at 10:30").minutes == 22 * 60 + 30)
    #expect(time("9:30 before breakfast").minutes == 9 * 60 + 30)
    #expect(time("07:30").minutes == 7 * 60 + 30)
    #expect(time("at 9").minutes == 21 * 60)
    #expect(time("around midnight").minutes == 0)
    #expect(time("tonight").minutes == 21 * 60 + 30)
    #expect(time("a fortnight from now").source == .default)
}

@Test func clockLabelsAndTheTimeAnnouncement() {
    #expect(FirstWeek.timeChange(450) == "Reminder at 7:30 am. Mornings.")
    #expect(FirstWeek.clockLabel(1290) == "9:30 pm")
    #expect(FirstWeek.clockLabel(0) == "12:00 am")
    #expect(FirstWeek.clockLabel(750) == "12:30 pm")
    #expect(FirstWeek.clockLabel(1290, hour12: false) == "21:30", "as a 24-hour time field shows it")
    #expect(FirstWeek.clockLabel(450, hour12: false) == "07:30")
    #expect(FirstWeek.timeChange(450, hour12: false) == "Reminder at 07:30. Mornings.")
}

@Test func aTypedTimeSnapsToTheQuarterHourAndKeepsTheHalfOfTheDay() {
    #expect(FirstWeek.parseTyped("7:30", near: 1290) == 19 * 60 + 30)
    #expect(FirstWeek.parseTyped("7:30", near: 450) == 450)
    #expect(FirstWeek.parseTyped("7:30 am", near: 1290) == 450)
    #expect(FirstWeek.parseTyped("9pm", near: 450) == 1260)
    #expect(FirstWeek.parseTyped("19.40", near: 450) == 19 * 60 + 45)
    #expect(FirstWeek.parseTyped("07:30", near: 1290) == 450)
    #expect(FirstWeek.parseTyped("12 am", near: 1290) == 0)
    #expect(FirstWeek.parseTyped("23:55", near: 1290) == 0)
    #expect(FirstWeek.parseTyped("25:00", near: 1290) == nil)
    #expect(FirstWeek.parseTyped("soon", near: 1290) == nil)
}

// MARK: firstWeekLight.test.ts

@Test func theEntranceLightsEachDayInTurnAndIsStillBy2point3s() {
    let step = WeekLight.stepWide
    let at0 = WeekLight.ignition(0, step: step)
    #expect(at0.horizon == 0)
    #expect(at0.days.allSatisfy { $0.glow == 0 && $0.core == 0 })
    for i in 0..<7 {
        let peak = WeekLight.ignition(WeekLight.dayAt(i, step: step) + 0.06, step: step)
        #expect(abs(peak.days[i].core - 1.8) < 1e-9, "day \(i) flashes to 1.8")
        #expect(abs(peak.days[i].glow - 1.5) < 1e-9, "and its glow pulses to 1.5")
        if i < 6 { #expect(peak.days[i + 1].core == 0, "day \(i + 1) is still dark") }
    }
    #expect(String(format: "%.2f", WeekLight.dayAt(6, step: step)) == "1.67")
    #expect(String(format: "%.2f", WeekLight.restAt(step: step)) == "1.95")
    #expect(abs(WeekLight.ignition(WeekLight.dayAt(6, step: step) + 0.12, step: step).surge - 1.2) < 1e-9)
    let end = WeekLight.ignition(WeekLight.entranceEnd(step: step), step: step)
    #expect(end == WeekLight.ignition(.infinity, step: step), "the last frame is the resting frame")
    #expect(end.days.allSatisfy { $0.glow == 1 && $0.core == 1 && $0.size == 1 } && end.crest == 1 && end.surge == 1 && end.horizon == 1)
    #expect(WeekLight.entranceEnd(step: step) <= 2.3)
    #expect(WeekLight.entranceEnd(step: WeekLight.stepNarrow) < WeekLight.entranceEnd(step: step))
}

@Test func bezierFollowsTheCurve() {
    let inOut = WeekLight.bezier(0.77, 0, 0.175, 1)
    #expect(inOut(0) == 0)
    #expect(inOut(1) == 1)
    #expect(inOut(0.2) < 0.1 && inOut(0.8) > 0.9)
    #expect(abs(WeekLight.bezier(0.42, 0, 0.58, 1)(0.5) - 0.5) < 1e-6, "a symmetric curve is halfway at halfway")
    #expect(abs(WeekLight.bezier(0, 0, 1, 1)(0.3) - 0.3) < 1e-6, "a straight one is linear")
}

@Test func skippingADayDropsItsLightToAnEmber() {
    #expect(WeekLight.dayLevel(3, on: false) == WeekLight.DayLevel(power: 0.12, size: 0.6, sink: 6, on: 0))
    #expect(WeekLight.dayLevel(6, on: true).power == 1)
    #expect(WeekLight.dayLevel(0, on: true).power < WeekLight.dayLevel(5, on: true).power)
}

// MARK: light-check.test.ts

/// A 64×36 grey frame; `at(x, y)` gives each pixel's brightness (0–1).
private func frame(_ at: (Int, Int) -> Double) -> [UInt8] {
    var rgba = [UInt8](repeating: 255, count: LightRead.width * LightRead.height * 4)
    for y in 0..<LightRead.height {
        for x in 0..<LightRead.width {
            let v = UInt8((at(x, y) * 255).rounded())
            let i = (y * LightRead.width + x) * 4
            (rgba[i], rgba[i + 1], rgba[i + 2]) = (v, v, v)
        }
    }
    return rgba
}

private func centre(_ x: Int, _ y: Int) -> Bool { (20..<44).contains(x) && (5..<26).contains(y) }

@Test func readLightEvenDarkBacklitAndBright() {
    #expect(LightRead.readLight(frame { _, _ in 0.5 }) == .good)
    #expect(LightRead.readLight(frame { _, _ in 0.1 }) == .dark)
    #expect(LightRead.readLight(frame { centre($0, $1) ? 0.1 : 0.8 }) == .backlit)
    #expect(LightRead.readLight(frame { centre($0, $1) ? 0.99 : 0.5 }) == .bright)
}

@Test func aBrightRightEdgeOfTheUnmirroredFrameIsOnTheirLeft() {
    let dir = LightRead.lightDirection(frame { x, _ in x >= 56 ? 0.9 : 0.4 })
    #expect(dir.side == .left)
    #expect(dir.strength > 0.08)
    #expect(LightRead.lightDirection(frame { _, _ in 0.5 }).strength < 0.04)
}

@Test func readFramingCloseFarOffCentreAndGood() {
    #expect(LightRead.readFraming(nil) == .none)
    #expect(LightRead.readFraming(CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.7)) == .close)
    #expect(LightRead.readFraming(CGRect(x: 0.45, y: 0.2, width: 0.1, height: 0.15)) == .far)
    #expect(LightRead.readFraming(CGRect(x: 0.05, y: 0.15, width: 0.3, height: 0.4)) == .off)
    #expect(LightRead.readFraming(CGRect(x: 0.35, y: 0.15, width: 0.3, height: 0.4)) == .good)
}

@Test func aReadingShowsAfter3SamplesAndChangesAtMostEvery2s() {
    var hold = LightRead.Hold<String>(hold: 3, minMs: 2000)
    #expect(hold("dark", now: 0) == nil)
    #expect(hold("dark", now: 166) == nil)
    #expect(hold("dark", now: 332) == "dark")
    for t in [500.0, 666, 832] { _ = hold("good", now: t) }
    #expect(hold("good", now: 1000) == "dark")
    #expect(hold("good", now: 2400) == "good")
}

@Test func theMicIsHeardThenSilentAfter4Seconds() {
    #expect(LightRead.mic(now: 1, started: 0, lastHeard: nil) == .waiting)
    #expect(LightRead.mic(now: 4.5, started: 0, lastHeard: nil) == .silent)
    #expect(LightRead.mic(now: 5, started: 0, lastHeard: 4) == .heard)
    #expect(LightRead.mic(now: 7, started: 0, lastHeard: 4) == .waiting)
}
