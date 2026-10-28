import Foundation

/// The line about the day's newest entry at the top of "What Saro noticed" (FR-REF-04): built in code around the stored
/// verbatim words, never generated.
public struct LastInferred: Sendable, Hashable, Codable {
    public var kind: EntryKind
    public var entryId: String
    public var message: String
    /// The words the line quotes, if any.
    public var quote: Candidate?
}

/// The day's narrative (ai.ts draftInsight, the D-13 template): titles, a subtitle and body lines that only count and
/// quote. The model's narrative may stand in for the subtitle once it passes the drift check.
public struct Narrative: Sendable, Hashable, Codable {
    public var title: String
    public var subtitle: String
    public var body: [String]
    public var lastInferred: LastInferred?
    /// The phrase the subtitle quotes, so the letter can link it to its entry.
    public var quote: Candidate?

    /// Every line shown, for the layer-3 output gate (SR-08).
    public var prose: String { ([title, subtitle] + body + [lastInferred?.message ?? ""]).joined(separator: "\n") }

    /// The narrative's own quotes, numbered apart from the reading's candidates.
    public var quotes: [Candidate] { [quote, lastInferred?.quote].compactMap { $0 } }
}

/// One entry as the narrative reads it: its gate-cleared words (empty for a still or a song, as on the web), its stored
/// quote, and a still's caption or a song's title.
public struct NarrativeEntry: Sendable, Hashable {
    public var id: String
    public var kind: EntryKind
    public var day: String
    public var text: String
    public var field: String
    public var quote: Candidate?
    public var label: String?

    public init(id: String, kind: EntryKind, day: String, text: String = "", field: String = "body", quote: Candidate? = nil,
                label: String? = nil) {
        self.id = id
        self.kind = kind
        self.day = day
        self.text = text
        self.field = field
        self.quote = quote
        self.label = label
    }
}

public enum DayNarrative {
    static let narrativeQuoteIndex = -1
    static let lastQuoteIndex = -2

    private static let counts = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
    private static let order: [EntryKind] = [.reflection, .moment, .voice, .still, .music]
    private static let nouns: [EntryKind: (String, String, String)] = [
        .reflection: ("a", "reflection", "reflections"), .moment: ("a", "moment", "moments"), .voice: ("an", "echo", "echoes"),
        .still: ("a", "still", "stills"), .music: ("a", "song", "songs"),
    ]

    /// The narrative for `day`'s entries, oldest first; `recent` holds the 13 days before it (clear days only), for
    /// "Work has come up on 3 of the last 14 days". `avoidTitle` rotates to the next title (Refresh narrative).
    public static func draft(day: String, entries: [NarrativeEntry], recent: [NarrativeEntry], avoidTitle: String? = nil) -> Narrative? {
        guard let newest = entries.last else { return nil }
        let corpus = entries.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
        let signals = Heuristics.analyzeText(corpus)
        let seed = Heuristics.seed("\(day)\n\(corpus)\n\(entries.map(\.kind.rawValue).joined(separator: ","))")
        let a = signals.themes.first
        let b = signals.themes.dropFirst().first
        let labelA = a?.rawValue ?? "", labelB = b?.rawValue ?? ""
        let countA = a.flatMap { signals.themeCounts[$0] } ?? 0
        let focus = a.map { a in signals.focus.filter { Lexicon.themeIndex[$0] == a || Lexicon.emotionIndex[$0] != nil } } ?? signals.focus
        // A phrase cut off from the guard word that let its entry pass would trip the gate on its own.
        let phrase = corpus.isEmpty ? nil : Heuristics.extractPhrase(corpus, focus: focus).flatMap { SafetyGate.phraseHit($0) ? nil : $0 }
        let source = phrase.flatMap { p in entries.first { $0.text.contains(p) } }
        let said = source.map { $0.kind != .reflection } == true ? "said" : "wrote"
        let prior = a.flatMap { a in recent.last { mentions($0, a) } }
        let verb = prior?.kind == .reflection ? "wrote" : "talked"
        let priorDay = prior.map { label($0.day) } ?? ""
        let n = entries.count
        let count = n < counts.count ? counts[n] : "\(n)"
        let moments = n == 1 ? "moment" : "moments"
        let kinds = listKinds(entries)

        let titles = if a != nil, b != nil {
            ["A day of \(labelA) and \(labelB).", "\(cap(labelA)) and \(labelB), side by side.", "Moving between \(labelA) and \(labelB)."]
        } else if a != nil, countA > 1 {
            ["A day shaped by \(labelA).", "\(cap(labelA)) kept coming back.", "Circling \(labelA)."]
        } else if a != nil {
            ["A day that touched on \(labelA).", "A note on \(labelA).", "\(cap(labelA)), briefly."]
        } else {
            ["A day in \(count) \(moments).", "\(cap(count)) \(moments), kept.", "What you kept: \(kinds)."]
        }
        let subtitles = if let phrase, prior != nil {
            ["You \(said) \"\(phrase)\". You also \(verb) about \(labelA) on \(priorDay).",
             "\(cap(labelA)) came up on \(priorDay) too. This time you \(said) \"\(phrase)\".",
             "In your words: \"\(phrase)\". You \(verb) about \(labelA) on \(priorDay) as well."]
        } else if let phrase {
            ["You \(said) \"\(phrase)\".", "In your words: \"\(phrase)\".", "You put it like this: \"\(phrase)\"."]
        } else if prior != nil {
            ["You also \(verb) about \(labelA) on \(priorDay)."]
        } else {
            ["You added \(kinds)."]
        }

        var k = seed % titles.count
        for _ in titles where titles[k] == avoidTitle { k = (k + 1) % titles.count }

        var body = ["You added \(kinds)."]
        if let a {
            let countB = b.flatMap { signals.themeCounts[$0] } ?? 0
            body.append("\(cap(labelA)) came up \(times(countA))\(b != nil ? ", \(labelB) \(times(countB))" : "").")
            if prior != nil {
                let days = Set(recent.filter { mentions($0, a) }.map(\.day)).count + 1
                body.append("\(cap(labelA)) has come up on \(days) of the last 14 days, most recently \(priorDay).")
            } else {
                body.append("This is the first time \(labelA) has come up in the last two weeks.")
            }
        } else {
            let words = signals.keywords.filter { !SafetyGate.phraseHit($0) }.prefix(3)
            if !words.isEmpty { body.append("Words that stood out: \(words.joined(separator: ", ")).") }
        }
        let subtitle = subtitles[k % subtitles.count]
        return Narrative(title: titles[k], subtitle: subtitle, body: body.first == subtitle ? Array(body.dropFirst()) : body,
                         lastInferred: lastInferred(newest),
                         quote: source.flatMap { quote(phrase!, in: $0, index: narrativeQuoteIndex) })
    }

    /// lastInferredFor: the newest entry's kind and its stored words, at most 150 characters.
    public static func lastInferred(_ e: NarrativeEntry) -> LastInferred {
        let q = e.quote?.text
        var quoted = e.quote.map { Candidate(index: lastQuoteIndex, entryId: e.id, field: $0.field, text: $0.text, utf16From: $0.utf16From,
                                             utf16To: $0.utf16To) }
        let message: String
        switch e.kind {
        case .reflection: message = q.map { "You wrote \"\($0)\"." } ?? "You wrote a reflection."
        case .moment: message = q.map { "You said \"\($0)\" on camera." } ?? "You recorded a moment."
        case .voice: message = q.map { "You said \"\($0)\"." } ?? "You left yourself an echo."
        case .still:
            let caption = e.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            message = caption.isEmpty ? "You kept a still." : "You kept a still: \"\(caption)\""
            quoted = caption.isEmpty ? nil : Candidate(index: lastQuoteIndex, entryId: e.id, field: "caption_user", text: caption,
                                                       utf16From: 0, utf16To: caption.utf16.count)
        case .music:
            let title = e.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            message = title.isEmpty ? "You added a song." : "You added \"\(title)\"."
            quoted = nil
        }
        return LastInferred(kind: e.kind, entryId: e.id, message: message.count > 150 ? String(message.prefix(148)) + "…" : message, quote: quoted)
    }

    /// "two reflections and a moment".
    static func listKinds(_ entries: [NarrativeEntry]) -> String {
        let parts = order.compactMap { kind -> String? in
            let n = entries.filter { $0.kind == kind }.count
            guard n > 0, let (article, one, many) = nouns[kind] else { return nil }
            return n == 1 ? "\(article) \(one)" : "\(n) \(many)"
        }
        guard let last = parts.last else { return "" }
        return parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + last : last
    }

    /// "Tue 22 Sep" (formatDayLabel), in English like the rest of the copy.
    public static func label(_ day: String) -> String {
        guard let d = LocalDay.date(day) else { return day }
        let c = Calendar(identifier: .gregorian).dateComponents([.weekday, .day, .month], from: d)
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(weekdays[(c.weekday ?? 1) - 1]) \(c.day ?? 0) \(months[(c.month ?? 1) - 1])"
    }

    static func times(_ n: Int) -> String { n == 1 ? "once" : n == 2 ? "twice" : "\(n) times" }
    static func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    private static func mentions(_ e: NarrativeEntry, _ theme: Theme) -> Bool {
        !e.text.isEmpty && Heuristics.analyzeText(e.text).themes.contains(theme)
    }

    private static func quote(_ phrase: String, in e: NarrativeEntry, index: Int) -> Candidate? {
        let r = (e.text as NSString).range(of: phrase)
        guard r.location != NSNotFound else { return nil }
        return Candidate(index: index, entryId: e.id, field: e.field, text: phrase, utf16From: r.location, utf16To: NSMaxRange(r))
    }
}
