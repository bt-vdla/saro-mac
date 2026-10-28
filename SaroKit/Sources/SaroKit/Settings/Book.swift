import Foundation

/// The Book of the year (exportBook.ts buildBook): a self-contained HTML book, one chapter per month of the person's
/// words and the letters they kept. Every word is escaped; `dir="auto"` lets each line take its own direction. The
/// caller passes only what may be shown: never a held day's letter, never an AI title in place of the person's own.
public enum Book {
    public enum Kind: String, Sendable { case reflection = "Reflection", moment = "Moment", echo = "Echo", still = "Still", letter = "Letter" }

    public struct Piece: Sendable, Hashable {
        public var kind: Kind
        /// Local minutes after midnight, in the zone it was captured in; nil for a letter, which closes its day.
        public var minutes: Int?
        public var title: String?
        public var prompt: String?
        public var body: [String]

        public init(kind: Kind, minutes: Int?, title: String? = nil, prompt: String? = nil, body: [String]) {
            self.kind = kind
            self.minutes = minutes
            self.title = title?.jsTrim.isEmpty == false && !(title ?? "").jsTest(#"^Reflection\s+[–-]\s+"#) ? title?.jsTrim : nil
            self.prompt = prompt?.jsTrim.isEmpty == false ? prompt?.jsTrim : nil
            self.body = body
        }
    }

    /// One local day (`YYYY-MM-DD`) and what it holds.
    public struct Day: Sendable, Hashable {
        public var day: String
        public var pieces: [Piece]

        public init(day: String, pieces: [Piece]) {
            self.day = day
            self.pieces = pieces
        }
    }

    public static func fileName(_ year: Int) -> String { "saro-book-of-\(year).html" }

    public static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Lines of text, one paragraph per non-empty line.
    public static func paragraphs(_ texts: String?...) -> [String] {
        texts.compactMap { $0 }.joined(separator: "\n").split(whereSeparator: \.isNewline).map { String($0).jsTrim }.filter { !$0.isEmpty }
    }

    static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    static func render(_ p: Piece) -> String {
        let label = p.kind == .letter ? "Saro’s letter" : "\(p.kind.rawValue) · \(Rhythm.formatClock(p.minutes ?? 0))"
        return "<article class=\"piece\(p.kind == .letter ? " letter" : "")\"><p class=\"kind\">\(escape(label))</p>"
            + (p.title.map { "<h4 dir=\"auto\">\(escape($0))</h4>" } ?? "")
            + (p.prompt.map { "<p class=\"prompt\" dir=\"auto\">\(escape($0))</p>" } ?? "")
            + p.body.map { "<p dir=\"auto\">\(escape($0))</p>" }.joined() + "</article>"
    }

    static let style = """
    :root{color-scheme:light dark;--ink:#13201A;--ink2:#46524B;--ink3:#6B7570;--bg:#FBFAF6;--line:#E3E1D8;--voice:#B0501F}
    @media (prefers-color-scheme:dark){:root{--ink:#ECEFEA;--ink2:#C4CBC6;--ink3:#8E9892;--bg:#0F1713;--line:#26302B;--voice:#F2A078}}
    *{box-sizing:border-box}
    body{margin:0;background:var(--bg);color:var(--ink);font:18px/1.65 Newsreader,"New York",Georgia,serif;-webkit-font-smoothing:antialiased}
    main{max-width:36rem;margin:0 auto;padding:5rem 1.25rem 7rem}
    .eyebrow,.kind,.meta,.count{font:600 11px/1.3 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.12em;text-transform:uppercase;color:var(--ink3)}
    h1{font-weight:400;font-size:3.25rem;line-height:1.05;letter-spacing:-.025em;margin:.75rem 0 .5rem}
    .sub{font-style:italic;color:var(--ink2);margin:0 0 1.5rem}
    .contents{margin:3.5rem 0 0;padding:0;list-style:none;border-top:1px solid var(--line)}
    .contents li{display:flex;justify-content:space-between;gap:1rem;padding:.6rem 0;border-bottom:1px solid var(--line)}
    .contents a{color:inherit;text-decoration:none}
    .chapter{margin-top:6rem;break-before:page}
    .chapter>h2{font-weight:400;font-size:2.4rem;letter-spacing:-.02em;margin:0 0 .25rem}
    .day{font:600 13px/1.4 system-ui,sans-serif;color:var(--ink2);margin:3rem 0 0;padding-top:1rem;border-top:1px solid var(--line)}
    .piece{margin:1.5rem 0 0;break-inside:avoid}
    .piece p{margin:.35rem 0 0}
    .piece h4{font-weight:500;font-size:1.3rem;line-height:1.3;margin:.35rem 0 0}
    .prompt{font-style:italic;color:var(--ink2)}
    .letter{border-left:2px solid var(--voice);padding-left:1rem}
    .letter .kind{color:var(--voice)}
    .empty{font-style:italic;color:var(--ink2);margin-top:4rem}
    @media print{:root{--bg:#fff;--ink:#000}main{padding-top:0}}
    """

    /// The book for `year`: a title page, a contents list of months, and one chapter per month, oldest first.
    public static func build(year: Int, name: String?, days: [Day], madeAt: Date = .now, calendar: Calendar = .current) -> String {
        func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
        let kept = days.filter { $0.day.hasPrefix("\(year)-") }.sorted { $0.day < $1.day }.compactMap { d -> Day? in
            let pieces = d.pieces.filter { !$0.body.isEmpty || $0.title != nil }.sorted { ($0.minutes ?? 1440) < ($1.minutes ?? 1440) }
            return pieces.isEmpty ? nil : Day(day: d.day, pieces: pieces)
        }
        let all = kept.flatMap(\.pieces)
        let entries = all.filter { $0.kind != .letter }.count
        let letters = all.count - entries
        let byMonth = Dictionary(grouping: kept) { Int($0.day.split(separator: "-")[1]) ?? 1 }
        let monthNumbers = byMonth.keys.sorted()

        let chapters = monthNumbers.enumerated().map { chapter, m in
            let month = months[m - 1]
            let body = (byMonth[m] ?? []).map { d -> String in
                let date = LocalDay.date(d.day) ?? .now
                let weekday = weekdays[calendar.component(.weekday, from: date) - 1]
                let dayNumber = calendar.component(.day, from: date)
                return "<h3 class=\"day\">\(weekday) \(dayNumber) \(month)</h3>" + d.pieces.map(render).joined()
            }.joined()
            return "<section class=\"chapter\" id=\"m\(m)\"><p class=\"eyebrow\">Chapter \(chapter + 1)</p><h2>\(month)</h2>\(body)</section>"
        }
        let contents = monthNumbers.map { m in
            let n = (byMonth[m] ?? []).flatMap(\.pieces).filter { $0.kind != .letter }.count
            return "<li><a href=\"#m\(m)\">\(months[m - 1])</a><span class=\"count\">\(count(n, "entry", "entries"))</span></li>"
        }.joined()
        let made = "\(months[calendar.component(.month, from: madeAt) - 1].prefix(3)) \(calendar.component(.day, from: madeAt)), \(calendar.component(.year, from: madeAt))"
        let name = name?.jsTrim ?? ""

        return [
            "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">",
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
            "<title>Book of \(year)</title><style>\(style)</style></head><body><main>",
            "<header><p class=\"eyebrow\">Saro</p>",
            "<h1>Book of \(year)</h1>",
            "<p class=\"sub\">\(escape(name.isEmpty ? "Your year, in your own words." : "\(name), this is your year, in your own words."))</p>",
            "<p class=\"meta\">\(count(entries, "entry", "entries")) · \(count(letters, "letter", "letters")) · Made \(made)</p></header>",
            monthNumbers.isEmpty ? "<p class=\"empty\">Nothing written in \(year) yet.</p>" : "<ol class=\"contents\">\(contents)</ol>\(chapters.joined())",
            "</main></body></html>",
        ].joined()
    }
}
