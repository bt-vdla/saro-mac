import Foundation

/// One moment of the first week, as stored after its gate cleared it (FR-REF-10): never raw text.
public struct WeekEntry: Sendable, Hashable {
    public var id: String
    public var at: Date
    /// The stored reading's words (its quote, title and summary), for what the moment was about.
    public var words: String
    /// Its stored verbatim quote.
    public var quote: String?
    public var mood: Mood?

    public init(id: String = UUID().uuidString, at: Date, words: String, quote: String? = nil, mood: Mood? = nil) {
        self.id = id
        self.at = at
        self.words = words
        self.quote = quote
        self.mood = mood
    }
}

public struct WeekNote: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Codable { case pattern, letter, checkIn = "check_in" }

    public var kind: Kind
    public var title: String
    public var lines: [String]
    /// The entries it was read from, so a note that drew on an entry since held is dropped (SR-15).
    public var sources: [String] = []
}

/// The first week's promises, kept offline (weekMilestones.ts): "a first pattern" once there are three moments, the
/// day 4–5 check-in, and "your first weekly letter" on day 6. Every line is counted from the moments or quotes them.
public enum WeekMilestones {
    private static let counts = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// "A first pattern", from the first three moments; nil until there are three, or when their words trip the gate.
    public static func firstPattern(_ entries: [WeekEntry], calendar: Calendar = .current) -> WeekNote? {
        let three = Array(entries.prefix(3))
        guard three.count == 3, !flagged(three) else { return nil }
        let common = shared(three)
        var lines: [String] = []
        let of = common?.n == 3 ? "all three of your first moments" : "two of your first three moments"
        if let theme = common?.theme { lines.append("\(DayNarrative.cap(theme.rawValue)) came up in \(of).") }
        else if let mood = common?.mood { lines.append("\(DayNarrative.cap(of)) sounded \(mood.rawValue.lowercased()).") }
        if let said = common.flatMap({ quote($0.from) }) { lines.append("You said “\(said)”.") }
        if let at = usualTime(three, calendar) { lines.append("All three came around \(clockLabel(at)).") }
        if lines.isEmpty { lines.append("Three moments, each about something different. I’ll keep watching.") }
        return WeekNote(kind: .pattern, title: "A first pattern", lines: lines, sources: three.map(\.id))
    }

    /// "Your first weekly letter", from the week's moments; with `carriesPattern` it brings the first pattern too.
    public static func firstLetter(name: String?, week: [WeekEntry], carriesPattern: Bool, calendar: Calendar = .current) -> WeekNote {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = name.isEmpty ? "Dear you," : "Dear \(name),"
        guard !week.isEmpty else {
            return WeekNote(kind: .letter, title: title, lines: ["No moments this week, and that’s all right.", "Tonight’s minute is still yours."])
        }
        var days: [String] = []
        for e in week {
            let d = weekdays[calendar.component(.weekday, from: e.at) - 1]
            if !days.contains(d) { days.append(d) }
        }
        let on = days.count > 4 ? "on \(count(days.count)) different days"
            : "on \(days.dropLast().joined(separator: ", "))\(days.count > 1 ? " and " : "")\(days.last!)"
        var lines = ["You came back \(times(week.count)) this week, \(on)."]
        if flagged(week) {
            return WeekNote(kind: .letter, title: title, lines: lines + ["I’ve kept this letter short. The rest can wait until you want it."],
                            sources: week.map(\.id))
        }
        if let at = usualTime(week, calendar) { lines.append("Most came around \(clockLabel(at)).") }
        let common = shared(week)
        if let theme = common?.theme { lines.append("\(DayNarrative.cap(theme.rawValue)) came up most, in \(count(common!.n)) of them.") }
        else if let mood = common?.mood { lines.append("\(DayNarrative.cap(count(common!.n))) of them sounded \(mood.rawValue.lowercased()).") }
        let richest = week.reduce(week[0]) { Heuristics.analyzeText($1.words).focus.count > Heuristics.analyzeText($0.words).focus.count ? $1 : $0 }
        if let said = quote(common?.from ?? richest) { lines.append("One line I kept: “\(said)”.") }
        if carriesPattern, let first = firstPattern(week, calendar: calendar)?.lines.first, first != lines.last {
            lines.append("And a first pattern: \(first.prefix(1).lowercased())\(first.dropFirst())")
        }
        return WeekNote(kind: .letter, title: title, lines: lines, sources: week.map(\.id))
    }

    /// The check-in on days 4–5: their goal, when it's short, else a plain question (firstWeek.ts checkInNote).
    public static func checkIn(goal: String?) -> WeekNote {
        let goal = goal?.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".!")) ?? ""
        return WeekNote(kind: .checkIn, title: "A check-in",
                        lines: [!goal.isEmpty && goal.count <= 48 ? "How’s “\(goal)” going?" : "How’s the week sitting?"])
    }

    /// The first week's day `now` falls on, counted from `startedOn` (day 0); nil outside the first two weeks.
    public static func weekDay(startedOn: String, now: Date, calendar: Calendar = .current) -> Int? {
        guard let noon = LocalDay.date(startedOn),
              let day = calendar.dateComponents([.day], from: calendar.startOfDay(for: noon), to: calendar.startOfDay(for: now)).day,
              (0...13).contains(day) else { return nil }
        return day
    }

    /// What the first week has to say today: the letter from day 6 for a week, the first pattern once there are three
    /// moments, otherwise nothing.
    public static func dueNote(startedOn: String, entries: [WeekEntry], now: Date, name: String?, calendar: Calendar = .current) -> WeekNote? {
        guard let day = weekDay(startedOn: startedOn, now: now, calendar: calendar), let noon = LocalDay.date(startedOn) else { return nil }
        let start = calendar.startOfDay(for: noon)
        let dayStart = { (offset: Int) in calendar.date(byAdding: .day, value: offset, to: start)! }
        let week = entries.filter { $0.at >= start && $0.at < dayStart(7) }.sorted { $0.at < $1.at }
        if day >= 6 { return firstLetter(name: name, week: week, carriesPattern: week.filter { $0.at < dayStart(6) }.count < 3, calendar: calendar) }
        return week.count >= 3 ? firstPattern(week, calendar: calendar) : nil
    }

    /// "9:30 pm" (firstWeek.ts clockLabel).
    public static func clockLabel(_ minutes: Int) -> String {
        let h = minutes / 60 % 24
        return "\(h % 12 == 0 ? 12 : h % 12):\(String(format: "%02d", minutes % 60)) \(h < 12 ? "am" : "pm")"
    }

    private static func count(_ n: Int) -> String { n < counts.count ? counts[n] : "\(n)" }
    private static func times(_ n: Int) -> String { n == 1 ? "once" : n == 2 ? "twice" : "\(count(n)) times" }

    private static func flagged(_ entries: [WeekEntry]) -> Bool {
        SafetyGate.phraseHit(entries.flatMap { [$0.words, $0.quote ?? ""] }.joined(separator: "\n"))
    }

    /// The theme, else the feeling, that most of the entries share (at least two), and the first entry with it.
    private static func shared(_ entries: [WeekEntry]) -> (theme: Theme?, mood: Mood?, n: Int, from: WeekEntry)? {
        var themes: [(Theme, [WeekEntry])] = []
        var moods: [(Mood, [WeekEntry])] = []
        for e in entries {
            for t in Heuristics.analyzeText(e.words).themes {
                if let i = themes.firstIndex(where: { $0.0 == t }) { themes[i].1.append(e) } else { themes.append((t, [e])) }
            }
            if let m = e.mood {
                if let i = moods.firstIndex(where: { $0.0 == m }) { moods[i].1.append(e) } else { moods.append((m, [e])) }
            }
        }
        func top<K>(_ list: [(K, [WeekEntry])]) -> (K, [WeekEntry])? { list.reduce(nil) { best, next in best.map { next.1.count > $0.1.count ? next : $0 } ?? next } }
        if let t = top(themes), t.1.count >= 2 { return (t.0, nil, t.1.count, t.1[0]) }
        if let m = top(moods), m.1.count >= 2, m.0 != .neutral { return (nil, m.0, m.1.count, m.1[0]) }
        return nil
    }

    /// Their words, verbatim: the moment's stored quote, when it's short enough to give back.
    private static func quote(_ e: WeekEntry) -> String? {
        guard let q = e.quote?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty, q.count <= 90, !SafetyGate.phraseHit(q) else { return nil }
        return q
    }

    /// The time most of them came at (all within two hours of it, round the clock), to the quarter hour, or nil.
    private static func usualTime(_ entries: [WeekEntry], _ calendar: Calendar) -> Int? {
        guard entries.count >= 2 else { return nil }
        let minutes = entries.map { e in
            let c = calendar.dateComponents([.hour, .minute], from: e.at)
            return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        let angle = { (m: Double) in m / 1440 * .pi * 2 }
        let x = minutes.reduce(0) { $0 + cos(angle($1)) }, y = minutes.reduce(0) { $0 + sin(angle($1)) }
        let mean = (atan2(y, x) / (.pi * 2) * 1440 + 1440).truncatingRemainder(dividingBy: 1440)
        let apart = { (m: Double) in
            let d = ((m - mean).truncatingRemainder(dividingBy: 1440) + 1440).truncatingRemainder(dividingBy: 1440)
            return min(d, 1440 - d)
        }
        guard minutes.allSatisfy({ apart($0) <= 120 }) else { return nil }
        return Int((mean / 15).rounded()) * 15 % 1440
    }
}
