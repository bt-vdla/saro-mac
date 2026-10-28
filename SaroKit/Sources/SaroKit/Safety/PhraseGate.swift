import Foundation

/// Layer 1 (SR-04, SR-05, SR-06): the phrase gate and the caution lexicon over one normalised form.
extension SafetyGate {
    /// SR-05: the one normaliser for patterns and text alike. Apostrophes dropped ("don't" -> "dont"), NFKC, lowercase,
    /// case and diacritic folding, a run of three or more of one ASCII letter cut to one ("dieeee" -> "die"), and every
    /// run of other punctuation or space collapsed to one token: " . " for a sentence end, so a guard word never reaches
    /// across a sentence; " , " for a clause break (comma, semicolon, colon, ellipsis), which a phrase reads through but a
    /// guard word doesn't; else one space. Letters, marks and digits of every script survive.
    public static func normalise(_ text: String) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: text.unicodeScalars.filter { !apostrophes.contains($0) })
        let folded = String(view).precomposedStringWithCompatibilityMapping.lowercased()
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var out = String.UnicodeScalarView()
        out.reserveCapacity(folded.utf8.count)
        var gap = 0, dots = 0, run = 0, last: Unicode.Scalar = " "
        for s in folded.unicodeScalars {
            // ASCII by hand: the property lookup is most of the normaliser's time on English text (the <1 ms budget, SR-04).
            let category = !s.isASCII ? s.properties.generalCategory
                : ("a"..."z").contains(s) ? .lowercaseLetter : ("0"..."9").contains(s) ? .decimalNumber : .otherPunctuation
            switch category {
            case .format: continue
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .nonspacingMark, .spacingMark, .decimalNumber, .letterNumber, .otherNumber:
                // Emoji presentation selectors are marks too; dropped so "kill ☠️ myself" still reads as two words.
                if s == "\u{093C}" || s.value >= 0xFE00 && s.properties.isVariationSelector { continue }
                // NFKC turns "…" into "...": one dot ends a sentence, two or more are a pause.
                let level = dots > 1 ? max(gap, 2) : dots == 1 ? 3 : gap
                if level > 0, !out.isEmpty { out.append(contentsOf: (level == 3 ? " . " : level == 2 ? " , " : " ").unicodeScalars) }
                run = level == 0 && s.isASCII && category == .lowercaseLetter && s == last ? run + 1 : 1
                (gap, dots, last) = (0, 0, s)
                if run == 3 { out.removeLast() }
                if run < 3 { out.append(devanagariFold(s)) }
            default:
                if s == "." { dots += 1 } else { gap = max(gap, sentenceEnds.contains(s) ? 3 : clauseBreaks.contains(s) ? 2 : 1) }
            }
        }
        return String(out)
    }

    /// Layer 1 and layer 3: true when the text contains a self-harm phrase. Always runs, AI on or off.
    public static func phraseHit(_ text: String) -> Bool {
        let n = normalise(text)
        return hit(phraseIndex, n) || wakeRegex.firstMatch(in: n, range: NSRange(location: 0, length: n.utf16.count)) != nil
    }

    /// SR-06: the broader caution lexicon, consulted only when layer 2 can't run. Never shows the SafetyCard by itself.
    public static func cautionHit(_ text: String) -> Bool { hit(cautionIndex, normalise(text)) }

    private static let apostrophes: Set<Unicode.Scalar> = ["'", "\u{2018}", "\u{2019}", "\u{201B}", "\u{02BC}", "`", "\u{00B4}",
                                                           "\u{2032}", "\u{FF07}"]
    private static let sentenceEnds: Set<Unicode.Scalar> = ["!", "?", "\n", "\r", "\u{0964}", "\u{0965}"]
    private static let clauseBreaks: Set<Unicode.Scalar> = [",", ";", ":"]

    /// Diacritic folding leaves Devanagari alone, so its spelling variants fold by hand: chandrabindu to anusvara, and the
    /// three nukta letters NFKC keeps precomposed (the rest decompose, and the nukta itself is dropped).
    private static func devanagariFold(_ s: Unicode.Scalar) -> Unicode.Scalar {
        switch s {
        case "\u{0901}": "\u{0902}"
        case "\u{0929}": "\u{0928}"
        case "\u{0931}": "\u{0930}"
        case "\u{0934}": "\u{0933}"
        default: s
        }
    }

    /// A whole-word phrase with `safety.ts`'s guards on the word just before or just after ("don't want to die",
    /// "take my life back").
    private struct Phrase: Sendable {
        let words: [String]
        let notBefore: Set<String>
        let notAfter: Set<String>
    }

    /// Each pattern also in its squeezed spelling ("kill" -> "kil"), which is what elongated text ("killll") normalises to.
    private static func phrases(_ list: [String], notBefore: [String] = [], notAfter: [String] = []) -> [Phrase] {
        let forms = list.map(normalise)
        return Set(forms + forms.map(squeezed)).map {
            Phrase(words: $0.split(separator: " ").map(String.init), notBefore: Set(notBefore), notAfter: Set(notAfter))
        }
    }

    private static func squeezed(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for c in s.unicodeScalars where !(c.isASCII && c.properties.isAlphabetic && c == out.last) { out.append(c) }
        return String(out)
    }

    /// Every combination of the parts, in order; an empty string skips that part.
    private static func combos(_ parts: [String]...) -> [String] {
        parts.reduce([""]) { acc, part in acc.flatMap { a in part.map { [a, $0].filter { !$0.isEmpty }.joined(separator: " ") } } }
    }

    /// Phrases keyed by first word, so matching is one dictionary lookup per word of text (the <1 ms budget, SR-04).
    private static func index(_ groups: [[Phrase]]) -> [String: [Phrase]] {
        Dictionary(grouping: groups.joined(), by: { $0.words[0] })
    }

    private static func hit(_ index: [String: [Phrase]], _ normalised: String) -> Bool {
        // Clause breaks drop out of the words; `paused[i]` says one stood just before word i, which blocks a guard there.
        var words: [String] = [], paused: [Bool] = [], pause = false
        for w in normalised.split(separator: " ") {
            if w == "," { pause = true; continue }
            words.append(String(w))
            paused.append(pause)
            pause = false
        }
        for i in words.indices {
            for p in index[words[i]] ?? [] where i + p.words.count <= words.count {
                let end = i + p.words.count
                // By hand rather than `elementsEqual`, which is the gate's hot loop and slow unoptimised.
                var k = 1
                while k < p.words.count, words[i + k] == p.words[k] { k += 1 }
                if k < p.words.count { continue }
                if i > 0, !paused[i], p.notBefore.contains(words[i - 1]) { continue }
                if end < words.count, !paused[end], p.notAfter.contains(words[end]) { continue }
                return true
            }
        }
        return false
    }

    private static let negated = ["dont", "didnt", "doesnt", "never", "not"]
    private static let housing = ["in", "with", "near", "there", "here", "at", "on", "together", "alone", "by", "next", "so",
                                  "far", "somewhere", "abroad", "close"]
    private static let wakeGuard = ["early", "at", "before", "for", "so", "too", "yet"]
    private static let cutGuard = ["some", "a", "slack", "off", "loose", "free", "out", "in", "short", "up"]

    private static let phraseIndex = index([
        // safety.ts
        phrases(["kill myself", "killing myself", "kill my self", "kil myself", "killmyself"]),
        phrases(["end my life", "ending my life", "end my own life", "end it all", "ending it all"]),
        phrases(["take my own life", "taking my own life", "take my life", "taking my life"],
                notAfter: ["back", "savings", "in", "into", "to", "more", "seriously", "apart"]),
        phrases(["suicide"], notAfter: ["squad"]),
        phrases(["suicidal", "suicde", "sucide", "suiside", "suicid", "suicidle", "sucidal", "suisidal", "suicidial", "suicidel"]),
        phrases(["want to die", "wanna die", "wanting to die", "want to be dead", "wanna be dead"],
                notBefore: negated, notAfter: ["of", "laughing"]),
        phrases(["wish i was dead", "wish i were dead", "wish i wasn't alive", "wish i was never born", "wish i had never been born",
                 "better off dead", "better off without me"]),
        phrases(["don't want to live", "do not want to live", "don't wanna live"], notAfter: housing),
        phrases(["don't want to be alive", "do not want to be alive", "don't want to exist", "do not want to exist"]),
        phrases(["don't want to wake up", "do not want to wake up"], notAfter: wakeGuard),
        phrases(["don't want to be here", "do not want to be here", "don't wanna be here"]),
        phrases(["no reason to live", "nothing to live for", "no point in living", "no point living", "no point anymore",
                 "no point to anything", "no point in anything", "no point going on", "no point in going on",
                 "what's the point anymore", "what's the point of living", "what's the point of anything",
                 "what's the point of being alive", "can't go on living", "tired of living", "tired of being alive",
                 "sick of being alive"]),
        phrases(["self harm", "selfharm", "self harming", "self harmed", "self injury", "self injuring"]),
        phrases(["harm myself", "harming myself", "hurt myself on purpose", "want to hurt myself", "wanna hurt myself",
                 "going to hurt myself", "gonna hurt myself", "thinking about hurting myself", "thought about hurting myself",
                 "thoughts of hurting myself", "urge to hurt myself", "feel like hurting myself", "want to cut myself",
                 "wanna cut myself", "urge to cut myself", "cut myself again", "cut myself on purpose", "started cutting again",
                 "unalive myself", "unaliving myself", "slit my wrists", "slitting my wrists", "take all my pills",
                 "take all the pills", "swallow all my pills"]),
        phrases(["cutting myself"], notAfter: cutGuard),
        phrases(["hang myself", "hanging myself"], notAfter: ["upside", "up"]),
        // safety.py:29-49 (bar the wake-up one below), with safety.ts's guards where the two overlap
        phrases(combos(["kill", "killing"], ["myself", "my self"])),
        phrases(combos(["end", "ending"], ["it all", "my life", "my own life"])),
        phrases(combos(["want", "wanted", "going", "plan", "planning", "ready"], ["to die"]),
                notBefore: negated, notAfter: ["of", "from", "laughing"]),
        phrases(combos(["wish", "wish that"], ["i was dead", "i were dead"])),
        phrases(combos(["wish i"], ["could", ""], ["just", ""], ["die", "disappear forever"])),
        phrases(combos(["no reason", "no point"], ["to", "in"], ["live", "living", "go on", "going on"])),
        phrases(["self harm", "selfharm", "self harming", "selfharming"]),
        phrases(combos(["want", "wanted", "wanting", "urge", "urges", "tempted", "thinking about", "thought about"], ["to", ""],
                       ["cut", "cutting", "hurt", "hurting", "harm", "harming"], ["myself", "my self"]), notAfter: cutGuard),
        phrases(combos(["started", "keep", "kept"], ["cutting", "hurting", "harming"], ["myself", "my self"]), notAfter: cutGuard),
        phrases(combos(["over dose", "overdose", "over dosing", "overdosing"], ["on", "with"])),
        phrases(["khud kushi", "khudkushi", "aatma hatya", "aatmahatya"]),
        phrases(combos(["mar", "marna", "mar jaana", "mar jana"], ["chahta", "chahti"])),
        phrases(["jeena nahi chahta", "jeena nahi chahti"]),
        phrases(combos(["jeene ka"], ["man", "mann", "dil"], ["nahi"])),
        // DRAFT: clinician review (SR-32) — expanded Hinglish, romanised
        phrases(["mar jaun", "mar jaaun", "mar jau", "mar jaau", "mar jaoon", "mar jaana hai", "mar jana hai",
                 "zinda nahi rehna", "zinda nahin rehna", "jeena nahin chahta", "jeena nahin chahti",
                 "sab khatam kar dun", "sab khatam kar doon", "sab khatam kar du", "sab khatm kar dun",
                 "khud ko khatam", "khud ko khatm", "khudko khatam", "atmahatya", "atma hatya"]),
        // DRAFT: clinician review (SR-32) — expanded Hinglish, Devanagari
        phrases(["मर जाऊं", "मर जाऊँ", "मर जाऊ", "मरना चाहता", "मरना चाहती", "मर जाना चाहता", "मर जाना चाहती", "मर जाना है",
                 "ज़िंदा नहीं रहना", "जिंदा नहीं रहना", "ज़िन्दा नहीं रहना", "जिन्दा नहीं रहना", "जीना नहीं चाहता", "जीना नहीं चाहती",
                 "सब ख़त्म कर दूं", "सब खत्म कर दूँ", "सब ख़त्म कर दूँ", "सब खत्म कर दूं", "ख़ुद को ख़त्म", "खुद को खत्म",
                 "आत्महत्या", "ख़ुदकुशी", "खुदकुशी"]),
    ])

    // safety.py's one pattern with a gap: "wish I could just not wake up". Written in normalised form.
    private static let wakeRegex = try! NSRegularExpression(
        pattern: "\\b(?:wish|hope|want)\\b[^.]{0,30}\\b(?:not|never) wake up\\b(?! (?:\(wakeGuard.joined(separator: "|")))\\b)")

    // P0 draft (SR-06): broad on purpose. A hit only blocks quote-backs and heuristic questions until layer 2 reads the entry.
    private static let cautionIndex = index([
        phrases(["hopeless", "hopelessness", "helpless", "worthless", "useless", "burden", "can't go on", "can't do this anymore",
                 "can't take it anymore", "give up", "giving up", "gave up on", "no way out", "trapped", "empty inside", "numb",
                 "disappear", "vanish", "fade away", "sleep forever", "not wake up", "never wake up", "pills", "overdose",
                 "razor", "razors", "blade", "blades", "rope", "noose", "bridge", "jump off", "cut", "cutting", "cuts", "scars",
                 "bleed", "bleeding", "die", "dying", "dead", "death", "kill", "killing", "end it", "goodbye forever",
                 "nobody would care", "no one would care", "no one would notice", "not worth it", "pointless", "alone forever",
                 "hate myself", "hurt myself", "punish myself", "starve myself"]),
        // DRAFT: clinician review (SR-32) — Hinglish caution words, romanised and Devanagari
        phrases(["bekaar", "bojh", "umeed nahi", "zindagi se thak", "gayab ho jaun", "neend ki goliyan", "goliyan", "marna",
                 "mar jaunga", "mar jaungi", "khatam", "बेकार", "बोझ", "उम्मीद नहीं", "ज़िंदगी से थक", "गायब हो जाऊं",
                 "नींद की गोलियां", "गोलियां", "मरना", "ख़त्म"]),
    ])
}
