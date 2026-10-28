import Foundation
import FoundationModels
import Testing
@testable import SaroKit

// MARK: Profile

@Test func addressAndTonePreviewLines() {
    #expect(Profile(name: "Asha Rao").address == "Asha")
    #expect(Profile(name: "Asha Rao", called: " Ash ").address == "Ash")
    #expect(Profile().address == nil)
    #expect(Tone.neutral.previewLine(name: "Asha") == "Asha, which moment from today stands out?")
    #expect(Tone.direct.previewLine(name: "Asha") == "Asha. One second you’d keep from today. Go.")
    #expect(Tone.gentle.previewLine(name: "  ") == "What moment still lingers?")
    #expect(Tone.contemplative.previewLine(name: nil) == "Which moment felt still inside?")
    #expect(FocusArea.allCases.count == 8)
    #expect(Set(FocusArea.allCases.map(\.symbol)).count == 8)
}

// MARK: Prefs

private func prefs(_ json: String) -> Prefs { Prefs.decode(Data(json.utf8)) }

@Test func brokenPrefsFallBackToDefaults() {
    #expect(Prefs.decode(nil) == Prefs())
    #expect(prefs("not json") == Prefs())
    #expect(prefs("[1, 2]") == Prefs())
    let p = prefs("""
        {"textScale": 3, "sounds": "yes", "ritualMinutes": 1440, "ritualWeekdays": 200, "ritualSource": "magic",
         "weekStartedOn": "2026-02-31", "lockAfter": "forever", "captionLocale": "", "rhythmDismissedAt": "soon",
         "letterMinutes": -1, "ritualSuggested": 99999, "reminderOn": 1}
        """)
    #expect(p == Prefs())
    let d = Prefs()
    #expect(d.textScale == 1 && !d.reminderOn && d.ritualMinutes == 1290 && d.ritualWeekdays == 0x7F)
    #expect(d.letterMinutes == 1080 && d.letterArrives && !d.writingTools && !d.reduceMotion && d.ritualSource == .default)
}

@Test func goodPrefsSurviveAndUnknownKeysAreIgnored() {
    var p = Prefs()
    p.textScale = 1.5
    p.captionLocale = "en-IN"
    p.reminderOn = true
    p.ritualMinutes = 7 * 60 + 30
    p.ritualWeekdays = 0b011_1110
    p.ritualSource = .user
    p.ritualSuggested = 1320
    p.weekStartedOn = "2026-10-25"
    p.rhythmDismissedAt = Date(timeIntervalSince1970: 1_800_000_000)
    p.lockAfter = .hour
    #expect(Prefs.decode(p.encoded) == p)
    #expect(prefs(#"{"sounds": true, "someday": 4}"#).sounds)
    #expect(prefs(#"{"textScale": 1.125}"#).textScale == 1.125)
    #expect(!String(decoding: p.encoded, as: UTF8.self).lowercased().contains("password"))
}

@Test func letterIsDueFromItsTime() throws {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = try #require(TimeZone(identifier: "Asia/Kolkata"))
    let at = { (h: Int, m: Int) in cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: h, minute: m))! }
    let p = Prefs()
    #expect(!p.letterDue(at: at(17, 59), calendar: cal))
    #expect(p.letterDue(at: at(18, 0), calendar: cal))
    #expect(p.letterDue(at: at(23, 59), calendar: cal))
    var early = Prefs()
    early.letterMinutes = 0
    #expect(early.letterDue(at: at(0, 0), calendar: cal))
}

@Test func ritualRequestsFollowTheWeekdayMaskAndTime() {
    var p = Prefs()
    #expect(p.ritualRequests.isEmpty)
    p.reminderOn = true
    #expect(p.ritualRequests.map(\.id) == (1...7).map { "saro-ritual-\($0)" })
    p.ritualWeekdays = 0b010_0010
    p.ritualMinutes = 21 * 60 + 30
    let r = p.ritualRequests
    #expect(r.map(\.id) == ["saro-ritual-2", "saro-ritual-6"])
    #expect(r.map(\.components) == [DateComponents(hour: 21, minute: 30, weekday: 2), DateComponents(hour: 21, minute: 30, weekday: 6)])
    p.ritualWeekdays = 0
    #expect(p.ritualRequests.isEmpty)
    p.ritualWeekdays = 1
    p.ritualMinutes = 5
    #expect(p.ritualRequests.first?.components == DateComponents(hour: 0, minute: 5, weekday: 1))
}

// MARK: Greeting

@Test func greetingBandsChangeAtEachBoundary() {
    let lines = [(0.0, "Still up."), (4.49, "Still up."), (4.5, "Up before the light."), (5.99, "Up before the light."),
                 (6, "Good morning."), (10, "The day is still open."), (11.99, "The day is still open."), (12, "Good afternoon."),
                 (15, "The light is turning."), (17.49, "The light is turning."), (17.5, "Good evening."), (20, "The day is settling."),
                 (22.49, "The day is settling."), (22.5, "The quiet hours."), (23.99, "The quiet hours."), (24, "Still up."),
                 (-0.5, "The quiet hours.")]
    for (hour, line) in lines { #expect(Greeting.line(hour: hour) == line, "hour \(hour)") }
    #expect(Greeting.band(hour: 0) == 0 && Greeting.band(hour: 22.5) == 8)
    #expect(Greeting.eyebrow(hour: 10.5) == "Late morning")
}

// MARK: Readiness

@Test func everyModelStateHasItsOwnHonestLine() {
    #expect(Readiness.ModelState(.available) == .ready)
    #expect(Readiness.ModelState(.unavailable(.deviceNotEligible)) == .deviceNotEligible)
    #expect(Readiness.ModelState(.unavailable(.appleIntelligenceNotEnabled)) == .notEnabled)
    #expect(Readiness.ModelState(.unavailable(.modelNotReady)) == .notReady)
    let states: [Readiness.ModelState] = [.ready, .deviceNotEligible, .notEnabled, .notReady]
    #expect(Set(states.map(\.line)).count == 4)
    #expect(Readiness.ModelState.notEnabled.line.contains("manages"))
    #expect(states.filter { $0.settingsURL != nil } == [.notEnabled])
    #expect(states.dropFirst().allSatisfy { $0.line.contains("In your words") || $0.line.contains("own words") })
}

@Test func everySpeechStateHasItsOwnHonestLine() {
    #expect(Readiness.SpeechState(.installed) == .installed)
    #expect(Readiness.SpeechState(.downloading) == .downloading(nil))
    #expect(Readiness.SpeechState(.supported) == .needsDownload)
    #expect(Readiness.SpeechState(.unsupported) == .unsupported)
    #expect(Readiness.SpeechState.downloading(0.416).line.contains("(42%)"))
    #expect(!Readiness.SpeechState.downloading(nil).line.contains("%"))
    let states: [Readiness.SpeechState] = [.installed, .downloading(nil), .needsDownload, .failed, .unsupported]
    #expect(Set(states.map(\.line)).count == states.count)
}

// MARK: Deep links

@Test func deepLinksParseAndRoundTrip() throws {
    let links: [DeepLink] = [.capture(.moment), .capture(.voice), .capture(.reflection), .day("2026-10-26"), .entry("ABC-123"),
                             .letter("2026-10-26"), .settings("rhythm"), .settings(nil), .knows(query: "tea with Ravi"), .knows(query: nil)]
    for link in links { #expect(DeepLink(link.url) == link, "\(link.url)") }
    #expect(DeepLink.capture(.voice).url.absoluteString == "saro://capture/voice")
    #expect(DeepLink.day("2026-10-26").url.absoluteString == "saro://day/2026-10-26")
    for bad in ["saro://day/2026-02-31", "saro://day/yesterday", "saro://capture/dance", "https://day/2026-10-26", "saro://nowhere",
                "saro://entry", "saro://letter/26-10-2026"] {
        #expect(DeepLink(try #require(URL(string: bad))) == nil, "\(bad)")
    }
    #expect(DeepLink(try #require(URL(string: "SARO://Capture/write"))) == .capture(.reflection))
    #expect(DeepLink(try #require(URL(string: "saro://knows?q="))) == .knows(query: nil))
}

// MARK: Migration v3

/// A journal as it stood before v3 (every earlier migration run), optionally with one entry.
private func journalBeforeV3(withEntry: Bool) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "saro-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let db = try SQLite(path: root.appending(path: "saro.sqlite").path)
    let v3 = try #require(Schema.migrations.firstIndex(of: Schema.v3))
    for (i, sql) in Schema.migrations.prefix(v3).enumerated() {
        try db.exec(sql)
        try db.exec("PRAGMA user_version = \(i + 1)")
    }
    if withEntry {
        try db.run("INSERT INTO entry (id, kind, captured_at, tz_id, local_day, updated_at) VALUES ('e1','reflection',?,?,?,?)",
                   [.text(Date.now.iso), .text("UTC"), .text("2026-10-26"), .text(Date.now.iso)])
    }
    return root
}

@Test func v3MigratesAJournalWithEntriesAsOnboarded() async throws {
    let l = try Ledger(rootURL: try journalBeforeV3(withEntry: true))
    #expect(try await l.schemaVersion() == Schema.migrations.count)
    let p = try await l.profile()
    #expect(p.onboardingDoneAt != nil)
    #expect(p.tone == .neutral && p.focusAreas.isEmpty && !p.memoryPaused)
    #expect(try await l.allEntries().count == 1)
}

@Test func v3MigratesAnEmptyJournalAsNotOnboarded() async throws {
    let l = try Ledger(rootURL: try journalBeforeV3(withEntry: false))
    #expect(try await l.profile().onboardingDoneAt == nil)
    #expect(try await tempLedger().profile().onboardingDoneAt == nil)
}

@Test func profileRowIsOneRowAndComesBackAfterErase() async throws {
    let l = try tempLedger()
    await #expect(throws: (any Error).self) { try await l.run("INSERT INTO profile (id, created_at, updated_at) VALUES (2, 'x', 'x')") }
    await #expect(throws: (any Error).self) { try await l.run("UPDATE profile SET tone='shouty'") }
    try await l.run("DELETE FROM profile")
    #expect(try await l.profile().onboardingDoneAt == nil)
    #expect(try await l.run("SELECT COUNT(*) AS n FROM profile").first?["n"] == .int(1))
}

// MARK: Profile row

@Test func profileRoundTripsAndBumpsUpdatedAt() async throws {
    let l = try tempLedger()
    let before = try await l.profile()
    try await Task.sleep(for: .milliseconds(5))
    var p = before
    p.name = "Asha Rao"
    p.called = "Asha"
    p.tone = .contemplative
    p.focusAreas = [.clarity, .energy]
    p.onboardingDoneAt = Date(timeIntervalSince1970: 1_800_000_000)
    try await l.saveProfile(p)
    let after = try await l.profile()
    #expect(after.name == "Asha Rao" && after.called == "Asha" && after.tone == .contemplative)
    #expect(after.focusAreas == [.clarity, .energy])
    #expect(after.onboardingDoneAt == p.onboardingDoneAt)
    #expect(after.updatedAt > before.updatedAt)
    #expect(after.createdAt == before.createdAt)
}

@Test func pausingMemoryThroughTheProfileOpensAndClosesAWindow() async throws {
    let l = try tempLedger()
    var p = try await l.profile()
    p.memoryPaused = true
    try await l.saveProfile(p)
    try await l.saveProfile(p)
    var pauses = try await l.pauses()
    #expect(pauses.count == 1 && pauses[0].to == nil)
    try await Task.sleep(for: .milliseconds(5))
    p.memoryPaused = false
    try await l.saveProfile(p)
    pauses = try await l.pauses()
    #expect(pauses.count == 1)
    let window = try #require(pauses.first)
    let to = try #require(window.to)
    #expect(window.contains(window.from) && !window.contains(to) && !window.contains(window.from.addingTimeInterval(-1)))
    try await l.openPause()
    try await l.openPause()
    #expect(try await l.pauses().filter { $0.to == nil }.count == 1)
    try await l.closePause()
    #expect(try await l.pauses().allSatisfy { $0.to != nil })
}

// MARK: Starter context

@Test func starterContextRoundTripsAndVersionsPasses() async throws {
    let l = try tempLedger()
    #expect(try await l.latestStarter() == nil)
    #expect(try await l.newStarterVersion() == 1)
    var s = StarterContext(version: 1)
    s.answers = [1: "I'm Asha", 3: "Usually late, around 10 pm"]
    s.picks = [Pick(kind: .name, text: "Asha", value: "Asha", start: 4, end: 8, q: 1),
               Pick(kind: .time, text: "around 10 pm", value: "22:00", start: 15, end: 27, q: 3)]
    s.reflectTime = "22:00"
    s.firstPrompt = "What made today feel late?"
    try await l.saveStarter(s)
    s.source = .ai
    try await l.saveStarter(s)
    let got = try #require(try await l.latestStarter())
    #expect(got.id == s.id && got.answers == s.answers && got.picks == s.picks && got.source == .ai)
    #expect(got.reflectTime == "22:00" && got.firstPrompt == s.firstPrompt)
    #expect(try await l.newStarterVersion() == 2)
    try await l.saveStarter(StarterContext(version: 2))
    #expect(try await l.latestStarter()?.version == 2)
}

@Test func nothingDerivedFromAHeldAnswerIsStored() async throws {
    let l = try tempLedger()
    var s = StarterContext(version: 1)
    s.answers = [2: "my sister Maya", 3: "late at night"]
    s.picks = [Pick(kind: .person, text: "Maya", value: "Maya", start: 10, end: 14, q: 2),
               Pick(kind: .time, text: "late at night", value: "23:00", start: 0, end: 13, q: 3)]
    s.reflectTime = "23:00"
    s.firstPrompt = "What would you tell Maya?"
    s.held = [3]
    try await l.saveStarter(s)
    let got = try #require(try await l.latestStarter())
    #expect(got.picks.map(\.text) == ["Maya"])
    #expect(got.reflectTime == nil && got.firstPrompt == nil && got.held == [3])
    #expect(got.answers == s.answers)

    var dropped = StarterContext(version: 2)
    dropped.picks = s.picks
    dropped.dropped = [s.picks[0].dropKey]
    #expect(dropped.storable.picks.map(\.kind) == [.time])
    #expect(s.picks[0].dropKey == "person|maya")
}

// MARK: Reflection turns

@Test func anAnswerNeedsAVerdict() async throws {
    let l = try tempLedger()
    var bare = ReflectionTurn(kind: .dailyQuestion, question: "What stayed with you?", generator: "curated", localDay: "2026-10-26")
    bare.answer = "The walk home."
    await #expect(throws: (any Error).self) { try await l.insertTurn(bare) }
    let t = ReflectionTurn(kind: .dailyQuestion, question: "What stayed with you?", generator: "curated", localDay: "2026-10-26")
    try await l.insertTurn(t)
    await #expect(throws: (any Error).self) { try await l.setTurnAnswer(id: t.id, answer: "The walk home.", verdict: "") }
    #expect(try await l.turns(day: "2026-10-26").first?.answer == nil)
    try await l.setTurnAnswer(id: t.id, answer: "The walk home.", verdict: "clear")
    let got = try #require(try await l.turns(day: "2026-10-26").first)
    #expect(got.answer == "The walk home." && got.answerVerdict == "clear" && got.updatedAt >= got.createdAt)
}

@Test func aHeldAnswerDropsTheDaysReadings() async throws {
    let l = try tempLedger()
    let day = "2026-10-26"
    for kind in ["day_reading", "letter", "pattern"] {
        try await l.insertSnapshot(InsightSnapshot(kind: kind, day: day, aiRunId: nil, generator: "heuristic", inputHash: nil, payload: "{}"))
    }
    let t = ReflectionTurn(kind: .dailyQuestion, question: "q", generator: "curated", localDay: day)
    try await l.insertTurn(t)
    try await l.setTurnAnswer(id: t.id, answer: "a", verdict: "safety_hold")
    #expect(try await l.latestSnapshot(kind: "day_reading", day: day) == nil)
    #expect(try await l.latestSnapshot(kind: "letter", day: day) == nil)
    #expect(try await l.latestSnapshot(kind: "pattern", day: day) != nil)
}

@Test func turnsFilterByKindEntryAndArchive() async throws {
    let l = try tempLedger()
    let e = Entry(kind: .moment, localDay: "2026-10-26")
    try await l.insertEntry(e)
    let prompt = ReflectionTurn(kind: .prompt, question: "Which moment stands out?", generator: "tone", localDay: e.localDay, entryId: e.id)
    var old = ReflectionTurn(kind: .dailyQuestion, question: "old", generator: "curated", localDay: e.localDay)
    old.archivedAt = .now
    let current = ReflectionTurn(kind: .dailyQuestion, question: "new", generator: "curated", localDay: e.localDay)
    for t in [prompt, old, current] { try await l.insertTurn(t) }
    #expect(try await l.turns(day: e.localDay).map(\.id) == [prompt.id, current.id])
    #expect(try await l.turns(day: e.localDay, kind: .dailyQuestion).map(\.question) == ["new"])
    #expect(try await l.turns(day: e.localDay, kind: .dailyQuestion, includeArchived: true).count == 2)
    #expect(try await l.turns(entryId: e.id).map(\.kind) == [.prompt])
    #expect(try await l.turns(day: "2026-10-25").isEmpty)
}
