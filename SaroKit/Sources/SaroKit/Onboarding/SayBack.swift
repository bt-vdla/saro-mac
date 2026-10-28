import Foundation

/// Their words said back to them (lib/demo/memory.ts sayBack and goalPhrase): the first prompt and What Saro knows use
/// the same lines, so a goal reads "you want to be more present for your kids" wherever it's shown.
public enum SayBack {
    static let maxChars = 90

    private static let you: [String: String] = ["myself": "yourself", "my": "your", "me": "you", "mine": "yours", "i'm": "you’re", "i": "you"]
    private static let firstPerson = Rx(#"\b(?:myself|mine|my|me|i['’]m|i)\b"#, .caseInsensitive)
    private static let toMe = Rx(#"\b((?:kind|kinder|nice|nicer|gentle|gentler|easy|easier|hard|harder|soft|softer|honest|patient|good|better)\s+(?:to|on|with)|(?:feel|be|more)\s+like|(?:time|space|room)\s+for)\s+me\b"#, .caseInsensitive)
    private static let meTime = Rx(#"\bme[\s-]time\b"#, .caseInsensitive)
    private static let our = Rx(#"\bour(s?)\b"#, .caseInsensitive)
    private static let youAm = Rx(#"\byou am\b"#, .caseInsensitive)
    private static let youWas = Rx(#"\byou was\b"#, .caseInsensitive)

    // Keys are built with this, so it never changes: a deleted goal's key has to match next time.
    static func toYou(_ s: String) -> String {
        firstPerson.replace(s) { you[$0.text.lowercased().replacingOccurrences(of: "’", with: "'")] ?? $0.text }
    }

    /// "who I am" is "who you are", "kinder to me" and "more like me" are "…yourself", "me time" is "time for yourself",
    /// "our" is "your".
    public static func sayBack(_ s: String) -> String {
        let mine = our.replace(meTime.replace(toMe.replace(s, "$1 myself"), "time for myself"), "your$1")
        return youWas.replace(youAm.replace(toYou(mine), "you are"), "you were")
    }

    // What a goal opens on: "I want to", "I just need to", "I'd love to", "I'm trying to", "we want to", "trying to", or
    // "to" opening the clause. Group 1 is set when it's a need.
    private static let adverbs = #"(?:(?:just|really|also|still|honestly|genuinely|actually|finally|so)\s+)*"#
    private static let goalLead = Rx(#"(?:\b(?:i(?:['’]m|\s+am)|we(?:['’]re|\s+are))\s+"# + adverbs + #"(?:trying|going|hoping|planning)|\b(?:i|we)(?:['’]d|\s+would)\s+"# + adverbs + #"(?:like|love)|\b(?:i|we)\s+"# + adverbs + #"(?:(need|have)|want|hope|plan)|\b(?:trying|hoping)|^\s*)\s*to\s+"#, .caseInsensitive)

    private static func words(_ s: String) -> Set<String> { Set(s.split(separator: " ").map(String.init)) }
    private static let dangling = words("a an the to of for with at in on by from into onto about until till than as because if when while whether and but or nor so every each very really just my our your their its")
    private static let subordinate = words("because until till before after when while if unless so than as that though although since whether who which where")
    // "the kind of person who": the person didn't finish the thought, so there's no line to write.
    private static let unfinished = words("who whom whose which that where")
    // Words that alone say nothing: "be able" is all that's left of "I want to be able to".
    private static let empty = words("be able get have do feel go to")
    private static let filler = words("lol lmao haha hahaha tbh honestly please ok okay idk")
    // A verb the second half of "I want to be a better listener and more patient" shares ("be more patient").
    private static let sharedVerb = words("be feel get become stay")
    private static let saysNothing = words("often again soon now still ever anymore much too than lol lmao haha please tbh")
    // After "more" or "less", one of these says how much of a verb ("worry less about…"): without the verb it's no goal.
    private static let howMuch = words("about as at on to with when if because and but or")
    // A verb that opens a goal on its own ("Worry less about…", "Spend more time…").
    // ponytail: a short list, not a tagger (words that are mostly nouns, like "work", are left out).
    private static let openingVerb = words("be feel get become stay stop start worry sleep eat drink spend move read write walk run exercise stress care think overthink talk listen laugh smile complain travel cook give take say see go do make find learn practise practice save trust enjoy")
    // A preposition can end the line when a clause before it leaves it there: "someone my kids can talk to".
    private static let strands = words("to with about for on at from of in into")
    private static let strandedBy = words("that who whom which what where someone somebody something anyone anybody anything somewhere place person people reason can could will would")

    // After "more" or "less": a word that describes ("more patient" → "to be more patient") rather than one that names.
    // ponytail: suffixes and a short list, not a dictionary.
    static let describes = Rx(#"^(?:calm|kind|present|patient|happy|healthy|fit|strong|brave|open|honest|free|sure|tidy|steady|ready|easy|chill|gentle|humble|loyal|aware|awake|alive|sober|tired|lonely|friendly|lovely|busy|lazy|angry|grumpy|sleepy|chatty|funny|loving|caring|understanding|forgiving|outgoing|easygoing|myself|like)$|^.{2,}(?:ous|ful|less|ish|[^e]ed)$|^.{3,}(?:ive|ent|ant|able|ible|ial|ical|nal|ual|istic|etic|atic|ntic)$"#)
    static let namesAThing = Rx(#"(?:ment|ness|ity|ance|ence|tion|sion|ship|hood|ism)$"#)

    private static let beforeClause = Rx(#"[^,.;:!?\n]*\z"#)
    private static let afterClause = Rx(#"^[^,.;:!?\n]*"#)
    private static let join = Rx(#"\s+(?:and|but)\s+"#, .caseInsensitive)
    private static let betweenOpen = Rx(#"\bbetween\b(?!.*\band\b)"#, .caseInsensitive)
    private static let andBut = Rx(#"\b(?:and|but)\b"#, .caseInsensitive)
    private static let moreLessFewer = Rx(#"^(?:more|less|fewer)\b"#, .caseInsensitive)
    private static let bareTo = Rx(#"^\s*to\s+$"#, .caseInsensitive)
    private static let endPunctuation = Rx(#"[.!?]+$"#)

    private static func length(_ s: String) -> Int { (s as NSString).length }

    /// At most `room` characters of whole words; a clause cut short goes back to before its opening word.
    private static func fitWords(_ phrase: String, room: Int) -> String {
        guard length(phrase) > room else { return phrase }
        var words = phrase.split(whereSeparator: \.isWhitespace).map(String.init)
        while !words.isEmpty, length(words.joined(separator: " ")) > room { words.removeLast() }
        if let i = words.indices.dropFirst().last(where: { subordinate.contains(words[$0].lowercased()) }) { words = Array(words[..<i]) }
        while let last = words.last, dangling.contains(last.lowercased()) { words.removeLast() }
        return words.joined(separator: " ")
    }

    /// A goal pick said back as what follows "You want" or "You need": "to be more present for your kids", "more
    /// sleep". Nil when it can't be a clean sentence. `answer` is the whole answer it came from.
    public static func goalPhrase(_ span: String, answer: String? = nil) -> (need: Bool, phrase: String)? {
        let at = answer.map { ($0 as NSString).range(of: span).location } ?? NSNotFound
        let text = at != NSNotFound ? answer! : span
        let ns = text as NSString
        let from = at == NSNotFound ? 0 : at
        let before = beforeClause.first(ns.substring(to: from))?.text ?? ""
        let tail = afterClause.first(ns.substring(from: min(ns.length, from + length(span))))?.text ?? ""
        // On to the next "and" or "but", except the "and" in "between work and life".
        var after = tail
        if let j = join.first(tail) {
            let tns = tail as NSString
            let part = tns.substring(to: j.range.location)
            let rest = tns.substring(from: NSMaxRange(j.range))
            let next = join.first(rest).map { (rest as NSString).substring(to: $0.range.location) } ?? rest
            after = j.text.lowercased().contains("and") && betweenOpen.test(before + span + part) ? part + j.text + next : part
        }
        let clause = before + span
        let found = goalLead.first(span)
        let own = found.flatMap { $0.range.location == 0 && !bareTo.test($0.text) ? $0 : nil }
        let lead = own ?? goalLead.first(clause)
        let opener = before.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var need = false
        var head: String?
        var rest = span + after
        if let own {
            need = own[1] != nil
            (head, rest) = ("to ", (span as NSString).substring(from: own.range.length) + after)
        } else if let lead, lead.range.location <= length(before) {
            need = lead[1] != nil
            let cns = clause as NSString
            let between = cns.substring(with: NSRange(location: NSMaxRange(lead.range), length: max(0, length(before) - NSMaxRange(lead.range))))
            let verb = between.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
            if !andBut.test(between) {
                (head, rest) = ("to ", cns.substring(from: NSMaxRange(lead.range)) + after)
            } else if sharedVerb.contains(verb), moreLessFewer.test(span) {
                (head, rest) = ("to ", "\(verb) \(span)\(after)")
            }
        } else if openingVerb.contains(opener) {
            (head, rest) = ("to ", "\(opener) \(rest)")
        }
        if head == nil {
            let parts = jsSplit(rest.lowercased())
            let first = parts.first ?? "", second = parts.count > 1 ? parts[1] : ""
            if ["more", "less", "fewer"].contains(first) {
                if second.isEmpty || saysNothing.contains(second) || howMuch.contains(second) || (second.hasSuffix("ly") && !describes.test(second)) { return nil }
                head = first != "fewer" && describes.test(second) && !namesAThing.test(second) ? "to be " : ""
            } else {
                head = openingVerb.contains(first) ? "to " : ""
            }
        }
        var said = sayBack(endPunctuation.replace(rest, ""))
        if let c = said.first, !c.isWhitespace { said = c.lowercased() + said.dropFirst() }
        var words = said.split(whereSeparator: \.isWhitespace).map(String.init)
        func word(_ fromEnd: Int) -> String { words.count >= fromEnd ? words[words.count - fromEnd].lowercased() : "" }
        while !words.isEmpty, filler.contains(word(1)) { words.removeLast() }
        let stranded = strands.contains(word(1)) && words.dropLast(2).contains { strandedBy.contains($0.lowercased()) }
        if !stranded { while !words.isEmpty, filler.contains(word(1)) || dangling.contains(word(1)) { words.removeLast() } }
        if unfinished.contains(word(1)) || words.allSatisfy({ empty.contains($0.lowercased()) }) { return nil }
        // "To be more" hasn't said more of what yet.
        if ["more", "less"].contains(word(1)), ["be", "become", "get", "stay"].contains(word(2)) { return nil }
        let goal = fitWords(words.joined(separator: " "), room: maxChars - length("You \(need ? "need" : "want") \(head!)."))
        return goal.isEmpty ? nil : (need, head! + goal)
    }

    /// `s.split(/\s+/)` as JavaScript does it: a leading space gives an empty first part.
    static func jsSplit(_ s: String) -> [String] {
        var parts = s.split(whereSeparator: \.isWhitespace).map(String.init)
        if s.first?.isWhitespace == true { parts.insert("", at: 0) }
        if s.last?.isWhitespace == true { parts.append("") }
        return parts.isEmpty ? [""] : parts
    }
}
