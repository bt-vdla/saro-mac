import Foundation

/// The web's lib/search normalize.ts, fuzzy.ts and snippet.ts: folding, stopwords, a light stemmer, bounded
/// Damerau-Levenshtein and snippets. Offsets are UTF-16 units, as the web's are.
enum SearchText {
    struct Token: Equatable {
        let term: String
        let start: Int
        let end: Int
    }

    private static let maxTokenLength = 64

    /// Lowercased, NFKD-folded, diacritic-free terms with [start, end) offsets into `text`. Apostrophes join a word.
    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var term = "", start = 0, end = 0, i = 0
        func flush() {
            if !term.isEmpty { tokens.append(Token(term: String(term.prefix(maxTokenLength)), start: start, end: end)) }
            term = ""
        }
        for scalar in text.unicodeScalars {
            let next = i + scalar.utf16.count
            for c in fold(scalar) {
                if c == " " { flush() } else if c != "'" {
                    if term.isEmpty { start = i }
                    term.unicodeScalars.append(c)
                    end = next
                }
            }
            i = next
        }
        flush()
        return tokens
    }

    /// One scalar as the scalars of its folded term: letters and digits, `'` for an apostrophe, `" "` for a separator.
    private static func fold(_ s: Unicode.Scalar) -> [Unicode.Scalar] {
        if s.isASCII {
            let v = s.value
            if (0x61...0x7A).contains(v) || (0x30...0x39).contains(v) { return [s] }
            if (0x41...0x5A).contains(v) { return [Unicode.Scalar(v + 32)!] }
            return [s == "'" || s == "`" ? "'" : " "]
        }
        if "‘’ʼ´".unicodeScalars.contains(s) { return ["'"] }
        return String(s).lowercased().decomposedStringWithCompatibilityMapping.unicodeScalars.compactMap { c in
            let p = c.properties
            if p.generalCategory == .nonspacingMark || p.generalCategory == .enclosingMark || p.isVariationSelector
                || c.value == 0x200C || c.value == 0x200D { return nil }
            if c.isASCII { return fold(c).first }
            return p.isAlphabetic || p.numericType != nil || p.generalCategory == .spacingMark ? c : " "
        }
    }

    static let stopwords: Set<String> = Set("""
        a about above after again against all also am an and any are as at be because been before being below between both \
        but by can could did do does doing down during each few for from further had has have having he her here hers \
        herself him himself his how i if in into is it its itself just me more most my myself no nor not now of off on once \
        only or other our ours ourselves out over own same she should so some such than that the their theirs them \
        themselves then there these they this those through to too under until up very was we were what when where which \
        while who whom why will with would you your yours yourself yourselves im ive youre youve youd youll hes shes \
        theyre theyve weve thats whats theres heres
        """.split(separator: " ").map(String.init))

    // MARK: Stemming (Porter2 steps 1a–1c plus Porter's final-e rule; plain a–z words of 3+ letters only)

    private static let exceptions = ["news": "news", "goes": "go", "dying": "die", "lying": "lie", "tying": "tie"]

    static func stem(_ term: String) -> String {
        guard term.count >= 3, term.utf8.allSatisfy({ (0x61...0x7A).contains($0) }) else { return term }
        if let e = exceptions[term] { return e }
        return String(decoding: dropFinalE(step1c(step1b(step1a(Array(term.utf8))))), as: UTF8.self)
    }

    private typealias Word = [UInt8]

    private static func isVowel(_ w: Word, _ i: Int) -> Bool {
        switch w[i] {
        case 0x61, 0x65, 0x69, 0x6F, 0x75: true
        case 0x79: i > 0 && !isVowel(w, i - 1)
        default: false
        }
    }

    private static func hasVowel(_ w: Word) -> Bool { w.indices.contains { isVowel(w, $0) } }
    private static func measure(_ w: Word) -> Int { (w.indices.dropFirst()).filter { !isVowel(w, $0) && isVowel(w, $0 - 1) }.count }
    private static func regionOne(_ w: Word) -> Int { (w.indices.dropFirst()).first { !isVowel(w, $0) && isVowel(w, $0 - 1) }.map { $0 + 1 } ?? w.count }
    private static func ends(_ w: Word, _ s: String) -> Bool { w.count >= s.utf8.count && w.suffix(s.utf8.count).elementsEqual(s.utf8) }

    private static func shortSyllable(_ w: Word) -> Bool {
        let n = w.count
        if n == 2 { return isVowel(w, 0) && !isVowel(w, 1) }
        return n > 2 && !isVowel(w, n - 3) && isVowel(w, n - 2) && !isVowel(w, n - 1) && !"wxy".utf8.contains(w[n - 1])
    }

    private static func step1a(_ w: Word) -> Word {
        if ends(w, "sses") { return Word(w.dropLast(2)) }
        if ends(w, "ied") || ends(w, "ies") { return Word(w.dropLast(w.count > 4 ? 2 : 1)) }
        if ends(w, "us") || ends(w, "ss") || !ends(w, "s") { return w }
        return (0..<max(0, w.count - 2)).contains { isVowel(w, $0) } ? Word(w.dropLast()) : w
    }

    private static func step1b(_ w: Word) -> Word {
        guard let suffix = ["eedly", "ingly", "edly", "eed", "ing", "ed"].first(where: { ends(w, $0) }) else { return w }
        let base = Word(w.dropLast(suffix.utf8.count))
        if suffix == "eed" || suffix == "eedly" { return base.count >= regionOne(w) ? base + Array("ee".utf8) : w }
        guard hasVowel(base) else { return w }
        if ["at", "bl", "iz"].contains(where: { ends(base, $0) }) { return base + [0x65] }
        if ["bb", "dd", "ff", "gg", "mm", "nn", "pp", "rr", "tt"].contains(where: { ends(base, $0) }) { return Word(base.dropLast()) }
        return shortSyllable(base) && regionOne(base) >= base.count ? base + [0x65] : base
    }

    private static func step1c(_ w: Word) -> Word {
        let n = w.count
        return n > 2 && w[n - 1] == 0x79 && !isVowel(w, n - 2) ? Word(w.dropLast()) + [0x69] : w
    }

    private static func dropFinalE(_ w: Word) -> Word {
        guard w.count >= 4, w.last == 0x65 else { return w }
        let base = Word(w.dropLast()), m = measure(base)
        return m > 1 || (m == 1 && !shortSyllable(base)) ? base : w
    }

    // MARK: Fuzzy

    static func maxEdits(_ length: Int) -> Int { length >= 8 ? 2 : length >= 4 ? 1 : 0 }

    /// Distinct padded bigrams: "walk" → ^w wa al lk k$.
    static func bigrams(_ term: String) -> [String] {
        let padded = Array("^" + term + "$")
        var out: [String] = []
        for i in 0..<(padded.count - 1) {
            let g = String(padded[i...i + 1])
            if !out.contains(g) { out.append(g) }
        }
        return out
    }

    /// Optimal string alignment distance (an adjacent transposition costs 1), or `max + 1` once it exceeds `max`.
    static func editDistance(_ a: String, _ b: String, max: Int) -> Int {
        let a = Array(a.utf16), b = Array(b.utf16)
        if abs(a.count - b.count) > max { return max + 1 }
        if a.isEmpty || b.isEmpty { return Swift.max(a.count, b.count) }
        var twoBack = [Int](repeating: 0, count: b.count + 1), previous = Array(0...b.count), current = twoBack
        for i in 1...a.count {
            current[0] = i
            var rowMin = i
            for j in 1...b.count {
                var d = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d = min(d, twoBack[j - 2] + 1) }
                current[j] = d
                rowMin = min(rowMin, d)
            }
            if rowMin > max { return max + 1 }
            (twoBack, previous, current) = (previous, current, twoBack)
        }
        return previous[b.count] <= max ? previous[b.count] : max + 1
    }

    // MARK: Snippets

    struct Match {
        let start: Int
        let end: Int
        var mask: Int
    }

    static func popcount(_ mask: Int) -> Int { mask.nonzeroBitCount }

    private static func densestCluster(_ matches: [Match], length: Int) -> [Match] {
        var best = Array(matches.prefix(1)), bestScore = -1
        for i in matches.indices {
            var mask = 0, j = i
            while j < matches.count, matches[j].end - matches[i].start <= length {
                mask |= matches[j].mask
                let score = popcount(mask) * 1000 + j - i
                if score > bestScore { (bestScore, best) = (score, [matches[i], matches[j]]) }
                j += 1
            }
        }
        return best
    }

    /// ~`length` units of `text` centred on the cluster covering the most distinct query terms, cut at spaces, with an
    /// ellipsis on each cut side. Highlights index into the returned snippet. `text` is whitespace-collapsed.
    static func snippet(_ text: String, _ matches: [Match], length: Int = 160) -> (snippet: String, highlights: [Range<Int>]) {
        let u = Array(text.utf16)
        if u.count <= length { return (text, matches.map { $0.start..<$0.end }) }
        let cluster = densestCluster(matches, length: length)
        let cs = cluster.first?.start ?? 0, ce = cluster.last?.end ?? 0
        var start = cs, end = cs + length
        if ce - cs < length {
            let room = length - (ce - cs)
            end = min(u.count, max(0, cs - room / 2) + length)
            start = end - length
        }
        let space: UInt16 = 0x20
        if start > 0 { while start < cs, u[start - 1] != space { start += 1 } }
        while start < cs, u[start] == space { start += 1 }
        if end < u.count { while end > ce, u[end] != space { end -= 1 } }
        while end > ce, u[end - 1] == space { end -= 1 }
        if end <= start { end = min(u.count, start + length) }
        let prefix = start > 0 ? "…" : "", suffix = end < u.count ? "…" : ""
        let shift = prefix.utf16.count - start
        let highlights = matches.compactMap { m -> Range<Int>? in
            let from = max(m.start, start), to = min(m.end, end)
            return from < to ? (from + shift)..<(to + shift) : nil
        }
        return (prefix + String(decoding: u[start..<end], as: UTF16.self) + suffix, highlights)
    }

    static func clean(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
}
