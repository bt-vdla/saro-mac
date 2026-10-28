import Foundation

/// One searchable entry (the web's SearchDoc, built as search-docs.ts builds it).
public struct SearchDoc: Sendable, Hashable {
    public var id: String
    public var kind: EntryKind
    public var day: String
    public var capturedAt: Date
    public var title: String?
    public var summary: String?
    public var body: String?
    public var transcript: String?
    public var tags: [String] = []
    public var extra: String?
    /// The palette's meta column (a recording's length). Not indexed.
    public var meta: String?
    /// What Copy text copies: the person's own words. Not indexed.
    public var copySource: String?

    public init(id: String, kind: EntryKind, day: String, capturedAt: Date, title: String? = nil, summary: String? = nil,
                body: String? = nil, transcript: String? = nil, tags: [String] = [], extra: String? = nil, meta: String? = nil) {
        (self.id, self.kind, self.day, self.capturedAt) = (id, kind, day, capturedAt)
        (self.title, self.summary, self.body, self.transcript, self.tags, self.extra, self.meta) = (title, summary, body, transcript, tags, extra, meta)
    }
}

/// The web's in-memory engine (lib/search/engine.ts): BM25F over six weighted fields, stems, prefixes for the word
/// being typed, typo tolerance by edit distance, a phrase bonus for words in order, recency only as a tie-break, every
/// word when it can (else the most words), and a snippet around the densest cluster of matches.
public struct SearchIndex: Sendable {
    public enum Field: Int, Sendable, CaseIterable { case title, summary, body, transcript, tags, extra }

    public struct Result: Sendable {
        public let doc: SearchDoc
        public let score: Double
        public let field: Field
        public let snippet: String
        /// UTF-16 ranges into `snippet` and into the title.
        public let highlights: [Range<Int>]
        public let titleHighlights: [Range<Int>]
        public let matchedTerms: [String]
    }

    private static let weights: [Double] = [3, 2, 1, 1, 2, 1.5]
    private static let leadFields: [Field] = [.summary, .body, .transcript, .extra, .tags]
    private static let (k1, b) = (1.2, 0.75)
    private static let (exact, stemmed, prefixMin, prefixMax) = (1.0, 0.75, 0.45, 0.6)
    private static let fuzzy = [1.0, 0.35, 0.2]
    private static let (phraseBonus, recencyBoost, recencyScale) = (0.3, 0.01, 30.0 * 86_400)
    private static let (maxTerms, maxQuery, maxPrefixTerms, maxFuzzyTerms) = (12, 1000, 50, 25)
    // ponytail: per-field term frequency packed 5 bits a field (capped at 31), as the web does; BM25 saturates long before.
    private static let (tfBits, tfMax) = (5, 31)

    private struct Term {
        let text: String
        let stop: Bool
        let gramCount: Int
        var docs: [Int] = []
        var tfs: [Int] = []
    }

    private struct Doc {
        let doc: SearchDoc
        let time: Double
        let lengths: [Int]
        let sequence: [Int]
    }

    private var entries: [Doc] = []
    private var vocabulary: [String: Int] = [:]
    private var terms: [Term] = []
    private var stems: [String: [Int]] = [:]
    private var grams: [String: [Int]] = [:]
    private var fieldTokens = [Int](repeating: 0, count: 6)
    private var fieldDocs = [Int](repeating: 0, count: 6)

    public init(_ docs: [SearchDoc]) { for d in docs { add(d) } }

    /// Every entry, in the order given.
    public var docs: [SearchDoc] { entries.map(\.doc) }

    static func text(_ doc: SearchDoc, _ field: Field) -> String {
        switch field {
        case .title: doc.title ?? ""
        case .tags: doc.tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
        case .summary: SearchText.clean(doc.summary ?? "")
        case .body: SearchText.clean(doc.body ?? "")
        case .transcript: SearchText.clean(doc.transcript ?? "")
        case .extra: SearchText.clean(doc.extra ?? "")
        }
    }

    private mutating func termID(_ text: String) -> Int {
        if let id = vocabulary[text] { return id }
        let id = terms.count
        let g = SearchText.bigrams(text)
        terms.append(Term(text: text, stop: SearchText.stopwords.contains(text), gramCount: g.count))
        vocabulary[text] = id
        stems[SearchText.stem(text), default: []].append(id)
        for gram in g { grams[gram, default: []].append(id) }
        return id
    }

    private mutating func add(_ doc: SearchDoc) {
        var counts: [Int: Int] = [:], lengths: [Int] = [], ids: [Int] = []
        for f in Field.allCases {
            let tokens = SearchText.tokenize(Self.text(doc, f))
            let shift = Self.tfBits * f.rawValue
            for t in tokens {
                let id = termID(t.term)
                let packed = counts[id] ?? 0
                ids.append(id)
                if (packed >> shift) & Self.tfMax < Self.tfMax { counts[id] = packed + (1 << shift) }
            }
            lengths.append(tokens.count)
            if !tokens.isEmpty {
                fieldTokens[f.rawValue] += tokens.count
                fieldDocs[f.rawValue] += 1
            }
        }
        let index = entries.count
        entries.append(Doc(doc: doc, time: doc.capturedAt.timeIntervalSince1970, lengths: lengths, sequence: ids))
        for (id, packed) in counts {
            terms[id].docs.append(index)
            terms[id].tfs.append(packed)
        }
    }

    // MARK: Query

    private struct Query {
        let terms: [String]
        let literal: Bool
        let expansions: [[Int: Double]]
        let idf: [Double]
        let masks: [Int: Int]
    }

    private func byFrequency(_ a: Int, _ b: Int) -> Bool {
        let (x, y) = (terms[a], terms[b])
        return x.docs.count != y.docs.count ? x.docs.count > y.docs.count : x.text < y.text
    }

    private func fuzzyMatches(_ text: String, edits: Int, maxDf: Int) -> [(id: Int, distance: Int)] {
        let queryGrams = SearchText.bigrams(text)
        var shared: [Int: Int] = [:]
        for g in queryGrams { for id in grams[g] ?? [] { shared[id, default: 0] += 1 } }
        let length = text.count
        var found: [(id: Int, distance: Int)] = []
        for (id, n) in shared {
            let t = terms[id]
            guard !t.docs.isEmpty, t.docs.count <= maxDf, !t.stop, abs(t.text.count - length) <= edits,
                  // An edit breaks at most 3 padded bigrams, so a true match shares at least this many; the rest skip the DP.
                  n >= max(queryGrams.count, t.gramCount) - 3 * edits else { continue }
            let d = SearchText.editDistance(text, t.text, max: edits)
            if d > 0 && d <= edits { found.append((id, d)) }
        }
        found.sort { $0.distance != $1.distance ? $0.distance < $1.distance : byFrequency($0.id, $1.id) }
        return Array(found.prefix(Self.maxFuzzyTerms))
    }

    private func expand(_ text: String, prefix: Bool, literal: Bool) -> [Int: Double] {
        var out: [Int: Double] = [:]
        let usable = { (id: Int) in !terms[id].docs.isEmpty && (literal || !terms[id].stop) }
        func add(_ id: Int, _ w: Double) { if usable(id), w > (out[id] ?? 0) { out[id] = w } }
        if let id = vocabulary[text] { add(id, Self.exact) }
        if !literal { for id in stems[SearchText.stem(text)] ?? [] { add(id, Self.stemmed) } }
        if prefix, let first = text.first {
            let completions = (grams["^\(first)"] ?? []).filter { id in
                terms[id].text.count > text.count && terms[id].text.hasPrefix(text) && usable(id)
            }.sorted(by: byFrequency)
            for id in completions.prefix(Self.maxPrefixTerms) {
                add(id, Self.prefixMin + (Self.prefixMax - Self.prefixMin) * Double(text.count) / Double(terms[id].text.count))
            }
        }
        // A word that already matches only takes typo neighbours no more common than itself, so "mood" never drags in
        // every "good"; an unmatched word takes them all.
        let matchedDf = out.keys.map { terms[$0].docs.count }.max() ?? 0
        let edits = literal || text.contains(where: \.isNumber) ? 0 : SearchText.maxEdits(text.count)
        if edits > 0 {
            for m in fuzzyMatches(text, edits: edits, maxDf: matchedDf > 0 ? matchedDf : .max) { add(m.id, Self.fuzzy[m.distance]) }
        }
        return out
    }

    /// Every expansion shares the IDF of the best-matching (then most frequent) one, so rare typos don't inflate it.
    private func idf(_ expansion: [Int: Double]) -> Double {
        var best = 0.0, df = 0
        for (id, w) in expansion {
            let n = terms[id].docs.count
            if w > best || (w == best && n > df) { (best, df) = (w, n) }
        }
        return log(1 + (Double(entries.count - df) + 0.5) / (Double(df) + 0.5))
    }

    private func parse(_ raw: String) -> Query? {
        let tokens = SearchText.tokenize(String(raw.prefix(Self.maxQuery))).map(\.term)
        guard let last = tokens.last else { return nil }
        let content = tokens.filter { !SearchText.stopwords.contains($0) }
        let literal = content.isEmpty
        var qterms: [String] = []
        for t in literal ? tokens : content where qterms.count < Self.maxTerms && !qterms.contains(t) { qterms.append(t) }
        let expansions = qterms.map { expand($0, prefix: $0 == last, literal: literal) }
        var masks: [Int: Int] = [:]
        for (i, e) in expansions.enumerated() { for id in e.keys { masks[id, default: 0] |= 1 << i } }
        return Query(terms: qterms, literal: literal, expansions: expansions, idf: expansions.map(idf), masks: masks)
    }

    private func bm25f(_ packed: Int, _ lengths: [Int], _ avg: [Double]) -> Double {
        var weighted = 0.0, rest = packed, f = 0
        while rest != 0 {
            let tf = rest & Self.tfMax
            if tf > 0 { weighted += Self.weights[f] * Double(tf) / (1 - Self.b + Self.b * Double(lengths[f]) / avg[f]) }
            rest >>= Self.tfBits
            f += 1
        }
        return weighted * (Self.k1 + 1) / (weighted + Self.k1)
    }

    private struct Hit {
        let doc: Int
        var mask = 0
        var parts: [Double]
        var matched = 0
        var score = 0.0
    }

    /// Consecutive query-term pairs that appear in order, stopwords skipped.
    private func adjacentPairs(_ d: Doc, _ q: Query) -> Int {
        var found = 0, p = 0
        for length in d.lengths {
            var previous = 0
            for _ in 0..<length {
                let id = d.sequence[p]
                p += 1
                if !q.literal && terms[id].stop { continue }
                let mask = q.masks[id] ?? 0
                found |= previous & (mask >> 1)
                previous = mask
            }
        }
        return found.nonzeroBitCount
    }

    // MARK: Search

    /// The best `limit` matches for `query`, of `kinds` only when given.
    public func search(_ query: String, kinds: Set<EntryKind>? = nil, limit: Int = 20) -> [Result] {
        guard limit > 0, !entries.isEmpty, let q = parse(query) else { return [] }
        let avg = (0..<6).map { fieldDocs[$0] > 0 ? Double(fieldTokens[$0]) / Double(fieldDocs[$0]) : 1 }
        var hits: [Int: Hit] = [:]
        for (i, expansion) in q.expansions.enumerated() {
            for (id, weight) in expansion {
                let t = terms[id]
                for (p, d) in t.docs.enumerated() {
                    if let kinds, !kinds.contains(entries[d].doc.kind) { continue }
                    var hit = hits[d] ?? Hit(doc: d, parts: Array(repeating: 0, count: q.terms.count))
                    hit.mask |= 1 << i
                    hit.parts[i] = max(hit.parts[i], weight * q.idf[i] * bm25f(t.tfs[p], entries[d].lengths, avg))
                    hits[d] = hit
                }
            }
        }
        let full = (1 << q.terms.count) - 1
        let every = hits.values.filter { $0.mask == full }
        let any = every.isEmpty
        var chosen = any ? Array(hits.values) : every
        let newest = chosen.map { entries[$0.doc].time }.max() ?? 0
        for i in chosen.indices {
            let d = entries[chosen[i].doc]
            chosen[i].matched = chosen[i].mask.nonzeroBitCount
            var score = chosen[i].parts.reduce(0, +)
            if chosen[i].matched > 1 { score *= 1 + Self.phraseBonus * Double(adjacentPairs(d, q)) / Double(q.terms.count - 1) }
            score *= 1 + Self.recencyBoost / (1 + (newest - d.time) / Self.recencyScale)
            chosen[i].score = score
        }
        chosen.sort { a, b in
            if any && a.matched != b.matched { return a.matched > b.matched }
            if a.score != b.score { return a.score > b.score }
            let (x, y) = (entries[a.doc], entries[b.doc])
            return x.time != y.time ? x.time > y.time : x.doc.id < y.doc.id
        }
        return chosen.prefix(limit).map { result($0, q) }
    }

    /// Exact and stem matches share the top tier; prefix is next; fuzzy last.
    private static func tier(_ w: Double) -> Int { w >= stemmed ? 2 : w >= prefixMin ? 1 : 0 }

    private func result(_ hit: Hit, _ q: Query) -> Result {
        let doc = entries[hit.doc].doc
        let texts = Field.allCases.map { Self.text(doc, $0) }
        struct M { var m: SearchText.Match; let id: Int }
        let found: [[M]] = texts.map { text in
            SearchText.tokenize(text).compactMap { t in
                guard let id = vocabulary[t.term], let mask = q.masks[id], mask != 0 else { return nil }
                return M(m: SearchText.Match(start: t.start, end: t.end, mask: mask), id: id)
            }
        }
        let weight = { (m: M, i: Int) in q.expansions[i][m.id] ?? 0 }
        let each = { (mask: Int) in q.terms.indices.filter { mask & (1 << $0) != 0 } }
        var bestTier = [Int](repeating: 0, count: q.terms.count)
        for ms in found { for m in ms { for i in each(m.m.mask) { bestTier[i] = max(bestTier[i], Self.tier(weight(m, i))) } } }
        // Only each term's best tier in this entry is highlighted: "café" yes, its fuzzy neighbour "cake" no.
        let kept: [[M]] = found.map { ms in
            ms.compactMap { m in
                var k = m
                k.m.mask = each(m.m.mask).filter { Self.tier(weight(m, $0)) == bestTier[$0] }.reduce(0) { $0 | 1 << $1 }
                return k.m.mask != 0 ? k : nil
            }
        }
        var best = 0, bestScore = 0.0, source = -1, sourceScore = 0.0
        for (f, ms) in kept.enumerated() {
            var w = [Double](repeating: 0, count: q.terms.count)
            for m in ms { for i in each(m.m.mask) { w[i] = max(w[i], weight(m, i)) } }
            let score = Self.weights[f] * zip(w, q.idf).reduce(0) { $0 + $1.0 * $1.1 }
            let coverage = zip(w, q.idf).reduce(0) { $0 + ($1.0 > 0 ? $1.1 : 0) }
            if score > bestScore { (best, bestScore) = (f, score) }
            if f > 0 && coverage > sourceScore { (source, sourceScore) = (f, coverage) }
        }
        let lead = Self.leadFields.map { texts[$0.rawValue] }.first { !$0.isEmpty } ?? ""
        let s = source < 0 ? SearchText.snippet(lead, []) : SearchText.snippet(texts[source], kept[source].map(\.m))
        return Result(doc: doc, score: hit.score, field: Field(rawValue: best) ?? .title, snippet: s.snippet, highlights: s.highlights,
                      titleHighlights: kept[0].map { $0.m.start..<$0.m.end }, matchedTerms: q.terms.indices.filter { hit.mask & (1 << $0) != 0 }.map { q.terms[$0] })
    }

    /// The lead text a result with no query shows: the first non-empty of summary, body, transcript, extra and tags.
    static func lead(_ doc: SearchDoc) -> String { leadFields.map { text(doc, $0) }.first { !$0.isEmpty } ?? "" }
}
