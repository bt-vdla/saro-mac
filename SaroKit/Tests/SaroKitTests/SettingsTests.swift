import Foundation
@testable import SaroKit
import Testing

// Ports of parseIntent.test.ts, tonePreview.test.ts, rhythm.test.ts, exportBook.test.ts and aiLog.test.ts, plus the
// ledger's data paths: storage, What Saro read, the book, export → import, and erase.

private typealias P = ParseIntent

/// The web tests' context: reminder off at 9 pm, letter 6 pm, 100%, follow the day, Gentle, focus Clarity.
private func values(_ change: (inout SettingsValues) -> Void = { _ in }) -> SettingsValues {
    var v = SettingsValues()
    change(&v)
    return v
}

private func changes(_ text: String, _ v: SettingsValues, sourceLocation: SourceLocation = #_sourceLocation) -> [P.Change] {
    guard case .changes(let list, _, _) = P.parse(text, current: v) else {
        Issue.record("\(text) → \(P.parse(text, current: v))", sourceLocation: sourceLocation)
        return []
    }
    return list
}

private func summary(_ list: [P.Change]) -> [String] { list.map { "\($0.key.rawValue): \($0.from) → \($0.to)" } }
private func note(_ text: String, _ v: SettingsValues) -> String? {
    if case .changes(_, let note, _) = P.parse(text, current: v) { return note }
    return nil
}
private func hm(_ h: Int, _ m: Int = 0) -> Int { h * 60 + m }
private func clock(_ h: Int, _ m: Int = 0, pm: Bool) -> P.Clock { .time(minutes: hm(h, m), assumedPm: pm) }

@Suite struct ParseIntentTests {
    @Test func clockTimes() {
        #expect(P.parseClock("at 9") == clock(21, pm: true))
        #expect(P.parseClock("9:30") == clock(21, 30, pm: true))
        #expect(P.parseClock("at 10") == clock(22, pm: true))
        #expect(P.parseClock("10:40") == clock(22, 40, pm: true))
        #expect(P.parseClock("at 11") == clock(23, pm: true))
        #expect(P.parseClock("11:30") == clock(23, 30, pm: true))
        #expect(P.parseClock("at 1") == clock(13, pm: true))
        #expect(P.parseClock("9 30") == clock(21, 30, pm: true))
        #expect(P.parseClock("930") == clock(21, 30, pm: true))
        #expect(P.parseClock("9pm") == clock(21, pm: false))
        #expect(P.parseClock("7 am") == clock(7, pm: false))
        #expect(P.parseClock("10:40 am") == clock(10, 40, pm: false))
        #expect(P.parseClock("21:30") == clock(21, 30, pm: false))
        #expect(P.parseClock("09:30") == clock(9, 30, pm: false))
        #expect(P.parseClock("12") == clock(12, pm: false))
        #expect(P.parseClock("0") == clock(0, pm: false))
        #expect(P.parseClock("30 min earlier") == nil)
        #expect(P.parseClock("text 125%") == nil)
        #expect(P.parseClock("text 112.5%") == nil)
        #expect(P.parseClock("25:00") == .invalid("25:00"))
        #expect(P.parseClock("at 25") == .invalid("25"))
        #expect(P.parseClock("9:75") == .invalid("9:75"))
        #expect(P.parseClock("13pm") == .invalid("13pm"))
    }

    @Test func reminders() {
        let on = values { ($0.reminderOn, $0.reminderMinutes) = (true, hm(21, 30)) }
        #expect(summary(changes("remind me at 9", on)) == ["reminder: 9:30 pm → 9:00 pm"])
        #expect(changes("remind me at 9", on).first?.why.contains("evening") == true)
        #expect(changes("remind me at 2", on).first?.why == "Read as afternoon: 2:00 pm, not morning")
        #expect(summary(changes("remind me later", on)) == ["reminder: 9:30 pm → 10:00 pm"])
        #expect(summary(changes("move my reminder 30 min earlier", on)) == ["reminder: 9:30 pm → 9:00 pm"])
        #expect(summary(changes("an hour later", on)) == ["reminder: 9:30 pm → 10:30 pm"])
        #expect(summary(changes("turn off reminders", on)) == ["reminder: 9:30 pm → Off"])
        #expect(P.parse("remind me at 9:30 pm", current: on) == .alreadySet("Your reminder is already 9:30 pm."))
        let off = values()
        #expect(summary(changes("remind me at 21:30", off)) == ["reminder: Off → 9:30 pm"])
        #expect(summary(changes("set up a reminder", off)) == ["reminder: Off → 9:00 pm"])
        #expect(summary(changes("remind me at 10", off)) == ["reminder: Off → 10:00 pm"])
        #expect(summary(changes("remind me at 10:40", off)) == ["reminder: Off → 10:40 pm"])
        #expect(summary(changes("remind me at 9 30", off)) == ["reminder: Off → 9:30 pm"])
        #expect(summary(changes("remind me when it gets dark", off)) == ["reminder: Off → 8:00 pm"])
        #expect(summary(changes("don't remind me at 9", on)) == ["reminder: 9:30 pm → Off"])
    }

    @Test func morningAndEveningWords() {
        #expect(P.parseClock("at 7 in the morning") == clock(7, pm: false))
        #expect(P.parseClock("every morning at 7") == clock(7, pm: false))
        #expect(P.parseClock("at 10 at night") == clock(22, pm: false))
        #expect(P.parseClock("at 3 in the afternoon") == clock(15, pm: false))
        #expect(P.parseClock("12 at night") == clock(0, pm: false))
        #expect(P.parseClock("19 in the morning") == .invalid("19"))
        let off = values()
        let morning = changes("remind me at 7 in the morning", off)
        #expect(summary(morning) == ["reminder: Off → 7:00 am"])
        #expect(morning.first?.why.contains("evening") == false)
        #expect(summary(changes("remind me every morning at 7", off)) == ["reminder: Off → 7:00 am"])
        #expect(summary(changes("remind me in the morning", off)) == ["reminder: Off → 8:00 am"])
        #expect(summary(changes("remind me in the evening", off)) == ["reminder: Off → 9:00 pm"])
        #expect(summary(changes("send my letter at 8 in the evening", off)) == ["letterTime: after 6:00 pm → after 8:00 pm"])
    }

    @Test func timesInWords() {
        let off = values()
        let cases: [(String, String)] = [
            ("remind me at ten thirty", "10:30 pm"), ("remind me at half past nine", "9:30 pm"), ("remind me at nine", "9:00 pm"),
            ("remind me at quarter to ten", "9:45 pm"), ("remind me at seven o'clock in the morning", "7:00 am"),
            ("remind me at eight oh five am", "8:05 am"), ("at seven forty-five", "7:45 pm"),
            ("remind me at half past 9 in the morning", "9:30 am"), ("remind me at quarter to 10", "9:45 pm"),
            ("remind me at nine-thirty", "9:30 pm"), ("remind me at eight-oh-five", "8:05 pm"), ("remind me at 5 to 9", "8:55 pm"),
            ("remind me at 20 past 7", "7:20 pm"), ("remind me at 5 minutes to 9 in the morning", "8:55 am"),
            ("move my reminder from 8 to 9", "9:00 pm"), ("move my reminder from ten to eleven", "11:00 pm"),
            ("change the reminder 8 to 9", "9:00 pm"), ("move my morning reminder from 7 to 8", "8:00 am"),
        ]
        for (text, to) in cases { #expect(summary(changes(text, off)) == ["reminder: Off → \(to)"], "\(text)") }
        #expect(P.parse("remind me at teatime", current: off) == .alreadySet("I couldn’t read “teatime” as a time. Try 9:30 pm or 21:30."))
        #expect(P.parse("remind me at half past", current: off) == .alreadySet("I couldn’t read “half past” as a time. Try 9:30 pm or 21:30."))
        #expect(summary(changes("don't remind me at all", values { $0.reminderOn = true })) == ["reminder: 9:00 pm → Off"])
    }

    @Test func unreadableTimes() {
        let v = values()
        #expect(P.parse("remind me at 25", current: v) == .alreadySet("I couldn’t read “25” as a time. Try 9:30 pm or 21:30."))
        #expect(P.parse("remind me at 9:75", current: v) == .alreadySet("I couldn’t read “9:75” as a time. Try 9:30 pm or 21:30."))
        #expect(summary(changes("remind me at 25 and bigger text", v)) == ["textScale: 100% → 112.5%"])
        #expect(note("remind me at 25 and bigger text", v)?.contains("couldn’t read “25”") == true)
    }

    @Test func letterTime() {
        let v = values()
        #expect(summary(changes("send my letter at 7", v)) == ["letterTime: after 6:00 pm → after 7:00 pm"])
        #expect(summary(changes("letter an hour later", v)) == ["letterTime: after 6:00 pm → after 7:00 pm"])
        #expect(note("send my letter at 7", v) == nil)
        #expect(summary(changes("letter at 7am", v)) == ["letterTime: after 6:00 pm → after 7:00 am"])
        #expect(note("letter at 7am", v) == "The evening letter is written from your day. At 7:00 am it opens before most of the day has happened.")
        #expect(note("letter at 3", v)?.contains("At 3:00 pm it opens before") == true)
        #expect(note("letter an hour earlier", values { $0.letterMinutes = hm(17, 30) })?.contains("At 4:30 pm") == true)
    }

    @Test func fromOneTimeToAnother() {
        let on = values { ($0.reminderOn, $0.reminderMinutes) = (true, hm(21, 30)) }
        #expect(summary(changes("move my reminder from 9:30 to 10", on)) == ["reminder: 9:30 pm → 10:00 pm"])
        let off = values()
        for (text, to) in [("move my reminder from 9:30 to 10", "10:00 pm"), ("change reminder from 8:30 to 9", "9:00 pm"),
                           ("move reminder from 7.45 to 8", "8:00 pm"), ("change my reminder from 9:15 to 9:45", "9:45 pm"),
                           ("move my reminder from 10:20 to 11", "11:00 pm"), ("move my reminder from half nine to ten", "10:00 pm")] {
            #expect(summary(changes(text, off)) == ["reminder: Off → \(to)"], "\(text)")
        }
    }

    @Test func dashesAndMinutesToTheHour() {
        let off = values()
        #expect(summary(changes("remind me at 7-30", off)) == ["reminder: Off → 7:30 pm"])
        #expect(summary(changes("7-30", off)) == ["reminder: Off → 7:30 pm"])
        #expect(summary(changes("remind me at 3 to 9", off)) == ["reminder: Off → 8:57 pm"])
        #expect(summary(changes("remind me at 1 to 2", off)) == ["reminder: Off → 1:59 pm"])
        #expect(changes("remind me at 1 to 2", off).first?.why.contains("afternoon") == true)
    }

    @Test func toneThemeSizeAndComfort() {
        let v = values()
        #expect(summary(changes("be more direct", v)) == ["tone: Gentle → Direct"])
        #expect(summary(changes("blunter please", v)) == ["tone: Gentle → Direct"])
        #expect(summary(changes("more thoughtful", v)) == ["tone: Gentle → Contemplative"])
        #expect(P.parse("softer", current: v) == .alreadySet("Saro already talks this way: Gentle."))
        #expect(summary(changes("dark mode", v)) == ["theme: Follow the day → Dark"])
        #expect(summary(changes("bigger text", v)) == ["textScale: 100% → 112.5%"])
        #expect(summary(changes("make the text 125%", v)) == ["textScale: 100% → 125%"])
        #expect(summary(changes("captions always on", v)) == ["captionsAlways: Off → On"])
        #expect(summary(changes("reduce motion", v)) == ["reduceMotion: Follow device → On"])
        #expect(summary(changes("less blur", v)) == ["reduceTransparency: Follow device → On"])
        #expect(summary(changes("turn blur off", v)) == ["reduceTransparency: Follow device → On"])
        #expect(summary(changes("solid backgrounds", v)) == ["reduceTransparency: Follow device → On"])
        #expect(summary(changes("reduce motion and transparency", v)) == ["reduceMotion: Follow device → On", "reduceTransparency: Follow device → On"])
        #expect(summary(changes("pause memory", v)) == ["memoryPaused: On → Paused"])
        #expect(summary(changes("turn on sounds and haptics", v)) == ["sounds: Off → On", "haptics: Off → On"])
        // The Mac's sizes go to 150%.
        #expect(summary(changes("bigger text", values { $0.textScale = 1.25 })) == ["textScale: 125% → 150%"])
        let big = values { ($0.textScale, $0.reduceMotion) = (1.5, true) }
        #expect(P.parse("bigger text", current: big) == .alreadySet("Text is already at its largest, 150%."))
        #expect(summary(changes("don't reduce motion", big)) == ["reduceMotion: On → Follow device"])
        #expect(summary(changes("turn animations on", big)) == ["reduceMotion: On → Follow device"])
    }

    @Test func moreBlurNeverReducesTransparency() {
        let reduced = values { $0.reduceTransparency = true }
        for text in ["turn blur on", "enable blur", "I like the glass", "more transparency please", "bring the blur back"] {
            #expect(summary(changes(text, reduced)) == ["reduceTransparency: On → Follow device"], "\(text)")
        }
        for text in ["turn blur on", "enable blur", "I like the glass", "more transparency please"] {
            #expect(P.parse(text, current: values()) == .alreadySet("Transparency already follows your device."), "\(text)")
        }
    }

    @Test func severalAtOnce() {
        let v = values()
        #expect(summary(changes("remind me at 9:30 and make it dark, bigger text", v))
            == ["reminder: Off → 9:30 pm", "theme: Follow the day → Dark", "textScale: 100% → 112.5%"])
        #expect(summary(changes("bigger text in dark mode", v)) == ["theme: Follow the day → Dark", "textScale: 100% → 112.5%"])
        #expect(summary(changes("remind me when it gets dark", v)) == ["reminder: Off → 8:00 pm"])
        #expect(summary(changes("make it light and playful", values { $0.tone = .direct })) == ["tone: Direct → Gentle"])
        #expect(P.parse("make it light and playful", current: v) == .alreadySet("Saro has no playful tone yet. Gentle is the closest, and it’s already on."))
        let neutral = values { $0.tone = .neutral }
        #expect(summary(changes("keep it light and playful", neutral)) == ["tone: Neutral → Gentle"])
        #expect(note("keep it light and playful", neutral) == nil)
        #expect(summary(changes("light mode", v)) == ["theme: Follow the day → Light"])
        #expect(summary(changes("turn off captions, dark mode", values { $0.captionsAlways = true }))
            == ["captionsAlways: On → Off", "theme: Follow the day → Dark"])
        #expect(summary(changes("dark mode off", values { $0.theme = .dark })) == ["theme: Dark → Light"])
        let mixed = "remind me at 10 and bigger text, turn blur on, be more direct"
        #expect(summary(changes(mixed, v)) == ["reminder: Off → 10:00 pm", "textScale: 100% → 112.5%", "tone: Gentle → Direct"])
        #expect(note(mixed, v) == "Transparency already follows your device.")
        #expect(summary(changes("forget about the reminder, turn on dark mode", values { $0.reminderOn = true }))
            == ["reminder: 9:00 pm → Off", "theme: Follow the day → Dark"])
    }

    @Test func focusAddRemoveOnlyAndThree() {
        let v = values()
        #expect(summary(changes("focus on sleep and relationships", v)) == ["focus: Clarity → Clarity, Relationships, Energy"])
        #expect(summary(changes("stop focusing on clarity", v)) == ["focus: Clarity → None"])
        #expect(summary(changes("only focus on habits", v)) == ["focus: Clarity → Habits"])
        #expect(summary(changes("drop clarity", v)) == ["focus: Clarity → None"])
        let full = values { $0.focus = [.clarity, .habits, .energy] }
        #expect(P.parse("add purpose to my focus", current: full) == .alreadySet("You can pick 3. Drop one first."))
        #expect(P.parse("be more direct", current: values { ($0.tone, $0.focus) = (nil, nil) }) == .none)
    }

    @Test func needsYouAndNonsense() {
        let v = values()
        #expect(P.parse("delete everything", current: v) == .needsYou)
        #expect(P.parse("forget about Maya", current: v) == .needsYou)
        guard case .changes = P.parse("don't forget to remind me at 9", current: v) else { Issue.record("not a change"); return }
        #expect(P.parse("what is the weather", current: v) == .none)
        #expect(P.parse("   ", current: v) == .none)
    }

    @Test func proposalsTakeOneKeyAtATime() {
        let v = values { ($0.reminderOn, $0.reminderMinutes) = (true, hm(21, 30)) }
        guard case .changes(_, _, let proposed) = P.parse("remind me later and dark mode", current: v) else { Issue.record("no change"); return }
        let applied = v.taking(.reminder, from: proposed)
        #expect(applied.reminderMinutes == hm(22) && applied.theme == .clock)
        #expect(applied.taking(.reminder, from: v) == v)
        #expect(P.valid(proposed))
        #expect(!P.valid(values { $0.focus = [.clarity, .habits, .energy, .purpose] }))
    }
}

@Suite struct TonePreviewTests {
    let s = "You slept better on the nights you ran, and the mornings after felt lighter."
    func said(_ text: String) -> String { TonePreview.previewSentence(TonePreview.toSecondPerson(text)) }
    let tail = " You’re doing better than you think."

    @Test func neutralAndGentle() {
        #expect(TonePreview.rewrite(s, tone: .neutral) == s)
        #expect(TonePreview.rewrite(s, tone: .gentle) == "It seems you slept better on the nights you ran, and the mornings after felt lighter." + tail)
        #expect(TonePreview.rewrite(TonePreview.sample, tone: .gentle).hasPrefix("It seems you slept"))
        #expect(TonePreview.rewrite("Maya came up three times.", tone: .gentle) == "Maya came up three times." + tail)
        #expect(TonePreview.rewrite("Woke up tired again.", tone: .gentle) == "Woke up tired again." + tail)
        #expect(TonePreview.rewrite("Didn’t sleep much.", tone: .gentle) == "Didn’t sleep much." + tail)
    }

    @Test func firstPersonOpenings() {
        #expect(TonePreview.rewrite(said("I've been sleeping badly all week."), tone: .gentle) == "It seems you’ve been sleeping badly all week." + tail)
        #expect(TonePreview.rewrite(said("I’m tired of work."), tone: .gentle) == "It seems you’re tired of work." + tail)
        #expect(TonePreview.rewrite(said("I'll try again tomorrow."), tone: .gentle) == "It seems you’ll try again tomorrow." + tail)
        #expect(TonePreview.rewrite(said("I'd rather stay in."), tone: .gentle) == "It seems you’d rather stay in." + tail)
        #expect(TonePreview.rewrite(said("Mine was the best."), tone: .gentle) == "It seems yours was the best." + tail)
        #expect(TonePreview.rewrite(said("It’s been a long week."), tone: .gentle) == "It seems it’s been a long week." + tail)
        #expect(TonePreview.rewrite(said("I’m tired of work."), tone: .direct) == "You’re tired of work.")
    }

    @Test func quotesAndAbbreviations() {
        let mum = said("my mum said \"I love you\" today.")
        #expect(mum == "Your mum said \"I love you\" today.")
        for tone in Tone.allCases { #expect(TonePreview.rewrite(mum, tone: tone).contains("\"I love you\""), "\(tone)") }
        let tired = said("I was tired, i.e. exhausted. Then I slept.")
        #expect(tired == "You were tired, i.e. exhausted.")
        #expect(TonePreview.rewrite(tired, tone: .gentle) == "It seems you were tired, i.e. exhausted." + tail)
        #expect(TonePreview.previewSentence("Saw Dr. Patel, e.g. the usual checkup. Then home.") == "Saw Dr. Patel, e.g. the usual checkup.")
        #expect(TonePreview.previewSentence("Ran at 7 a.m. Then work.") == "Ran at 7 a.m.")
    }

    @Test func direct() {
        #expect(TonePreview.rewrite(s, tone: .direct) == "You slept better on the nights you ran.")
        #expect(TonePreview.rewrite(TonePreview.sample, tone: .direct) == "You slept better on the nights you ran.")
        #expect(TonePreview.rewrite("You wrote \"phone in the kitchen, lights out by eleven\", twice.", tone: .direct)
            == "You wrote \"phone in the kitchen, lights out by eleven\".")
        let words = "In your words: \"Woke up before the alarm and actually felt rested\"."
        #expect(TonePreview.rewrite(words, tone: .direct) == "\"Woke up before the alarm and actually felt rested\".")
        #expect(TonePreview.rewrite(words, tone: .gentle) == words + tail)
        #expect(TonePreview.rewrite("You put it like this: \"phone in the kitchen\".", tone: .direct) == "\"Phone in the kitchen\".")
        #expect(TonePreview.rewrite("You also talked about work on Monday.", tone: .direct) == "You talked about work on Monday.")
        #expect(TonePreview.rewrite("Work came up on Monday too.", tone: .gentle) == "It seems work came up on Monday too." + tail)
        #expect(TonePreview.rewrite("The pattern is clear: you sleep better after a run.", tone: .direct) == "You sleep better after a run.")
    }

    @Test func questionsFragmentsAndSoftSentences() {
        let q = "Why do you keep doing this?"
        #expect(TonePreview.rewrite(q, tone: .direct) == q)
        #expect(TonePreview.rewrite(q, tone: .gentle) == "A gentle question: why do you keep doing this? There’s no wrong answer.")
        #expect(TonePreview.rewrite(q, tone: .contemplative) == q)
        #expect(TonePreview.rewrite("You seemed calm.", tone: .gentle) == "You seemed calm." + tail)
        #expect(TonePreview.rewrite("Just a bit tired.", tone: .gentle) == "Just a bit tired." + tail)
        #expect(TonePreview.rewrite("Just a bit tired.", tone: .direct) == "Tired.")
        #expect(TonePreview.rewrite("A day shaped by work.", tone: .gentle) == "A day shaped by work." + tail)
        #expect(TonePreview.rewrite("You wrote \"just a bit tired, really\".", tone: .direct) == "\"Just a bit tired, really\".")
        #expect(TonePreview.rewrite("You said \"it finally shipped\".", tone: .gentle) == "You said \"it finally shipped\"." + tail)
        #expect(TonePreview.rewrite(s, tone: .contemplative) == "\(s.dropLast()). What do you make of that?")
        #expect(TonePreview.rewrite("What would a quiet week look like?", tone: .contemplative) == "What would a quiet week look like?")
    }

    @Test func previewAndSecondPerson() {
        #expect(TonePreview.previewSentence("  Sleep came up twice.  You also wrote about Maya. ") == "Sleep came up twice.")
        #expect(TonePreview.previewSentence("You said \"it shipped. finally.\" on Monday.") == "You said \"it shipped. finally.\" on Monday.")
        #expect(TonePreview.previewSentence(String(repeating: "word ", count: 60)).count <= 140)
        #expect(TonePreview.toSecondPerson("I think my run helped, and I'm sleeping better.") == "You think your run helped, and you’re sleeping better.")
        #expect(TonePreview.toSecondPerson("Maya told me I was calmer.") == "Maya told you you were calmer.")
        #expect(TonePreview.toSecondPerson("i was tired and my head hurt, but I kept going") == "You were tired and your head hurt, but you kept going")
        #expect(TonePreview.toSecondPerson("i'm fine, i.e. mostly fine") == "You’re fine, i.e. mostly fine")
        #expect(TonePreview.toSecondPerson("iPhone died again") == "iPhone died again")
    }

    @Test func capitals() {
        #expect(TonePreview.rewrite("THE BEST DAY EVER.", tone: .gentle) == "THE BEST DAY EVER." + tail)
        #expect(TonePreview.rewrite("THE BEST DAY EVER.", tone: .direct) == "THE BEST DAY EVER.")
        #expect(TonePreview.rewrite("iPhone died again, so no photos.", tone: .direct) == "iPhone died again.")
        #expect(TonePreview.rewrite("eBay order finally came, and it was worth it.", tone: .direct) == "eBay order finally came.")
        #expect(TonePreview.rewrite("slept badly again.", tone: .gentle) == "Slept badly again." + tail)
        #expect(TonePreview.rewrite("slept badly again.", tone: .contemplative) == "Slept badly again. What do you make of that?")
        #expect(TonePreview.rewrite("why am I like this?", tone: .contemplative) == "Why am I like this?")
    }
}

@Suite struct RhythmTests {
    let today = "2026-09-26"
    func at(_ daysAgo: Int, _ h: Int, _ m: Int) -> Rhythm.EntryTime { .init(localDay: LocalDay.adding(-daysAgo, to: today), minutes: h * 60 + m) }
    func t(_ s: String) -> (Int, Int) { let p = s.split(separator: ":").map { Int($0)! }; return (p[0], p[1]) }

    @Test func clockHelpers() {
        #expect(Rhythm.mod(-15) == 23 * 60 + 45)
        #expect(Rhythm.formatClock(0) == "12:00 am")
        #expect(Rhythm.formatClock(720) == "12:00 pm")
        #expect(Rhythm.formatClock(22 * 60 + 40) == "10:40 pm")
        #expect(Rhythm.formatRange(590 + 720, 690 + 720) == "9:50 to 11:30 pm")
        #expect(Rhythm.formatRange(23 * 60 + 30, 40) == "11:30 pm to 12:40 am")
        #expect(Rhythm.circularGap(23 * 60 + 50, 10) == 20)
    }

    @Test func midnightNotNoon() {
        let m = Rhythm.circularMean([(23 * 60 + 50, 1), (10, 1)])
        #expect(m?.mean == 0)
        #expect((m?.r ?? 0) > 0.99)
    }

    @Test func everyDayCountsOnce() throws {
        let times = [1, 2, 3, 4, 5].map { at($0, 22, 0) } + Array(repeating: at(0, 8, 0), count: 4)
        let s = try #require(Rhythm.stats(times, today: today))
        #expect(s.days == 6 && s.entries == 9)
        #expect(Rhythm.circularGap(s.mean, 22 * 60) < 60)
    }

    @Test func tightEveningHabit() throws {
        let times = ["22:30", "22:50", "22:40", "22:35", "22:45", "22:40"].enumerated().map { at($0.offset + 1, t($0.element).0, t($0.element).1) }
        let s = Rhythm.stats(times, today: today)
        #expect(Rhythm.usualTime(s) == 22 * 60 + 40)
        let now = LocalDay.date(today)!
        #expect(Rhythm.suggestReminder(s, reminderOn: true, reminderMinutes: 21 * 60, dismissedAt: nil, now: now) == .init(usual: 1360, target: 1345))
        #expect(Rhythm.suggestReminder(s, reminderOn: false, reminderMinutes: 22 * 60 + 25, dismissedAt: nil, now: now) == .init(usual: 1360, target: 1345))
        #expect(Rhythm.suggestReminder(s, reminderOn: true, reminderMinutes: 22 * 60 + 10, dismissedAt: nil, now: now) == nil)
        #expect(Rhythm.suggestReminder(s, reminderOn: true, reminderMinutes: 21 * 60, dismissedAt: now.addingTimeInterval(-7 * 86_400), now: now) == nil)
        #expect(Rhythm.suggestReminder(s, reminderOn: true, reminderMinutes: 21 * 60, dismissedAt: now.addingTimeInterval(-15 * 86_400), now: now) != nil)
        #expect(Rhythm.describe(s).jsTest(#"^6 entries over 6 days, mostly \d+:\d\d to \d+:\d\d pm$"#))
    }

    @Test func scatteredOrTooFew() {
        let scattered = ["07:00", "12:30", "18:00", "23:30", "03:00", "15:00"].enumerated().map { at($0.offset, t($0.element).0, t($0.element).1) }
        let s = Rhythm.stats(scattered, today: today)
        #expect(Rhythm.usualTime(s) == nil)
        #expect(Rhythm.suggestReminder(s, reminderOn: false, reminderMinutes: 1260, dismissedAt: nil) == nil)
        #expect(Rhythm.describe(s).contains("many times of day"))
        #expect(Rhythm.usualTime(Rhythm.stats(["22:30", "22:40", "22:35", "22:45"].enumerated().map { at($0.offset, t($0.element).0, t($0.element).1) }, today: today)) == nil)
        #expect(Rhythm.usualTime(Rhythm.stats(["22:30", "22:40", "22:35", "22:45", "22:50"].enumerated().map { at($0.offset % 3, t($0.element).0, t($0.element).1) }, today: today)) == nil)
    }

    @Test func theThreshold() throws {
        let tight = Rhythm.stats(["22:30", "22:40", "22:35", "22:45", "22:40"].enumerated().map { at(min($0.offset, 3), t($0.element).0, t($0.element).1) }, today: today)
        #expect(tight?.days == 4)
        #expect(Rhythm.circularGap(Rhythm.usualTime(tight) ?? 0, 22 * 60 + 40) <= 10)
        let loose = try #require(Rhythm.stats(["16:30", "23:30", "19:00", "01:00", "21:00", "18:00"].enumerated().map { at($0.offset, t($0.element).0, t($0.element).1) }, today: today))
        #expect(loose.r >= 0.6 && loose.r < 0.8)
        #expect(Rhythm.usualTime(loose) != nil)
    }

    @Test func lastFourteenDaysAndOwnTimeZone() {
        let s = Rhythm.stats([at(13, 22, 0), at(14, 22, 0), at(-1, 22, 0)], today: today)
        #expect(s?.entries == 1)
        #expect(Rhythm.stats([], today: today) == nil)
        // 21:30 UTC captured in Tokyo is 6:30 am there, whatever this Mac's zone.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let tokyo = Rhythm.EntryTime(localDay: today, capturedAt: utc.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 21, minute: 30))!, tzId: "Asia/Tokyo")
        #expect(tokyo.minutes == 6 * 60 + 30)
        #expect(Rhythm.usualTime(Rhythm.stats(Rhythm.sampleFortnight(today: today), today: today)) != nil)
    }
}

@Suite struct FocusCopyTests {
    @Test func everyPickHasItsLine() {
        #expect(FocusCopy.preview([]) == nil)
        #expect(FocusCopy.preview([.creative]) == "Move, then improve.")
        for a in FocusArea.allCases {
            #expect(FocusCopy.single[a] != nil)
            for b in FocusArea.allCases where a != b { #expect(FocusCopy.preview([a, b]) != nil, "\(a) \(b)") }
        }
        #expect(FocusCopy.preview([.steadiness, .clarity]) == "Remove the noise and keep the tempo, not the intensity.")
        #expect(FocusCopy.preview([.clarity, .habits, .energy]) == FocusCopy.three)
    }
}

@Suite struct BookAndStorageTests {
    @Test func storageCountsSharedFilesOnce() {
        let s = StorageSummary(items: [
            .init(entryId: "1", kind: .moment, day: "d", bytes: 150_000_000, file: "a.mov"),
            .init(entryId: "2", kind: .moment, day: "d", bytes: 150_000_000, file: "a.mov"),
            .init(entryId: "3", kind: .voice, day: "d", bytes: 2_000_000, file: "b.caf"),
            .init(entryId: "4", kind: .reflection, day: "d", bytes: 5),
            .init(entryId: "5", kind: .still, day: "d", bytes: -1, file: "c.jpg"),
        ])
        #expect(s.kinds[0].count == 2 && s.kinds[0].bytes == 150_000_000)
        #expect(s.kinds.first { $0.kind == .still }?.bytes == 0)
        #expect(s.totalBytes == 152_000_005 && s.trashBytes == 0)
        #expect(s.largest.first?.bytes == 150_000_000)
        let t = StorageSummary(items: [
            .init(entryId: "1", kind: .moment, day: "d", bytes: 40_000_000, file: "gone.mov", inTrash: true),
            .init(entryId: "2", kind: .moment, day: "d", bytes: 10_000_000, file: "a.mov"),
            .init(entryId: "3", kind: .moment, day: "d", bytes: 10_000_000, file: "a.mov", inTrash: true),
        ])
        #expect(t.kinds[0].count == 1)
        #expect([t.kinds[0].bytes, t.trashBytes, t.totalBytes] == [50_000_000, 40_000_000, 50_000_000] as [Int64])
    }

    let days = [
        Book.Day(day: "2026-09-22", pieces: [
            Book.Piece(kind: .reflection, minutes: 21 * 60 + 5, title: "Reflection – Sep 22", body: Book.paragraphs("A quiet walk.\n\n<script>alert(1)</script>")),
            Book.Piece(kind: .echo, minutes: 8 * 60 + 5, body: []),
            Book.Piece(kind: .still, minutes: 18 * 60 + 5, body: ["River path"]),
            Book.Piece(kind: .letter, minutes: nil, body: ["A slower day. You walked.", "It helped."]),
        ]),
        Book.Day(day: "2026-08-03", pieces: [Book.Piece(kind: .moment, minutes: 20 * 60 + 5, prompt: "What stayed with you?", body: ["Maya laughing & the salt."])]),
        Book.Day(day: "2025-12-30", pieces: [Book.Piece(kind: .reflection, minutes: 540, title: "Old year", body: ["Last December."])]),
    ]

    @Test func oneChapterPerMonthEscaped() {
        let html = Book.build(year: 2026, name: "Alex", days: days, madeAt: LocalDay.date("2026-09-26")!)
        #expect(html.components(separatedBy: "<section class=\"chapter\"").count - 1 == 2)
        #expect(html.range(of: "<h2>August</h2>")!.lowerBound < html.range(of: "<h2>September</h2>")!.lowerBound)
        #expect(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;") && !html.contains("<script>"))
        #expect(html.contains("Maya laughing &amp; the salt."))
        #expect(!html.contains("Last December") && !html.contains("Reflection – Sep 22"))
        #expect(html.contains("Alex, this is your year, in your own words."))
        #expect(html.contains("<p dir=\"auto\">It helped.</p>"))
        #expect(html.contains("3 entries · 1 letter · Made Sep 26, 2026"))
        #expect(html.range(of: "A quiet walk.")!.lowerBound < html.range(of: "A slower day. You walked.")!.lowerBound)
        #expect(html.range(of: "Still · 6:05 pm")!.lowerBound < html.range(of: "Reflection · 9:05 pm")!.lowerBound)
        #expect(html.contains("Tuesday 22 September"))
        #expect(Book.build(year: 2024, name: nil, days: days).contains("Nothing written in 2024 yet."))
        #expect(Book.build(year: 2024, name: nil, days: days).contains("Your year, in your own words."))
    }

    @Test func rightToLeft() {
        let html = Book.build(year: 2026, name: nil, days: [Book.Day(day: "2026-09-22", pieces: [Book.Piece(kind: .reflection, minutes: 0, title: "יום שקט", body: ["הלכתי לים."])])])
        #expect(html.contains("<h4 dir=\"auto\">יום שקט</h4>") && html.contains("<p dir=\"auto\">הלכתי לים.</p>"))
    }

    @Test func aiLogRowsSayHowMuchNeverWhat() {
        let row = AILog.Row(at: .now, feature: "day_reading", executor: "on_device", rung: "permissive_json", latencyMs: 1800,
                            localDay: "2026-10-26", entryIds: ["a", "b", "c"], chars: 1240)
        #expect(AILog.describe(row) == "Read 3 entries from Mon 26 Oct · 1,240 characters · On this Mac · Apple on-device model · permissive rung · 1.8 s")
        let heuristic = AILog.Row(at: .now, feature: "entry_reading", executor: "heuristic", rung: "heuristic", latencyMs: 3, localDay: "2026-10-24",
                                  entryIds: ["a"], chars: 12)
        #expect(AILog.describe(heuristic) == "Read 1 entry from Sat 24 Oct · 12 characters · In your words (no model)")
        let refused = AILog.Row(at: .now, feature: "entry_reading", executor: "heuristic", rung: "heuristic", status: "guardrail", latencyMs: 400, entryIds: ["a"])
        #expect(AILog.describe(refused) == "Read 1 entry · In your words (no model) · stopped at Apple’s guardrails · 0.4 s")
        #expect(AILog.label("day_reading") == "Daily insight")
        #expect(AILog.label("reflect-deeper") == "Reflect deeper")
        #expect(AILog.label("week_plan") == "Week plan")
    }

    @Test func aiLogGroupsByLocalDayNewestFirst() {
        let cal = Calendar.current
        func row(_ d: Int, _ h: Int, _ f: String) -> AILog.Row {
            AILog.Row(at: cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))!, feature: f, executor: "heuristic")
        }
        let groups = AILog.groupByDay([row(24, 9, "a"), row(26, 8, "b"), row(26, 22, "c"), row(25, 23, "d")])
        #expect(groups.map(\.day) == ["2026-09-26", "2026-09-25", "2026-09-24"])
        #expect(groups[0].rows.map(\.feature) == ["c", "b"])
    }
}

@Suite struct LedgerDataTests {
    func freshLedger() throws -> Ledger { try Ledger(rootURL: URL.temporaryDirectory.appending(path: "SaroDataTest-\(UUID().uuidString)")) }

    /// Rows of every kind the journal keeps, and a recording on disk.
    func seed(_ l: Ledger) async throws -> Entry {
        let asset = MediaAsset(fileName: "2026-10-26/voice/a.caf", kind: .audio, origin: "test", state: "ready")
        try FileManager.default.createDirectory(at: l.url(for: asset).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 4096).write(to: l.url(for: asset))
        try await l.insertMedia(asset)
        var voice = Entry(kind: .voice, localDay: "2026-10-26")
        voice.mediaId = asset.id
        try await l.insertEntry(voice)
        try await l.setTranscript(mediaId: asset.id, words: [TranscriptWord(text: "Walked", startMs: 0, durMs: 300, confidence: 0.9)], extractorVersion: "t")
        let page = Entry(kind: .reflection, body: "Chai with Ravi.", localDay: "2026-10-26")
        try await l.insertEntry(page)
        var run = AIRun(feature: "entry_reading", executor: "heuristic", status: "ok")
        run.localDay = "2026-10-26"
        try await l.insertRun(run, inputs: [AIRunInput(entryId: page.id, field: "body", text: page.body!)])
        try await l.insertVerdict(SafetyVerdictRow(entryId: page.id, textSha256: sha256(page.body!), safetyVersion: "t", layer: 1, verdict: "clear", reasonCode: "none"))
        try await l.insertSnapshot(InsightSnapshot(kind: "day_reading", day: "2026-10-26", aiRunId: run.id, generator: "heuristic", inputHash: nil, payload: "{}"))
        var p = try await l.profile()
        p.name = "Alex Rivers"
        try await l.saveProfile(p)
        return page
    }

    func rows(_ l: Ledger) async throws -> [String: Int] {
        var out: [String: Int] = [:]
        for t in try await l.tableNames() { out[t] = try await l.run("SELECT COUNT(*) AS n FROM \(t)").first?["n"]?.int ?? 0 }
        return out
    }

    @Test func storageTimesAndLog() async throws {
        let l = try freshLedger()
        let page = try await seed(l)
        let s = try await l.storageSummary()
        #expect(s.kinds.first { $0.kind == .voice }?.bytes == 4096)
        #expect(s.kinds.first { $0.kind == .reflection }?.count == 1)
        #expect(s.databaseBytes > 0)
        #expect(try await l.entryTimes(days: 14, today: "2026-10-27").count == 2)
        #expect(try await l.entryTimes(days: 1, today: "2026-10-27").isEmpty)
        let log = try await l.aiLog(offset: 0, limit: 20)
        #expect(log.count == 1 && log[0].entryIds == [page.id] && log[0].chars == 15)
        #expect(try await l.aiRunCount() == 1)
    }

    @Test func bookLeavesOutHeldLetters() async throws {
        let l = try freshLedger()
        let page = try await seed(l)
        let reading = DayReading(mood: .calm, moodBasis: "chai", quoteIndexes: [1], question: "What else?", narrative: "You had chai with Ravi.")
        let payload = String(decoding: try JSONEncoder().encode(DayPayload(reading: reading, quotes: [], entryIds: [page.id])), as: UTF8.self)
        try await l.insertSnapshot(InsightSnapshot(kind: "letter", day: "2026-10-26", aiRunId: nil, generator: "heuristic", inputHash: nil, payload: payload))
        let html = Book.build(year: 2026, name: "Alex", days: try await l.bookDays(year: 2026))
        #expect(html.contains("Chai with Ravi.") && html.contains("Walked") && html.contains("You had chai with Ravi."))
        try await l.insertVerdict(SafetyVerdictRow(entryId: page.id, textSha256: sha256(page.body!), safetyVersion: "t", layer: 1, verdict: "safety_hold", reasonCode: "x"))
        let held = Book.build(year: 2026, name: "Alex", days: try await l.bookDays(year: 2026))
        #expect(!held.contains("You had chai with Ravi.") && !held.contains("Saro’s letter"))
    }

    /// FR-EXP-02: export, import into an empty journal, same rows and files; importing again adds nothing.
    @Test func exportImportRoundTrip() async throws {
        let a = try freshLedger()
        _ = try await seed(a)
        let dir = URL.temporaryDirectory.appending(path: "SaroExport-\(UUID().uuidString).saroexport")
        try await a.exportEverything(to: dir, prefs: Prefs().encoded)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appending(path: "saro.json"))) as? [String: Any]
        #expect((json?["prefs"] as? [String: Any])?["textScale"] as? Double == 1)

        let b = try freshLedger()
        let first = try await b.importExport(from: dir)
        #expect(first.files == 1 && first.rows > 0)
        let expected = try await rows(a)
        #expect(try await rows(b) == expected)
        #expect(try await b.profile().name == "Alex Rivers")
        #expect(FileManager.default.fileExists(atPath: b.mediaURL.appending(path: "2026-10-26/voice/a.caf").path))
        let again = try await b.importExport(from: dir)
        #expect(again.rows == 0 && again.files == 0)
        #expect(try await rows(b) == expected)
    }

    @Test func importRefusesWhatIsntAnExport() async throws {
        let l = try freshLedger()
        await #expect(throws: ImportError.self) { try await l.importExport(from: URL.temporaryDirectory.appending(path: "nothing-\(UUID().uuidString)")) }
    }

    /// DR-16: no row, media file or backup is left; the journal still opens empty.
    @Test func eraseLeavesNothing() async throws {
        let l = try freshLedger()
        _ = try await seed(l)
        try FileManager.default.createDirectory(at: l.backupsURL, withIntermediateDirectories: true)
        try Data("snapshot".utf8).write(to: l.backupsURL.appending(path: "saro-1.sqlite"))
        try await l.eraseAll()
        #expect(try await rows(l).values.allSatisfy { $0 == 0 })
        #expect(try FileManager.default.contentsOfDirectory(atPath: l.mediaURL.path).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: l.backupsURL.path))
        let sqlite = try Data(contentsOf: l.rootURL.appending(path: "saro.sqlite"))
        #expect(sqlite.range(of: Data("Chai with Ravi".utf8)) == nil)
        #expect(try await l.profile().name == nil)
        #expect(try await l.schemaVersion() == Schema.migrations.count)
    }
}
