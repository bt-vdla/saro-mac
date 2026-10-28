import Foundation

/// The tone picker's preview (tonePreview.ts): one real sentence of the person's, said four ways. Pure and
/// deterministic, so the four versions never flicker between renders. The rules are also the floor under the
/// on-device rewrite: whatever the model can't do, these still say.
public enum TonePreview {
    public static let sample = "It seems you slept better on the nights you ran, and the mornings after felt lighter."

    static let quote = #"["“”]"#
    static func isQuote(_ c: Character) -> Bool { c == "\"" || c == "“" || c == "”" }

    /// A period that belongs to "i.e.", "e.g.", "a.m." or "Dr." rather than ending the sentence ("at 7 p.m. Then…" ends).
    static func abbreviation(_ text: [Character], _ i: Int) -> Bool {
        guard text[i] == "." else { return false }
        let start = (text[..<i].lastIndex(of: " ") ?? -1) + 1
        let word = String(text[start...i]).jsReplace(#"^[(“"]+"#, all: false, with: "")
        if word.jsTest(#"^(?:mr|mrs|ms|dr|st)\.$"#, i: true) { return true }
        let next = String(text[min(i + 1, text.count)..<min(i + 3, text.count)])
        return word.jsTest(#"^(?:(?:[a-z]\.){2,}|etc\.|vs\.)$"#, i: true) && !next.jsTest(#"^ [A-Z“"]"#)
    }

    /// The first sentence of `text`, whitespace collapsed; quoted sentences stay whole. At most 140 characters.
    public static func previewSentence(_ text: String) -> String {
        let clean = Array(text.jsReplace(#"\s+"#, with: " ").jsTrim)
        var quoted = false
        var end = clean.count
        for i in clean.indices {
            if isQuote(clean[i]) { quoted.toggle() }
            else if !quoted, ".!?".contains(clean[i]), i + 1 == clean.count || clean[i + 1] == " ", !abbreviation(clean, i) {
                end = i + 1
                break
            }
        }
        let sentence = String(clean[..<end])
        guard sentence.count > 140 else { return sentence }
        let cut = String(sentence.prefix(139))
        return String(cut[..<(cut.lastIndex(of: " ") ?? cut.endIndex)]).jsReplace(#"[\s,;:]+$"#, with: "") + "…"
    }

    static let hedges = #"\b(it seems( that| like)?|it looks like|it sounds like|i think|i wonder if|maybe|perhaps|probably|possibly|kind of|sort of|a little|a bit|somewhat|just|actually|really|honestly|basically|also)\s+"#
    // Already soft somewhere ("you seemed calm"), so gentle doesn't add a second "It seems".
    static let soft = #"\b(it seems|seems?|seemed|appears?|appeared|looks like|sounds like|might|may|maybe|perhaps|probably|possibly|i think|i wonder)\b"#
    // The openings "It seems …" goes in front of (and lower-cases). Anything else keeps its shape: a fragment ("Woke up
    // tired."), a name ("Maya came up"). ponytail: a closed list, so a name never gets "It seems"; the model does better.
    static let commonOpeners = Set("you yours your the this that these those today tonight yesterday it there some most when after before on in at every each what how one two three first second third last several many nothing something everything we they my our sleep work running mornings evenings nights words family health creativity relationships money purpose nature learning".split(separator: " ").map(String.init))
    static let questionWords = Set("why what how when where who which whose do does did is are was were can could would should will have has am".split(separator: " ").map(String.init))

    // First person to second, so a reflection reads as Saro talking about it. Typed quickly, "i" is lower case; "i.e."
    // isn't a person.
    static let person: [(String, String)] = [
        (#"\bi am\b"#, "you are"), (#"\bi['’]m\b"#, "you’re"), (#"\bi was\b"#, "you were"), (#"\bi['’]ve\b"#, "you’ve"),
        (#"\bi['’]d\b"#, "you’d"), (#"\bi['’]ll\b"#, "you’ll"), (#"\bi\b(?!\.\w)"#, "you"), (#"\bmyself\b"#, "yourself"),
        (#"\bmine\b"#, "yours"), (#"\bmy\b"#, "your"), (#"\bme\b"#, "you"),
    ]

    /// The person's own sentence, as Saro would say it back to them; what they quoted stays as it was said.
    public static func toSecondPerson(_ text: String) -> String {
        upperFirst(outsideQuotes(text) { part in person.reduce(part) { $0.jsReplace($1.0, i: true, with: $1.1) } })
    }

    static func trimEnd(_ s: String) -> String { s.jsTrim.jsReplace(#"[\s.!?…]+$"#, with: "") }

    /// Capitalises the first letter, past an opening quote; a word with its own capitals ("iPhone", "eBay") stays.
    static func upperFirst(_ s: String) -> String {
        s.jsReplace(#"^([“"]?)([a-z])(?![a-z'’]*[A-Z])"#, all: false) { g, _ in (g[1] ?? "") + (g[2] ?? "").uppercased() }
    }

    /// Written in capitals ("THE BEST DAY EVER"): their emphasis, so nothing is put in front of it.
    static func shouted(_ s: String) -> Bool { s.jsTest("[A-Z]{2}") && s == s.uppercased() }
    static func wordCount(_ s: String) -> Int { s.split(separator: " ").count }
    static func firstWord(_ s: String) -> String {
        String(s.split(separator: " ", omittingEmptySubsequences: false).first ?? "").replacingOccurrences(of: "’", with: "'")
            .jsReplace("[^A-Za-z']", with: "")
    }
    static func stem(_ word: String) -> String { String(word.lowercased().split(separator: "'", omittingEmptySubsequences: false).first ?? "") }

    /// Applies `edit` to the parts of `s` outside quotes: the person's own quoted words stay as they wrote them.
    static func outsideQuotes(_ s: String, _ edit: (String) -> String) -> String {
        var out = ""
        var rest = s
        while let m = rest.jsMatch(#"[“"][^”"]*[”"]"#)?[0], let r = rest.range(of: m) {
            out += edit(String(rest[..<r.lowerBound])) + m
            rest = String(rest[r.upperBound...])
        }
        return out + edit(rest)
    }

    /// The index of the first `char` outside quotes.
    static func indexOutside(_ s: [Character], _ char: Character) -> Int? {
        var quoted = false
        for (i, c) in s.enumerated() {
            if isQuote(c) { quoted.toggle() } else if !quoted, c == char { return i }
        }
        return nil
    }

    /// "The day…" → "the day…" after a lead-in; only a plain capital is lowered, never "THE", "iPhone" or a name.
    static func lowerOpening(_ s: String) -> String {
        let raw = firstWord(s)
        let first = stem(raw)
        guard raw.jsTest("^[A-Z][a-z']*$"), commonOpeners.contains(first) || questionWords.contains(first) else { return s }
        return s.prefix(1).lowercased() + s.dropFirst()
    }

    /// Whether "It seems " reads as a sentence in front of `s`: a known opening ("You’re", "The") and a few words.
    static func takesItSeems(_ s: String) -> Bool { commonOpeners.contains(stem(firstWord(s))) && wordCount(s) >= 3 }

    /// The first clause: up to the first comma, semicolon, dash or "but" outside quotes.
    static func firstClause(_ s: String) -> String {
        let c = Array(s)
        var quoted = false
        for i in c.indices {
            if isQuote(c[i]) { quoted.toggle() }
            if quoted { continue }
            if ",;—–".contains(c[i]) || String(c[i..<min(i + 5, c.count)]).lowercased() == " but " { return String(c[..<i]) }
        }
        return s
    }

    /// `sentence` in Saro's `tone`: gentle softens and reassures, direct strips hedges, contemplative asks.
    public static func rewrite(_ sentence: String, tone: Tone) -> String {
        let s = sentence.jsReplace(#"\s+"#, with: " ").jsTrim
        // Neutral is the sentence as written, only with its first letter capitalised as every other tone's is.
        guard !s.isEmpty, tone != .neutral else { return upperFirst(s) }
        let question = s.hasSuffix("?")
        let core = trimEnd(s)
        switch tone {
        case .neutral:
            return s
        case .contemplative:
            return question ? upperFirst(s) : "\(upperFirst(core)). What do you make of that?"
        case .direct:
            let end = question ? "?" : "."
            let plain = outsideQuotes(core) { $0.jsReplace(hedges, i: true, with: "") }.jsReplace(#"\s+"#, with: " ").jsTrim
            // 'You said "…"', 'In your words: "…"': their words are the point.
            if let lead = plain.jsMatch(#"^([^“"]+?)[:,]?\s*([“"][^”"]+[”"])$"#), wordCount(lead[1] ?? "") <= 6, wordCount(lead[2] ?? "") >= 3 {
                return upperFirst(lead[2] ?? "") + end
            }
            // "The pattern is clear: you sleep better": after a colon is the point.
            let chars = Array(plain)
            let afterColon = indexOutside(chars, ":").map { String(chars[($0 + 1)...]) }
            let point = afterColon.flatMap { wordCount($0) >= 3 ? $0.jsTrim : nil } ?? plain
            let clause = firstClause(point).jsTrim
            return upperFirst(wordCount(clause) >= 3 ? clause : point) + end
        case .gentle:
            // A question gets a softer frame. Their quoted words are certain, and a soft sentence is soft already, so
            // neither gets "It seems".
            if question { return "A gentle question: \(lowerOpening(core))? There’s no wrong answer." }
            let keep = core.jsTest(soft, i: true) || core.jsTest(quote) || shouted(core) || !takesItSeems(core)
            return "\(keep ? upperFirst(core) : "It seems \(lowerOpening(core))"). You’re doing better than you think."
        }
    }
}
