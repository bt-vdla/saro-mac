import Foundation

/// "Your first week" (firstWeek.ts): the ritual time taken from what someone said, and the week's milestones. Pure
/// and deterministic, so the tests see exactly what a person sees.
public enum FirstWeek {
    public struct Milestone: Sendable, Hashable {
        public enum Kind: String, Sendable { case baseline, pattern, checkin, letter }
        public var kind: Kind
        public var title: String
        public var note: String
    }

    public struct DayPlan: Sendable, Hashable {
        /// 0 is today.
        public var index: Int
        /// Whether that day has a reminder (today always does).
        public var on: Bool
        public var milestone: Milestone?
    }

    public struct RitualSuggestion: Sendable, Hashable {
        /// Minutes after local midnight.
        public var minutes: Int
        public var source: Prefs.RitualSource
        /// The words the time came from, to show back.
        public var span: Pick?
    }

    public static let defaultMinutes = 21 * 60 + 30

    // Earliest match wins. Used only when a span carries no normalised value.
    private static let ritualWords: [(Rx, Int)] = [
        (Rx(#"\bmidnight\b"#, .caseInsensitive), 0),
        (Rx(#"\b(?:mornings?|breakfast|wak(?:e|ing))\b"#, .caseInsensitive), 7 * 60 + 30),
        (Rx(#"\blunch(?:time)?\b"#, .caseInsensitive), 12 * 60 + 30),
        (Rx(#"\bafternoons?\b"#, .caseInsensitive), 16 * 60),
        (Rx(#"\b(?:dinner|supper|evenings?|bed(?:time)?|nights?|tonight)\b"#, .caseInsensitive), 21 * 60 + 30),
    ]
    private static let morning = Rx(#"\b(?:mornings?|breakfast|wak(?:e|ing)|dawn|sunrise)\b"#, .caseInsensitive)
    private static let clock12 = Rx(#"\b(1[0-2]|0?[1-9])(?:[:.]([0-5]\d))?\s*([ap])\.?m\b"#, .caseInsensitive)
    private static let clock = Rx(#"\b([01]?\d|2[0-3])[:.]([0-5]\d)\b"#)
    private static let clockHour = Rx(#"\b(?:around|about|at|by|after|before)\s+(1[0-2]|0?[1-9])\b(?![:.]?\d)"#, .caseInsensitive)
    private static let hhmm = Rx(#"^([01]\d|2[0-3]):([0-5]\d)$"#)

    /// A clock time in the words, or nil. A bare "9:30" or "at 9" is evening unless the words say morning, as About you
    /// reads it; "07:30" and "22:15" are taken as written.
    static func clockIn(_ text: String) -> Int? {
        if let m = clock12.first(text) {
            return (Int(m[1]!)! % 12 + (m[3]!.lowercased() == "p" ? 12 : 0)) * 60 + Int(m[2] ?? "0")!
        }
        let exact = clock.first(text)
        guard let m = exact ?? clockHour.first(text), let hour = m[1], let h = Int(hour) else { return nil }
        let written24 = hour.count == 2 && hour.first == "0"
        let pm = (1...11).contains(h) && !written24 && !morning.test(text)
        return (h + (pm ? 12 : 0)) * 60 + (exact != nil ? Int(m[2]!)! : 0)
    }

    private static func wordsIn(_ text: String) -> Int? {
        ritualWords.compactMap { rx, minutes in rx.first(text).map { ($0.range.location, minutes) } }.min { $0.0 < $1.0 }?.1
    }

    /// The ritual time from the first time pick that names one, to the quarter hour: its normalised value ("21:30"),
    /// else a clock time in its words, else the earliest time-of-day word. Nothing: 21:30, from Saro (`default`).
    public static func ritualFromSpans(_ picks: [Pick]) -> RitualSuggestion {
        for p in picks where p.kind == .time {
            let value = hhmm.first(p.value).map { Int($0[1]!)! * 60 + Int($0[2]!)! }
            guard let minutes = value ?? clockIn(p.text) ?? wordsIn(p.text) else { continue }
            let quarter = (Double(minutes) / 15).rounded(.toNearestOrAwayFromZero)
            return RitualSuggestion(minutes: (Int(quarter) * 15) % 1440, source: .answer, span: p)
        }
        return RitualSuggestion(minutes: defaultMinutes, source: .default)
    }

    public enum Part: String, Sendable { case mornings = "Mornings", afternoons = "Afternoons", evenings = "Evenings", lateEvenings = "Late evenings" }

    /// How Saro names an hour: the part of the day (for the ritual hour) and today's label (for the hour now).
    public static func hourCopy(_ hour: Double) -> (part: Part, day0: String) {
        let h = wrap24(hour)
        // Small hours read as the night before, not as morning.
        let late = h >= 22 || h < 4
        return (late ? .lateEvenings : h < 12 ? .mornings : h < 17 ? .afternoons : .evenings, h >= 17 || h < 4 ? "TONIGHT" : "TODAY")
    }

    public static func wrap24(_ hour: Double) -> Double { (hour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24) }

    /// The shortest way round the clock from one hour to another, in hours (−12 to 12).
    public static func hourDelta(from: Double, to: Double) -> Double {
        let d = wrap24(to - from)
        return d > 12 ? d - 24 : d
    }

    /// Which days of the coming week have a reminder, from a weekday mask (Sunday = bit 0). Today is always on.
    public static func weekOn(_ weekdays: Int, startDay: Int) -> [Bool] {
        (0..<7).map { $0 == 0 || (weekdays >> ((startDay + $0) % 7)) & 1 == 1 }
    }

    /// The mask with day `index` of the week (0 = today) switched.
    public static func toggleWeekday(_ weekdays: Int, startDay: Int, index: Int) -> Int { weekdays ^ (1 << ((startDay + index) % 7)) }

    private static let quotes = Rx(#"^["'“‘]+|["'”’]+$"#)
    private static let trailing = Rx(#"[.!?,;:…]+$"#)
    private static let ownCapital = Rx(#"^I(?:\b|['’])"#)
    private static let sentenceCapital = Rx(#"^[A-Z](?![A-Z])"#)
    private static let want = Rx(#"^(?:I want to|I['’]d like to|I would like to|I hope to|I need to|I['’]m trying to|I am trying to|trying to)\s+"#, .caseInsensitive)
    private static let act = Rx(#"^(?:stop|start|keep|be|get|go|make|spend|take)\b"#, .caseInsensitive)

    /// A pick's words for the middle of a sentence: no quotes or trailing punctuation, and the capital that only began
    /// their sentence dropped ("The launch" → "the launch"; "I", "I'm" and "NHS" keep theirs).
    static func phrase(_ text: String) -> String {
        let t = trailing.replaceFirst(quotes.replace(text.trimmingCharacters(in: .whitespacesAndNewlines), ""), "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ownCapital.test(t) || !sentenceCapital.test(t) ? t : t.prefix(1).lowercased() + t.dropFirst()
    }

    /// A goal pick without its "I want to", and whether what's left is something to do ("stop…") or to have.
    static func goalOf(_ text: String) -> (goal: String, act: Bool) {
        let said = phrase(text)
        let goal = phrase(want.replaceFirst(said, ""))
        return (goal, goal != said || act.test(goal))
    }

    /// The day 4–5 check-in: their goal in quotes when it's short, else a plain question.
    public static func checkInNote(goal: String?) -> String {
        let g = goal.map { goalOf($0).goal } ?? ""
        return !g.isEmpty && g.count <= 48 ? "How’s “\(g)” going?" : "How’s the week sitting?"
    }

    static func letterMilestone(name: String?, carriesPattern: Bool, dayOff: Bool) -> Milestone {
        let who = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Milestone(kind: .letter, title: who.isEmpty ? "Dear you," : "Dear \(who),",
                         note: "Your first weekly letter\(carriesPattern ? ", and a first pattern" : "").\(dayOff ? " It still comes." : "")")
    }

    /// The first week, today first: a baseline today, a first pattern on the third day with a moment (if that's by day
    /// 5), a check-in on the first day 4–5 after it, and the letter on day 6 whatever happens.
    public static func plan(on: [Bool], name: String? = nil, goal: String? = nil) -> [DayPlan] {
        var days = (0..<7).map { DayPlan(index: $0, on: $0 == 0 || (on.indices.contains($0) && on[$0])) }
        let third = days.filter(\.on).dropFirst(2).first
        let pattern = third.map { $0.index <= 5 ? $0.index : -1 } ?? -1
        days[0].milestone = Milestone(kind: .baseline, title: "A baseline", note: "Your first moment. The week starts here.")
        if pattern > 0 { days[pattern].milestone = Milestone(kind: .pattern, title: "A first pattern", note: "Three moments are enough to notice one.") }
        if let check = days.first(where: { $0.on && (4...5).contains($0.index) && $0.index > pattern }) {
            days[check.index].milestone = Milestone(kind: .checkin, title: "A check-in", note: checkInNote(goal: goal))
        }
        days[6].milestone = letterMilestone(name: name, carriesPattern: pattern < 0, dayOff: !days[6].on)
        return days
    }

    /// The week from the weekday mask, starting on `startDay` (0 = Sunday).
    public static func plan(startDay: Int, weekdays: Int, goal: String? = nil, name: String? = nil) -> [DayPlan] {
        plan(on: weekOn(weekdays, startDay: startDay), name: name, goal: goal)
    }

    /// What VoiceOver hears after day `index` is switched: "Wednesday off. The first pattern moves to Thursday."
    public static func weekChange(before: [DayPlan], after: [DayPlan], index: Int, dayNames: [String]) -> String {
        var parts = ["\(dayNames[index]) \(after[index].on ? "on" : "off")."]
        for (kind, label, gone) in [(Milestone.Kind.pattern, "The first pattern", "The first pattern moves into the letter."),
                                    (.checkin, "The check-in", "No check-in this week.")] {
            let from = before.firstIndex { $0.milestone?.kind == kind }
            let to = after.firstIndex { $0.milestone?.kind == kind }
            if from != to { parts.append(to.map { "\(label) moves to \(dayNames[$0])." } ?? gone) }
        }
        if index == 6, !after[6].on { parts.append("The letter still comes.") }
        return parts.joined(separator: " ")
    }

    /// "9:30 pm", or "21:30" where the clock runs to 24.
    public static func clockLabel(_ minutes: Int, hour12: Bool = true) -> String {
        let h = minutes / 60 % 24, mm = String(format: "%02d", minutes % 60)
        return hour12 ? "\(h % 12 == 0 ? 12 : h % 12):\(mm) \(h < 12 ? "am" : "pm")" : String(format: "%02d:", h) + mm
    }

    /// What VoiceOver hears after the time changes: "Reminder at 7:30 am. Mornings."
    public static func timeChange(_ minutes: Int, hour12: Bool = true) -> String {
        "Reminder at \(clockLabel(minutes, hour12: hour12)). \(hourCopy(Double(minutes) / 60).part.rawValue)."
    }

    private static let typed = Rx(#"^\s*(\d{1,2})(?:\s*[:.]\s*(\d{2}))?\s*(?:([ap])\.?\s*m?\.?)?\s*$"#, .caseInsensitive)

    /// A time typed into the ritual pill ("7:30", "7.30 pm", "19:30", "9pm"), to the quarter hour; nil if it isn't one.
    /// A bare hour from 1 to 11 keeps the half of the day the pill was showing.
    public static func parseTyped(_ text: String, near current: Int) -> Int? {
        guard let m = typed.first(text), let h = Int(m[1]!), h <= 23 else { return nil }
        let minute = Int(m[2] ?? "0") ?? 0
        guard minute < 60 else { return nil }
        var hour = h
        if let meridiem = m[3]?.lowercased() {
            guard (1...12).contains(h) else { return nil }
            hour = h % 12 + (meridiem == "p" ? 12 : 0)
        } else if (1...11).contains(h), current >= 12 * 60, m[1]!.first != "0" {
            hour = h + 12
        }
        let quarter = Int((Double(hour * 60 + minute) / 15).rounded(.toNearestOrAwayFromZero)) * 15
        return quarter % 1440
    }
}
