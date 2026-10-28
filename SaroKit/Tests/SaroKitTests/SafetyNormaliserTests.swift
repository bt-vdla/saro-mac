import Foundation
import Testing
@testable import SaroKit

// MARK: - Normaliser properties (SR-05)

let normaliserSamples = flagged + notFlagged + [
    "", " ", "...", "a", "Café, naïve façade", "Straße", "ǅemal", "ﬁne ﬂow", "e.g. 3.5 kg", "?!", "— wait —", "i want to , die",
    "मैं मर जाऊँ।", "क़ ख़ ग़ ज़ ड़ ढ़ फ़ य़", "न\u{093C} र\u{093C} ळ\u{093C}", "தற்கொலை", "আত্মহত্যা", "ਖ਼ੁਦਕੁਸ਼ੀ", "خودکشی",
    "Привет, мир", "Καλημέρα", "死にたい", "我想死", "죽고 싶다", "שָׁלוֹם", "สวัสดีครับ", "👩‍💻🏳️‍🌈❤️1️⃣",
]

@Test func normaliserIsIdempotent() {
    for text in normaliserSamples {
        let once = SafetyGate.normalise(text)
        #expect(SafetyGate.normalise(once) == once, "\(text)")
    }
}

@Test func normaliserOutputIsSingleSpacedAndTrimmed() {
    for text in normaliserSamples {
        let n = SafetyGate.normalise(text)
        #expect(!n.hasPrefix(" ") && !n.hasSuffix(" ") && !n.contains("  "), "\(text) -> \(n)")
    }
}

@Test func normaliserNeverDropsNonASCIILetters() {
    let letters: Set<Unicode.GeneralCategory> = [.uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter]
    let foldedOnPurpose: Set<Unicode.Scalar> = ["\u{0929}", "\u{0931}", "\u{0934}"]
    for text in normaliserSamples {
        let folded = text.precomposedStringWithCompatibilityMapping.lowercased()
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let out = Set(SafetyGate.normalise(text).unicodeScalars)
        for s in folded.unicodeScalars where !s.isASCII && letters.contains(s.properties.generalCategory) && !foldedOnPurpose.contains(s) {
            #expect(out.contains(s), "U+\(String(s.value, radix: 16)) dropped from \(text)")
        }
    }
    // Scripts already in normal form pass through unchanged, vowel signs and viramas included.
    for text in ["मैं मर जाऊं", "तेरे बिना", "தற்கொலை", "আত্মহত্যা", "خودکشی", "привет мир", "死にたい", "我想死", "죽고 싶다", "สวัสดีครับ"] {
        #expect(SafetyGate.normalise(text) == text, "\(text)")
    }
}

@Test func normaliserFoldsDevanagariNuktaAndChandrabindu() {
    let pairs: [(String, String)] = [
        ("\u{0958}", "क"), ("\u{0959}", "ख"), ("\u{095A}", "ग"), ("\u{095B}", "ज"), ("\u{095C}", "ड"), ("\u{095D}", "ढ"),
        ("\u{095E}", "फ"), ("\u{095F}", "य"), ("\u{0929}", "न"), ("\u{0931}", "र"), ("\u{0934}", "ळ"),
        ("क\u{093C}", "क"), ("ज\u{093C}", "ज"), ("न\u{093C}", "न"), ("र\u{093C}", "र"),
        ("जाऊँ", "जाऊं"), ("हँसना", "हंसना"), ("ज़िंदगी", "जिंदगी"), ("ख़ुदकुशी", "खुदकुशी"),
    ]
    for (variant, base) in pairs {
        #expect(SafetyGate.normalise(variant) == SafetyGate.normalise(base), "\(variant)")
    }
    // Folding stops at spelling: a different vowel sign is a different word.
    #expect(SafetyGate.normalise("मारना") != SafetyGate.normalise("मरना"))
}

@Test func normaliserDropsInvisibleCharacters() {
    for invisible in ["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}", "\u{00AD}", "\u{200E}", "\u{200F}", "\u{202E}",
                      "\u{FE0F}", "\u{E0067}"] {
        #expect(SafetyGate.normalise("sui\(invisible)cide") == "suicide", "U+\(String(invisible.unicodeScalars.first!.value, radix: 16))")
    }
}

@Test func normaliserBreaks() {
    #expect(SafetyGate.normalise("I want\u{00A0}to\u{3000}die\u{202F}now") == "i want to die now")
    #expect(SafetyGate.normalise("one. Two") == "one . two")
    #expect(SafetyGate.normalise("one! Two? Three\nfour।पाँच") == "one . two . three . four . पांच")
    #expect(SafetyGate.normalise("one, two; three: four") == "one , two , three , four")
    #expect(SafetyGate.normalise("one... two… three.. four") == "one , two , three , four")
    #expect(SafetyGate.normalise("one...\nTwo") == "one . two")
    #expect(SafetyGate.normalise("don‛t don＇t don’t don't don´t donʼt don`t") == "dont dont dont dont dont dont dont")
    #expect(SafetyGate.normalise("Nooooo, I'm sooo tired. Kill, skill, all") == "no , im so tired . kill , skill , all")
}
