import Foundation
import Synchronization

/// One entry found by `Ledger.search`.
public struct SearchHit: Sendable, Hashable, Identifiable {
    public var id: String { entryId }
    public let entryId: String
    public let kind: EntryKind
    public let localDay: String
    public let capturedAt: Date
    /// The user's title, a writing's first line, the AI title (cleared entries only) or a still's caption.
    /// Nil means the app shows the kind's noun.
    public let title: String?
    /// One line of the entry's words around the densest cluster of matches.
    public let snippet: String
    /// What Copy text copies (SearchPalette.tsx): the transcript, body or caption, else the summary or title shown above.
    public let copyText: String
    /// UTF-16 ranges of the matched words in `snippet` and in `title`.
    public var highlights: [Range<Int>] = []
    public var titleHighlights: [Range<Int>] = []
    /// The meta column: a recording's length ("1:24").
    public var meta: String?
}

extension Ledger {
    private static let cache = Mutex<(ledger: ObjectIdentifier, changes: Int, index: SearchIndex)?>(nil)

    /// Live entries matching `query` through the web's engine (stems, prefixes while typing, typos, field weights,
    /// phrase and recency boosts; every word when it can, else the most), best first. An empty query returns the newest
    /// entries. Saro's own text (titles, summaries, still descriptions, moods) is indexed only for an entry the gate
    /// cleared for its current text, on a day that isn't held, so held or unchecked entries are never found or shown by
    /// generated words.
    public func search(_ query: String, kind: EntryKind? = nil, limit: Int = 50) throws -> [SearchHit] {
        let index = try searchIndex()
        guard !SearchText.tokenize(query).isEmpty else {
            return index.docs.filter { kind == nil || $0.kind == kind }.prefix(limit).map { Self.hit($0, snippet: String(SearchIndex.lead($0).prefix(160))) }
        }
        return index.search(query, kinds: kind.map { [$0] }, limit: limit).map { r in
            var h = Self.hit(r.doc, snippet: r.snippet)
            h.highlights = r.highlights
            h.titleHighlights = r.titleHighlights
            return h
        }
    }

    /// The index, rebuilt only when the journal changed since it was built: every write goes through this connection,
    /// so its change count is a cheap version (the web keeps its index live per session the same way).
    private func searchIndex() throws -> SearchIndex {
        let changes = try db.run("SELECT total_changes() AS n").first?.int("n") ?? 0
        let me = ObjectIdentifier(self)
        if let c = Self.cache.withLock({ $0 }), c.ledger == me, c.changes == changes { return c.index }
        let built = SearchIndex(try searchDocs())
        Self.cache.withLock { $0 = (me, changes, built) }
        return built
    }

    private static func hit(_ d: SearchDoc, snippet: String) -> SearchHit {
        SearchHit(entryId: d.id, kind: d.kind, localDay: d.day, capturedAt: d.capturedAt, title: d.title, snippet: snippet,
                  copyText: d.copySource ?? d.summary ?? d.title ?? "", meta: d.meta)
    }

    /// Every live entry, newest first, as the web's search-docs.ts builds it.
    func searchDocs() throws -> [SearchDoc] {
        let held = try heldDays()
        let rows = try db.run("""
            SELECT e.id, e.kind, e.local_day, e.captured_at, e.title_user, e.caption_user, e.body, m.duration_ms,
              v.verdict, v.text_sha256, r.input_hash, a.title AS ai_title, a.summary AS ai_summary, a.caption AS ai_caption,
              a.mood_label,
              (SELECT group_concat(w.text, ' ' ORDER BY w.idx) FROM transcript_word w WHERE w.media_id = e.media_id
                 AND w.extractor_version = (SELECT extractor_version FROM transcript_word WHERE media_id = e.media_id
                                            ORDER BY rowid DESC LIMIT 1)) AS transcript
            FROM live_entry e
            LEFT JOIN media_asset m ON m.id = e.media_id
            LEFT JOIN entry_annotation a ON a.rowid = (SELECT MAX(rowid) FROM entry_annotation WHERE entry_id = e.id)
            LEFT JOIN ai_run r ON r.id = a.ai_run_id
            LEFT JOIN safety_verdict v ON v.rowid = (SELECT MAX(rowid) FROM safety_verdict WHERE entry_id = e.id)
            ORDER BY e.captured_at DESC
            """)
        return rows.map { r in
            let text = { (k: String) in r.str(k).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } }
            let kind = EntryKind(rawValue: r.str("kind") ?? "") ?? .reflection
            let day = r.str("local_day") ?? ""
            let body = text("body"), caption = text("caption_user")
            let cleared = Self.cleared(r, kind, held: held)
            let saro = { (k: String) in cleared ? text(k) : nil }
            var doc = SearchDoc(id: r.str("id") ?? "", kind: kind, day: day, capturedAt: r.date("captured_at") ?? .distantPast,
                                title: text("title_user"), summary: saro("ai_summary"), transcript: text("transcript"))
            doc.copySource = text("transcript") ?? body ?? caption
            switch kind {
            case .moment, .voice:
                doc.title = doc.title ?? saro("ai_title")
                doc.tags = [saro("mood_label")].compactMap { $0 }
                doc.meta = r.int("duration_ms").flatMap(Self.clock)
            case .reflection:
                doc.body = body
                // A writing's first line is its title when it has more than one; the rest is its body.
                if doc.title == nil, let body, body.contains("\n"), let first = body.split(separator: "\n").first {
                    doc.title = String(first.prefix(80))
                    doc.body = String(body.dropFirst(first.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                doc.title = doc.title ?? saro("ai_title")
            case .still:
                doc.title = doc.title ?? caption ?? saro("ai_caption")
                doc.extra = [caption, saro("ai_caption")].compactMap { $0 }.joined(separator: " · ")
            case .music:
                doc.title = doc.title ?? saro("ai_title")
                doc.body = body
            }
            return doc
        }
    }

    /// Days a safety hold covers (SR-13): an entry's newest verdict holds, or the person's answer or mood note does.
    func heldDays() throws -> Set<String> {
        Set(try db.run("""
            SELECT e.local_day AS d FROM live_entry e JOIN safety_verdict v
              ON v.rowid = (SELECT MAX(rowid) FROM safety_verdict WHERE entry_id = e.id)
            WHERE v.verdict NOT IN ('clear','unavailable_clear','technical_hold','unavailable_caution')
            UNION SELECT local_day FROM reflection_turn WHERE answer_verdict = 'safety_hold'
            UNION SELECT local_day FROM day_state WHERE mood_note_verdict = 'safety_hold'
            """).compactMap { $0.str("d") })
    }

    /// A recording's length as m:ss (search-docs.ts's clock).
    static func clock(_ ms: Int) -> String? {
        guard ms > 0 else { return nil }
        let s = Int((Double(ms) / 1000).rounded())
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}

extension LocalDay {
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september",
                                 "october", "november", "december"]

    /// The day a typed date names, as `YYYY-MM-DD`, or nil: "today", "yesterday", "3 days ago", "fri" (the latest on
    /// or before today), "last fri" (strictly before today), "12 oct" / "oct 12th" (last year's if this year's is
    /// still ahead) and "2026-10-12".
    public static func parse(_ text: String, now: Date = .now) -> String? {
        let t = text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let today = string(for: now)
        // Three letters tell any two weekdays (or months) apart.
        let named = { (names: [String], word: Substring) in word.count >= 3 ? names.firstIndex { $0.hasPrefix(word) } : nil }
        let valid = { (day: String) in date(day).map { string(for: $0) } == day ? day : nil }
        if t == "today" { return today }
        if t == "yesterday" { return adding(-1, to: today) }
        if let m = t.wholeMatch(of: /(\d{1,4}) days? ago/), let n = Int(m.1) { return adding(-n, to: today) }
        if t.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil { return valid(t) }
        if let m = t.wholeMatch(of: /(last )?([a-z]+)/), let dow = named(weekdays, m.2) {
            let back = (Calendar(identifier: .gregorian).component(.weekday, from: now) - 1 - dow + 7) % 7
            return adding(-(back == 0 && m.1 != nil ? 7 : back), to: today)
        }
        let parts: (day: Substring, month: Substring)? =
            if let m = t.wholeMatch(of: /(\d{1,2})(?:st|nd|rd|th)? ([a-z]+)/) { (m.1, m.2) }
            else if let m = t.wholeMatch(of: /([a-z]+) (\d{1,2})(?:st|nd|rd|th)?/) { (m.2, m.1) }
            else { nil }
        guard let parts, let month = named(months, parts.month), let day = Int(parts.day),
              let year = Int(today.prefix(4)) else { return nil }
        for y in [year, year - 1] {
            guard let d = valid(String(format: "%04d-%02d-%02d", y, month + 1, day)) else { return nil }
            if d <= today { return d }
        }
        return nil
    }
}
