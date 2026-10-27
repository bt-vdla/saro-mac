import Foundation
import Testing
@testable import SaroKit

@Test func registerSeedsTheBRDDecisions() {
    let d = Decision.all.filter { $0.id.hasPrefix("D-") }
    #expect(d.map(\.id) == (1...22).map { String(format: "D-%02d", $0) })
    #expect(Set(d.filter { $0.status == .decided }.map(\.id)) == ["D-02", "D-03", "D-05", "D-14"])
    #expect(d.allSatisfy { $0.status == .open || ($0.option($0.decidedChoice) != nil && $0.decidedOn == "2026-10-27") })
    #expect(Decision.all.filter { $0.id.hasPrefix("B-") }.count == 17)
    #expect(Set(Decision.all.map(\.id)).count == Decision.all.count)
}

@Test func everyRecommendationIsAnOption() {
    for d in Decision.all { #expect(d.option(d.recommendation) != nil, "\(d.id)") }
}

@Test func newestChoiceWins() {
    let d = Decision.all.first { $0.id == "D-01" }!
    #expect(d.currentChoice(in: []) == nil)
    let events = [
        DecisionEvent(decisionId: "D-01", choice: "b", note: nil, screenId: nil, appVersion: "0.1.0"),
        DecisionEvent(decisionId: "D-01", choice: "c", note: "changed my mind", screenId: "day.canvas", appVersion: "0.1.0"),
        DecisionEvent(decisionId: "D-01", choice: nil, note: "just a note", screenId: nil, appVersion: "0.1.0"),
        DecisionEvent(decisionId: "D-04", choice: "a", note: nil, screenId: nil, appVersion: "0.1.0"),
    ]
    #expect(d.currentChoice(in: events) == "c")
    #expect(d.currentStatus(in: events) == .decided)
    let seeded = Decision.all.first { $0.id == "D-02" }!
    #expect(seeded.currentChoice(in: []) == "b")
    #expect(seeded.currentChoice(in: [DecisionEvent(decisionId: "D-02", choice: "a", note: nil, screenId: nil, appVersion: "0.1.0")]) == "a")
}

@Test func exportsCarryStampAndEveryDecision() throws {
    let stamp = DevExport.Stamp(appVersion: "0.1.0", gitCommit: "abc1234-dirty")
    let events = [DecisionEvent(decisionId: "B-04", choice: "b", note: "try | NSScrollView\nnext", screenId: "day.canvas", appVersion: "0.1.0")]
    let notes = [ScreenNote(screenId: "day.canvas", note: "pinch feels slow", appVersion: "0.1.0")]
    let json = DevExport.json(decisions: Decision.all, events: events, notes: notes, stamp: stamp)
    let obj = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    #expect(obj["git_commit"] as? String == "abc1234-dirty")
    #expect(obj["app_version"] as? String == "0.1.0")
    let items = try #require(obj["decisions"] as? [[String: Any]])
    #expect(items.count == Decision.all.count)
    #expect(items.first { $0["id"] as? String == "B-04" }?["current_choice"] as? String == "b")
    #expect((obj["screen_notes"] as? [String: Any])?["day.canvas"] != nil)

    let md = DevExport.markdown(decisions: Decision.all, events: events, notes: notes, stamp: stamp)
    #expect(md.contains("app 0.1.0 (abc1234-dirty)"))
    for d in Decision.all { #expect(md.contains("## \(d.id) ·"), "\(d.id)") }
    #expect(md.contains("pinch feels slow"))
}
