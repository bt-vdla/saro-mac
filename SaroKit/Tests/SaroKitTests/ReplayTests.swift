import Foundation
import Testing
@testable import SaroKit

private let hours = [10.5, 10.5, 18, 22.1]

@Test func replayEntriesLandAtTheirTimeAndStayLanded() {
    #expect(Replay.reached(hours, at: 0) == 0)
    #expect(Replay.reached(hours, at: 10.49) == 0)
    #expect(Replay.reached(hours, at: 10.5) == 2)
    #expect(Replay.reached(hours, at: 17.99) == 2)
    #expect(Replay.reached(hours, at: 18) == 3)
    #expect(Replay.reached(hours, at: 24) == 4)
    #expect(Replay.reached([], at: 12) == 0)
    let calendar = Calendar(identifier: .gregorian)
    let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 22, minute: 10, second: 36))!
    #expect(abs(Replay.hour(of: date, calendar: calendar) - (22 + 10.0 / 60 + 0.01)) < 1e-9)
}

@Test func replayStopsStepEntryToEntryThenToTheEnds() {
    #expect(Replay.nextStop(hours, after: 0) == 10.5)
    #expect(Replay.nextStop(hours, after: 10.5) == 18)
    #expect(Replay.nextStop(hours, after: 18) == 22.1)
    #expect(Replay.nextStop(hours, after: 22.1) == 24)
    #expect(Replay.previousStop(hours, before: 24) == 22.1)
    #expect(Replay.previousStop(hours, before: 19) == 18)
    #expect(Replay.previousStop(hours, before: 18) == 10.5)
    #expect(Replay.previousStop(hours, before: 10.5) == 0)
    #expect(Replay.nextStop([], after: 3) == 24)
    #expect(Replay.previousStop([], before: 3) == 0)
}

@Test func replayLapseIsSlowNearEntriesAndFastWhereNothingHappens() {
    let lapse = Replay.dayLapse(hours, seconds: 20)
    #expect(abs(lapse.length - 20) < 1e-9)
    #expect(lapse.hour(at: 0) == 0)
    #expect(lapse.hour(at: 20) == 24)
    #expect(lapse.hour(at: 99) == 24)
    var previous = -1.0
    for t in stride(from: 0.0, through: 20, by: 0.05) {
        let h = lapse.hour(at: t)
        #expect(h >= previous)
        previous = h
    }
    let busy = lapse.time(at: 11) - lapse.time(at: 10)
    let empty = lapse.time(at: 4) - lapse.time(at: 3)
    #expect(busy > empty * 5)
    for h in [0, 3.3, 10.5, 18, 23.9, 24] { #expect(abs(lapse.hour(at: lapse.time(at: h)) - h) < 1e-9) }
    #expect(abs(Replay.dayLapse([], seconds: 20).time(at: 12) - 10) < 1e-9)
}

@Test func replayMoodLineAndClusters() {
    let line = Replay.moodSegments([(hour: 18, label: "calm"), (hour: 9, label: "tired"), (hour: 12, label: "tired")])
    #expect(line == [Replay.MoodSegment(from: 9, to: 18, label: "tired"), Replay.MoodSegment(from: 18, to: 24, label: "calm")])
    #expect(Replay.clusters([0, 10, 40, 61, 82, 200], gap: 22) == [0...1, 2...4, 5...5])
    #expect(Replay.clusters([], gap: 22).isEmpty)
}
