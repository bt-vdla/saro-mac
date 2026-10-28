import Foundation

/// Layer 1 (SR-04, SR-05, SR-06): the phrase gate and the caution lexicon over one normalised form.
extension SafetyGate {
    /// SR-05: the one normaliser for patterns and text alike. Apostrophes dropped ("don't" -> "dont"), NFKC, lowercase,
    /// case and diacritic folding, a run of three or more of one ASCII letter cut to one ("dieeee" -> "die"), and every
    /// run of other punctuation or space collapsed to one token: " . " for a sentence end, so a guard word never reaches
    /// across a sentence; " , " for a clause break (comma, semicolon, colon, ellipsis), which a phrase reads through but a
    /// guard word doesn't; else one space. Letters, marks and digits of every script survive.
    public static func normalise(_ text: String) -> String {
        // NFKC would turn an acute accent used as an apostrophe ("don´t") into a space, so it goes first.
        let text = text.unicodeScalars.contains("\u{00B4}") ? text.replacingOccurrences(of: "\u{00B4}", with: "") : text
        let folded = text.precomposedStringWithCompatibilityMapping.lowercased()
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var out = String.UnicodeScalarView()
        out.reserveCapacity(folded.utf8.count)
        var gap = 0, dots = 0, run = 0, last: Unicode.Scalar = " "
        for s in folded.unicodeScalars {
            // ASCII and Devanagari by hand: the property lookup is most of the normaliser's time (the <1 ms budget, SR-04).
            let v = s.value
            let category: Unicode.GeneralCategory
            switch v {
            // Apostrophes, fullwidth included after NFKC: "don't" -> "dont".
            case 0x27, 0x60, 0x02BC, 0x2018, 0x2019, 0x201B, 0x2032: continue
            case 0x61...0x7A: category = .lowercaseLetter
            case 0x30...0x39: category = .decimalNumber
            case 0...0x7F, 0x0964, 0x0965, 0x0970: category = .otherPunctuation
            case 0x0900...0x097F: category = .otherLetter
            default: category = s.properties.generalCategory
            }
            switch category {
            case .format: continue
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .nonspacingMark, .spacingMark, .decimalNumber, .letterNumber, .otherNumber:
                // Emoji presentation selectors are marks too; dropped so "kill ☠️ myself" still reads as two words.
                if v == 0x093C || v >= 0xFE00 && s.properties.isVariationSelector { continue }
                // NFKC turns "…" into "...": one dot ends a sentence, two or more are a pause.
                let level = dots > 1 ? max(gap, 2) : dots == 1 ? 3 : gap
                if level > 0, !out.isEmpty { out.append(contentsOf: (level == 3 ? " . " : level == 2 ? " , " : " ").unicodeScalars) }
                run = level == 0 && v < 0x80 && category == .lowercaseLetter && s == last ? run + 1 : 1
                (gap, dots, last) = (0, 0, s)
                if run == 3 { out.removeLast() }
                if run < 3 { out.append(devanagariFold(s)) }
            default:
                if v == 0x2E { dots += 1 } else { gap = max(gap, sentenceEnds.contains(s) ? 3 : clauseBreaks.contains(s) ? 2 : 1) }
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

    private static let sentenceEnds: Set<Unicode.Scalar> = ["!", "?", "\n", "\r", "\u{0964}", "\u{0965}"]
    private static let clauseBreaks: Set<Unicode.Scalar> = [",", ";", ":"]

    /// Diacritic folding leaves Devanagari alone, so its spelling variants fold by hand: chandrabindu to anusvara, and the
    /// three nukta letters NFKC keeps precomposed (the rest decompose, and the nukta itself is dropped).
    private static func devanagariFold(_ s: Unicode.Scalar) -> Unicode.Scalar {
        // On the value, not the scalar: this runs for every letter, and integer cases stay cheap unoptimised.
        switch s.value {
        case 0x0901: "\u{0902}"
        case 0x0929: "\u{0928}"
        case 0x0931: "\u{0930}"
        case 0x0934: "\u{0933}"
        default: s
        }
    }

    /// A whole-word phrase with `safety.ts`'s guards on the word just before or the words just after ("don't want to die",
    /// "take my life back", "wake up the kids").
    private struct Phrase: Sendable {
        let words: [String]
        let notBefore: Set<String>
        let notAfter: [[String]]
    }

    private static func phrases(_ list: [String], notBefore: [String] = [], notAfter: [String] = []) -> [Phrase] {
        let guards = notAfter.map { normalise($0).split(separator: " ").map(String.init) }
        return Set(list.map(normalise).flatMap(squeezings)).map {
            Phrase(words: $0.split(separator: " ").map(String.init), notBefore: Set(notBefore), notAfter: guards)
        }
    }

    /// The pattern with each double letter kept or squeezed ("all pills" -> "al pills", "all pils", "al pils"): elongated
    /// text ("alll my pills") normalises its run to one letter and leaves the phrase's other doubles alone.
    private static func squeezings(_ s: String) -> [String] {
        var forms = [""], last: Unicode.Scalar = " "
        for c in s.unicodeScalars {
            forms = c == last && ("a"..."z").contains(c) ? forms + forms.map { $0 + String(c) } : forms.map { $0 + String(c) }
            last = c
        }
        return forms
    }

    /// Every combination of the parts, in order; an empty string skips that part.
    private static func combos(_ parts: [String]...) -> [String] {
        parts.reduce([""]) { acc, part in acc.flatMap { a in part.map { [a, $0].filter { !$0.isEmpty }.joined(separator: " ") } } }
    }

    /// A word trie of the phrases, so matching costs one dictionary lookup per word walked, however many phrases share a
    /// start like "want to" (the <1 ms budget, SR-04). `ends` holds every phrase that ends at this node.
    private struct Node: Sendable {
        var next: [String: Node] = [:]
        var ends: [Phrase] = []

        mutating func insert(_ p: Phrase, from k: Int = 0) {
            if k == p.words.count { ends.append(p) } else { next[p.words[k], default: Node()].insert(p, from: k + 1) }
        }
    }

    private static func index(_ groups: [[Phrase]]) -> Node {
        var root = Node()
        for p in groups.joined() { root.insert(p) }
        return root
    }

    private static func hit(_ trie: Node, _ normalised: String) -> Bool {
        // Clause breaks drop out of the words; `paused[i]` says one stood just before word i, which blocks a guard there.
        var words: [String] = [], paused: [Bool] = [], pause = false
        for w in normalised.split(separator: " ") {
            if w == "," { pause = true; continue }
            words.append(String(w))
            paused.append(pause)
            pause = false
        }
        for i in words.indices {
            var node = trie, end = i
            while end < words.count, let child = node.next[words[end]] {
                (node, end) = (child, end + 1)
                for p in node.ends {
                    if i > 0, !paused[i], p.notBefore.contains(words[i - 1]) { continue }
                    if p.notAfter.contains(where: { g in
                        g.indices.allSatisfy { end + $0 < words.count && !paused[end + $0] && words[end + $0] == g[$0] }
                    }) { continue }
                    return true
                }
            }
        }
        return false
    }

    private static let negated = ["dont", "didnt", "doesnt", "never", "not"]
    private static let housing = ["in", "with", "near", "there", "here", "at", "on", "together", "alone", "by", "next", "so",
                                  "far", "somewhere", "abroad", "close"]
    // DRAFT: clinician review (SR-32), safety-2 — "late" onwards, as whole phrases so "wake up the next day" and
    // "wake up with this feeling" still hit.
    private static let wakeGuard = ["early", "at", "before", "for", "so", "too", "yet", "late", "the house", "the whole house"]
        + combos(["the", "my", "our", "his", "her"], ["kids", "baby", "family", "neighbours", "neighbors"])
        + combos(["with a"], ["migraine", "headache", "hangover", "cold", "fever"])
    // DRAFT: clinician review (SR-32), safety-2 — "in" dropped: it cancelled "cut myself in the bathroom" and
    // "used to cut myself in college" to spare the rare "cutting myself in on the deal".
    private static let cutGuard = ["some", "a", "slack", "off", "loose", "free", "out", "short", "up"]

    private static let phraseIndex = index([
        // safety.ts
        phrases(["kill myself", "killing myself", "kill my self", "kil myself", "killmyself"]),
        phrases(["end my life", "ending my life", "end my own life", "end it all", "ending it all"]),
        phrases(["take my own life", "taking my own life", "take my life", "taking my life"],
                notAfter: ["back", "savings", "in", "into", "to", "more", "seriously", "apart"]),
        // DRAFT: clinician review (SR-32), safety-2 — guards after "squad".
        phrases(["suicide"], notAfter: ["squad", "mission", "missions", "doors", "door", "sprint", "sprints", "drill", "drills",
                                        "bomber", "bombers", "bombing", "bombings"]),
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
                 "no point to anything", "no point in anything",
                 "what's the point anymore", "what's the point of living", "what's the point of anything",
                 "what's the point of being alive", "can't go on living", "tired of being alive",
                 "sick of being alive"]),
        // DRAFT: clinician review (SR-32), safety-2 — guarded: "no point going on about it", "tired of living out of a suitcase".
        phrases(["no point going on", "no point in going on"], notAfter: ["about"]),
        phrases(["tired of living"], notAfter: ["out", "under", "paycheck", "off", "from"]),
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
        phrases(combos(["no reason", "no point"], ["to", "in"], ["live", "living", "go on", "going on"]), notAfter: ["about"]),
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
        // DRAFT: clinician review (SR-32), safety-2 — English phrasings the synthetic corpus caught missing
        phrases(["wish id never been born", "wish i hadnt been born", "wish i had not been born", "wish i never was born",
                 "nothing left to live for", "dont wanna be alive", "dont wanna exist", "do not wanna be alive",
                 "took an overdose", "taken an overdose", "take an overdose", "taking an overdose"]),
        phrases(["dont wanna wake up", "do not wanna wake up"], notAfter: wakeGuard),
        phrases(["want 2 die", "wanted 2 die"], notBefore: negated, notAfter: ["of", "laughing"]),
        phrases(combos(["better off if i", "better off if i just", "happier if i", "better if i just"],
                       ["was gone", "were gone", "wasnt here", "werent here", "wasnt around", "werent around", "didnt exist",
                        "was dead", "were dead", "died"])),
        phrases(combos(["no one", "nobody", "noone"], ["would", "will", "would even", "wouldnt even"], ["miss me", "notice", "care"],
                       ["if i"], ["died", "was gone", "were gone", "was dead", "wasnt here", "wasnt around", "killed myself"])),
        phrases(combos(["part of me"], ["wants to", "just wants to"], ["die", "be dead", "end it", "not exist", "disappear forever"])),
        phrases(combos(["want to", "wanna", "wish i could", "wish i could just"], ["stop existing", "not exist", "not be alive"])),
        phrases(["life isnt worth living", "life is not worth living", "lifes not worth living", "not worth living anymore"],
                notBefore: ["unexamined"]),
        phrases(combos(["i should", "i should just", "maybe i should", "maybe i should just", "i might as well", "i might as well just"],
                       ["die", "be dead"]), notAfter: ["of", "laughing", "from", "trying"]),
        phrases(combos(["i hope i", "i hope i just", "hoping i", "hoping i just", "i pray i"], ["die"]),
                notAfter: ["before", "of", "laughing", "old", "first", "happy", "doing", "trying", "peacefully"]),
        phrases(combos(["how many"], ["pills", "tablets", "sleeping pills"], ["it would take", "would it take"]), notAfter: ["to"]),
        phrases(combos(["how many"], ["pills", "tablets", "sleeping pills"], ["it would take", "would it take", "it takes", "does it take"],
                       ["to die", "to overdose", "to end it", "to not wake up"])),
        phrases(combos(["stockpiling", "stockpile", "hoarding"], ["my", "the", ""],
                       ["pills", "tablets", "meds", "sleeping pills", "painkillers"])),
        phrases(combos(["taking", "swallowing"], ["all my", "all of my", "all the"], ["pills", "sleeping pills"])),
        phrases(combos(["take", "taking", "swallow", "swallowing", "swallowed"], ["the whole", "a whole"], ["bottle", "packet"],
                       ["of pills", "of sleeping pills", "of painkillers", "of tablets", "of paracetamol"])),
        phrases(combos(["going to", "gonna", "want to", "wanna", "planning to", "plan to", "thinking about", "thought about",
                        "thinking of"], ["overdose", "overdosing"])),
        phrases(combos(["painless", "easiest", "quickest", "easy", "quick"], ["way", "ways"], ["to die", "to end it", "to end my life"])),
        phrases(combos(["want to", "wanna", "going to", "gonna", "thinking about", "thinking of", "thought about", "planning to"],
                       ["jump", "jumping"], ["off", "from", "in front of"], ["a", "the", "my"],
                       ["bridge", "roof", "building", "balcony", "terrace", "cliff", "train", "bus"])),
        phrases(combos(["throw", "throwing", "threw"], ["myself"], ["off", "from", "in front of", "under"], ["a", "the", "my"],
                       ["bridge", "roof", "building", "balcony", "terrace", "cliff", "train", "bus", "car", "truck"])),
        phrases(combos(["used to", "use to"], ["cut", "burn", "harm"], ["myself", "my self"]), notAfter: cutGuard),
        phrases(combos(["want", "wanted", "wanting", "urge", "urges", "tempted", "thinking about", "thought about"], ["to", ""],
                       ["burn", "burning"], ["myself", "my self"])),
        phrases(combos(["cut", "cutting", "burn", "burning", "burned", "burnt", "hurt", "hurting", "hit", "hitting", "scratched",
                        "scratching"], ["myself", "my self"], ["on purpose", "deliberately", "intentionally"])),
        phrases(combos(["kill", "kil", "killing"], ["myslef", "mysef", "myslf", "mysefl"])),
        phrases(combos(["want to", "wanna", "gonna", "going to", "about to", "ready to", "might", "might just", "should just", "imma"],
                       ["kms"])),
        phrases(combos(["want to", "wanna", "going to", "gonna", "thinking about", "thought about", "plan to", "planning to",
                        "tried to"], ["unalive", "unaliving"]),
                notAfter: ["him", "her", "them", "you", "everyone", "the", "this", "that", "his"]),
        // DRAFT: clinician review (SR-32), safety-2 — Hinglish, romanised ("nhi" and "nai" are common typed spellings of "nahi")
        phrases(["mujhe marna hai", "mujhe mar jaana hai", "mujhe mar jaana chahiye", "mujhe mar jana chahiye", "mujhe marna chahiye",
                 "marjaun", "marjau", "marjaana hai", "marjana hai", "khudkhushi", "khud khushi", "khudakushi",
                 "mere bina sab khush", "mere bagair behtar", "mere bagair sab behtar",
                 "nas kaat", "nass kaat", "nas kat", "nasen kaat", "nasein kaat", "kalai kaat", "kalai kat"]),
        phrases(combos(["jeena", "jina"], ["nahi", "nahin", "nhi", "nai"], ["chahta", "chahti"])),
        phrases(combos(["zinda", "jinda"], ["nahi", "nahin", "nhi", "nai"], ["rehna", "rahna"])),
        phrases(combos(["jeene ka", "jine ka"], ["man", "mann", "dil"], ["nahi", "nahin", "nhi", "nai"])),
        phrases(combos(["jeene ki", "jine ki"], ["ichha", "icha", "iccha", "ichchha", "chahat"], ["nahi", "nahin", "nhi", "nai", "khatam"])),
        phrases(combos(["jeene", "jine", "zinda rehne", "jinda rehne", "zinda rahne"], ["ka"], ["koi", ""],
                       ["matlab", "fayda", "faida", "maksad"], ["nahi", "nahin", "nhi", "nai"])),
        phrases(combos(["kaash main", "kash main", "kaash mai", "kash mai", "kaash me", "kash me"], ["paida"], ["hi", ""], ["na", "nahi"],
                       ["hota", "hoti", "hua hota", "hui hoti"])),
        phrases(combos(["mere bina"], ["sab", "sab log", ""], ["behtar", "better"])),
        phrases(combos(["apni jaan"], ["le"], ["lun", "loon", "lu", "lunga", "lungi", "lena chahta", "lena chahti", "leni hai"])),
        phrases(combos(["khud ko", "khudko", "apne aap ko", "apne ap ko"], ["maar", "mar", "maarna", "khatam", "khatm"])),
        phrases(combos(["phaansi", "phansi", "faansi", "fansi", "phasi", "fasi"], ["laga", "lagaa"], ["lun", "loon", "lu", "lunga", "lungi"])),
        phrases(combos(["kabhi", "dobara", "phir kabhi"], ["na"], ["uthun", "uthoon", "uthu", "jaagun", "jaagoon", "jagun"])),
        phrases(combos(["chhat", "chat", "chhath", "terrace", "balcony", "building", "bridge", "pul"], ["se"], ["kood", "kud", "kooda"],
                       ["jaun", "jau", "jaoon", "jaaun", "jaunga", "jaungi"])),
        phrases(combos(["saari", "sari", "saare", "sare", "sab"], ["goliyan", "goliya", "golian", "dawaiyan", "dawaiya", "tablets", "pills"],
                       ["kha", "khaa", "nigal"], ["lun", "loon", "lu", "lunga", "lungi", "jaun"])),
        // DRAFT: clinician review (SR-32), safety-2 — Hinglish, Devanagari (nukta and chandrabindu fold, so one spelling covers both)
        phrases(["मुझे मरना है", "मुझे मर जाना है", "मुझे मर जाना चाहिए", "मुझे मरना चाहिए", "मर जाउं", "मर जाउ", "खुदखुशी"]),
        phrases(combos(["जीने की"], ["इच्छा", "चाहत"], ["नहीं", "नही", "खत्म"])),
        phrases(combos(["जीने का", "जिंदा रहने का", "जिन्दा रहने का"], ["मन", "दिल", "कोई मतलब", "मतलब", "कोई फायदा", "फायदा"],
                       ["नहीं", "नही"])),
        phrases(combos(["काश मैं", "काश मै"], ["पैदा"], ["ही", ""], ["न", "ना", "नहीं"], ["होता", "होती", "हुआ होता", "हुई होती"])),
        phrases(combos(["मेरे बिना"], ["सब", "सब लोग", ""], ["बेहतर"])),
        phrases(combos(["अपनी जान"], ["ले"], ["लूं", "लूंगा", "लूंगी", "लू", "लेना चाहता", "लेना चाहती"])),
        phrases(combos(["खुद को", "अपने आप को"], ["मार", "खत्म"])),
        phrases(combos(["फांसी", "फासी"], ["लगा"], ["लूं", "लूंगा", "लूंगी", "लू"])),
        phrases(combos(["नस", "नसें", "कलाई"], ["काट"])),
        phrases(combos(["कभी", "दोबारा", "फिर कभी"], ["न", "ना"], ["उठूं", "उठू", "जागूं"])),
        phrases(combos(["छत", "बिल्डिंग", "पुल", "बालकनी"], ["से"], ["कूद"], ["जाऊं", "जाउं", "जाऊ", "जाऊंगा", "जाऊंगी"])),
        phrases(combos(["सारी", "सब"], ["गोलियां", "दवाइयां"], ["खा"], ["लूं", "लू", "लूंगा", "लूंगी", "जाऊं"])),
    ])

    // safety.py's one pattern with a gap: "wish I could just not wake up". Written in normalised form.
    // DRAFT: clinician review (SR-32), safety-2 — the -ing and "pray" triggers, and "I don't / won't / wouldn't wake up".
    // A " , " clause break counts as one character of the 30, as the one space it was before the normaliser kept pauses.
    private static let wakeRegex = try! NSRegularExpression(
        pattern: "\\b(?:wish|wishing|hope|hoping|want|wanting|pray|praying)\\b(?:[^.,]| , ){0,30}"
            + "\\b(?:not|never|i dont|i wont|i wouldnt|i didnt) wake up\\b(?! (?:\(wakeGuard.joined(separator: "|")))\\b)")

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
