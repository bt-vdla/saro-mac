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
