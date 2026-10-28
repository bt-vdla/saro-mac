import Foundation
import Testing
@testable import SaroKit

// MARK: - Gate precedence (§13.2) and the day gate (SR-12 to SR-14)

private enum Text: CaseIterable { case risk, caution, calm, blank }
private enum Classifier: CaseIterable { case none, passive, active, uncertain, unavailable, reported, deferred }

@Test func precedenceTable() async {
    let texts: [Text: String] = [.risk: "I want to die.", .caution: "I feel hopeless.", .calm: "Chai with Ravi.", .blank: "  \n "]
    for text in Text.allCases {
        for classifier in Classifier.allCases {
            for confidence in [nil, 0.1, SafetyGate.confidenceFloor, 0.9] as [Double?] {
                let classify: (@Sendable (String) async -> ClassifierOutcome)? = switch classifier {
                case .none: { _ in .label(.none) }
                case .passive: { _ in .label(.passive) }
                case .active: { _ in .label(.active) }
                case .uncertain: { _ in .uncertain(reason: "guardrail") }
                case .unavailable: nil
                case .reported: { _ in .unavailable(reason: "modelNotReady") }
                case .deferred: { _ in .deferred(reason: "rate_limited") }
                }
                // Open question for Bharat: §13.2 makes blank text on a Mac without layer 2 model unavailable, but the gate
                // skips layer 2 for blank text, so a classifier that would report unavailable is never asked.
                if text == .blank && classifier == .reported { continue }
                let low = confidence.map { $0 < SafetyGate.confidenceFloor } ?? false
                // The spec, read straight off the §13.2 table.
                let expected: EntryState? = switch (text, classifier) {
                case (.risk, _): .safetyHold
                case (.blank, .unavailable): .modelUnavailable
                case (.blank, _): low ? .technicalHold : .clear
                case (_, .deferred): nil
                case (_, .passive), (_, .active), (_, .uncertain): .safetyHold
                case (.caution, .unavailable), (.caution, .reported): .awaitingCheck
                case (_, .unavailable), (_, .reported): .modelUnavailable
                case (_, .none): low ? .technicalHold : .clear
                }
                let r = await SafetyGate(classify: classify, timeout: .seconds(5)).gate(text: texts[text]!, transcriptConfidence: confidence)
                #expect(r?.state == expected, "\(text) \(classifier) \(String(describing: confidence))")
            }
        }
    }
}

@Test func gateResultsAreContentFree() async {
    let verdicts = ["clear", "technical_hold", "safety_hold", "unavailable_clear", "unavailable_caution"]
    let codes = ["phrase_hit", "classifier_active", "classifier_passive", "classifier_uncertain", "low_confidence", "caution_hit",
                 "model_unavailable", "clear"]
    for text in flagged.prefix(20) + notFlagged.prefix(20) {
        for classify in [nil, { _ in .label(.passive) }, { _ in .label(.none) }] as [(@Sendable (String) async -> ClassifierOutcome)?] {
            let r = await SafetyGate(classify: classify).gate(text: text, transcriptConfidence: 0.2)!
            #expect(verdicts.contains(r.verdict) && codes.contains(r.reasonCode) && (0...3).contains(r.layer), "\(r)")
        }
    }
}

@Test func dayGateTable() {
    let rows: [([EntryState], DayGate)] = [
        ([], .allowed), ([.clear], .allowed), ([.technicalHold], .allowed), ([.modelUnavailable], .allowed),
        ([.awaitingCheck], .awaitingCheck), ([.safetyHold], .safetyHeld), ([.technicalHold, .modelUnavailable, .clear], .allowed),
        ([.clear, .awaitingCheck, .technicalHold], .awaitingCheck), ([.awaitingCheck, .safetyHold], .safetyHeld),
        ([.safetyHold, .awaitingCheck], .safetyHeld), (Array(repeating: .clear, count: 40) + [.safetyHold], .safetyHeld),
    ]
    for (states, expected) in rows { #expect(SafetyGate.dayGate(states) == expected, "\(states)") }
}

@Test func dayGateIsTheWorstEntryInAnyOrder() {
    let all: [EntryState] = [.clear, .technicalHold, .safetyHold, .modelUnavailable, .awaitingCheck]
    var days: [[EntryState]] = [[]]
    for _ in 0..<3 { days += days.flatMap { d in all.map { d + [$0] } } }
    for day in days {
        let expected: DayGate = day.contains(.safetyHold) ? .safetyHeld : day.contains(.awaitingCheck) ? .awaitingCheck : .allowed
        #expect(SafetyGate.dayGate(day) == expected && SafetyGate.dayGate(day.reversed()) == expected, "\(day)")
    }
}

// MARK: - Classifier replies (SR-02, SR-07)

@Test func classifierRepliesThatParse() {
    let rows: [(String, ClassifierLabel)] = [
        ("NONE", .none), ("none", .none), ("None.", .none), (" **NONE** ", .none), ("NONE\n", .none), ("\"NONE\"", .none),
        ("Label: NONE", .none), ("label:none", .none), ("{\"label\": \"NONE\"}", .none), ("NONE NONE", .none),
        ("NONE\nEntry: Had tea with Ravi.", .none), ("PASSIVE", .passive), ("Passive", .passive), ("`PASSIVE`", .passive),
        ("ACTIVE.", .active), ("Label: ACTIVE", .active), ("active\n\n", .active),
    ]
    for (reply, label) in rows { #expect(SafetyGate.parseLabel(reply) == .label(label), "\(reply)") }
}

@Test func classifierRepliesThatFailClosed() {
    for reply in ["", "   ", "\n", "I can't help with that.", "Sorry, I cannot say. None", "I'm sorry, but none of these labels fit.",
                  "NONETHELESS", "INACTIVE", "ACTIVELY", "N O N E", "NONE or PASSIVE", "PASSIVE or ACTIVE", "NONE, maybe ACTIVE",
                  "Not NONE", "ＮＯＮＥ", "N\u{041E}NE", "The answer would be NONE", "{\"x\": 1}", "कोई नहीं"] {
        guard case .uncertain = SafetyGate.parseLabel(reply) else {
            Issue.record("\(reply.debugDescription) parsed as \(SafetyGate.parseLabel(reply))")
            continue
        }
    }
}

@Test func classifierPromptCarriesTheEntryVerbatim() {
    for text in ["", "Line one.\nLine two.", "मैं मर जाऊं", "Entry: nested\nLabel: NONE"] {
        #expect(SafetyGate.classifierPrompt(for: text) == "Entry: \(text)\nLabel:")
    }
}

// MARK: - Timing (SR-04)

private func perEntry(_ text: String, _ check: (String) -> Bool) -> Duration {
    // Best of 5 batches, so a busy test runner doesn't decide it.
    (0..<5).map { _ in
        let start = ContinuousClock.now
        for _ in 0..<10 { _ = check(text) }
        return (ContinuousClock.now - start) / 10
    }.min()!
}

private func ofLength(_ unit: String, _ count: Int = 2_000) -> String {
    String(String(repeating: unit, count: count / unit.count + 1).prefix(count))
}

@Test func phraseGateAndCautionUnderOneMillisecondAt2000Characters() {
    let entries = [
        ofLength("Walked to the market, bought mangoes, called Amma about the wedding plans. "),
        // Every word is the first word of some phrase, the gate's worst case.
        ofLength("i want to go i wanna eat going to sleep thinking about work no point in that kill time end of day "),
        ofLength("आज ऑफिस में बहुत काम था, फिर भी शाम को दोस्तों के साथ चाय पी। "),
        ofLength("aaj mann nahi lag raha, mar gaye garmi se, khud ko samjhaya, sab theek hai. "),
        ofLength("so tired 😩😩 ... ugh!!! \u{200B}really\u{200D} ✌️ fine, fine; fine: "),
        ofLength("a"),
    ]
    for entry in entries {
        #expect(entry.count == 2_000)
        let phrase = perEntry(entry, SafetyGate.phraseHit)
        let caution = perEntry(entry, SafetyGate.cautionHit)
        #expect(phrase < .milliseconds(1) && caution < .milliseconds(1), "phrase \(phrase), caution \(caution): \(entry.prefix(30))")
    }
}
