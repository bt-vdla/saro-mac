import Foundation

/// Saro's evening letter (port of `components/insights/letter.ts`): the day reading typeset. Nothing here is generated;
/// only the template sentences and sign-off are added around the user's words. Codable, so a kept letter reads the same.
public struct Letter: Sendable, Hashable, Codable {
    public var paragraphs: [String]
    public var mood: Mood
    public var question: String?
    public var quotes: [Candidate]
    public var signOff = "— Saro"

    /// composeLetter: the narrative's title and subtitle (the model's narrative in its place, once it passed the drift
    /// check), then its body, up to three paragraphs. A reading without a narrative falls back to the model's narrative
    /// or a template sentence from its picked quotes; nil with neither. `mood` is the person's own when they set one.
    public init?(reading: DayReading, candidates: [Candidate], narrative: Narrative? = nil, mood: Mood? = nil) {
        var quotes = reading.quoteIndexes.compactMap { i in candidates.first { $0.index == i } }
        if let q = narrative?.quote, !quotes.contains(where: { $0.text == q.text }) { quotes.append(q) }
        let model = reading.narrative?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = narrative, !n.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let opening = [n.title, model?.isEmpty == false ? model! : n.subtitle].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: " ")
            paragraphs = Array(([opening] + n.body.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter { !$0.isEmpty }.prefix(3))
        } else {
            guard let opening = model?.isEmpty == false ? model : Self.template(quotes) else { return nil }
            paragraphs = [opening]
        }
        self.mood = mood ?? reading.mood
        question = reading.question?.trimmingCharacters(in: .whitespacesAndNewlines)
        if question?.isEmpty == true { question = nil }
        self.quotes = quotes
    }

    /// Quotes the paragraphs don't already hold, so the letter still gives them back (unplacedQuotes).
    public var unplacedQuotes: [Candidate] {
        quotes.filter { q in !paragraphs.contains { $0.contains(q.text) || Self.typeset($0).contains(Self.typeset(q.text)) } }
    }

    /// Whether today's letter notification should be waiting (FR-REF-09): only once a ready reading exists, never on a
    /// held day or one awaiting a check (SR-13, SR-14), and not once the letter has been read.
    public enum Notice: Sendable, Hashable { case schedule(Date), cancel, none }

    public static func notice(status: DayStatus, hasLetter: Bool, opened: Bool, letterAt: Date, now: Date = .now) -> Notice {
        switch status {
        case .held, .awaitingCheck: return .cancel
        case .ready where opened: return .cancel
        case .ready where hasLetter && letterAt > now: return .schedule(letterAt)
        default: return .none
        }
    }

    private static func template(_ quotes: [Candidate]) -> String? {
        guard let last = quotes.last else { return nil }
        let quoted = quotes.map { "\"\($0.text)\"" }
        let list = quoted.count == 1 ? quoted[0] : quoted.dropLast().joined(separator: ", ") + " and " + quoted[quoted.count - 1]
        return "In your words today: \(list)" + (".!?।".contains(last.text.last ?? " ") ? "" : ".")
    }

    public struct Segment: Sendable, Hashable {
        public var text: String
        public var quote: Candidate?
    }

    /// Splits text, typeset or not, so each quoted phrase (with its quote marks, when it has them) is its own segment.
    public static func segments(_ text: String, quotes: [Candidate]) -> [Segment] {
        var out: [Segment] = []
        var rest = Substring(text)
        while true {
            var best: (range: Range<Substring.Index>, quote: Candidate)?
            for q in quotes {
                let needles = ["\"\(q.text)\"", "“\(q.text)”", q.text]
                guard let r = (needles + needles.map(typeset)).lazy.compactMap({ rest.range(of: $0) }).first else { continue }
                if best.map({ r.lowerBound < $0.range.lowerBound }) ?? true { best = (r, q) }
            }
            guard let best else { break }
            if best.range.lowerBound > rest.startIndex { out.append(Segment(text: String(rest[..<best.range.lowerBound]))) }
            out.append(Segment(text: String(rest[best.range]), quote: best.quote))
            rest = rest[best.range.upperBound...]
        }
        if !rest.isEmpty { out.append(Segment(text: String(rest))) }
        return out
    }

    /// Curly quotes and apostrophes, for type set in Newsreader.
    public static func typeset(_ s: String) -> String {
        s.replacingOccurrences(of: #"(^|[\s(\[{—–-])""#, with: "$1“", options: .regularExpression)
            .replacingOccurrences(of: "\"", with: "”")
            .replacingOccurrences(of: "'", with: "’")
    }
}
