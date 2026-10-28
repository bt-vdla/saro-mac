import Foundation

/// Saro's evening letter (port of `components/insights/letter.ts`): the day reading typeset. Nothing here is generated;
/// only the template sentence and sign-off are added around the user's words.
public struct Letter: Sendable, Hashable {
    public var paragraphs: [String]
    public var mood: Mood
    public var question: String?
    public var quotes: [Candidate]
    public var signOff = "— Saro"

    /// The narrative when the reading has one, else a template sentence from its picked quotes; nil with neither.
    public init?(reading: DayReading, candidates: [Candidate]) {
        let quotes = reading.quoteIndexes.compactMap { i in candidates.first { $0.index == i } }
        let narrative = reading.narrative?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let opening = narrative?.isEmpty == false ? narrative : Self.template(quotes) else { return nil }
        paragraphs = [opening]
        mood = reading.mood
        question = reading.question?.trimmingCharacters(in: .whitespacesAndNewlines)
        if question?.isEmpty == true { question = nil }
        self.quotes = quotes
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

    /// Splits text so each quoted phrase (with its quote marks, when it has them) is its own segment.
    public static func segments(_ text: String, quotes: [Candidate]) -> [Segment] {
        var out: [Segment] = []
        var rest = Substring(text)
        while true {
            var best: (range: Range<Substring.Index>, quote: Candidate)?
            for q in quotes {
                guard let r = ["\"\(q.text)\"", "“\(q.text)”", q.text].lazy.compactMap({ rest.range(of: $0) }).first else { continue }
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
