import Foundation

/// A word and its UTF-16 offsets in the text it came from.
public struct Token: Sendable, Hashable {
    public let text: String
    public let lower: String
    public let start: Int
    public let end: Int
}

/// What `analyzeText` reads from an entry's own words.
public struct TextSignals: Sendable, Hashable {
    /// Ranked by hits, then first appearance.
    public var themes: [Theme]
    /// Moods with at least one un-negated hit, ranked by hits, then catalogue order.
    public var moods: [Mood]
    public var names: [String]
    /// Lowercase words that hit a lexicon, used to pick quotable phrases.
    public var focus: [String]
}

/// The heuristic twin ("In your words"): ports of `saro/frontend/lib/demo/ai.ts`. Every string is computed from or
/// copied out of the user's words, and the same input always gives the same output.
public enum Heuristics {
    public static let maxCandidates = 24

    // ai.ts's WORD_SOURCE, widened from Latin to every script so Devanagari entries get candidates too. A word starts on
    // a letter or digit, so it never begins inside a character such as the keycap "#️⃣".
    private static let wordRegex = try! NSRegularExpression(pattern: #"[\p{L}\p{N}][\p{L}\p{M}\p{N}]*(?:['’-][\p{L}\p{M}\p{N}]+)*"#)
    private static let sentenceRegex = try! NSRegularExpression(pattern: #"^.*?[.!?।](?=\s|$)"#)
    private static let rawSentenceRegex = try! NSRegularExpression(pattern: #"(?s)\S(?:.*?(?:[.!?।](?=\s|\z)|\S(?=\s*\z)))?"#)
    private static let titleClauseRegex = try! NSRegularExpression(pattern: #"[^,;:—–()]+"#)
    private static let phraseClauseRegex = try! NSRegularExpression(pattern: #"[^.!?।;:,\n—–()"“”]+"#)

    private static func all(_ text: String) -> NSRange { NSRange(location: 0, length: (text as NSString).length) }

    public static func tokenize(_ text: String) -> [Token] {
        let ns = text as NSString
        return wordRegex.matches(in: text, range: all(text)).map {
            let t = ns.substring(with: $0.range)
            return Token(text: t, lower: t.lowercased().replacingOccurrences(of: "’", with: "'"), start: $0.range.location,
                         end: NSMaxRange($0.range))
        }
    }

    public static func analyzeText(_ text: String) -> TextSignals {
        let ns = text as NSString
        let tokens = tokenize(text)
        var themeCounts: [Theme: Int] = [:], themeFirst: [Theme: Int] = [:], moodCounts: [Mood: Int] = [:]
        var focus: [String] = []
        var names: [String: (n: Int, first: Int)] = [:]
        for (i, t) in tokens.enumerated() {
            if let theme = Lexicon.themeIndex[t.lower] {
                themeCounts[theme, default: 0] += 1
                if themeFirst[theme] == nil { themeFirst[theme] = i }
                focus.append(t.lower)
            }
            let bigram = i + 1 < tokens.count ? Lexicon.emotionIndex["\(t.lower) \(tokens[i + 1].lower)"] : nil
            if let mood = bigram ?? Lexicon.emotionIndex[t.lower], !isNegated(tokens, i) {
                moodCounts[mood, default: 0] += 1
                focus.append(t.lower)
            }
            if isName(t, ns, tokens, i) { names[t.text, default: (0, i)].n += 1 }
        }
        let order = Mood.allCases
        return TextSignals(
            themes: themeCounts.keys.sorted { (themeCounts[$0]!, -themeFirst[$0]!) > (themeCounts[$1]!, -themeFirst[$1]!) },
            moods: moodCounts.keys.sorted {
                (moodCounts[$0]!, -order.firstIndex(of: $0)!) > (moodCounts[$1]!, -order.firstIndex(of: $1)!)
            },
            names: names.keys.sorted { (names[$0]!.n, -names[$0]!.first) > (names[$1]!.n, -names[$1]!.first) },
            focus: focus)
    }

    private static func isNegated(_ tokens: [Token], _ i: Int) -> Bool {
        tokens[max(0, i - 3)..<i].contains { Lexicon.negators.contains($0.lower) }
    }

    private static func startsSentence(_ ns: NSString, _ tokens: [Token], _ i: Int) -> Bool {
        guard i > 0 else { return true }
        let gap = ns.substring(with: NSRange(location: tokens[i - 1].end, length: tokens[i].start - tokens[i - 1].end))
        return gap.contains { ".!?\n".contains($0) }
    }

    private static func isName(_ t: Token, _ ns: NSString, _ tokens: [Token], _ i: Int) -> Bool {
        let s = Array(t.text.unicodeScalars.prefix(2))
        guard s.count == 2, ("A"..."Z").contains(s[0]), ("a"..."z").contains(s[1]) else { return false }
        return !startsSentence(ns, tokens, i) && !Lexicon.commonCaps.contains(t.lower)
    }

    private static func stripLeading(_ tokens: ArraySlice<Token>) -> ArraySlice<Token> {
        var out = tokens
        while true {
            if let first = out.first, Lexicon.leadingFiller.contains(first.lower) {
                out = out.dropFirst()
                continue
            }
            guard let hedge = Lexicon.hedges.first(where: { h in h.count <= out.count && zip(h, out).allSatisfy { $0 == $1.lower } })
            else { return out }
            out = out.dropFirst(hedge.count)
        }
    }

    private static func stripTrailing(_ tokens: ArraySlice<Token>, keep: Int = 2) -> ArraySlice<Token> {
        var out = tokens
        while out.count > keep, let last = out.last, Lexicon.trailingDangle.contains(last.lower) { out = out.dropLast() }
        return out
    }

    private static func capitalize(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// The first sentence, whitespace collapsed, cut at a word boundary (or else a whole character) to `max` UTF-16 units.
    public static func firstSentence(_ text: String, max: Int = 160) -> String {
        let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let sentence = sentenceRegex.firstMatch(in: clean, range: all(clean)).map { (clean as NSString).substring(with: $0.range) } ?? clean
        let ns = sentence as NSString
        if ns.length <= max { return sentence }
        var units = 0
        let cut = String(sentence.prefix { units += $0.utf16.count; return units < max }) as NSString
        let space = cut.range(of: " ", options: .backwards).location
        let kept = space != NSNotFound && space > max / 3 ? cut.substring(to: space) : cut as String
        return kept.replacingOccurrences(of: #"[\s,;:.!?-]+$"#, with: "", options: .regularExpression) + "…"
    }

    /// A summary worth showing: not empty, and not the title or the transcript's opening again (utils.ts).
    public static func summaryAddsSomething(_ summary: String, title: String?, transcript: String?) -> Bool {
        let plain = { (s: String) in
            s.lowercased().replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        let words = plain(summary)
        guard !words.isEmpty else { return false }
        if let title, plain(title) == words { return false }
        return !(transcript.map { plain($0).hasPrefix(words) } ?? false)
    }

    /// A title of at most `maxWords` from the first clause of the first sentence: fillers and hedges dropped, then
    /// articles and intensifiers if that makes it fit, otherwise cut at a clean word.
    public static func compressTitle(_ text: String, maxWords: Int = 7) -> String {
        let sentence = firstSentence(text, max: 1000)
        for m in titleClauseRegex.matches(in: sentence, range: all(sentence)) {
            var words = stripLeading(tokenize((sentence as NSString).substring(with: m.range))[...])
            if words.count > maxWords {
                var compact = Array(words), i = 0
                while i < compact.count && compact.count > maxWords {
                    if Lexicon.lowValue.contains(compact[i].lower) { compact.remove(at: i) } else { i += 1 }
                }
                words = compact.count <= maxWords ? compact[...] : stripTrailing(words.prefix(maxWords))
            }
            if words.count >= 2 { return capitalize(words.map(\.text).joined(separator: " ")) }
        }
        return capitalize(tokenize(text).prefix(maxWords).map(\.text).joined(separator: " "))
    }

    private struct Window {
        let score: Int
        let range: NSRange
    }

    /// One scored window per clause: the whole clause when it has at most maxWords + 2 words, otherwise the maxWords
    /// window with the most `focus` words (preferring windows that start on a subject).
    private static func windows(_ text: String, focus: Set<String>, maxWords: Int = 8) -> [Window] {
        let ns = text as NSString
        func hits(_ ts: ArraySlice<Token>) -> Int { ts.filter { focus.contains($0.lower) }.count }
        var out: [Window] = []
        for m in phraseClauseRegex.matches(in: text, range: all(text)) {
            let tokens = stripLeading(tokenize(ns.substring(with: m.range))[...])
            guard tokens.count >= 2 else { continue }
            var win = tokens
            let whole = tokens.count <= maxWords + 2
            if !whole {
                var from = tokens.startIndex, best = -1
                for s in tokens.startIndex...(tokens.endIndex - maxWords) {
                    let w = tokens[s..<s + maxWords]
                    let score = hits(w) * 10 + (s == tokens.startIndex || Lexicon.subjectStart.contains(w.first!.lower) ? 2 : 0)
                        + (s + maxWords == tokens.endIndex ? 1 : 0)
                    if score > best { (best, from) = (score, s) }
                }
                win = tokens[from..<from + maxWords]
                while from > tokens.startIndex, win.count > 2, Lexicon.leadingDangle.contains(win.first!.lower) { win = win.dropFirst() }
                if from + maxWords < tokens.endIndex { win = stripTrailing(win) }
            }
            guard win.count >= 2, let first = win.first, let last = win.last else { continue }
            let score = hits(win) * 3 + (win.count >= 3 ? 1 : 0) + (win.count >= 4 ? 1 : 0) + (whole ? 1 : 0)
            out.append(Window(score: score, range: NSRange(location: m.range.location + first.start, length: last.end - first.start)))
        }
        return out
    }

    /// A short verbatim phrase from `text`, always an exact substring of it.
    public static func extractPhrase(_ text: String, focus: [String] = [], maxWords: Int = 8) -> String? {
        var best: Window?
        for w in windows(text, focus: Set(focus), maxWords: maxWords) where w.score > best?.score ?? .min { best = w }
        return best.map { (text as NSString).substring(with: $0.range) }
    }

    /// An entry's own mood: the feeling its words name most, or nil when they name none or the phrase gate fires.
    public static func entryMoodFor(_ text: String) -> Mood? {
        guard !text.allSatisfy(\.isWhitespace), !SafetyGate.phraseHit(text) else { return nil }
        return analyzeText(text).moods.first
    }

    /// Up to 24 numbered verbatim phrases (§11.6): the best window of every clause plus the first sentence, in text order.
    /// `firstIndex` lets a caller number several entries' candidates as one list.
    public static func candidates(entryId: String, field: String, text: String, firstIndex: Int = 0) -> [Candidate] {
        let ns = text as NSString
        var ranges = windows(text, focus: Set(analyzeText(text).focus)).enumerated()
            .sorted { ($0.element.score, -$0.offset) > ($1.element.score, -$1.offset) }
            .prefix(maxCandidates - 1).map(\.element.range)
        // The first sentence, unless it is a single clause a window already holds.
        if let first = rawSentenceRegex.firstMatch(in: text, range: all(text))?.range, first.length <= 160,
           !ranges.contains(where: { ns.substring(with: $0) == ns.substring(with: first).trimmingCharacters(in: .punctuationCharacters) }) {
            ranges.append(first)
        }
        return ranges.sorted { ($0.location, $0.length) < ($1.location, $1.length) }.enumerated().map { i, r in
            Candidate(index: firstIndex + i, entryId: entryId, field: field, text: ns.substring(with: r), utf16From: r.location,
                      utf16To: NSMaxRange(r))
        }
    }

    /// The "In your words" twin of an entry reading.
    public static func heuristicReading(text: String, candidates: [Candidate]) -> EntryReading {
        let signals = analyzeText(text)
        let best = extractPhrase(text, focus: signals.focus)
        return EntryReading(title: compressTitle(text), summary: firstSentence(text), mood: signals.moods.first ?? .neutral,
                            quoteIndex: (candidates.first { $0.text == best } ?? candidates.first)?.index)
    }

    /// The "In your words" twin of a day reading: the most common entry mood, up to two quotes (from different entries
    /// when it can), no narrative, and a curated question for the day's themes.
    public static func heuristicDayReading(digests: [EntryDigest], candidates: [Candidate]) -> DayReading {
        let moods = digests.compactMap(\.mood)
        let counts = moods.reduce(into: [Mood: Int]()) { $0[$1, default: 0] += 1 }
        let mood = moods.first { counts[$0] == counts.values.max() } ?? .neutral

        // Most lexicon words first; on a tie the shorter phrase, then the earlier one.
        let scores = candidates.map { analyzeText($0.text).focus.count }
        let ranked = candidates.indices.sorted {
            (scores[$0], -candidates[$0].text.count, -$0) > (scores[$1], -candidates[$1].text.count, -$1)
        }.map { candidates[$0] }
        var picked: [Candidate] = []
        for c in ranked where picked.count < 2 && !picked.contains(where: { $0.entryId == c.entryId }) { picked.append(c) }
        for c in ranked where picked.count < 2 && !picked.contains(where: { overlaps($0, c) }) { picked.append(c) }

        let corpus = (candidates.map(\.text) + digests.flatMap { [$0.title, $0.summary] }).joined(separator: "\n")
        return DayReading(mood: mood, quoteIndexes: picked.map(\.index),
                          question: pickQuestion(themes: analyzeText(corpus).themes, seed: seed(corpus)))
    }

    private static func overlaps(_ a: Candidate, _ b: Candidate) -> Bool {
        a.entryId == b.entryId && a.field == b.field && a.utf16From < b.utf16To && b.utf16From < a.utf16To
    }

    /// A curated question from the top theme's pool, else the general pool (ai.ts `pickQuestion`, nothing excluded).
    public static func pickQuestion(themes: [Theme], seed: Int) -> String {
        let pool = Lexicon.questions[themes.first] ?? Lexicon.questions[nil]!
        return pool[seed % pool.count]
    }

    /// FNV-1a, so the same words always pick the same question across launches.
    static func seed(_ s: String) -> Int {
        Int(s.utf8.reduce(2_166_136_261 as UInt32) { ($0 ^ UInt32($1)) &* 16_777_619 })
    }
}
