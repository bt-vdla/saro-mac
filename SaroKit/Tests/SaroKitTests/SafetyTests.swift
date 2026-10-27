import Foundation
import Testing
@testable import SaroKit

// test_safety.py and safety.test.ts corpora, plus the Hinglish and idiom cases from the brief.
let flagged = [
    "I want to kill myself.", "I've been thinking about ending my life", "i am going to end it all",
    "Sometimes I wish I could just not wake up tomorrow.", "Everyone would be better off without me.",
    "I don't want to be alive anymore.", "I feel suicidal tonight", "I keep thinking about wanting to hurt myself",
    "I started cutting myself again", "There's no point in living like this", "mujhe khudkushi ka khayal aata hai",
    "ab jeena nahi chahta", "I KILL MYSELF", "I want to die.",
    "honestly i just want to kill my self", "I don't want to be here anymore", "I don’t want to be here", "i dont want to be here",
    "There's no point anymore.", "what’s the point anymore", "I've been thinking about suicide a lot", "Feeling suicidal tonight",
    "feeling sucidal again", "thinking about suiside", "I want to end my life", "Sometimes I wish I was dead",
    "I started cutting again", "I keep wanting to hurt myself. I want to hurt myself.", "the urge to hurt myself is back",
    "I don't want to wake up tomorrow", "i wanna die", "I DON'T WANT TO LIVE ANYMORE", "I don't want to live like this",
    "nothing to live for", "self-harm", "I have been self harming", "I want to end it all", "I keep cutting myself",
    "I thought about taking my own life", "I do not want to be alive",
    "Kabhi kabhi lagta hai main mar jaun toh sab theek ho jayega.", "mujhe mar jaana hai", "main mar jana chahti hoon",
    "ab zinda nahi rehna", "jeena nahi chahti", "sab khatam kar dun kya", "khud ko khatam kar lungi", "aatmahatya ka socha",
    "मैं मर जाऊं तो अच्छा", "मैं मर जाऊँ", "मैं मरना चाहता हूँ", "अब ज़िंदा नहीं रहना", "जिंदा नहीं रहना", "जीना नहीं चाहती",
    "सब ख़त्म कर दूं", "सब खत्म कर दूँ", "ख़ुद को ख़त्म कर दूँगा", "खुद को खत्म", "आत्महत्या के ख़याल", "ख़ुदकुशी", "खुदकुशी",
    "I don't want to live. In the morning it was the same.",
]

let notFlagged = [
    "This deadline is killing me.", "I could kill him for eating my lunch.",
    "lol I'd rather die than sit through another standup", "I cut myself chopping onions.", "I died laughing at that meme.",
    "I didn't wake up until 10.", "Dying to see the new film.", "I want to die of embarrassment",
    "I hurt myself playing football.", "Bought groceries.", "",
    "Killing it at work today!", "I'm dying to see Maya next weekend", "This song kills me every time", "The deadline is killing me",
    "I'm dead tired", "I want to die of embarrassment after that meeting", "I don't want to die before I see Japan",
    "I don't want to live in London forever", "We don't want to live with my parents again", "Cutting myself some slack this week",
    "Cutting myself off from social media for a bit", "I cut my hand chopping onions", "I hurt my knee on the run",
    "Suicide Squad was a terrible film", "I don't want to wake up early on Saturday", "No point arguing about it",
    "I want to take my life back from my inbox", "Take my life savings? No thanks.", "hanging myself upside down on the yoga swing",
    "I'd die for this cake", "I could sleep for a week, I'm so tired",
    "this job is killing me", "I'm dying to see you", "I'll die if I have to sit through another meeting", "take my life back",
    "Aaj bahut thak gayi hoon. Office mein sab kuch galat ho raha hai, mann nahi lag raha kisi cheez mein.",
    "Ajay amar jaun ka dost hai", "अमर जाऊं",
]

@Test func phraseGateFlagsRiskPhrases() {
    for text in flagged { #expect(SafetyGate.phraseHit(text), "\(text)") }
}

@Test func phraseGateIgnoresIdiomsAndBenignContinuations() {
    for text in notFlagged { #expect(!SafetyGate.phraseHit(text), "\(text)") }
}

@Test func phraseBuriedInLongerEntry() {
    #expect(SafetyGate.phraseHit("Long day at work. The launch slipped again and honestly there is no point anymore. Going to bed."))
}

@Test func guardsOnlyCancelTheirOwnOccurrence() {
    #expect(SafetyGate.phraseHit("I don't want to die of old age. But I want to die."))
}

@Test func normaliserPreservesDevanagariAndFolds() {
    #expect(SafetyGate.normalise("I DON’T  want—to die!!  Café") == "i dont want to die . cafe")
    let hindi = SafetyGate.normalise("मैं मर जाऊँ।")
    #expect(hindi.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) })
    #expect(hindi == SafetyGate.normalise("मैं मर जाऊं"))
    #expect(SafetyGate.normalise("ज़िंदा") == SafetyGate.normalise("जिंदा"))
    #expect(SafetyGate.normalise("मारना") != SafetyGate.normalise("मरना"))
    #expect(SafetyGate.normalise("sui\u{200B}cide") == "suicide")
}

@Test func cautionLexiconIsBroaderThanThePhraseGate() {
    for text in ["I feel so hopeless.", "Like a burden on everyone.", "I just want to disappear", "Counting my pills.", "bas bojh hoon"] {
        #expect(SafetyGate.cautionHit(text), "\(text)")
        #expect(!SafetyGate.phraseHit(text), "\(text)")
    }
    #expect(!SafetyGate.cautionHit("Shipped the onboarding flow and had chai with Ravi."))
}

@Test func phraseGateRunsUnderOneMillisecond() {
    let entry = String(repeating: "Long day at work. Shipped the onboarding flow finally. Had chai with Ravi and we talked about his move to Pune. ", count: 18)
    // Best of 5 batches, so a busy test runner doesn't decide it.
    let perEntry = (0..<5).map { _ in
        let start = ContinuousClock.now
        for _ in 0..<10 { _ = SafetyGate.phraseHit(entry) }
        return (ContinuousClock.now - start) / 10
    }.min()!
    #expect(perEntry < .milliseconds(1), "\(perEntry) for \(entry.count) chars")
}

// MARK: - The gate

let none: @Sendable (String) async -> ClassifierOutcome = { _ in .label(.none) }

func gate(_ text: String, confidence: Double? = nil, _ classify: (@Sendable (String) async -> ClassifierOutcome)? = none) async -> GateResult {
    await SafetyGate(classify: classify, timeout: .milliseconds(200)).gate(text: text, transcriptConfidence: confidence)
}

@Test func clearState() async {
    let r = await gate("Had chai with Ravi.")
    #expect((r.verdict, r.layer, r.reasonCode, r.state) == ("clear", 2, "clear", .clear))
}

@Test func technicalHoldOnlyWhenLayerTwoRan() async {
    let r = await gate("Had chai with Ravi.", confidence: 0.2)
    #expect((r.verdict, r.layer, r.reasonCode, r.state) == ("technical_hold", 0, "low_confidence", .technicalHold))
    let unavailable = await gate("Had chai with Ravi.", confidence: 0.2, nil)
    #expect(unavailable.state == .modelUnavailable)
    #expect(await gate("Had chai with Ravi.", confidence: 0.9).state == .clear)
}

@Test func safetyHoldStates() async {
    let phrase = await gate("I want to die.")
    #expect((phrase.verdict, phrase.layer, phrase.reasonCode, phrase.state) == ("safety_hold", 1, "phrase_hit", .safetyHold))
    #expect(await gate("Saving up my sleeping pills.") { _ in .label(.active) }.reasonCode == "classifier_active")
    let passive = await gate("I used to cut, three years clean.") { _ in .label(.passive) }
    #expect((passive.verdict, passive.reasonCode, passive.state) == ("safety_hold", "classifier_passive", .safetyHold))
}

@Test func cancelledGateIsSafetyHold() async {
    let task = Task { await gate("A quiet evening.") { _ in
        try? await Task.sleep(for: .seconds(30))
        return .label(.none)
    } }
    task.cancel()
    #expect(await task.value.state == .safetyHold)
}

@Test func uncertainClassifierIsSafetyHold() async {
    let refusal: @Sendable (String) async -> ClassifierOutcome = { _ in SafetyGate.parseLabel("I'm sorry, I can't help with that.") }
    let garbage: @Sendable (String) async -> ClassifierOutcome = { _ in SafetyGate.parseLabel("{\"x\": 1}") }
    let hang: @Sendable (String) async -> ClassifierOutcome = { _ in
        try? await Task.sleep(for: .seconds(30))
        return .label(.none)
    }
    for classify in [refusal, garbage, hang] {
        let r = await gate("A quiet evening.", classify)
        #expect((r.verdict, r.reasonCode, r.state) == ("safety_hold", "classifier_uncertain", .safetyHold))
    }
}

@Test func modelUnavailableStates() async {
    let clear = await gate("A quiet evening with tea.", nil)
    #expect((clear.verdict, clear.layer, clear.reasonCode, clear.state) == ("unavailable_clear", 1, "model_unavailable", .modelUnavailable))
    let caution = await gate("I feel hopeless.", nil)
    #expect((caution.verdict, caution.reasonCode, caution.state) == ("unavailable_caution", "caution_hit", .awaitingCheck))
    let reported = await gate("I feel hopeless.") { _ in .unavailable(reason: "modelNotReady") }
    #expect(reported.state == .awaitingCheck)
}

@Test func precedence() async {
    // safety hold > model unavailable > technical hold > clear
    #expect(await gate("I want to die.", confidence: 0.1, nil).state == .safetyHold)
    #expect(await gate("I want to die.", confidence: 0.1).state == .safetyHold)
    #expect(await gate("Quiet.", confidence: 0.1) { _ in .label(.passive) }.state == .safetyHold)
    #expect(await gate("Quiet.", confidence: 0.1) { _ in .uncertain(reason: "guardrail") }.state == .safetyHold)
    #expect(await gate("Quiet.", confidence: 0.1, nil).state == .modelUnavailable)
    #expect(await gate("Quiet.", confidence: 0.1).state == .technicalHold)
    #expect(await gate("Quiet.", confidence: 0.9).state == .clear)
}

@Test func verdictStringsRoundTrip() {
    #expect(EntryState(verdict: "clear") == .clear)
    #expect(EntryState(verdict: "technical_hold") == .technicalHold)
    #expect(EntryState(verdict: "safety_hold") == .safetyHold)
    #expect(EntryState(verdict: "unavailable_clear") == .modelUnavailable)
    #expect(EntryState(verdict: "unavailable_caution") == .awaitingCheck)
    #expect(EntryState(verdict: nil) == .awaitingCheck)
    #expect(EntryState(verdict: "typo") == .safetyHold)
}

@Test func longTextIsChunkedAndAnyRiskyChunkFlags() async {
    let calm = String(repeating: "We walked by the river and talked about nothing much. ", count: 300)
    let chunks = SafetyGate.chunks(calm + "RISK.")
    #expect(chunks.count > 1)
    #expect(chunks.allSatisfy { $0.count <= SafetyGate.chunkLimit })
    #expect(chunks.joined() == calm + "RISK.")
    let r = await gate(calm + "RISK.") { $0.contains("RISK") ? .label(.passive) : .label(.none) }
    #expect(r.state == .safetyHold)
    #expect(await gate(calm).state == .clear)
}

@Test func outputGate() {
    let g = SafetyGate(classify: nil)
    #expect(g.outputGateHit("You said you want to end it all."))
    #expect(!g.outputGateHit("You had chai with Ravi."))
}

@Test func parseLabel() {
    #expect(SafetyGate.parseLabel("NONE") == .label(.none))
    #expect(SafetyGate.parseLabel(" passive.\n") == .label(.passive))
    #expect(SafetyGate.parseLabel("Label: ACTIVE") == .label(.active))
    if case .uncertain = SafetyGate.parseLabel("I can't help with that request.") {} else { Issue.record("refusal parsed as a label") }
    if case .uncertain = SafetyGate.parseLabel("") {} else { Issue.record("empty parsed as a label") }
    #expect(SafetyGate.classifierPrompt(for: "x") == "Entry: x\nLabel:")
    #expect(SafetyGate.classifierInstructions.contains("I used to cut, three years clean now. Saw the scars in the mirror today.\nLabel: PASSIVE"))
}

@Test func dayGateRules() {
    #expect(SafetyGate.dayGate([.clear, .clear]) == .allowed)
    #expect(SafetyGate.dayGate([.clear, .technicalHold]) == .allowed)
    #expect(SafetyGate.dayGate([.modelUnavailable, .clear]) == .allowed)
    #expect(SafetyGate.dayGate([.clear, .awaitingCheck]) == .awaitingCheck)
    #expect(SafetyGate.dayGate([.awaitingCheck, .safetyHold, .clear]) == .safetyHeld)
    #expect(SafetyGate.dayGate([]) == .allowed)
}

@Test func crisisResourcesByRegion() {
    #expect(CrisisResources.forRegion("IN").first?.name == "Tele-MANAS")
    #expect(CrisisResources.forRegion("US").first?.contact == "Call or text 988")
    #expect(CrisisResources.forRegion("GB").first == CrisisResources.findAHelpline)
    #expect(CrisisResources.forRegion(nil).first == CrisisResources.findAHelpline)
    for code in ["IN", "US", "GB", nil] as [String?] {
        let list = CrisisResources.forRegion(code)
        #expect(list.count == 3 && list.contains(CrisisResources.findAHelpline))
        #expect(list.allSatisfy { ["tel", "https"].contains($0.url.scheme) })
    }
    #expect(CrisisResources.teleManas.contact.contains("14416"))
}

