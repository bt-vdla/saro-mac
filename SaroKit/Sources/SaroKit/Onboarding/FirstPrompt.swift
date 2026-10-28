import Foundation

/// The first reflection question, written from what the person said in About you (firstPrompt.ts). Templates over
/// their own picks, so it works with Apple Intelligence off; an answer the phrase gate flags leaves only the fallback.
public enum FirstPrompt {
    public struct Candidate: Sendable, Hashable {
        public struct Slot: Sendable, Hashable {
            /// Where their own words sit in `text`, in UTF-16 offsets.
            public var start: Int, end: Int
            public var kind: Pick.Kind
        }

        public var text: String
        public var slot: Slot?

        public init(text: String, slot: Slot? = nil) {
            self.text = text
            self.slot = slot
        }
    }

    static let maxChars = 90

    /// [before, their words, after]; the name is nil when it has to be left out. `plural` is their words'.
    typealias Template = @Sendable (_ name: String?, _ words: String, _ plural: Bool) -> (String, String, String)

    private static func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    // Tried in order, with their name first: the shorter gentle line keeps the name when the longer one won't fit.
    private static func theme(_ tone: Tone) -> [Template] {
        switch tone {
        case .gentle:
            [{ n, p, pl in (n.map { "\($0), " } ?? "", n == nil ? cap(p) : p, " \(pl ? "have" : "has") been taking up a lot of room. How are you holding up today?") },
             { n, p, pl in (n.map { "\($0), " } ?? "", n == nil ? cap(p) : p, " \(pl ? "have" : "has") been taking up a lot of room. How are you holding up?") }]
        case .neutral: [{ n, p, _ in (n.map { "\($0), what came up today around " } ?? "What came up today around ", p, "?") }]
        case .direct: [{ n, p, pl in (n.map { "\($0). " } ?? "", cap(p), ". What actually happened with \(pl ? "them" : "it") today?") }]
        case .contemplative: [{ n, p, _ in (n.map { "\($0), where did " } ?? "Where did ", p, " sit with you today?") }]
        }
    }
    private static let worry: Template = { n, p, _ in (n.map { "\($0), you’ve been feeling " } ?? "You’ve been feeling ", p, ". Where did it show up today?") }
    private static let goal: Template = { n, p, _ in (n.map { "\($0), you want " } ?? "You want ", p, ". What’s one small sign of that from today?") }
    private static let person: Template = { n, p, _ in (n.map { "\($0), what’s one moment with " } ?? "What’s one moment with ", p, " from today?") }

    private static let ownerLead = Rx(#"^(?:my|our)\b"#, .caseInsensitive)
    private static let capitalised = Rx(#"^[A-Z][a-z]"#)

    /// Their words as they'd sit mid-sentence: "my" becomes "your", lowercase unless it starts with a name.
    static func phraseOf(_ pick: Pick) -> String {
        let s = ownerLead.replaceFirst(pick.text, "your")
        let first = s.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let isName = pick.kind == .person && capitalised.test(first) && !Onboarding.isRelation(first)
        return isName ? s : s.prefix(1).lowercased() + s.dropFirst()
    }

    private static func fill(_ templates: [Template], name: String, words: String, kind: Pick.Kind?, plural: Bool = false) -> Candidate? {
        for n in name.isEmpty ? [nil] : [name, nil] {
            for t in templates {
                let (before, middle, after) = t(n, words, plural)
                let text = before + middle + after
                guard (text as NSString).length <= maxChars else { continue }
                let at = (before as NSString).length
                return Candidate(text: text, slot: kind.map { Candidate.Slot(start: at, end: at + (middle as NSString).length, kind: $0) })
            }
        }
        return nil
    }

    // MARK: The theme, as they said it

    // A theme is said back as the whole phrase it came in, as something that takes up room: "My mum is ill" is "your mum
    // being ill", "Work is stressing me out" is "work stressing you out", "I can't sleep" is "not being able to sleep",
    // "So tired" is "being so tired"; "Money worries" stays as it is. A clause it can't turn into one isn't used.
    // ponytail: patterns over one clause, not a parser; an on-device model draft is the upgrade.
    private static let edge = Rx(#"[.,;:!?\n()]|\s[-–—]\s|\s(?:and|but|or|because|although)\s"#, .caseInsensitive)
    private static let fillerHead = Rx(#"^(?:(?:honestly|mostly|probably|definitely|just|really|lately|like|um+|uh+|well|oh|i guess|i think)\b[\s,]*)+"#, .caseInsensitive)
    private static let fillerTail = Rx(#"(?:[\s,]+(?:mostly|honestly|probably|tbh|lol|haha|i guess|i think))+$"#, .caseInsensitive)
    private static let endStop = Rx(#"[.!?…]+$"#)
    private static let capitalWord = Rx(#"^[A-Z][a-z']*$"#)
    private static let lowerWord = Rx(#"^[a-z]+$"#)

    private static func set(_ s: String) -> Set<String> { Set(s.split(separator: " ").map(String.init)) }
    private static let be = set("is are was were am")
    private static let have = set("has have had")
    private static let doo = set("do does did")
    private static let modal = set("will would should must might may shall can could")
    private static let pronoun = set("i we he she they it you this that there who what")
    private static let clauseWords = set("i we he she they is are was were am")
    private static let object = set("me us him them it you")
    private static let preposition = set("about of with to for in on at from by over after before around between into without")
    // Determiners, quantifiers and intensifiers: never where a subject ends.
    private static let quiet = set("a an the my our your his her their these those some any no so very too really super quite pretty all many much more most lots loads")
    // What can follow a state: "tired lately", "stressed about work", "burnt out".
    private static let trail = set("lately recently again all constantly always now out up down off").union(preposition)
    private static let adverb = set("never always constantly barely hardly still really also")
    private static let state = set("ill sick unwell bad sad low down lost stuck broke skint burnt burned fed mad upset worse busy")
    // Past forms that are describing words after a noun: "sleep deprived", "work related".
    private static let participle = set("deprived related induced based obsessed fuelled fueled driven focused starved filled packed overloaded")
    private static let verbS = set("hurts aches sucks stresses drains bothers scares annoys kills matters keeps feels seems gets makes takes goes comes means")
    private static let ingNoun = set("wedding morning evening meeting building ceiling feeling thing nothing something everything anything spring ring housing funding clothing")
    private static let singularS = set("news maths chaos series species lens gas")
    private static let past: [String: String] = [
        "broke": "breaking", "lost": "losing", "got": "getting", "left": "leaving", "split": "splitting", "fell": "falling",
        "quit": "quitting", "went": "going", "had": "having", "found": "finding", "made": "making", "took": "taking",
        "felt": "feeling", "came": "coming", "began": "beginning", "sold": "selling", "bought": "buying", "paid": "paying",
        "spent": "spending", "ran": "running", "hurt": "hurting",
    ]

    // "can't" is "can not", "I'm" is "I am", "Money's tight" is "Money is tight" ("my partner's job" stays a partner's).
    private static let expansions: [(Rx, String)] = [
        (Rx("’"), "'"),
        (Rx(#"\b(it|that|there|he|she|what|who|this)'s\b"#, .caseInsensitive), "$1 is"),
        (Rx(#"'s\s+(?=(?:been|got)\b)"#, .caseInsensitive), " has "),
        (Rx(#"'s\s+(?=(?:not|ill|sick|unwell|poorly|in|at|going|getting|being|really|so|very|too|still|always|a|an|crazy|busy|tight|hard|tough|stressful|awful|bad|rough|struggling|over)\b)"#, .caseInsensitive), " is "),
        (Rx(#"\bcan't\b"#, .caseInsensitive), "can not"),
        (Rx(#"\bwon't\b"#, .caseInsensitive), "will not"),
        (Rx(#"n't\b"#, .caseInsensitive), " not"),
        (Rx(#"'m\b"#, .caseInsensitive), " am"),
        (Rx(#"'re\b"#, .caseInsensitive), " are"),
        (Rx(#"'ve\b"#, .caseInsensitive), " have"),
        (Rx(#"'ll\b"#, .caseInsensitive), " will"),
        (Rx(#"'d\b"#, .caseInsensitive), " would"),
    ]
    private static func expand(_ s: String) -> String { expansions.reduce(s) { $1.0.replace($0, $1.1) } }

    private static let ie = Rx("ie$"), silentE = Rx("(?:[^aeiouy]|u)e$"), cvc = Rx("^[^aeiou]*[aeiou][^aeiouwxy]$")
    private static let ied = Rx("ied$"), ed = Rx("[^e]ed$"), ies = Rx("ies$"), es = Rx("(?:ss|sh|ch|x|z|o)es$"), ingEnd = Rx("ing$")

    /// "hate" → "hating", "stop" → "stopping", "die" → "dying", "see" → "seeing".
    static func ing(_ verb: String) -> String {
        if ie.test(verb) { return String(verb.dropLast(2)) + "ying" }
        if silentE.test(verb), verb != "be" { return String(verb.dropLast()) + "ing" }
        if cvc.test(verb) { return verb + String(verb.last!) + "ing" }
        return verb + "ing"
    }

    /// A verb as it was said ("broke", "moved", "worried", "stresses", "hate") as the -ing word.
    static func ingOf(_ verb: String) -> String {
        if let p = past[verb] { return p }
        if ied.test(verb) { return String(verb.dropLast(3)) + "ying" }
        if ed.test(verb) { return String(verb.dropLast(2)) + "ing" }
        if verbS.contains(verb) { return ing(ies.test(verb) ? String(verb.dropLast(3)) + "y" : es.test(verb) ? String(verb.dropLast(2)) : String(verb.dropLast())) }
        return ing(verb)
    }

    /// The clause of `text` around [start, end): "My mum is ill" out of "My mum is ill and I'm worried about her".
    private static func around(_ text: String, _ start: Int, _ end: Int) -> String {
        let ns = text as NSString
        var from = 0, to = ns.length
        for m in edge.all(text) {
            if NSMaxRange(m.range) <= start {
                from = NSMaxRange(m.range)
            } else if m.range.location >= end, !(m.text.lowercased().contains("and")
                        && ns.substring(with: NSRange(location: from, length: m.range.location - from)).range(of: #"\bbetween\b"#, options: [.regularExpression, .caseInsensitive]) != nil) {
                // "Balance between work and family" is one phrase.
                to = m.range.location
                break
            }
        }
        return ns.substring(with: NSRange(location: from, length: max(0, to - from)))
    }

    private static func describes(_ word: String) -> Bool {
        state.contains(word) || (SayBack.describes.test(word) && !SayBack.namesAThing.test(word) && word != "like" && word != "myself")
    }

    private static func at(_ a: [String], _ i: Int) -> String? { a.indices.contains(i) ? a[i] : nil }

    /// A phrase with no verb in it ("Money worries", "Moving for work", "So tired lately"), or nil when it may hide one.
    private static func nounPhrase(_ words: [String], _ low: [String]) -> (words: [String], plural: Bool)? {
        let hides = low.indices.contains { i in
            let x = low[i]
            return be.contains(x) || have.contains(x) || doo.contains(x) || modal.contains(x) || clauseWords.contains(x) || verbS.contains(x)
                || (i > 0 && adverb.contains(x)) || (object.contains(x) && !preposition.contains(at(low, i - 1) ?? ""))
        }
        guard let last = low.last, !hides, !preposition.contains(last), !quiet.contains(last) else { return nil }
        if !low.contains("being"), !ingEnd.test(low[0]), let first = low.firstIndex(where: { !quiet.contains($0) }) {
            // A state is "being" it: "being so tired lately", "being stressed about work", "being sleep deprived".
            let isState = describes(low[first]) && (first == low.count - 1 || trail.contains(low[first + 1]))
            if isState || (low.count == 2 && !quiet.contains(low[0]) && (describes(low[1]) || participle.contains(low[1]))) {
                return (["being"] + words, false)
            }
        }
        let gerund = low[0] == "not" || low[0] == "being" || (ingEnd.test(low[0]) && !ingNoun.contains(low[0]))
        let stop = low.indices.first { $0 > 0 && trail.contains(low[$0]) } ?? low.count
        var head = low[stop - 1]
        if head == "lots" || head == "loads" { head = last }
        return (words, !gerund && head.range(of: "[^siu']s$", options: .regularExpression) != nil && !singularS.contains(head))
    }

    /// A clause said as a phrase: "My mum is ill" → "your mum being ill"; nil when it can't be one.
    private static func clausePhrase(_ words: [String], _ low: [String]) -> (words: [String], plural: Bool)? {
        // Who it's about: no one named for "I" or "we" (it's them), "you and your partner" for "my partner and I".
        let and = low.firstIndex(of: "and") ?? -1
        var subject: [String]
        var j: Int
        if low[0] == "i" || low[0] == "we" {
            (subject, j) = ([], 1)
        } else if and > 0, at(low, and + 1) == "i" {
            (subject, j) = (["you", "and"] + words[..<and], and + 2)
        } else {
            guard let v = low.indices.first(where: { i in
                let x = low[i]
                return i > 0 && !quiet.contains(low[i - 1]) && !low[i - 1].hasSuffix("'s")
                    && (be.contains(x) || have.contains(x) || doo.contains(x) || modal.contains(x) || verbS.contains(x) || past[x] != nil
                        || (ed.test(x) && !participle.contains(x)))
            }) else { return nounPhrase(words, low) }
            j = v
            subject = Array(words[..<j])
            if low[..<j].contains(where: pronoun.contains) { return nil }
        }
        // "I just moved" is moving; "I really hate my job" is really hating it.
        var adverbs: [String] = []
        while let x = at(low, j), adverb.contains(x) || x == "just" {
            if x != "just" { adverbs.append(words[j]) }
            j += 1
        }
        guard let verb = at(low, j), lowerWord.test(verb), !quiet.contains(verb), !preposition.contains(verb), !pronoun.contains(verb) else { return nil }
        var k = j + 1
        func not() -> [String] {
            guard at(low, k) == "not" else { return [] }
            k += 1
            return ["not"]
        }
        var said: [String]
        if be.contains(verb) || (have.contains(verb) && at(low, k) == "been") || (have.contains(verb) && at(low, k) == "not" && at(low, k + 1) == "been") {
            let neg = not()
            if at(low, k) == "been" { k += 1 }
            if at(low, k) == "being" { k += 1 }
            let next = at(low, k) ?? ""
            said = neg + (ingEnd.test(next) && !ingNoun.contains(next) ? [] : ["being"])
        } else if have.contains(verb) {
            let neg = not()
            if at(low, k) == "got" { k += 1 }
            said = neg + ["having"]
        } else if doo.contains(verb) || verb == "can" || verb == "could" {
            guard at(low, k) == "not", let next = at(low, k + 1) else { return nil }
            k += 1
            if doo.contains(verb) {
                said = ["not", ingOf(next)]
                k += 1
            } else {
                said = ["not", "being", "able", "to"]
            }
        } else if modal.contains(verb) {
            return nil
        } else if ["keep", "keeps", "kept"].contains(verb), ingEnd.test(at(low, k) ?? "") {
            // "We keep fighting" is fighting.
            said = []
        } else {
            said = [ingOf(verb)]
        }
        let rest = Array(words[min(k, words.count)...]), restLow = Array(low[min(k, low.count)...])
        if rest.isEmpty, said.isEmpty { return nil }
        if restLow.indices.contains(where: { i in
            clauseWords.contains(restLow[i]) || (restLow[i] == "it" && !preposition.contains(at(restLow, i - 1) ?? at(low, k - 1) ?? ""))
        }) { return nil }
        if let last = restLow.last, preposition.contains(last) || quiet.contains(last) { return nil }
        return (subject + adverbs + said + rest, false)
    }

    /// The theme pick said back as the whole phrase it came in, and whether it takes "have"; nil when it can't be.
    static func themePhrase(_ pick: Pick, answer: String) -> (phrase: String, plural: Bool)? {
        let ns = answer as NSString
        let inPlace = pick.end <= ns.length && pick.start >= 0 && ns.substring(with: NSRange(location: pick.start, length: pick.end - pick.start)) == pick.text
        let start = inPlace ? pick.start : ns.range(of: pick.text).location
        guard start != NSNotFound else { return nil }
        var clause = around(answer, start, start + (pick.text as NSString).length).trimmingCharacters(in: .whitespacesAndNewlines)
        clause = endStop.replaceFirst(fillerTail.replaceFirst(fillerHead.replaceFirst(clause, ""), ""), "")
        clause = expand(clause.trimmingCharacters(in: .whitespacesAndNewlines))
        // Its first word is mid-sentence now ("being so tired"), unless it's always capitalised ("NHS").
        let words = clause.split(whereSeparator: \.isWhitespace).enumerated().map { i, w in
            i == 0 && capitalWord.test(String(w)) ? w.lowercased() : String(w)
        }
        guard !words.isEmpty, words.count <= 8, let said = clausePhrase(words, words.map { $0.lowercased() }) else { return nil }
        // Curly apostrophes, like the rest of the prompt.
        let phrase = SayBack.sayBack(said.words.joined(separator: " ")).replacingOccurrences(of: "'", with: "’")
        return (phrase.prefix(1).lowercased() + phrase.dropFirst(), said.plural)
    }

    // MARK: Compose

    /// The candidates, in order: their theme (Q2), a worry, their goal (Q4), a person, then `fallback` (their tone's
    /// line by default). A candidate over 90 characters drops the name, and if still too long is skipped. If any answer
    /// trips the phrase gate, only the fallback is offered.
    public static func compose(answers: [Int: String], picks: [Pick], name: String, tone: Tone, fallback: String? = nil) -> [Candidate] {
        let last = Candidate(text: fallback ?? tone.previewLine(name: name))
        if (1...5).contains(where: { SafetyGate.phraseHit(answers[$0] ?? "") }) { return [last] }
        let first = name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let theme = picks.first { $0.kind == .theme && $0.q == 2 && Onboarding.isThemeId($0.value) }
        let worry = picks.first { $0.kind == .theme && !Onboarding.isThemeId($0.value) }
        let goal = picks.first { $0.kind == .goal && $0.q == 4 }
        let person = picks.first { $0.kind == .person }
        let label = worry?.value.lowercased() ?? ""
        // Nil when the goal or the theme can't be said back as a whole sentence; then there's no prompt from it.
        let said = goal.flatMap { SayBack.goalPhrase($0.text, answer: answers[$0.q]) }
        let topic = theme.flatMap { themePhrase($0, answer: answers[$0.q] ?? $0.text) }
        let candidates: [Candidate?] = [
            topic.flatMap { fill(Self.theme(tone), name: first, words: $0.phrase, kind: .theme, plural: $0.plural) },
            // The label is Saro's word for the feeling; it is only their words when they used it.
            worry.flatMap { fill([Self.worry], name: first, words: label, kind: $0.text.lowercased() == label ? .theme : nil) },
            said.flatMap { fill([Self.goal], name: first, words: $0.phrase, kind: .goal) },
            person.flatMap { fill([Self.person], name: first, words: phraseOf($0), kind: .person) },
        ]
        return candidates.compactMap { $0 } + [last]
    }

    /// This pass's candidates, from what is stored: a held answer gets the fallback only.
    public static func compose(starter: StarterContext, name: String, tone: Tone) -> [Candidate] {
        let fallback = tone.previewLine(name: name)
        guard starter.held.isEmpty else { return [Candidate(text: fallback)] }
        return compose(answers: starter.answers, picks: starter.picks.filter { !starter.dropped.contains($0.dropKey) }, name: name, tone: tone,
                       fallback: fallback)
    }

    /// The question the first reflection opens on (firstMode.ts, VideoReflectionScreen's seedPrompt): the first prompt
    /// About you kept, on a replay too, else the tone's line, else the web's fallback. Never a day's reading: the page or
    /// recording that keeps it may yet be held.
    public static func opening(_ first: String?, tone: Tone?, name: String?) -> String {
        if let first, !first.jsTrim.isEmpty { return first }
        return tone?.previewLine(name: name) ?? "If you could freeze one second from today, which would it be?"
    }
}

/// The gate's verdict on an About you answer, for the text it was given; nil when the gate deferred (unchecked).
public struct AnswerVerdict: Sendable, Hashable {
    public var text: String
    public var verdict: String?

    public init(text: String, verdict: String?) {
        self.text = text
        self.verdict = verdict
    }

    /// Read by the gate and clear, with or without Apple Intelligence. Anything else is held or awaiting a check (a
    /// caution hit while the model is off, or no verdict yet), and nothing is learned from it (SR-14).
    public var checked: Bool { verdict == "clear" || verdict == "unavailable_clear" }

    /// A caution hit while the model is off: kept, unread, with a quiet way to talk to someone.
    public var caution: Bool { verdict == "unavailable_caution" }

    /// Whether to ask the gate again: no verdict yet, or one made without the model once it can run (SR-17).
    public func needsRegate(modelAvailable: Bool) -> Bool {
        verdict == nil || (modelAvailable && (verdict == "unavailable_clear" || caution))
    }
}

extension StarterContext {
    /// What may be stored or used: only answers whose verdict is in for the text they have now, the held ones marked,
    /// and the picks made again from the checked ones, so nothing is composed or learned from text the gate hasn't
    /// seen or hasn't cleared. An answer awaiting a check is kept as they wrote it.
    public func gated(_ verdicts: [Int: AnswerVerdict], knownName: String) -> StarterContext {
        var s = self
        s.answers = answers.filter { verdicts[$0.key]?.text == $0.value }
        s.held = Set(s.answers.keys.filter { verdicts[$0]?.verdict == "safety_hold" })
        s.picks = Onboarding.picks(answers: s.answers.filter { verdicts[$0.key]?.checked == true }, dropped: dropped, knownName: knownName)
        s.reflectTime = Onboarding.reflectTime(s.picks)
        return s
    }
}

extension FirstPrompt {
    /// Where the first question stands once About you is answered.
    public enum State: Sendable, Equatable {
        /// An answer is still at the gate.
        case waiting
        /// An answer was held: no personal prompt, the SafetyCard instead.
        case held
        case ready([Candidate])
    }

    /// Waiting until every answer has its verdict; held if any was held; their tone's line alone if any answer went
    /// unchecked; otherwise the candidates made from what they said.
    public static func state(_ starter: StarterContext, verdicts: [Int: AnswerVerdict], name: String, tone: Tone) -> State {
        let answered = starter.answers.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if answered.contains(where: { verdicts[$0.key]?.text != $0.value }) { return .waiting }
        let s = starter.gated(verdicts, knownName: name)
        if !s.held.isEmpty { return .held }
        let unchecked = s.answers.keys.contains { verdicts[$0]?.checked != true }
        if unchecked { return .ready([Candidate(text: tone.previewLine(name: name))]) }
        return .ready(compose(starter: s, name: name, tone: tone))
    }
}
