import Foundation

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
    /// One line of the entry's words, starting a few words before the first match.
    public let snippet: String
}

extension Ledger {
    /// Live entries containing every word of `query` (case- and diacritic-insensitive), best first: a title match
    /// outranks a summary match, which outranks body, caption or transcript; ties go to the newest. An empty query
    /// returns the newest entries. AI text is read only for entries whose newest verdict is `clear` or
    /// `unavailable_clear`, so a held entry is never found (or shown) by generated words.
    // ponytail: a full scan per keystroke; FTS5 once journals outgrow it (BRD: alpha search is a lexical filter).
    public func search(_ query: String, kind: EntryKind? = nil, limit: Int = 50) throws -> [SearchHit] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let rows = try db.run("""
            SELECT e.id, e.kind, e.local_day, e.captured_at, e.title_user, e.caption_user, e.body,
              CASE WHEN v.verdict IN ('clear','unavailable_clear') THEN a.title END AS ai_title,
              CASE WHEN v.verdict IN ('clear','unavailable_clear') THEN a.summary END AS ai_summary,
              (SELECT group_concat(w.text, ' ' ORDER BY w.idx) FROM transcript_word w WHERE w.media_id = e.media_id
                 AND w.extractor_version = (SELECT extractor_version FROM transcript_word WHERE media_id = e.media_id
                                            ORDER BY rowid DESC LIMIT 1)) AS transcript
            FROM live_entry e
            LEFT JOIN entry_annotation a ON a.rowid = (SELECT MAX(rowid) FROM entry_annotation WHERE entry_id = e.id)
            LEFT JOIN safety_verdict v ON v.rowid = (SELECT MAX(rowid) FROM safety_verdict WHERE entry_id = e.id)
            WHERE ?1 IS NULL OR e.kind = ?1
            ORDER BY e.captured_at DESC
            LIMIT ?2
            """, [kind.map { .text($0.rawValue) } ?? .null, .int(words.isEmpty ? Int64(limit) : -1)])

        var found: [(score: Int, hit: SearchHit)] = []
        for r in rows {
            let text = { (k: String) in r.str(k).flatMap { $0.isEmpty ? nil : $0 } }
            let kind = EntryKind(rawValue: r.str("kind") ?? "") ?? .reflection
            let body = text("body")
            let firstLine = kind == .reflection && body?.contains("\n") == true
                ? body?.split(separator: "\n").first.map { String($0.prefix(80)) } : nil
            let title = text("title_user") ?? firstLine ?? text("ai_title") ?? (kind == .still ? text("caption_user") : nil)
            let fields: [(text: String?, weight: Int)] = [(title, 3), (text("ai_summary"), 2), (body, 1),
                                                          (text("caption_user"), 1), (text("transcript"), 1)]
            var score = 0
            for w in words {
                let best = fields.filter { $0.text?.localizedStandardContains(w) == true }.map(\.weight).max() ?? 0
                if best == 0 { score = 0; break }
                score += best
            }
            guard words.isEmpty || score > 0 else { continue }
            let sources = [body, text("transcript"), text("caption_user"), text("ai_summary")].compactMap { $0 }
            let match = words.lazy.compactMap { w in sources.first { $0.localizedStandardContains(w) }.map { ($0, w) } }.first
            let snippet = match.map { Self.snippet($0.0, around: $0.1, dropping: title) }
                ?? Self.snippet(text("ai_summary") ?? body ?? text("transcript") ?? text("caption_user") ?? "", around: nil, dropping: title)
            found.append((score, SearchHit(entryId: r.str("id") ?? "", kind: kind, localDay: r.str("local_day") ?? "",
                                           capturedAt: r.date("captured_at") ?? .distantPast, title: title, snippet: snippet)))
        }
        return found.sorted { $0.score != $1.score ? $0.score > $1.score : $0.hit.capturedAt > $1.hit.capturedAt }
            .prefix(limit).map(\.hit)
    }

    /// `text` on one line, without a leading repeat of the title, starting at most ~24 characters (at a word
    /// boundary) before the first match of `word`.
    static func snippet(_ text: String, around word: String?, dropping title: String?) -> String {
        var flat = Substring(text.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        if let title, let r = flat.range(of: title, options: [.anchored, .caseInsensitive]) {
            flat = flat[r.upperBound...].drop { " .,;:!?…—–-".contains($0) }
        }
        guard let word, let r = flat.localizedStandardRange(of: word),
              flat.distance(from: flat.startIndex, to: r.lowerBound) > 24 else { return String(flat.prefix(160)) }
        var cut = flat.index(r.lowerBound, offsetBy: -24)
        while cut < r.lowerBound, flat[flat.index(before: cut)] != " " { cut = flat.index(after: cut) }
        return "…" + flat[cut...].prefix(160)
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
