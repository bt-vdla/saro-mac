import Foundation
import NaturalLanguage

/// About you (extract.ts): what Saro picks up from an answer, as exact UTF-16 spans, so a highlight maps onto the
/// answer's NSTextView ranges and is exactly what gets stored. Pure, local and deterministic: it runs on every keystroke.
public enum Onboarding {
    /// The kinds each question may pick up.
    public static let questionKinds: [Int: [Pick.Kind]] = [1: [.name], 2: [.person, .theme, .goal], 3: [.time, .person],
                                                           4: [.goal, .theme, .person], 5: [.tone]]
    /// On a tie in length, the earlier kind wins.
    static let priority: [Pick.Kind] = [.name, .person, .time, .goal, .tone, .theme]

    static let relations = Set("mum mom mother dad father parents partner wife husband boyfriend girlfriend son daughter kid kids brother sister boss manager team friend friends grandma grandpa".split(separator: " ").map(String.init))
    public static func isRelation(_ word: String) -> Bool { relations.contains(word.lowercased()) }

    private static let determiners: Set = ["the", "my", "our"]
    private static let owners: Set = ["my", "our"]

    private struct Span {
        var kind: Pick.Kind, text: String, value: String, start: Int, end: Int
    }

    private static func span(_ ns: NSString, _ kind: Pick.Kind, _ start: Int, _ end: Int, _ value: String? = nil) -> Span {
        let text = ns.substring(with: NSRange(location: start, length: end - start))
        return Span(kind: kind, text: text, value: value ?? text, start: start, end: end)
    }

    private static func gap(_ ns: NSString, _ from: Int, _ to: Int) -> String {
        to > from ? ns.substring(with: NSRange(location: from, length: to - from)) : ""
    }

    private static func onlySpace(_ ns: NSString, _ a: Token, _ b: Token) -> Bool {
        let g = gap(ns, a.end, b.start)
        return !g.isEmpty && g.allSatisfy(\.isWhitespace)
    }

    // MARK: Name

    // "Everyone calls me Bee", "I go by Bee", "I'm called Bee" and "my nickname is Bee" name Bee.
    private static let nameLead = Rx(#"^\s*(?:(?:hi|hey|hello)\b[\s,.!-]*)?(?:(?:i['’]m|i am|it['’]s|call me|(?:[a-z'’]+\s+){1,2}call(?:s|ed)?\s+me|i go by|(?:my\s+)?(?:nick)?name(?:['’]s|\s+is)|called|named|just)\b[\s,]*)*"#, .caseInsensitive)
    // "Sam here" is Sam.
    private static let notName: Set = ["and", "but", "or", "here", "lol", "haha", "thanks", "please", "btw", "too", "x"]
    // "I'm not sure" or "I don't know" gives no name at all.
    private static let notAName = Set("i not no nope unsure dunno idk don't don’t whatever anything nothing nobody none sure maybe".split(separator: " ").map(String.init))
    // Letters in any script, so "محمد" or "Zoë" is a name too.
    private static let nameWord = Rx(#"[\p{L}\p{M}]+(?:['’-][\p{L}\p{M}]+)*"#)

    private static func nameSpans(_ ns: NSString) -> [Span] {
        let text = ns as String
        let lead = nameLead.first(text)?.range.length ?? 0
        guard let first = nameWord.first(text, from: lead), !notAName.contains(first.text.lowercased()) else { return [] }
        let firstEnd = NSMaxRange(first.range)
        let start = first.range.location
        if let second = nameWord.first(text, from: firstEnd) {
            let secondEnd = NSMaxRange(second.range)
            let between = gap(ns, firstEnd, second.range.location)
            if !between.isEmpty, between.allSatisfy(\.isWhitespace), !notName.contains(second.text.lowercased()), secondEnd - start <= 30 {
                return [span(ns, .name, start, secondEnd)]
            }
        }
        return [span(ns, .name, start, min(firstEnd, start + 30))]
    }

    // MARK: Person

    // analyzeText skips sentence starts, so a name standing alone on Q2 ("Maya." or "Mark and the launch") is checked
    // here: a capitalised one-word fragment that isn't a word Saro already knows.
    // ponytail: no dictionary, so an unlisted noun standing alone ("Rugby.") reads as a person and the ledger lets them
    // leave it out; NLTagger's personal names (below) and the lists take the common cases.
    private static let commonWords = Set((
        "mostly usually lately sometimes always often anyway whatever life school uni college exam exams wedding baby pregnancy dog dogs cat cats puppy pets house home flat apartment move " +
        "taxes christmas travel trip holiday holidays vacation grief loss food diet weight body gym weather politics news war " +
        "climate summer winter spring autumn divorce dating love sex surgery doctor hospital illness car church faith god music " +
        "art coffee alcohol phone internet interview promotion business startup project help stuff things everything nothing " +
        "rugby football soccer cricket tennis golf hockey basketball running " +
        "paris london tokyo berlin madrid rome dublin toronto chicago boston seattle dubai mumbai delhi bangalore singapore " +
        "lagos nairobi manila seoul beijing shanghai lisbon amsterdam barcelona glasgow manchester edinburgh bristol leeds " +
        "india china japan france germany spain italy canada mexico brazil america england scotland wales ireland " +
        "australia europe africa asia ukraine russia gaza israel " +
        "netflix youtube instagram tiktok twitter facebook reddit spotify amazon google apple uber linkedin whatsapp slack zoom " +
        "chatgpt crypto bitcoin " +
        "chemo chemotherapy cancer covid autism therapy rehab menopause insomnia migraines diabetes dementia"
    ).split(separator: " ").map(String.init))
    private static let nounEnding = Rx(#"(?:ing|tion|sion|ness|ment|ism|ship|hood|ics|ies|ity)$"#)
    private static let calendar = Rx(#"^(?:(?:mon|tues|wednes|thurs|fri|satur|sun)days?|january|february|march|april|may|june|july|august|september|october|november|december)$"#)
    private static let capitalised = Rx(#"^[A-Z][a-z]"#)

    private static func loneName(_ ns: NSString, _ tokens: [Token], _ i: Int) -> Bool {
        let t = tokens[i]
        let opens = i == 0 || gap(ns, tokens[i - 1].end, t.start).contains { ".!?\n".contains($0) }
        let closes = i + 1 == tokens.count || gap(ns, t.end, tokens[i + 1].start).contains { ".,;!?\n".contains($0) }
            || tokens[i + 1].lower == "and"
        // Past 14 letters it's a word, not a first name.
        guard opens, closes, t.text.utf16.count <= 14, capitalised.test(t.text), !relations.contains(t.lower) else { return false }
        if commonWords.contains(t.lower) || nounEnding.test(t.lower) || calendar.test(t.lower) || !timeSpans(t.text as NSString).isEmpty { return false }
        let signals = Heuristics.analyzeText(t.text)
        let keyword = t.lower.utf16.count >= 3 && !Lexicon.stop.contains(t.lower) && !t.lower.allSatisfy(\.isNumber)
        return keyword && signals.themes.isEmpty && signals.moods.isEmpty
    }

    /// Personal names NLTagger finds, on top of the capitalised-word floor: names in any script or left lowercase.
    static func taggedNames(_ text: String) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var out: Set<String> = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if tag == .personalName { out.formUnion(text[range].split(whereSeparator: \.isWhitespace).map(String.init)) }
            return true
        }
        return out
    }

    private static func personSpans(_ ns: NSString, _ tokens: [Token], ownName: String, q: Int) -> [Span] {
        let text = ns as String
        let own = Set(ownName.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
        let known = { (n: String) in !own.contains(n.lowercased()) && !isRelation(n) && Heuristics.analyzeText(n).themes.isEmpty }
        // ponytail: NLTagger guesses, so a word it tags must also not be a feeling or a word Saro knows as something else.
        let tagged = taggedNames(text).filter {
            (capitalised.test($0) || !$0.unicodeScalars.allSatisfy(\.isASCII)) && known($0)
                && Heuristics.analyzeText($0).moods.isEmpty && !commonWords.contains($0.lowercased())
        }
        let names = Set(Heuristics.analyzeText(text).names.filter(known) + tagged)
        var out: [Span] = []
        var used: Set<Int> = []
        for (i, t) in tokens.enumerated() where !used.contains(i) {
            let prev = i > 0 ? tokens[i - 1] : nil
            let next = i + 1 < tokens.count ? tokens[i + 1] : nil
            if relations.contains(t.lower) {
                let start = prev.map { owners.contains($0.lower) && onlySpace(ns, $0, t) } == true ? prev!.start : t.start
                let withName = next.map { names.contains($0.text) && onlySpace(ns, t, $0) } ?? false
                if withName { used.insert(i + 1) }
                out.append(span(ns, .person, start, withName ? next!.end : t.end, withName ? next!.text : t.lower))
            } else if names.contains(t.text) || (q == 2 && !own.contains(t.lower) && loneName(ns, tokens, i)) {
                out.append(span(ns, .person, t.start, t.end))
            }
        }
        return out
    }

    // MARK: Theme / worry

    private static let spend = Rx(#"^spen(?:d|ds|ding|t)$"#)

    private static func themeSpans(_ ns: NSString, _ tokens: [Token], q: Int) -> [Span] {
        let focus = Set(Heuristics.analyzeText(ns as String).focus)
        var out: [Span] = []
        for (i, t) in tokens.enumerated() where focus.contains(t.lower) {
            // "Spend more time with my kids" is time, not money.
            if spend.test(t.lower), tokens.dropFirst(i + 1).prefix(3).contains(where: { $0.lower == "time" }) { continue }
            let signals = Heuristics.analyzeText(t.lower)
            guard let value = signals.themes.first?.rawValue ?? (q == 2 ? signals.moods.first?.rawValue : nil) else { continue }
            let start = i > 0 && determiners.contains(tokens[i - 1].lower) && onlySpace(ns, tokens[i - 1], t) ? tokens[i - 1].start : t.start
            out.append(span(ns, .theme, start, t.end, value))
        }
        return out
    }

    // MARK: Time

    private static let periodTime: [String: String] = [
        "morning": "08:00", "lunch": "12:30", "afternoon": "15:00", "evening": "19:00", "night": "22:00", "tonight": "22:00",
        "bedtime": "22:00", "midnight": "00:00", "weekend": "weekends", "commute": "commute", "early morning": "06:30",
        "late evening": "21:30", "late night": "23:00",
        // "Late, usually." A bare "late" on the quiet-time question means late at night.
        "late": "23:00",
        "after work": "18:30", "before work": "07:30", "after dinner": "20:30", "before dinner": "18:30", "after bed": "22:00",
        "before bed": "22:00",
    ]
    private static let period = Rx(#"\b(?:(early|late)\s+(?:(?:at|in\s+the)\s+)?)?(morning|afternoon|evening|night|tonight|bedtime|midnight|lunch|weekend|commute)s?\b"#, .caseInsensitive)
    private static let relative = Rx(#"\b(after|before)\s+(work|bed|dinner)\b"#, .caseInsensitive)
    // After a lead word ("around 10") any hour is a time; on its own only one that can't be anything else ("10:30",
    // "10pm", "10ish", or "11" standing alone, as in "Late. 11."), so "2 kids" isn't. A counted noun makes it a count.
    private static let clock = Rx(#"(?:\b(around|about|at|by|after|before|maybe|roughly|between|until|till|past)\s+)?\b(\d{1,2})(?:[:.](\d{2}))?(?!\d)(?:\s?([ap])\.?m\b\.?|(ish|\s?o['’]clock)\b)?"#, .caseInsensitive)
    private static let counted = Rx(#"^\s+(?:minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?|times?|nights?|people|children|child|babies|jobs?|shifts?|meetings?)\b"#, .caseInsensitive)
    private static let nextWord = Rx(#"^\s+([a-z]+)"#, .caseInsensitive)
    private static let fragmentStart = Rx(#"(?:^|[.!?;,\n]|\b(?:usually|mostly|normally|probably))\s*\z"#, .caseInsensitive)
    private static let fragmentEnd = Rx(#"^\s*(?:[.!?;,\n]|\z)"#)
    private static let late = Rx(#"\blate\b"#, .caseInsensitive)
    private static let lateNegated = Rx(#"(?:\b(?:never|not|no)|n['’]t)\s+\z"#, .caseInsensitive)
    private static let morningWords = Rx(#"\bam\b|morning"#, .caseInsensitive)
    private static let middayWords = Rx(#"\b(?:noon|midday|lunch)"#, .caseInsensitive)

    private static func clockValue(_ text: String, hour: Int, minute: Int, meridiem: String?) -> String? {
        guard hour <= 23, minute <= 59 else { return nil }
        var h = hour
        if let meridiem { h = hour % 12 + (meridiem.lowercased() == "p" ? 12 : 0) }
        // A bare hour is the evening's: "at 10" is 22:00 and "at 12" midnight, unless the words say morning or midday.
        else if (1...11).contains(hour), !morningWords.test(text) { h = hour + 12 }
        else if hour == 12, !middayWords.test(text) { h = 0 }
        return String(format: "%02d:%02d", h, minute)
    }

    private static func timeSpans(_ ns: NSString) -> [Span] {
        let text = ns as String
        var out: [Span] = []
        func each(_ rx: Rx, _ valueOf: (Rx.Match) -> String?) {
            for m in rx.all(text) { if let v = valueOf(m) { out.append(span(ns, .time, m.range.location, NSMaxRange(m.range), v)) } }
        }
        each(period) { m in
            let base = m[2]!.lowercased()
            return m[1].flatMap { periodTime["\($0.lowercased()) \(base)"] } ?? periodTime[base]
        }
        each(relative) { periodTime["\($0[1]!.lowercased()) \($0[2]!.lowercased())"] }
        each(clock) { m in
            let exact = m[3] ?? m[4] ?? m[5]
            let after = ns.substring(from: NSMaxRange(m.range))
            let next = nextWord.first(after)?[1]?.lowercased()
            if exact == nil, counted.test(after) || next.map(relations.contains) == true { return nil }
            let alone = fragmentStart.test(ns.substring(to: m.range.location)) && fragmentEnd.test(after)
            guard m[1] != nil || exact != nil || alone else { return nil }
            return clockValue(text, hour: Int(m[2]!) ?? 99, minute: Int(m[3] ?? "0") ?? 99, meridiem: m[4])
        }
        // "It's never late enough" isn't a time.
        each(late) { lateNegated.test(ns.substring(to: $0.range.location)) ? nil : periodTime["late"] }
        return out
    }

    // MARK: Goal

    private static let goalStart = Rx(#"\b(?:i want to|i['’]d like to|i would like to|trying to|i hope to|i need to|more|less|fewer|stop|start)\b"#, .caseInsensitive)
    private static let goalWords = 8
    private static let dangling = Set("a an the to of for with at in on by from my our your some".split(separator: " ").map(String.init))

    private static func goalSpans(_ ns: NSString, _ tokens: [Token]) -> [Span] {
        var out: [Span] = []
        for m in goalStart.all(ns as String) {
            guard let from = tokens.firstIndex(where: { $0.start >= m.range.location }) else { continue }
            let triggerWords = Heuristics.tokenize(m.text).count
            var last = from
            var i = from + 1
            while i < tokens.count, i - from < goalWords {
                if gap(ns, tokens[i - 1].end, tokens[i].start).contains(where: { ",.;!?".contains($0) }) { break }
                // "More balance between work and life" is one goal.
                let before = tokens[from..<i]
                let between = tokens[i].lower == "and" && before.contains { $0.lower == "between" } && !before.contains { $0.lower == "and" }
                if ["and", "but"].contains(tokens[i].lower), !between { break }
                last = i
                i += 1
            }
            // A goal cut at the word cap shouldn't end on "to" or "a".
            while last > from, dangling.contains(tokens[last].lower) { last -= 1 }
            // "More." alone says nothing; a goal needs at least one word after its trigger.
            if last - from + 1 > triggerWords { out.append(span(ns, .goal, m.range.location, tokens[last].end)) }
        }
        return out
    }

    // MARK: Tone

    private static let toneWords: [String: Tone] = [
        "gentle": .gentle, "gently": .gentle, "soft": .gentle, "kind": .gentle, "warm": .gentle, "patient": .gentle,
        "direct": .direct, "straight": .direct, "blunt": .direct, "honest": .direct, "frank": .direct, "push": .direct, "challenge": .direct,
        "plain": .neutral, "plainly": .neutral, "simple": .neutral, "clear": .neutral, "normal": .neutral,
        "slow": .contemplative, "slowly": .contemplative, "quiet": .contemplative, "deep": .contemplative,
        "thoughtful": .contemplative, "calm": .contemplative,
    ]
    private static let toneNegators: Set = ["not", "no", "never", "don't", "too"]

    // A negator up to 3 words back, within the same clause ("Not too soft. Straight." is straight).
    private static func negated(_ ns: NSString, _ tokens: [Token], _ i: Int) -> Bool {
        for k in stride(from: i - 1, through: max(0, i - 3), by: -1) {
            if gap(ns, tokens[k].end, tokens[k + 1].start).contains(where: { ".,;:!?\n".contains($0) }) { return false }
            if toneNegators.contains(tokens[k].lower) { return true }
        }
        return false
    }

    private static func toneSpans(_ ns: NSString, _ tokens: [Token]) -> [Span] {
        // "kind of blunt" is a hedge, not a request for kindness.
        let hedge = { (k: Int) in tokens[k].lower == "kind" && k + 1 < tokens.count && tokens[k + 1].lower == "of" }
        guard let i = tokens.indices.first(where: { toneWords[tokens[$0].lower] != nil && !hedge($0) && !negated(ns, tokens, $0) })
        else { return [] }
        return [span(ns, .tone, tokens[i].start, tokens[i].end, toneWords[tokens[i].lower]!.rawValue)]
    }

    // MARK: Resolve

    /// Every pick for question `question` (1–5), overlaps resolved (the longer span wins, then name > person > time >
    /// goal > tone > theme), leaving out the person's own name and any pick in `dropped`.
    public static func extract(answer: String, question q: Int, knownName: String = "", dropped: Set<String> = []) -> [Pick] {
        let kinds = questionKinds[q] ?? []
        let ns = answer as NSString
        let tokens = Heuristics.tokenize(answer)
        var spans: [Span] = []
        if kinds.contains(.name) { spans += nameSpans(ns) }
        if kinds.contains(.person) { spans += personSpans(ns, tokens, ownName: knownName, q: q) }
        if kinds.contains(.theme) { spans += themeSpans(ns, tokens, q: q) }
        if kinds.contains(.time) { spans += timeSpans(ns) }
        if kinds.contains(.goal) { spans += goalSpans(ns, tokens) }
        if kinds.contains(.tone) { spans += toneSpans(ns, tokens) }
        let ranked = spans.sorted {
            ($1.end - $1.start, priority.firstIndex(of: $0.kind)!, $0.start) < ($0.end - $0.start, priority.firstIndex(of: $1.kind)!, $1.start)
        }
        var kept: [Span] = []
        for s in ranked where !kept.contains(where: { s.start < $0.end && $0.start < s.end }) { kept.append(s) }
        return kept.sorted { $0.start < $1.start }
            .map { Pick(kind: $0.kind, text: $0.text, value: $0.value, start: $0.start, end: $0.end, q: q) }
            .filter { !dropped.contains($0.dropKey) }
    }

    private static let hhmm = Rx(#"^\d\d:\d\d$"#)
    // A clock time ("around 10:40") is more specific than a period ("late"), and either beats "weekends". Between two of
    // a kind the later one wins: the day goes quiet at its end ("home at 7, then 9:30 is quiet").
    private static func timeRank(_ p: Pick) -> Int { hhmm.test(p.value) ? (p.text.contains(where: \.isNumber) ? 0 : 1) : 2 }
    private static func bySpecificity(_ a: Pick, _ b: Pick) -> Bool { (timeRank(a), -a.q, -a.start) < (timeRank(b), -b.q, -b.start) }

    /// Picks across every answered question, in question order, except that the time picks go most specific first:
    /// First week takes the first time pick as the ritual time.
    public static func picks(answers: [Int: String], dropped: Set<String> = [], knownName: String = "") -> [Pick] {
        let all = (1...5).flatMap { extract(answer: answers[$0] ?? "", question: $0, knownName: knownName, dropped: dropped) }
        var times = all.filter { $0.kind == .time }.sorted(by: bySpecificity)[...]
        return all.map { $0.kind == .time ? times.popFirst() ?? $0 : $0 }
    }

    // MARK: Profile fields

    private static let focusOf: [String: FocusArea] = [
        "sleep": .energy, "health": .energy, "work": .clarity, "money": .steadiness, "nature": .steadiness,
        "Anxious": .steadiness, "Overwhelmed": .steadiness, "Frustrated": .steadiness,
        "family": .relationships, "relationships": .relationships, "creativity": .creative, "purpose": .purpose, "learning": .habits,
    ]
    private static let habitWords = Rx(#"\b(daily|every|routine|start|stop)\b"#, .caseInsensitive)

    /// The first three focus areas the picks point at, in the order they appear.
    public static func focusAreas(_ picks: [Pick]) -> [FocusArea] {
        var out: [FocusArea] = []
        func add(_ f: FocusArea?) { if let f, out.count < 3, !out.contains(f) { out.append(f) } }
        for p in picks {
            switch p.kind {
            case .person: add(.relationships)
            case .theme: add(focusOf[p.value])
            case .goal:
                let s = Heuristics.analyzeText(p.text)
                s.themes.forEach { add(focusOf[$0.rawValue]) }
                s.moods.forEach { add(focusOf[$0.rawValue]) }
                if habitWords.test(p.text) { add(.habits) }
            default: break
            }
        }
        return out
    }

    public static func tone(_ picks: [Pick]) -> Tone? { picks.first { $0.kind == .tone }.flatMap { Tone(rawValue: $0.value) } }

    /// The name Q1 gave, if it gave one.
    public static func name(_ picks: [Pick]) -> String? { picks.first { $0.kind == .name }?.value }

    /// The most specific time they gave ("HH:MM"): a clock time beats a period, then the later one.
    public static func reflectTime(_ picks: [Pick]) -> String? {
        guard let best = picks.filter({ $0.kind == .time }).sorted(by: bySpecificity).first, timeRank(best) < 2 else { return nil }
        return best.value
    }

    public static func isThemeId(_ value: String) -> Bool { Theme(rawValue: value) != nil }

    /// What the chip under an answer calls a kind (HighlightedAnswer.tsx KIND_WORD).
    public static func word(_ kind: Pick.Kind) -> String {
        switch kind {
        case .name: "name"
        case .person: "person"
        case .theme: "on your mind"
        case .time: "time"
        case .goal: "want"
        case .tone: "tone"
        }
    }
}

/// An NSRegularExpression with JavaScript-shaped helpers, over UTF-16 offsets like the web's string indices.
struct Rx: @unchecked Sendable {
    struct Match {
        let range: NSRange
        let text: String
        let groups: [String?]
        /// Capture group `i` (0 is the whole match), nil when it didn't take part.
        subscript(_ i: Int) -> String? { i < groups.count ? groups[i] : nil }
    }

    let re: NSRegularExpression

    init(_ pattern: String, _ options: NSRegularExpression.Options = []) { re = try! NSRegularExpression(pattern: pattern, options: options) }

    private func match(_ r: NSTextCheckingResult, in ns: NSString) -> Match {
        Match(range: r.range, text: ns.substring(with: r.range), groups: (0..<r.numberOfRanges).map {
            let g = r.range(at: $0)
            return g.location == NSNotFound ? nil : ns.substring(with: g)
        })
    }

    func first(_ s: String, from: Int = 0) -> Match? {
        let ns = s as NSString
        guard from <= ns.length else { return nil }
        return re.firstMatch(in: s, range: NSRange(location: from, length: ns.length - from)).map { match($0, in: ns) }
    }

    func all(_ s: String) -> [Match] {
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { match($0, in: ns) }
    }

    func test(_ s: String) -> Bool { first(s) != nil }

    /// Every match replaced by a template ("$1 myself"), as JavaScript's replace with a /g regex.
    func replace(_ s: String, _ template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    /// The first match replaced, as JavaScript's replace with a non-global regex.
    func replaceFirst(_ s: String, _ template: String) -> String {
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) else { return s }
        let ns = s as NSString
        return ns.replacingCharacters(in: m.range, with: re.replacementString(for: m, in: s, offset: 0, template: template))
    }

    /// Every match replaced by what `f` makes of it.
    func replace(_ s: String, _ f: (Match) -> String) -> String {
        let ns = s as NSString
        var out = ""
        var at = 0
        for r in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: at, length: r.range.location - at)) + f(match(r, in: ns))
            at = NSMaxRange(r.range)
        }
        return out + ns.substring(from: at)
    }
}
