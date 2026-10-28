import Foundation
import NaturalLanguage

/// The heuristic twin of memory extraction: ports of `saro/frontend/lib/demo/memory.ts`, plus NLTagger for places,
/// organisations and one more person signal. Every observation quotes a whole sentence of the person's own words, at
/// its UTF-16 span, so What Saro knows never shows a word they didn't write.
public enum MemoryRules {
    public static let extractorVersion = "mem-1"

    // MARK: Sentences

    private static let sentenceRegex = try! NSRegularExpression(pattern: #"[^.!?\n]+[.!?]*"#)

    /// memory.ts sentencesOf, with spans: runs up to . ! ? or a line break, trimmed.
    static func sentences(_ text: String) -> [NSRange] {
        let ns = text as NSString
        return sentenceRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            var r = m.range
            while r.length > 0, let c = Unicode.Scalar(ns.character(at: r.location)), CharacterSet.whitespacesAndNewlines.contains(c) {
                r.location += 1
                r.length -= 1
            }
            while r.length > 0, let c = Unicode.Scalar(ns.character(at: NSMaxRange(r) - 1)), CharacterSet.whitespacesAndNewlines.contains(c) {
                r.length -= 1
            }
            return r.length > 0 ? r : nil
        }
    }

    /// The first sentence of four words or more that passes `test`, else the first that does (memory.ts quote).
    static func quote(_ text: String, _ test: (String) -> Bool) -> NSRange? {
        let ns = text as NSString
        let hits = sentences(text).filter { test(ns.substring(with: $0)) }
        return hits.first { ns.substring(with: $0).split(separator: " ").count >= 4 } ?? hits.first
    }

    static func sentence(containing r: NSRange, in text: String) -> NSRange? {
        sentences(text).first { NSIntersectionRange($0, r).length > 0 }
    }

    // MARK: People (memory.ts personCue, isPerson, personMentions)

    private static func words(_ s: String) -> Set<String> { Set(s.split(separator: " ").map(String.init)) }
    static let personBefore = words("hugged hug kissed married")
    static let personAfter = words("thinks thought laughed laughs cried cries smiled hugged")
    static let talksBefore = words("told tell telling asked ask asking texted text texting messaged thanked")
    static let talksAfter = words("said says told tells asked asks called calls texted texts messaged came comes helped")
    static let timeWith = words("dinner lunch breakfast brunch coffee drinks tea walk date argued argument fight row laughed cried")
    static let talkWith = words("chat talk talked time")
    static let roles = words("therapist coach colleague coworker flatmate roommate housemate neighbour neighbor cousin aunt uncle niece nephew nan gran granny grandad mate bestie ex fiance fiancé fiancee fiancée")
    static let pronouns: Set = ["he", "she", "he's", "she's", "he'd", "she'd", "he'll", "she'll"]
    static let thingBefore = words("in on at into onto via using near across around visited visiting watched watching watch flew moved installed downloaded ordered")
    static let going = words("went go goes going gone drove drive driving flew fly walked walk ran popped nipped headed back moved trip travelled traveled")
    static let thingAfter = words("call calls show shows series episode episodes app account code script office trip flight station airport ticket tickets order orders refund delivery parcel package subscription feed reel reels post posts playlist support chat channel thread board page site store friends team teams people lot crew gang folks mates colleagues clients customers branch bank energy")
    static let business = words("bill bills billing refund contract broadband tariff meter invoice overdraft mortgage subscription parcel delivery helpline router wifi signal complaint payment payments fraud account card loan claim policy engineer prescription booking")
    static let notNames = words("saro i he she they it we you someone somebody everyone everybody nobody anyone anybody everything something nothing this that these those who what which one people doctor therapist nurse teacher police landlord neighbour neighbor christmas xmas easter diwali eid hanukkah chanukah ramadan thanksgiving halloween passover hogmanay spring summer autumn winter")
    static let brands = words("netflix amazon prime jira slack zoom teams google gmail youtube apple iphone ipad mac android samsung microsoft outlook excel spotify instagram insta tiktok facebook whatsapp messenger twitter linkedin reddit discord snapchat pinterest telegram notion figma github gitlab trello asana canva dropbox chatgpt openai uber lyft deliveroo doordash airbnb paypal venmo ebay etsy ikea tesco sainsbury sainsburys asda aldi lidl waitrose costco walmart target starbucks costa pret mcdonalds disney hbo hulu xbox playstation nintendo steam tinder hinge bumble duolingo strava peloton fitbit kindle audible alexa siri bbc nhs headspace octopus monzo barclays natwest lloyds hsbc santander halifax nationwide revolut vodafone eurostar trainline ryanair easyjet boots argos")
    /// onboarding/extract.ts RELATIONS.
    static let relations = words("mum mom mother dad father parents partner wife husband boyfriend girlfriend son daughter kid kids brother sister boss manager team friend friends grandma grandpa")

    static func isRelation(_ word: String) -> Bool { relations.contains(word.lowercased()) }

    enum Cue { case person, talks, thing }

    private static func breaks(_ s: String) -> Bool { s.contains { ".!?\n".contains($0) } }
    private static func stripPossessive(_ w: String) -> String { w.replacingOccurrences(of: #"['’]s$"#, with: "", options: .regularExpression) }
    private static func nameLike(_ w: String) -> Bool {
        let s = Array(w.unicodeScalars.prefix(2))
        return s.count == 2 && ("A"..."Z").contains(s[0]) && ("a"..."z").contains(s[1])
    }

    /// What one mention says: a person, `talks` (what companies do too), a thing, or nothing.
    static func personCue(_ text: String, _ tokens: [Token], _ i: Int) -> Cue? {
        let ns = text as NSString
        func gap(_ a: Int, _ b: Int) -> String {
            a >= 0 && b < tokens.count ? ns.substring(with: NSRange(location: tokens[a].end, length: tokens[b].start - tokens[a].end)) : "."
        }
        func lower(_ k: Int) -> String { k >= 0 && k < tokens.count ? tokens[k].lower : "" }
        let prev = breaks(gap(i - 1, i)) ? "" : lower(i - 1)
        let prev2 = !prev.isEmpty && !breaks(gap(i - 2, i - 1)) ? lower(i - 2) : ""
        let next = gap(i, i + 1).contains { !$0.isWhitespace && $0 != "'" && $0 != "’" } ? "" : lower(i + 1)
        let possessive = tokens[i].text.range(of: #"['’]s$"#, options: .regularExpression) != nil
        let sentence = (1..<7).compactMap { k in i + k < tokens.count && !breaks(gap(i, i + k)) ? tokens[i + k] : nil }
        let thing = (thingBefore.contains(prev) && !possessive) || (prev == "to" && going.contains(prev2) && !possessive)
            || thingAfter.contains(next) || sentence.contains { business.contains($0.lower) }
        if thing { return .thing }
        let nextWord = lower(i + 1)
        // "Sam, she…" is a person; "Called Sam. She…" may be someone else, so it counts as much as "told Sam".
        if gap(i, i + 1).allSatisfy({ $0.isWhitespace || $0 == "," }), pronouns.contains(nextWord) { return .person }
        if personBefore.contains(prev) || isRelation(prev) || roles.contains(prev) || (prev == "with" && timeWith.contains(prev2))
            || (prev == "and" && prev2 == "me") || personAfter.contains(next) || (next == "and" && lower(i + 2) == "i") {
            return .person
        }
        let pronounAfterBreak = [".", "!", "?"].contains(gap(i, i + 1).trimmingCharacters(in: .whitespacesAndNewlines)) && pronouns.contains(nextWord)
        return talksBefore.contains(prev) || talksAfter.contains(next) || (prev == "with" && talkWith.contains(prev2)) || pronounAfterBreak
            ? .talks : nil
    }

    /// A name is a person on a person cue seen at least as often as a thing cue, or on talking cues with no thing cue at all.
    static func isPerson(_ kinds: [MemoryObservation.Kind]) -> Bool {
        let person = kinds.filter { $0 == .person }.count, talks = kinds.filter { $0 == .personTalks }.count
        let things = kinds.filter { $0 == .personThing }.count
        return (person > 0 && person >= things) || (talks > 0 && things == 0)
    }

    struct Mention {
        let lower: String
        let display: String
        let cue: Cue?
        let range: NSRange
    }

    /// The capitalised words that could be people, with how person-like each mention reads.
    static func personMentions(_ text: String) -> [Mention] {
        let ns = text as NSString
        let tokens = Heuristics.tokenize(text)
        let mid = Set(Heuristics.analyzeText(text).names)
        func onlySpace(_ a: Int, _ b: Int) -> Bool {
            let g = ns.substring(with: NSRange(location: tokens[a].end, length: tokens[b].start - tokens[a].end))
            return !g.isEmpty && g.allSatisfy(\.isWhitespace)
        }
        func capitalNext(_ a: Int, _ b: Int) -> Bool {
            a >= 0 && b < tokens.count && mid.contains(tokens[a].text) && mid.contains(tokens[b].text) && onlySpace(a, b)
        }
        var out: [Mention] = []
        for (i, t) in tokens.enumerated() where nameLike(t.text) {
            let display = stripPossessive(t.text)
            let lower = display.lowercased()
            guard display.count >= 2, !notNames.contains(lower), !brands.contains(lower), !isRelation(lower),
                  !capitalNext(i - 1, i), !capitalNext(i, i + 1) else { continue }
            let opening = i == 0 || breaks(ns.substring(with: NSRange(location: tokens[i - 1].end, length: t.start - tokens[i - 1].end)))
            let next = i + 1 < tokens.count ? tokens[i + 1].lower : nil
            // At a sentence start every word is capitalised, so only a verb that people do makes it a name ("Sam texted me").
            if opening {
                guard let next, personAfter.contains(next) || talksAfter.contains(next) || (next == "and" && i + 2 < tokens.count && tokens[i + 2].lower == "i")
                else { continue }
            } else if !mid.contains(t.text) { continue }
            let asWord = Heuristics.analyzeText(lower)
            guard asWord.themes.isEmpty, asWord.moods.isEmpty else { continue }
            out.append(Mention(lower: lower, display: display, cue: personCue(text, tokens, i),
                               range: NSRange(location: t.start, length: (display as NSString).length)))
        }
        return out
    }

    // MARK: NLTagger names

    struct Tagged {
        let tag: NLTag
        let range: NSRange
    }

    static func taggedNames(_ text: String) -> [Tagged] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var out: [Tagged] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, r in
            if let tag, [.personalName, .placeName, .organizationName].contains(tag) { out.append(Tagged(tag: tag, range: NSRange(r, in: text))) }
            return true
        }
        return out
    }

    // MARK: Intentions

    /// "Tomorrow I" takes the lead after it too ("Tomorrow I will book…" is "book…"), so one plan keeps one key.
    private static let intentionLead = try! NSRegularExpression(pattern: """
        (?i)\\b(?:(?:tomorrow\\s+)?(?:i\\s+(?:(?:really|just|still|also|finally)\\s+)?(?:want|need|have|plan|hope|mean|intend)\\s+to|\
        i\\s+(?:will|should|must)|i['’]ll|i['’]m\\s+(?:going|planning|trying)\\s+to|i\\s+am\\s+(?:going|planning|trying)\\s+to)|\
        tomorrow\\s+i)\\s+
        """)
    private static let dangling = words("a an the to of for with at in on by from into onto about until till than as because if when while and but or so my our your their its very really just")

    /// What the person says they mean to do, in their own words: the clause after "I want to", "I'll", "tomorrow I"…,
    /// at most six words. Nil when nothing is left that says anything.
    static func intention(in sentence: String) -> (label: String, range: NSRange)? {
        let ns = sentence as NSString
        guard let m = intentionLead.firstMatch(in: sentence, range: NSRange(location: 0, length: ns.length)) else { return nil }
        // "If I have to sit through one more meeting…" is a condition, not a plan.
        let before = Heuristics.tokenize(ns.substring(to: m.range.location)).last?.lower
        if let before, ["if", "unless", "when", "whenever"].contains(before) { return nil }
        let rest = ns.substring(from: NSMaxRange(m.range))
        let clause = rest.prefix { !",;:.!?\n—–()".contains($0) }
        var tokens = Heuristics.tokenize(String(clause))
        if let cut = tokens.firstIndex(where: { ["and", "but", "because", "so", "if", "when", "before", "after"].contains($0.lower) }) {
            tokens = Array(tokens[..<cut])
        }
        tokens = Array(tokens.prefix(6))
        while let last = tokens.last, dangling.contains(last.lower) { tokens.removeLast() }
        guard let first = tokens.first, let last = tokens.last, !tokens.allSatisfy({ Lexicon.stop.contains($0.lower) }) else { return nil }
        let r = NSRange(location: NSMaxRange(m.range) + first.start, length: last.end - first.start)
        return (ns.substring(with: r), r)
    }

    // MARK: One entry

    /// Everything the heuristic twin reads from one entry's text. `mood` is the entry reading's mood (one lineage per
    /// entry, DR-13), and `moodQuote` the verbatim phrase it picked, used when no sentence names the feeling.
    public static func observe(entryId: String, field: String, text: String, localDay: String, mood: Mood? = nil,
                               moodQuote: Candidate? = nil) -> [MemoryObservation] {
        let ns = text as NSString
        let hash = sha256(text)
        func row(_ kind: MemoryObservation.Kind, _ key: String, _ label: String, _ r: NSRange) -> MemoryObservation {
            MemoryObservation(entryId: entryId, kind: kind, key: key, label: label, quote: ns.substring(with: r), field: field,
                        spanStart: r.location, spanEnd: NSMaxRange(r), textSha256: hash, localDay: localDay)
        }
        var out: [MemoryObservation] = []
        let tagged = taggedNames(text)

        // People: every mention keeps its cue; NLTagger's personal name is one more, weak, signal (like "told Sam").
        let mentions = personMentions(text)
        for m in mentions {
            guard let s = sentence(containing: m.range, in: text) else { continue }
            let nl = tagged.contains { $0.tag == .personalName && NSIntersectionRange($0.range, m.range).length > 0 }
            let kind: MemoryObservation.Kind = switch m.cue {
            case .person: .person
            case .thing: .personThing
            case .talks: .personTalks
            case nil: nl ? .personTalks : .personName
            }
            out.append(row(kind, "person:\(m.lower)", m.display, s))
        }

        // Places and organisations, as NLTagger reads them; brands, and names read as people here, aren't places.
        let people = Set(mentions.filter { $0.cue == .person || $0.cue == .talks }.map(\.lower))
        for t in tagged where t.tag != .personalName {
            let name = ns.substring(with: t.range)
            let lower = name.lowercased()
            guard name.count >= 2, name.first?.isUppercase == true, !brands.contains(lower), !notNames.contains(lower),
                  !people.contains(lower), let s = sentence(containing: t.range, in: text) else { continue }
            out.append(row(t.tag == .placeName ? .place : .org, "\(t.tag == .placeName ? "place" : "org"):\(lower)", name, s))
        }
        out += themes(entryId: entryId, field: field, text: text, localDay: localDay)
        out += intentions(entryId: entryId, field: field, text: text, localDay: localDay)
        if let e = emotion(entryId: entryId, field: field, text: text, localDay: localDay, mood: mood, moodQuote: moodQuote) { out.append(e) }
        return dedupe(out)
    }

    static func themes(entryId: String, field: String, text: String, localDay: String) -> [MemoryObservation] {
        let ns = text as NSString
        return Heuristics.analyzeText(text).themes.compactMap { theme in
            quote(text, { Heuristics.analyzeText($0).themes.contains(theme) }).map { r in
                MemoryObservation(entryId: entryId, kind: .theme, key: "theme:\(theme.rawValue)", label: theme.rawValue, quote: ns.substring(with: r),
                            field: field, spanStart: r.location, spanEnd: NSMaxRange(r), textSha256: sha256(text), localDay: localDay)
            }
        }
    }

    static func intentions(entryId: String, field: String, text: String, localDay: String) -> [MemoryObservation] {
        let ns = text as NSString
        return sentences(text).compactMap { s in
            intention(in: ns.substring(with: s)).map { i in
                MemoryObservation(entryId: entryId, kind: .intention, key: "intent:\(i.label.lowercased())", label: i.label,
                            quote: ns.substring(with: s), field: field, spanStart: s.location, spanEnd: NSMaxRange(s),
                            textSha256: sha256(text), localDay: localDay)
            }
        }
    }

    static func emotion(entryId: String, field: String, text: String, localDay: String, mood: Mood?, moodQuote: Candidate?) -> MemoryObservation? {
        guard let mood = mood ?? Heuristics.analyzeText(text).moods.first, mood != .neutral else { return nil }
        let ns = text as NSString
        let r = quote(text, { Heuristics.analyzeText($0).moods.contains(mood) })
            ?? moodQuote.map { NSRange(location: $0.utf16From, length: $0.utf16To - $0.utf16From) }
        guard let r, NSMaxRange(r) <= ns.length else { return nil }
        return MemoryObservation(entryId: entryId, kind: .emotion, key: "mood:\(mood.rawValue.lowercased())", label: mood.rawValue,
                           quote: ns.substring(with: r), field: field, spanStart: r.location, spanEnd: NSMaxRange(r),
                           textSha256: sha256(text), localDay: localDay)
    }

    /// One row per key, kind and sentence, and nothing whose words would trip the phrase gate (SR-08): a sentence can
    /// lose the guard word a whole entry passed on.
    static func dedupe(_ rows: [MemoryObservation]) -> [MemoryObservation] {
        var seen = Set<String>()
        return rows.filter { o in
            !SafetyGate.phraseHit(o.quote ?? "") && !SafetyGate.phraseHit(o.label)
                && seen.insert("\(o.key)|\(o.kind.rawValue)|\(o.spanStart ?? -1)").inserted
        }
    }

    // MARK: About you (memory.ts starterMemory)

    static let toneWord: [Tone: String] = [.gentle: "gentle", .direct: "direct", .neutral: "plain", .contemplative: "thoughtful"]
    private static let you: [String: String] = ["myself": "yourself", "my": "your", "me": "you", "mine": "yours", "i'm": "you’re", "i": "you"]

    /// Their words said back to them (memory.ts sayBack): "my" is "your", "kinder to me" is "kinder to yourself".
    public static func sayBack(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"(?i)\b((?:kind|kinder|nice|nicer|gentle|gentler|easy|easier|hard|harder|soft|softer|honest|patient|good|better)\s+(?:to|on|with)|(?:feel|be|more)\s+like|(?:time|space|room)\s+for)\s+me\b"#,
                                       with: "$1 myself", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bme[\s-]time\b"#, with: "time for myself", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bour(s?)\b"#, with: "your$1", options: .regularExpression)
        t = toYou(t)
        return t.replacingOccurrences(of: #"(?i)\byou am\b"#, with: "you are", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\byou was\b"#, with: "you were", options: .regularExpression)
    }

    static func toYou(_ s: String) -> String {
        let re = try! NSRegularExpression(pattern: #"(?i)\b(?:myself|mine|my|me|i['’]m|i)\b"#)
        let ns = s as NSString
        var out = ""
        var at = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: at, length: m.range.location - at))
            let w = ns.substring(with: m.range)
            out += you[w.lowercased().replacingOccurrences(of: "’", with: "'")] ?? w
            at = NSMaxRange(m.range)
        }
        return out + ns.substring(from: at)
    }

    private static func capitalize(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
    private static func isAre(_ noun: String) -> String { noun.range(of: #"[^s]s$"#, options: [.regularExpression, .caseInsensitive]) != nil ? "are" : "is" }
    private static func titleCase(_ s: String) -> String {
        s.contains(where: \.isUppercase) ? s : s.split(separator: " ").map { capitalize(String($0)) }.joined(separator: " ")
    }

    /// "21:30" as the web's clock: "9:30 pm".
    static func clock(_ hhmm: String) -> String? {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else { return nil }
        return "\(p[0] % 12 == 0 ? 12 : p[0] % 12):\(String(format: "%02d", p[1])) \(p[0] < 12 ? "am" : "pm")"
    }

    private static let nameLead = try! NSRegularExpression(pattern: #"(?i)^\s*(?:im|שמי|קוראים לי|אני|اسمي|أنا|me llamo|mi nombre es|soy|je m['’]appelle|je suis|moi c['’]est|ich heiße|ich bin|mein name ist|mi chiamo|meu nome é|eu sou|меня зовут|मेरा नाम)(?=[\s,.!]|$)"#)

    /// The name itself: the extractor's pick, or the word after a lead it doesn't know ("im sam", "שמי נועה").
    static func nameOf(_ value: String, answer: String?) -> String? {
        let ns = value as NSString
        guard let lead = nameLead.firstMatch(in: value, range: NSRange(location: 0, length: ns.length)) else { return value }
        let from = answer.flatMap { a in a.range(of: value).map { String(a[$0.lowerBound...]) } } ?? value
        let after = String(from.dropFirst((ns.substring(with: lead.range) as String).count))
        return after.firstMatch(of: /^[\s,:\-]*([\p{L}\p{M}]+(?:['’\-][\p{L}\p{M}]+)*)/).map { String($0.1) }
    }

    private static let goalLead = try! NSRegularExpression(pattern: #"(?i)(?:\b(?:i(?:['’]m|\s+am)|we(?:['’]re|\s+are))\s+(?:(?:just|really|also|still|honestly|genuinely|actually|finally|so)\s+)*(?:trying|going|hoping|planning)|\b(?:i|we)(?:['’]d|\s+would)\s+(?:(?:just|really|also|still|honestly|genuinely|actually|finally|so)\s+)*(?:like|love)|\b(?:i|we)\s+(?:(?:just|really|also|still|honestly|genuinely|actually|finally|so)\s+)*(?:(need|have)|want|hope|plan)|\b(?:trying|hoping)|^\s*)\s*to\s+"#)
    private static let describes = try! NSRegularExpression(pattern: #"^(?:calm|kind|kinder|present|patient|happy|healthy|fit|strong|brave|open|honest|free|sure|tidy|steady|ready|easy|chill|gentle|humble|loyal|aware|awake|alive|sober|tired|lonely|friendly|lovely|busy|lazy|angry|grumpy|sleepy|chatty|funny|loving|caring|understanding|forgiving|outgoing|easygoing|myself|like)$|^.{2,}(?:ous|ful|less|ish|[^e]ed)$|^.{3,}(?:ive|ent|ant|able|ible|ial|ical|nal|ual|istic|etic|atic|ntic)$"#)
    private static let openingVerb = words("be feel get become stay stop start worry sleep eat drink spend move read write walk run exercise stress care think overthink talk listen laugh smile complain travel cook give take say see go do make find learn practise practice save trust enjoy")
    private static let filler = words("lol lmao haha hahaha tbh honestly please ok okay idk")
    private static let unfinished = words("who whom whose which that where")
    private static let empty = words("be able get have do feel go to")

    /// A goal pick said back as one line: "You want to be kinder to yourself.", or nil when it can't be a whole sentence.
    // ponytail: the short form of memory.ts goalPhrase (lead, more/less, opening verb, clause end); onboarding's
    // SayBack.goalPhrase is the full grammar, and replaces this when it merges.
    static func goalLine(_ span: String, answer: String?) -> String? {
        var text = span.trimmingCharacters(in: .whitespaces)
        if let a = answer, let r = a.range(of: span) {
            text += a[r.upperBound...].prefix { !",.;:!?\n".contains($0) }
        }
        let ns = text as NSString
        var need = false
        var head = ""
        if let m = goalLead.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.range.location == 0, m.range.length > 0,
           !ns.substring(with: m.range).trimmingCharacters(in: .whitespaces).isEmpty {
            need = m.range(at: 1).location != NSNotFound
            head = "to "
            text = ns.substring(from: NSMaxRange(m.range))
        }
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if let i = tokens.firstIndex(where: { ["and", "but"].contains($0.lowercased()) }), i > 0 { tokens = Array(tokens[..<i]) }
        if head.isEmpty, let first = tokens.first?.lowercased() {
            if ["more", "less", "fewer"].contains(first) {
                guard tokens.count > 1 else { return nil }
                let second = tokens[1].lowercased().trimmingCharacters(in: .punctuationCharacters)
                if describes.firstMatch(in: second, range: NSRange(location: 0, length: (second as NSString).length)) != nil, first != "fewer" { head = "to be " }
            } else if openingVerb.contains(first) { head = "to " }
        }
        var said = sayBack(tokens.joined(separator: " ").replacingOccurrences(of: #"[.!?]+$"#, with: "", options: .regularExpression))
            .split(separator: " ").map(String.init)
        while let last = said.last?.lowercased(), filler.contains(last) || dangling.contains(last) { said.removeLast() }
        guard let last = said.last?.lowercased(), !unfinished.contains(last), !said.allSatisfy({ empty.contains($0.lowercased()) }) else { return nil }
        if said.count >= 1, ["more", "less"].contains(last), said.dropLast().last.map({ ["be", "become", "get", "stay"].contains($0.lowercased()) }) ?? true { return nil }
        let goal = said.joined(separator: " ")
        return MemoryList.clip("You \(need ? "need" : "want") \(head)\(goal.prefix(1).lowercased() + goal.dropFirst()).", MemoryList.maxChars)
    }

    /// One onboarding pick as a memory line, from what the extractor took it to mean. A theme, mood or named person shares
    /// its key with the one learned from entries, so the two never both show.
    static func starterLine(_ pick: Pick, answer: String?) -> (key: String, text: String)? {
        let words = pick.text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"[.!?]+$"#, with: "", options: .regularExpression)
        let value = pick.value.trimmingCharacters(in: .whitespaces).isEmpty ? words : pick.value.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        let lower = value.lowercased()
        switch pick.kind {
        case .name:
            return nameOf(value, answer: answer).map { ("starter:name", "You go by \(titleCase($0)).") }
        case .person:
            if isRelation(lower) { return ("starter:person:\(lower)", "Your \(lower) \(["parents", "kids", "friends"].contains(lower) ? "matter" : "matters") to you.") }
            let relation = Heuristics.tokenize(words).first { isRelation($0.lower) }?.lower
            return ("person:\(lower)", "\(relation.map { "Your \($0) " } ?? "")\(value) matters to you.")
        case .theme:
            if let t = Theme(rawValue: lower) { return ("theme:\(t.rawValue)", "\(capitalize(t.rawValue)) \(isAre(t.rawValue)) on your mind.") }
            if let m = Mood.allCases.first(where: { $0.rawValue.lowercased() == lower }) {
                return ("mood:\(m.rawValue.lowercased())", "You’ve been feeling \(m.rawValue.lowercased()).")
            }
            return ("starter:theme:\(lower)", "\(capitalize(toYou(words))) \(isAre(words)) on your mind.")
        case .time:
            let when = clock(value).map { "around \($0)" } ?? (value == "weekends" ? "at weekends" : value == "commute" ? "on your commute" : nil)
            return when.map { ("starter:time", "You like to reflect \($0).") }
        case .goal:
            let said = goalLead.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length))
                .flatMap { $0.range.location == 0 ? (value as NSString).substring(from: NSMaxRange($0.range)) : nil } ?? value
            return goalLine(value, answer: answer).map { ("starter:goal:\(toYou(said.replacingOccurrences(of: #"[.!?]+$"#, with: "", options: .regularExpression)).lowercased())", $0) }
        case .tone:
            return Tone(rawValue: lower).flatMap { toneWord[$0] }.map { ("starter:tone", "You’d like Saro to be \($0) with you.") }
        }
    }
}
