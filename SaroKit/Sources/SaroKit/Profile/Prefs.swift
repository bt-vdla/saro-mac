import Foundation

/// Device preferences (DR-21): comfort, ritual, letter and lock switches, with the web's defaults (prefs.ts
/// DEFAULT_PREFS) and its sanitiser. The app's PrefsStore keeps them in UserDefaults. Name, tone and focus live in the
/// ledger's profile row instead, so they export with the journal. Nothing here is a secret.
public struct Prefs: Sendable, Hashable, Codable {
    public enum RitualSource: String, Sendable, Codable { case answer, `default`, user }
    public enum LockAfter: String, Sendable, Codable, CaseIterable { case immediately, fiveMinutes, hour, never }

    public static let textScales: [Double] = [0.9, 1, 1.125, 1.25, 1.5]
    public static let everyDay = 0b111_1111

    public var textScale = 1.0
    public var captionsAlways = false
    /// A SpeechTranscriber locale identifier; nil follows the device.
    public var captionLocale: String?
    /// True turns it on; false follows the device.
    public var reduceMotion = false
    public var reduceTransparency = false
    public var sounds = false
    public var haptics = false
    /// Apple's Writing Tools in Saro's editors, which may use Private Cloud Compute; off unless chosen.
    public var writingTools = false

    public var reminderOn = false
    /// Minutes after local midnight.
    public var ritualMinutes = 1290
    /// Weekdays with a reminder, Sunday = bit 0.
    public var ritualWeekdays = everyDay
    /// Whether the time came from an answer, is Saro's starting point, or the person set it.
    public var ritualSource = RitualSource.default
    /// The time About you suggested when the ritual was saved, so a changed answer suggests again.
    public var ritualSuggested: Int?
    /// The first week's day 0, YYYY-MM-DD local.
    public var weekStartedOn: String?

    public var letterMinutes = 1080
    /// Whether the evening letter opens on its own once it's due.
    public var letterArrives = true
    /// When the rhythm suggestion was waved off; it stays quiet for 14 days after.
    public var rhythmDismissedAt: Date?

    public var lockEnabled = false
    public var lockAfter = LockAfter.fiveMinutes
    public var hideFromScreenShare = false

    public init() {}

    /// Whatever is stored, back as whole valid prefs: a missing, mistyped or out-of-range value falls back to its
    /// default (prefs.ts sanitizePrefs).
    public init(from decoder: Decoder) throws {
        self.init()
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        func value<T: Decodable>(_ key: CodingKeys, _: T.Type = T.self) -> T? { try? c.decodeIfPresent(T.self, forKey: key) }
        func minutes(_ key: CodingKeys) -> Int? { value(key, Int.self).flatMap { (0..<1440).contains($0) ? $0 : nil } }

        if let s = value(.textScale, Double.self), Self.textScales.contains(s) { textScale = s }
        captionsAlways = value(.captionsAlways) ?? captionsAlways
        captionLocale = value(.captionLocale, String.self).flatMap { $0.isEmpty ? nil : $0 }
        reduceMotion = value(.reduceMotion) ?? reduceMotion
        reduceTransparency = value(.reduceTransparency) ?? reduceTransparency
        sounds = value(.sounds) ?? sounds
        haptics = value(.haptics) ?? haptics
        writingTools = value(.writingTools) ?? writingTools
        reminderOn = value(.reminderOn) ?? reminderOn
        ritualMinutes = minutes(.ritualMinutes) ?? ritualMinutes
        if let w = value(.ritualWeekdays, Int.self), (0...Self.everyDay).contains(w) { ritualWeekdays = w }
        ritualSource = value(.ritualSource) ?? ritualSource
        ritualSuggested = minutes(.ritualSuggested)
        weekStartedOn = value(.weekStartedOn, String.self).flatMap { LocalDay.isValid($0) ? $0 : nil }
        letterMinutes = minutes(.letterMinutes) ?? letterMinutes
        letterArrives = value(.letterArrives) ?? letterArrives
        rhythmDismissedAt = value(.rhythmDismissedAt)
        lockEnabled = value(.lockEnabled) ?? lockEnabled
        lockAfter = value(.lockAfter) ?? lockAfter
        hideFromScreenShare = value(.hideFromScreenShare) ?? hideFromScreenShare
    }

    /// Stored bytes back as prefs; anything unreadable is the defaults.
    public static func decode(_ data: Data?) -> Prefs {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return data.flatMap { try? d.decode(Prefs.self, from: $0) } ?? Prefs()
    }

    /// JSON, as stored and as exported.
    public var encoded: Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        e.dateEncodingStrategy = .iso8601
        return (try? e.encode(self)) ?? Data()
    }

    /// Whether the evening letter can open: it's past the letter time, local (prefs.ts letterDue).
    public func letterDue(at date: Date = .now, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0) >= letterMinutes
    }

    /// One repeating reminder per chosen weekday at the ritual time, with ids `saro-ritual-<weekday>` (Calendar's
    /// 1 = Sunday); none while the reminder is off.
    public var ritualRequests: [(id: String, components: DateComponents)] {
        guard reminderOn else { return [] }
        return (0..<7).filter { ritualWeekdays & (1 << $0) != 0 }.map {
            ("saro-ritual-\($0 + 1)", DateComponents(hour: ritualMinutes / 60, minute: ritualMinutes % 60, weekday: $0 + 1))
        }
    }
}
