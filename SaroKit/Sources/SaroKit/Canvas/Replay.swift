import Foundation

/// The pure side of a day replay (lib/replay.ts): which entries have landed at a playhead, the stops between them, the
/// markers' clusters on the track, the time-lapse that plays a day in about 20 s, and the mood line. Hours are local
/// time, 0–24 (fractional).
public enum Replay {
    public static let dayHours = 24.0
    /// Two entries less than a second apart are one stop for the arrow keys.
    static let sameStop = 1.0 / 3600
    /// The day plays in quarter hours; the half hour either side of an entry plays at full time, the rest ~8× faster.
    static let dayBin = 0.25, near = 0.5, emptyWeight = 0.12

    /// A playback curve: the playhead (in hours) against seconds of playback.
    public struct Lapse: Sendable, Equatable {
        /// Hours per bin.
        public let bin: Double
        /// Seconds of playback at each bin edge; the last is the whole length.
        public let edges: [Double]

        public var length: Double { edges[edges.count - 1] }

        /// Where the playhead is `t` seconds in.
        public func hour(at t: Double) -> Double {
            let s = min(max(t, 0), length)
            var lo = 0, hi = edges.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if edges[mid] <= s { lo = mid } else { hi = mid }
            }
            let span = edges[hi] - edges[lo]
            return (Double(lo) + (span > 0 ? (s - edges[lo]) / span : 0)) * bin
        }

        /// How many seconds in the playhead reaches `hour` (so playing resumes from where it was).
        public func time(at hour: Double) -> Double {
            let x = min(max(hour / bin, 0), Double(edges.count - 1))
            let i = min(Int(x), edges.count - 2)
            return edges[i] + (edges[i + 1] - edges[i]) * (x - Double(i))
        }
    }

    public struct MoodSegment: Sendable, Equatable {
        public var from: Double
        public var to: Double
        public var label: String
    }

    /// Local hour of a moment, 0–24, to the second.
    public static func hour(of date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }

    /// How many of the sorted hours are at or before `hour`: the entries that have landed.
    public static func reached(_ hours: [Double], at hour: Double) -> Int {
        var lo = 0, hi = hours.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if hours[mid] <= hour { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// The next entry after the playhead, or the end of the day.
    public static func nextStop(_ hours: [Double], after hour: Double) -> Double {
        let i = reached(hours, at: hour + sameStop)
        return i < hours.count ? hours[i] : dayHours
    }

    /// The entry before the playhead, or the start of the day.
    public static func previousStop(_ hours: [Double], before hour: Double) -> Double {
        let i = reached(hours, at: hour - sameStop) - 1
        return i >= 0 ? hours[i] : 0
    }

    /// A day in `seconds`: full time around each entry (so it lands and its light shows), sped up where nothing happens.
    public static func dayLapse(_ hours: [Double], seconds: Double = 20) -> Lapse {
        let weights = (0..<Int(dayHours / dayBin)).map { i in
            let mid = (Double(i) + 0.5) * dayBin
            return hours.contains { abs($0 - mid) <= near } ? 1 : emptyWeight
        }
        let total = weights.reduce(0, +)
        var edges = [0.0]
        for w in weights { edges.append(edges[edges.count - 1] + w / total * seconds) }
        return Lapse(bin: dayBin, edges: edges)
    }

    /// The mood line: each mark colours the day from its time to the next mark, the last to midnight. Repeats merge.
    public static func moodSegments(_ marks: [(hour: Double, label: String)]) -> [MoodSegment] {
        let sorted = marks.enumerated().sorted { ($0.element.hour, $0.offset) < ($1.element.hour, $1.offset) }.map(\.element)
        var out: [MoodSegment] = []
        for (i, mark) in sorted.enumerated() {
            let to = i + 1 < sorted.count ? sorted[i + 1].hour : dayHours
            if let last = out.last, last.label == mark.label { out[out.count - 1].to = to }
            else if to > mark.hour { out.append(MoodSegment(from: mark.hour, to: to, label: mark.label)) }
        }
        return out
    }

    /// Markers along a track, left to right: each one less than `gap` from the one before joins its cluster, so drawn
    /// clusters never overlap. Returns each cluster's first and last index.
    public static func clusters(_ xs: [Double], gap: Double) -> [ClosedRange<Int>] {
        var out: [ClosedRange<Int>] = []
        for (i, x) in xs.enumerated() {
            if let last = out.last, x - xs[i - 1] < gap { out[out.count - 1] = last.lowerBound...i } else { out.append(i...i) }
        }
        return out
    }
}
