import Foundation

/// What Saro read (aiLog.ts, BRD FR-SET-05): each ai_run said in words that hold no content: which feature, when,
/// how many entries and characters it read, where it ran, and how it ended. Never the words themselves; a refusal
/// shows only its category.
public enum AILog {
    public struct Row: Sendable, Hashable, Identifiable {
        public var id: String
        public var at: Date
        public var feature: String
        public var executor: String
        public var rung: String?
        public var status: String
        public var latencyMs: Int?
        /// The day the run read, when it read one.
        public var localDay: String?
        /// The entries it read, oldest first.
        public var entryIds: [String]
        /// UTF-16 characters read across those entries (or typed, for Settings in words).
        public var chars: Int

        public init(id: String = UUID().uuidString, at: Date, feature: String, executor: String, rung: String? = nil, status: String = "ok",
                    latencyMs: Int? = nil, localDay: String? = nil, entryIds: [String] = [], chars: Int = 0) {
            self.id = id
            self.at = at
            self.feature = feature
            self.executor = executor
            self.rung = rung
            self.status = status
            self.latencyMs = latencyMs
            self.localDay = localDay
            self.entryIds = entryIds
            self.chars = chars
        }
    }

    static let featureLabel: [String: String] = [
        "entry-reading": "Reading a new entry", "day-reading": "Daily insight", "insights": "Daily insight", "narrative": "Insight story",
        "mood": "Mood", "question": "Daily question", "question-answer": "Your answer", "reflect-deeper": "Reflect deeper",
        "reflect-further": "Reflect further", "video-metadata": "Moment title and summary", "echo-summary": "Echo summary",
        "image-caption": "Still description", "processing": "Reading a new entry", "letter": "Evening letter",
        "first-prompt": "Your first question", "first-week": "Your first week", "settings-parse": "Settings in words",
        "tone-preview": "Tone preview",
    ]

    /// "reflect_deeper" → "Reflect deeper"; known features get their product name.
    public static func label(_ feature: String) -> String {
        if let known = featureLabel[feature.replacingOccurrences(of: "_", with: "-")] { return known }
        let words = feature.jsReplace("[-_]+", with: " ").jsTrim
        return words.isEmpty ? "AI" : words.prefix(1).uppercased() + words.dropFirst()
    }

    static let posix = Locale(identifier: "en_US_POSIX")
    static func number(_ n: Int) -> String { n.formatted(.number.locale(Locale(identifier: "en_US"))) }
    static func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(number(n)) \(n == 1 ? one : many)" }

    /// "Sat 26 Oct".
    public static func shortDay(_ day: String) -> String {
        guard let d = LocalDay.date(day) else { return day }
        return d.formatted(Date.VerbatimFormatStyle(format: "\(weekday: .abbreviated) \(day: .defaultDigits) \(month: .abbreviated)",
                                                    locale: posix, timeZone: .current, calendar: Calendar(identifier: .gregorian)))
    }

    /// How a run ended, by category only.
    static func ending(_ status: String) -> String? {
        switch status {
        case "ok": nil
        case "guardrail": "stopped at Apple’s guardrails"
        case "refusal": "the model declined"
        case "output_gate": "held back by Saro’s check"
        case "too_long": "too long to read"
        case "assetsUnavailable": "the model wasn’t ready"
        case "rate_limited": "the model was busy"
        default: "didn’t finish"
        }
    }

    /// "Read 3 entries from Sat 26 Oct · 1,240 characters · On this Mac · Apple on-device model · permissive rung · 1.8 s",
    /// or "… · In your words (no model)" for the heuristic.
    public static func describe(_ row: Row) -> String {
        var parts: [String] = []
        let n = row.entryIds.count
        if n > 0 {
            parts.append("Read \(plural(n, "entry", "entries"))" + (row.localDay.map { " from \(shortDay($0))" } ?? ""))
            if row.chars > 0 { parts.append(plural(row.chars, "character", "characters")) }
        } else {
            parts.append(row.chars > 0 ? "Read \(plural(row.chars, "character", "characters"))" : "Read nothing from your journal")
        }
        if row.executor == "heuristic" {
            parts.append("In your words (no model)")
        } else {
            parts.append("On this Mac")
            parts.append("Apple on-device model")
            if let rung = row.rung, rung != "heuristic" { parts.append("\(rung == "permissive_json" ? "permissive" : rung) rung") }
        }
        if let end = ending(row.status) { parts.append(end) }
        if let ms = row.latencyMs, row.executor != "heuristic" || ms >= 100 { parts.append(String(format: "%.1f s", Double(ms) / 1000)) }
        return parts.joined(separator: " · ")
    }

    /// Rows grouped by the local day they ran on, newest day and newest row first.
    public static func groupByDay(_ rows: [Row]) -> [(day: String, rows: [Row])] {
        var out: [(day: String, rows: [Row])] = []
        for row in rows.sorted(by: { $0.at > $1.at }) {
            let day = LocalDay.string(for: row.at)
            if out.last?.day == day { out[out.count - 1].rows.append(row) } else { out.append((day, [row])) }
        }
        return out
    }
}
