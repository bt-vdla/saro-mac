import Foundation
import Testing
@testable import SaroKit

// Synthetic only (SR-28). Lines a guard word, a clause break or an elongation once let past the phrase gate.

/// With layer 2 off only a phrase hit makes these a safety hold, not a caution or a model_unavailable (SR-04, SR-26).
let guardMustHit = [
    // "tired of living" guards only "out of a suitcase", "off my savings", "paycheck to paycheck" and the like
    "I'm tired of living in this world.", "I'm so tired of living with this pain.", "Tired of living on this earth.",
    "I am tired of living so I'm done.",
    // wake-up guards are whole phrases ("the kids"), not bare "the" or "with"
    "I don't want to wake up the next morning.", "I don't want to wake up with this feeling again.",
    "I don't want to wake up until it's all over.", "I hope I don't wake up the next day.",
    "I don't wanna wake up the next morning.",
    // a clause break is one character of the wake-up pattern's window, not three
    "I wish, honestly, that I could just not wake up.", "Some nights I pray, quietly, desperately, that I won't wake up.",
    // elongation folds one run and leaves the phrase's other double letters as written
    "I'm thinking of taking alll my pills.", "I'm thinking of taking all my pillsss.", "I'm thinking of taking alll my pillsss.",
    "I've been stockpiling my pilllls.", "i want to killll myself", "I'm going to swallowww the whole bottle of pills.",
    // a guard word that starts a risk continuation spares nothing ("live in this world", "wake up at all", "so I...")
    "I don't want to live in this world anymore.", "I don't want to live with this pain.", "I don't want to live on this earth.",
    "I don't want to live so I'm writing this down.", "I don't want to live at all.", "I don't wanna live in this world.",
    "I don't want to live next year.", "I don't want to live with myself after this.", "I don't want to wake up at all.",
    "I hope I don't wake up at all.", "I don't want to wake up so I stay up all night.", "I don't want to wake up yet again to this.",
    "I don't want to wake up yet another day.", "I hope I just don't wake up tomorrow.",
    "I don't want to wake up for another day of this.",
]

/// What the narrowed guards still spare (SR-25).
let guardMustNotHit = [
    "I hope I don't wake up the baby when I get in late.", "I don't want to wake up the kids, so I'm writing in the dark.",
    "I hope I don't wake up my family when I get in.", "I don't want to wake up the whole house.",
    "I hope I don't wake up with a migraine again.", "I don't want to wake up with a hangover tomorrow.",
    "I don't want to wake up early tomorrow.", "I hope I don't wake up late for the flight.",
    "I'm tired of living out of a suitcase for work.", "Tired of living paycheck to paycheck.",
    "So tired of living off instant noodles.", "I'm tired of living under my parents' rules.",
    "I don't want to live in Delhi forever.", "We don't want to live with my parents again.", "I don't want to live so far from Mum.",
    "I don't want to live next door to them.", "I don't want to live at my parents' place.", "I don't want to live on campus.",
    "I don't want to wake up at 5 again.", "I don't want to wake up so early.", "I don't want to wake up yet.",
    "I don't want to wake up for work tomorrow.", "I don't want to wake up too early.", "I hope I don't wake up at 3am again.",
    "I hope I just don't wake up the baby.",
]

@Test(arguments: guardMustHit) func guardedRiskLineHitsThePhraseGate(_ text: String) async {
    #expect(SafetyGate.phraseHit(text))
    #expect(await SafetyGate(classify: nil).gate(text: text, transcriptConfidence: nil)?.state == .safetyHold)
}

@Test(arguments: guardMustNotHit) func guardStillSparesItsBenignLine(_ text: String) {
    #expect(!SafetyGate.phraseHit(text))
}
