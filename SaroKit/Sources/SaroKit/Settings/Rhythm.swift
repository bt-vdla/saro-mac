import Foundation

/// When someone usually reflects, from their entry times (rhythm.ts): a circular mean over the last 14 local days,
/// where every day counts once however many entries it has. Times are local minutes after midnight (0–1439), read in
/// each entry's own time zone, so travel doesn't skew them.
public enum Rhythm {
    public static let dayMinutes = 1440
    public static let windowDays = 14
    /// A suggestion needs this many entries…
    public static let minEntries = 5
    /// …on this many distinct days…
    public static let minDays = 4
    /// …times this concentrated (R ≥ 0.6 is a circular σ of about 3.9 h)…
    public static let minR = 0.6
    /// …and a reminder this far (minutes) from the suggested time.
    public static let minGap = 30

    /// One entry's frozen local day and its local time of day.
    public struct EntryTime: Sendable, Hashable {
        public var localDay: String
        public var minutes: Int

        public init(localDay: String, minutes: Int) {
            self.localDay = localDay
            self.minutes = minutes
        }

        /// The entry's time of day in the zone it was captured in.
        public init(localDay: String, capturedAt: Date, tzId: String) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: tzId) ?? .current
            let c = cal.dateComponents([.hour, .minute], from: capturedAt)
            self.init(localDay: localDay, minutes: (c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
    }

    public struct Point: Sendable, Hashable {
        public var minutes: Int
        /// Days ago (0 = today).
        public var age: Int
    }

    public struct Stats: Sendable, Hashable {
        public var points: [Point]
        public var days: Int
        public var entries: Int
        /// Minutes after midnight, rounded to 5.
        public var mean: Int
        public var r: Double
        /// Circular standard deviation, in minutes (infinity when R is 0).
        public var sigma: Double
    }

    public struct Suggestion: Sendable, Hashable {
        public var usual: Int
        /// The reminder time to offer: 15 minutes before the usual time.
        public var target: Int
    }

    public static func mod(_ m: Int) -> Int { ((m % dayMinutes) + dayMinutes) % dayMinutes }
    /// Math.round's halves (toward +∞), so a mean of −12.5 minutes rounds as the web's does.
    static func round5(_ m: Double) -> Int { mod(Int((m / 5 + 0.5).rounded(.down)) * 5) }

    /// A time field's step (the web's `step=300`): 5 minutes onto the 5-minute grid, so 9:27 steps to 9:30 or 9:25, or
    /// an hour; either way past midnight wraps.
    public static func step(_ m: Int, by: Int, hour: Bool = false) -> Int {
        if hour { return mod(m + 60 * by) }
        return mod(by > 0 ? (m / 5 + 1) * 5 : ((m + 4) / 5 - 1) * 5)
    }

    /// 1290 → "9:30 pm".
    public static func formatClock(_ minutes: Int) -> String {
        let m = mod(minutes)
        let h = m / 60
        return "\(h % 12 == 0 ? 12 : h % 12):\(String(format: "%02d", m % 60)) \(h < 12 ? "am" : "pm")"
    }

    /// "9:50 to 11:30 pm", or "11:30 pm to 12:40 am" when the range crosses a half of the day.
    public static func formatRange(_ from: Int, _ to: Int) -> String {
        let a = formatClock(from), b = formatClock(to)
        return a.suffix(2) == b.suffix(2) ? "\(a.dropLast(3)) to \(b)" : "\(a) to \(b)"
    }

    /// Shortest distance round the clock between two times, in minutes (0–720).
    public static func circularGap(_ a: Int, _ b: Int) -> Int {
        let d = mod(a - b)
        return min(d, dayMinutes - d)
    }

    /// The weighted circular mean (rounded to 5 minutes) and the mean resultant length R (0–1).
    public static func circularMean(_ samples: [(minutes: Int, weight: Double)]) -> (mean: Int, r: Double)? {
        var c = 0.0, s = 0.0, total = 0.0
        for (minutes, weight) in samples {
            let theta = 2 * .pi * Double(minutes) / Double(dayMinutes)
            c += weight * cos(theta)
            s += weight * sin(theta)
            total += weight
        }
        guard total > 0 else { return nil }
        c /= total
        s /= total
        return (round5(atan2(s, c) / (2 * .pi) * Double(dayMinutes)), min(1, (c * c + s * s).squareRoot()))
    }

    /// The last 14 local days of entry times, as a rhythm; nil when there are none.
    public static func stats(_ times: [EntryTime], today: String = LocalDay.today()) -> Stats? {
        guard let now = LocalDay.date(today) else { return nil }
        var points: [Point] = []
        var perDay: [Int: Int] = [:]
        for t in times {
            guard let d = LocalDay.date(t.localDay) else { continue }
            // Both dates are noon, so a daylight-saving day still rounds to whole days.
            let age = Int((now.timeIntervalSince(d) / 86_400).rounded())
            guard (0..<windowDays).contains(age) else { continue }
            points.append(Point(minutes: mod(t.minutes), age: age))
            perDay[age, default: 0] += 1
        }
        guard let m = circularMean(points.map { ($0.minutes, 1 / Double(perDay[$0.age] ?? 1)) }) else { return nil }
        let sigma = m.r >= 1 ? 0 : m.r <= 0 ? .infinity : (-2 * log(m.r)).squareRoot() / (2 * .pi) * Double(dayMinutes)
        return Stats(points: points, days: perDay.count, entries: points.count, mean: m.mean, r: m.r, sigma: sigma)
    }

    /// When the person usually reflects, or nil with too few days or times too scattered to name one.
    public static func usualTime(_ stats: Stats?) -> Int? {
        guard let stats, stats.entries >= minEntries, stats.days >= minDays, stats.r >= minR else { return nil }
        return stats.mean
    }

    /// The reminder move to offer, or nil (no clear rhythm, already close, or waved off in the last 14 days).
    public static func suggestReminder(_ stats: Stats?, reminderOn: Bool, reminderMinutes: Int, dismissedAt: Date?,
                                       now: Date = .now) -> Suggestion? {
        guard let usual = usualTime(stats) else { return nil }
        if let dismissedAt, now.timeIntervalSince(dismissedAt) < Double(windowDays) * 86_400 { return nil }
        let target = round5(Double(usual - 15))
        if reminderOn, circularGap(target, reminderMinutes) < minGap { return nil }
        return Suggestion(usual: usual, target: target)
    }

    /// "14 entries over 9 days, mostly 9:50 to 11:30 pm": the strip's text alternative.
    public static func describe(_ stats: Stats?) -> String {
        guard let stats else { return "No entries in the last two weeks yet." }
        let count = "\(stats.entries) \(stats.entries == 1 ? "entry" : "entries") over \(stats.days) \(stats.days == 1 ? "day" : "days")"
        if stats.entries == 1 { return "\(count), at \(formatClock(stats.points[0].minutes))" }
        if stats.r < minR { return "\(count), at many times of day" }
        let spread = max(5, Int((stats.sigma / 5).rounded()) * 5)
        return "\(count), mostly \(formatRange(stats.mean - spread, stats.mean + spread))"
    }

    /// The demo's steady fortnight: eleven evenings between 10:20 and 11:05 pm, so the suggestion can be seen.
    public static func sampleFortnight(today: String = LocalDay.today()) -> [EntryTime] {
        [-20, 5, -10, 15, 0, -25, 10, 20, -5, 25, -15].enumerated().map {
            EntryTime(localDay: LocalDay.adding(-($0.offset + 1), to: today), minutes: 22 * 60 + 40 + $0.element)
        }
    }
}
