import Foundation

/// Every setting Say it can change, as it stands now (or as a proposal would leave it).
public struct SettingsValues: Sendable, Hashable {
    /// The palette, as Settings → Appearance names it.
    public enum Appearance: String, Sendable, CaseIterable { case clock, system, light, dark }

    public var reminderOn = false
    /// Minutes after local midnight.
    public var reminderMinutes = 21 * 60
    public var letterMinutes = 18 * 60
    public var textScale = 1.0
    public var captionsAlways = false
    /// True reduces; false follows the device.
    public var reduceMotion = false
    public var reduceTransparency = false
    public var sounds = false
    public var haptics = false
    public var memoryPaused = false
    public var theme = Appearance.clock
    /// Nil while the profile isn't loaded: tone and focus requests then match nothing.
    public var tone: Tone? = .gentle
    public var focus: [FocusArea]? = [.clarity]

    public init() {}

    public init(prefs: Prefs, profile: Profile?, theme: Appearance) {
        reminderOn = prefs.reminderOn
        reminderMinutes = prefs.ritualMinutes
        letterMinutes = prefs.letterMinutes
        textScale = prefs.textScale
        captionsAlways = prefs.captionsAlways
        reduceMotion = prefs.reduceMotion
        reduceTransparency = prefs.reduceTransparency
        sounds = prefs.sounds
        haptics = prefs.haptics
        memoryPaused = profile?.memoryPaused ?? false
        self.theme = theme
        tone = profile?.tone
        focus = profile?.focusAreas
    }

    /// These values with `key` taken from `other`: how Apply and Undo move one setting at a time.
    public func taking(_ key: ParseIntent.Key, from other: SettingsValues) -> SettingsValues {
        var v = self
        switch key {
        case .reminder: (v.reminderOn, v.reminderMinutes) = (other.reminderOn, other.reminderMinutes)
        case .letterTime: v.letterMinutes = other.letterMinutes
        case .tone: v.tone = other.tone
        case .theme: v.theme = other.theme
        case .textScale: v.textScale = other.textScale
        case .captionsAlways: v.captionsAlways = other.captionsAlways
        case .reduceMotion: v.reduceMotion = other.reduceMotion
        case .reduceTransparency: v.reduceTransparency = other.reduceTransparency
        case .sounds: v.sounds = other.sounds
        case .haptics: v.haptics = other.haptics
        case .memoryPaused: v.memoryPaused = other.memoryPaused
        case .focus: v.focus = other.focus
        }
        return v
    }
}

/// "Say it, and it's set" (parseIntent.ts): a closed list of settings someone can change in their own words. Nothing
/// here writes; a result proposes values, and the caller applies the keys the person keeps checked.
public enum ParseIntent {
    public static let maxFocus = 3
    public static let examples = ["remind me at 9:30", "bigger text", "be more direct"]

    public enum Key: String, Sendable, CaseIterable, Codable {
        case reminder, letterTime, tone, theme, textScale, captionsAlways, reduceMotion, reduceTransparency, sounds, haptics, memoryPaused, focus
    }

    public struct Change: Sendable, Hashable, Identifiable {
        public var key: Key
        public var label: String
        public var why: String
        public var from: String
        public var to: String
        public var id: Key { key }
    }

    public enum Result: Sendable, Hashable {
        case none
        /// Delete, erase, export or forget: never a diff here.
        case needsYou
        /// Nothing to change, and why: it's already set, or a part couldn't be done ("25" isn't a time).
        case alreadySet(String)
        /// `proposed` holds every change; `note` says what was asked for and couldn't be done, or is already set.
        case changes([Change], note: String?, proposed: SettingsValues)
    }

    /// A clock time; `assumedPm` when a bare 1–11 was read as evening, so the diff can say so.
    public enum Clock: Sendable, Hashable {
        case time(minutes: Int, assumedPm: Bool)
        /// Written like a time but isn't one ("25", "9:75"): said back, never guessed at.
        case invalid(String)
    }

    // MARK: Specs

    static let focusLabel: [FocusArea: String] = [
        .clarity: "Clarity", .steadiness: "Steadiness", .creative: "Creative", .relationships: "Relationships",
        .habits: "Habits", .confidence: "Confidence", .energy: "Energy", .purpose: "Purpose",
    ]
    static let themeLabel: [SettingsValues.Appearance: String] = [.clock: "Follow the day", .system: "System", .light: "Light", .dark: "Dark"]

    public static func pct(_ scale: Double) -> String {
        let p = scale * 100
        return p == p.rounded() ? "\(Int(p))%" : "\(p)%"
    }

    static func onOff(_ on: Bool) -> String { on ? "On" : "Off" }
    static func focusList(_ f: [FocusArea]) -> String { f.compactMap { focusLabel[$0] }.joined(separator: ", ") }

    public static func label(_ key: Key) -> String {
        switch key {
        case .reminder: "Reminder"
        case .letterTime: "Evening letter"
        case .tone: "How Saro talks"
        case .theme: "Appearance"
        case .textScale: "Text size"
        case .captionsAlways: "Captions always on"
        case .reduceMotion: "Reduce motion"
        case .reduceTransparency: "Reduce transparency"
        case .sounds: "Sounds"
        case .haptics: "Haptics"
        case .memoryPaused: "Memory"
        case .focus: "Focus"
        }
    }

    /// Nil when the value isn't known (no profile yet).
    static func format(_ key: Key, _ v: SettingsValues) -> String? {
        switch key {
        case .reminder: v.reminderOn ? Rhythm.formatClock(v.reminderMinutes) : "Off"
        case .letterTime: "after \(Rhythm.formatClock(v.letterMinutes))"
        case .tone: v.tone?.label
        case .theme: themeLabel[v.theme]
        case .textScale: pct(v.textScale)
        case .captionsAlways: onOff(v.captionsAlways)
        case .reduceMotion: v.reduceMotion ? "On" : "Follow device"
        case .reduceTransparency: v.reduceTransparency ? "On" : "Follow device"
        case .sounds: onOff(v.sounds)
        case .haptics: onOff(v.haptics)
        case .memoryPaused: v.memoryPaused ? "Paused" : "On"
        case .focus: v.focus.map { $0.isEmpty ? "None" : focusList($0) }
        }
    }

    static func same(_ key: Key, _ a: SettingsValues, _ b: SettingsValues) -> Bool {
        switch key {
        case .reminder: a.reminderOn == b.reminderOn && (!a.reminderOn || a.reminderMinutes == b.reminderMinutes)
        case .focus: Set(a.focus ?? []) == Set(b.focus ?? []) && a.focus?.count == b.focus?.count
        default: a.taking(key, from: b) == a
        }
    }

    static func already(_ key: Key, _ v: SettingsValues) -> String {
        switch key {
        case .reminder: v.reminderOn ? "Your reminder is already \(Rhythm.formatClock(v.reminderMinutes))." : "Your reminder is already off."
        case .letterTime: "Your letter already arrives after \(Rhythm.formatClock(v.letterMinutes))."
        case .tone: "Saro already talks this way: \(v.tone?.label ?? "")."
        case .theme:
            switch v.theme {
            case .clock: "Saro already follows the day."
            case .system: "Saro already follows macOS."
            case .light, .dark: "Saro is already \(v.theme.rawValue)."
            }
        case .textScale: "Text is already \(pct(v.textScale))."
        case .captionsAlways: v.captionsAlways ? "Captions are already always on." : "Always-on captions are already off."
        case .reduceMotion: v.reduceMotion ? "Reduced motion is already on." : "Motion already follows your device."
        case .reduceTransparency: v.reduceTransparency ? "Reduced transparency is already on." : "Transparency already follows your device."
        case .sounds: "Sounds are already \(v.sounds ? "on" : "off")."
        case .haptics: "Haptics are already \(v.haptics ? "on" : "off")."
        case .memoryPaused: v.memoryPaused ? "Memory is already paused." : "Memory is already on."
        case .focus: "Your focus is already \(v.focus.map { $0.isEmpty ? "empty" : focusList($0) } ?? "empty")."
        }
    }

    /// What each clause asked for, in the order it was first mentioned, with a reason for the diff.
    final class Draft {
        let current: SettingsValues
        var values: SettingsValues
        var whys: [Key: String] = [:]
        var order: [Key] = []
        /// Things asked for that couldn't be done (a fourth focus, a time that isn't one), said back in the result.
        var notes: [String] = []

        init(_ current: SettingsValues) {
            self.current = current
            values = current
        }

        func set(_ key: Key, why: String, _ change: (inout SettingsValues) -> Void) {
            if !order.contains(key) { order.append(key) }
            change(&values)
            whys[key] = why
        }

        func addNote(_ text: String) { if !notes.contains(text) { notes.append(text) } }
    }

    // MARK: Words

    static let needsYou = #"\b(delete|erase|wipe|forget|export|download|clear (all|my|everything)|remove (all |my |every )?(data|account|entries|entry|memories|memory|videos|recordings|everything|history))\b"#
    static let split = #"\s*(?:[,;]|\band then\b|\bthen\b|\balso\b|\band\b|\bplus\b)\s*"#
    static let off = #"\b(off|disable|stop|no|never|mute|hide|without|don't|do not|no more|none)\b"#
    static let on = #"\b(on|enable|start|always|show|unmute|yes|please|back)\b"#

    // "Remind me when it gets dark" is a time of day, not the night palette. That palette starts at 8 pm.
    static let dusk = #"\b(when it(?:'s| is)? ?(?:gets? |goes |turns )?dark|after dark|before dark|once it(?:'s| is) dark|at (?:dusk|sunset|nightfall)|dark out(?:side)?)\b"#
    static let duskMinutes = 20 * 60
    // "Make it light and playful", "keep it light": how Saro sounds, not the screen. Saro has no playful tone yet.
    static let playful = #"\b(playful|funny|light-?hearted|cheerful|jokey|jokes?|joking|humou?r\w*|breezy|keep it light|more fun)\b"#
    static let talk = #"\b(talk|speak|tone|voice)\w*"#
    static let reminderWords = #"\b(remind\w*|nudge\w*|notif\w*|alerts?|ping|buzz me)\b"#
    // A time with nothing else in the clause counts only when it's said like one ("at 9", "9:30", "9pm", or just "9").
    static let timeAsked = #"\b(?:at|for|to|around|by|until)\s+\d|\d[:.]\d|\d\s*(?:am|pm)\b|^\d{1,4}(?:\s\d{2})?$|\b(?:noon|midday|midnight)\b"#

    static let focusWords: [(FocusArea, String)] = [
        (.clarity, #"\b(clarity|clearer|decisions?|deciding)\b"#),
        (.steadiness, #"\b(steadiness|steady|steadier|emotional|emotions|stress|anxiety)\b"#),
        (.creative, #"\b(creative|creativity|creating|art|writing)\b"#),
        (.relationships, #"\b(relationships?|people|family|friends|partner)\b"#),
        (.habits, #"\b(habits?|consistency|consistent|routines?)\b"#),
        (.confidence, #"\b(confidence|confident|agency|self-belief)\b"#),
        (.energy, #"\b(energy|health|healthy|sleep|fitness|exercise)\b"#),
        (.purpose, #"\b(purpose|direction|meaning)\b"#),
    ]

    static let toneWords: [(Tone, String)] = [
        (.gentle, #"\b(gentle|gentler|gently|soft|softer|kind|kinder|warm|warmer)\b"#),
        (.direct, #"\b(direct|directly|blunt|blunter|straight|straighter|to the point|no fluff|tough|tougher|harsher)\b"#),
        (.contemplative, #"\b(contemplative|thoughtful|reflective|deeper|philosophical)\b"#),
        (.neutral, #"\b(neutral|plain|plainer|balanced)\b"#),
    ]
    static let toneWhy: [Tone: String] = [
        .gentle: "Softer openings, and it ends with reassurance",
        .direct: "Fewer softeners, first thing first",
        .contemplative: "It leaves you with a question",
        .neutral: "Plain and even",
    ]

    // Times said in words ("ten thirty", "nine-thirty", "half past nine", "5 to 9", "at nine") become digits first.
    static let units = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
    static let teens = ["ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    static let tens = ["twenty", "thirty", "forty", "fifty"]
    static let number: [String: Int] = {
        var n: [String: Int] = [:]
        for (i, w) in units.enumerated() { n[w] = i + 1 }
        for (i, w) in teens.enumerated() { n[w] = i + 10 }
        for (i, w) in tens.enumerated() { n[w] = (i + 2) * 10 }
        return n
    }()
    static let hourWord = "(\((units + ["ten", "eleven", "twelve"]).joined(separator: "|")))"
    /// An hour in words or digits, for "half past 9" and "9 thirty".
    static let hour = "(\((units + ["ten", "eleven", "twelve"]).joined(separator: "|"))|1[0-2]|[1-9])"
    static let tensWord = "(?:\(tens.joined(separator: "|")))(?:[ -](?:\(units.joined(separator: "|"))))?"
    /// Minutes after an hour: "thirty", "fifteen", "forty-five", "oh five".
    static let minuteWord = "((?:oh|o)[ -](?:\(units.joined(separator: "|")))|\(teens.joined(separator: "|"))|\(tensWord))"
    /// Minutes before "past" or "to": "five", "ten", "twenty-five", "5", "20".
    static let offset = #"(\d{1,2}|"# + "\(units.joined(separator: "|"))|\(teens.joined(separator: "|"))|\(tensWord))"

    static func hourValue(_ h: String) -> Int { number[h] ?? Int(h) ?? 0 }
    static func wordValue(_ words: String) -> Int {
        if let n = Int(words), words.allSatisfy(\.isNumber) { return n }
        return words.split(whereSeparator: { $0 == " " || $0 == "-" }).reduce(0) { $0 + (number[String($1)] ?? 0) }
    }
    static func pad2(_ n: Int) -> String { String(format: "%02d", n) }

    static func spellTimes(_ text: String) -> String {
        text
            // "7-30" is 7:30.
            .jsReplace(#"\b([01]?\d|2[0-3])-([0-5]\d)\b(?!\s*(?:%|percent|min|mins|minutes?|hours?|hrs?|days?|weeks?))"#, with: "$1:$2")
            .jsReplace(#"\b(from )?(?:(quarter|half)|"# + offset + #"( minutes?)?) (past|after|to|before|till) "# + hour + #"\b"#) { g, before in
                let whole = g[0] ?? ""
                // "From 9:30 to 10": the 30 is the first time's minutes.
                if before.jsTest(#"[:.]$"#) { return whole }
                let (from, part, offset, unit, relation, hourWord) = (g[1], g[2], g[3], g[4], g[5] ?? "", g[6] ?? "")
                let minutes = part == "quarter" ? 15 : part == "half" ? 30 : wordValue(offset ?? "")
                // "From 8 to 9", "change 8 to 9" are two times (parseClock takes the second): a number before "to" counts
                // as minutes only in fives ("5 to 9"), with "minutes", or said as a time ("at 3 to 9" is 8:57).
                // ponytail: "change 10 to 11" still reads as 10:50, as on the web.
                let toward = relation != "past" && relation != "after"
                if from != nil || (offset != nil && unit == nil && toward && minutes % 5 != 0 && !before.jsTest(#"\b(?:at|around|about|by) $"#)) {
                    return whole
                }
                let h = hourValue(hourWord)
                if minutes <= 0 || minutes >= 60 { return whole }
                if relation == "past" || relation == "after" { return "\(h):\(pad2(minutes))" }
                return part == "half" ? whole : "\(h == 1 ? 12 : h - 1):\(pad2(60 - minutes))"
            }
            .jsReplace(#"\bhalf "# + hour + #"\b"#) { g, _ in "\(hourValue(g[1] ?? "")):30" }
            .jsReplace(#"\b"# + hour + "[ -]" + minuteWord + #"\b"#) { g, _ in "\(hourValue(g[1] ?? "")):\(pad2(wordValue(g[2] ?? "")))" }
            .jsReplace(#"\b"# + hourWord + #"(?= ?(?:o'?clock|am|pm)\b)"#) { g, _ in "\(number[g[1] ?? ""] ?? 0)" }
            .jsReplace(#"\b(at|around|by|until|till|from|about|to) "# + hourWord + #"\b"#) { g, _ in "\(g[1] ?? "") \(number[g[2] ?? ""] ?? 0)" }
            .jsReplace(#"(\d) ?o'?clock\b"#, with: "$1")
    }

    static func normalize(_ text: String) -> String {
        spellTimes(
            text.lowercased()
                .jsReplace("[’‘]", with: "'")
                .jsReplace(#"\ba\.m\.?"#, with: "am")
                .jsReplace(#"\bp\.m\.?"#, with: "pm")
                .jsReplace(#"\ban hour and a half\b"#, with: "90 min")
                .jsReplace(#"\s+"#, with: " ")
        )
        .jsReplace(#"[.!?]+$"#, with: "")
        .jsTrim
        // "Don't forget to remind me" asks for a reminder, and "forget about the reminder" turns it off: neither is
        // about deleting data.
        .jsReplace(#"\b(?:don't|do not|never) forget (?:to |about )?"#, with: "")
        .jsReplace(#"\bforget it\b"#, with: "")
        .jsReplace(#"\b(?:forget|never mind|cancel|scrap|ditch|drop|kill|clear|remove|delete) (?:about )?(?:the |my |that |this )?(?:daily )?(?:reminders?|notifications?|nudges?)\b"#,
                   with: "reminder off")
        .jsTrim
    }

    static func direction(_ clause: String) -> Bool? {
        if clause.jsTest(off) { return false }
        if clause.jsTest(on) { return true }
        return nil
    }

    static func isBare(_ clause: String) -> Bool { clause.split(separator: " ", omittingEmptySubsequences: false).count <= 2 }

    /// "sounds and haptics off": a bare one- or two-word clause borrows the nearest clause's on/off, the previous first.
    static func fillDirections(_ clauses: [String]) -> [Bool?] {
        var out = clauses.map(direction)
        func bare(_ i: Int) -> Bool { out[i] == nil && isBare(clauses[i]) }
        if out.count > 1 {
            for i in 1..<out.count where bare(i) { out[i] = out[i - 1] }
            for i in stride(from: out.count - 2, through: 0, by: -1) where bare(i) { out[i] = out[i + 1] }
        }
        return out
    }

    enum Period: String { case morning, afternoon, evening }
    static let periods: [(Period, String)] = [
        (.morning, #"\bmornings?\b"#), (.afternoon, #"\bafternoons?\b"#), (.evening, #"\b(?:evenings?|nights?|tonight)\b"#),
    ]
    /// "In the morning", "every evening", "at night".
    static func periodOf(_ clause: String) -> Period? { periods.first { clause.jsTest($0.1) }?.0 }

    // When a period is named without a time: its span (the evening running past midnight) and the time to offer.
    static let periodSpan: [Period: (from: Int, to: Int, pick: Int)] = [
        .morning: (5 * 60, 12 * 60, 8 * 60), .afternoon: (12 * 60, 17 * 60, 14 * 60), .evening: (17 * 60, 29 * 60, 21 * 60),
    ]
    /// The current time when it's already in `period`, else the period's own time.
    static func periodTime(_ period: Period, current: Int) -> Int {
        let span = periodSpan[period]!
        let at = current < span.from ? current + Rhythm.dayMinutes : current
        return at < span.to ? current : span.pick
    }

    /// "9", "10:40", "9 30", "930", "9pm", "9.30 am", "21:30", "noon", "7 in the morning". A bare hour from 1 to 11 means
    /// pm; a morning or evening word, a leading zero ("09:30") or a 24-hour time means what it says.
    public static func parseClock(_ clause: String) -> Clock? {
        // "From 8 to 9", "change it 8 to 9": the new time is the one after "to" (the period still comes from the clause).
        let said = clause.jsMatch(#"\b(?:from|change|move|switch|shift)\b.*\bto (\d.*)$"#)?[1] ?? clause
        if said.jsTest(#"\bnoon\b|\bmidday\b"#) { return .time(minutes: 12 * 60, assumedPm: false) }
        if said.jsTest(#"\bmidnight\b"#) { return .time(minutes: 0, assumedPm: false) }
        guard let m = said.jsMatch(#"(?:^|[^\d:.])(\d{1,4})(?:[:.](\d{1,2})|\s(\d{2}))?\s*(am|pm)?(?![\d%:.]|\s*(?:%|percent|min\b|mins\b|minutes?|hours?|hrs?\b|h\b|x\b|days?|weeks?|times?|things?))"#),
              let digits = m[1] else { return nil }
        let (colonMinutes, spaceMinutes, meridiem) = (m[2], m[3], m[4])
        let bad = Clock.invalid((m[0] ?? "").jsReplace(#"^\D"#, all: false, with: "").jsTrim)
        var hour = Int(digits) ?? 0
        var minute = Int(colonMinutes ?? spaceMinutes ?? "0") ?? 0
        if digits.count > 2 {
            // "930", "2130": the last two digits are the minutes.
            if colonMinutes != nil || spaceMinutes != nil { return bad }
            hour = Int(digits.dropLast(2)) ?? 0
            minute = Int(digits.suffix(2)) ?? 0
        }
        if minute > 59 || colonMinutes?.count == 1 { return bad }
        if let meridiem {
            if hour < 1 || hour > 12 { return bad }
            return .time(minutes: (hour % 12 + (meridiem == "pm" ? 12 : 0)) * 60 + minute, assumedPm: false)
        }
        if hour > 23 { return bad }
        if let period = periodOf(clause) {
            // "7 in the morning" is 7 am, "10 at night" 10 pm, "12 at night" midnight; "19 in the morning" isn't a time.
            if hour > 12 { return period == .morning ? bad : .time(minutes: hour * 60 + minute, assumedPm: false) }
            let h = hour == 0 ? 0 : hour == 12 ? (period == .afternoon ? 12 : 0) : period == .morning ? hour : hour + 12
            return .time(minutes: h * 60 + minute, assumedPm: false)
        }
        let assumedPm = (1...11).contains(hour) && digits.first != "0"
        return .time(minutes: (assumedPm ? hour + 12 : hour) * 60 + minute, assumedPm: assumedPm)
    }

    /// "30 min earlier", "an hour later", "later" (±30): the shift in minutes, and the clause without it.
    static func parseShift(_ clause: String) -> (minutes: Int, rest: String)? {
        if let a = clause.jsMatch(#"\b(?:(\d+)\s*(m|mins?|minutes?|h|hrs?|hours?)|(half an? hour)|(an? hour|one hour)|(a quarter of an hour|a quarter hour|quarter of an hour))\s*(earlier|later|sooner|before|after)\b"#) {
            let size = a[1].map { (Int($0) ?? 0) * ((a[2] ?? "").hasPrefix("h") ? 60 : 1) } ?? (a[3] != nil ? 30 : a[4] != nil ? 60 : 15)
            let sign = (a[6] ?? "").jsTest("earlier|sooner|before") ? -1 : 1
            return (sign * size, clause.jsReplaceFirst(a[0] ?? "", with: " "))
        }
        guard let b = clause.jsMatch(#"\b(earlier|later|sooner)\b"#) else { return nil }
        return (b[1] == "later" ? 30 : -30, clause.jsReplaceFirst(b[0] ?? "", with: " "))
    }

    static func shiftWhy(_ minutes: Int) -> String {
        let size = abs(minutes)
        let amount = size % 60 == 0 ? "\(size / 60) \(size == 60 ? "hour" : "hours")" : "\(size) minutes"
        return "\(amount) \(minutes < 0 ? "earlier" : "later")"
    }

    // MARK: Matchers
    // Every matcher sees every clause, so "bigger text in dark mode" is two changes. The last two are weak: a focus
    // word with only a verb ("drop clarity") or a time on its own ("at 9:30") counts only when nothing else claimed it.

    struct Carry {
        enum FocusMode { case add, remove, only }
        var focus: FocusMode?
        /// The last reduce answer, for the bare second half of "reduce motion and transparency".
        var reduce: Bool?
        /// The request is about how Saro sounds ("light and playful"), so a bare "light" or "dark" isn't the palette.
        var talk: Bool
    }

    typealias Matcher = @Sendable (_ clause: String, _ dir: Bool?, _ draft: Draft, _ carry: inout Carry, _ claimed: Bool) -> Bool

    static func memory(_ clause: String, _: Bool?, _ draft: Draft, _: inout Carry, _: Bool) -> Bool {
        guard clause.jsTest(#"\b(memory|memories|remember|remembering|learning)\b"#) else { return false }
        let pause = clause.jsTest(#"\b(pause|stop|off|don't|do not|no longer|disable)\b"#) && !clause.jsTest(#"\b(unpause|resume)\b"#)
        let resume = clause.jsTest(#"\b(resume|unpause|start|again|back|on|enable)\b"#)
        guard pause || resume else { return false }
        draft.set(.memoryPaused, why: pause ? "Saro won't learn anything new. What's here stays." : "Saro learns from new entries again") {
            $0.memoryPaused = pause
        }
        return true
    }

    static func captions(_ clause: String, _ dir: Bool?, _ draft: Draft, _: inout Carry, _: Bool) -> Bool {
        guard clause.jsTest(#"\b(captions?|subtitles?)\b"#) else { return false }
        let on = dir != false
        draft.set(.captionsAlways, why: on ? "What you said stays on screen when you pause or Saro asks" : "Captions come and go with the recorder") {
            $0.captionsAlways = on
        }
        return true
    }

    /// Reduce motion or transparency: true (reduce it), false (follow the device), or nil when the clause doesn't say.
    static func reduceChoice(_ clause: String, _ dir: Bool?) -> Bool? {
        let follow = clause.jsTest(#"\b(follow\w*|device|system|default|normal)\b"#)
        // "Reduce motion" asks for less; "don't reduce motion" and "turn off reduced motion" ask for the device's again.
        if clause.jsTest(#"\breduc\w*"#) { return !(dir == false || follow) }
        if follow { return false }
        // Otherwise the clause is about the effect itself: less of it is the reduce switch on, more of it is off.
        if dir == false || clause.jsTest(#"\b(less|fewer|calm\w*|minimi[sz]e|hate|too much|remove|solid|opaque|dizzy|sick|nause\w*)\b"#) { return true }
        if dir == true || clause.jsTest(#"\b(more|like|love|keep|back|full|allow|want)\b"#) { return false }
        return nil
    }

    static func reduceMatcher(_ key: Key, object: String, whyOn: String) -> Matcher {
        { clause, dir, draft, carry, _ in
            guard clause.jsTest(object), let choice = reduceChoice(clause, dir) ?? (isBare(clause) ? carry.reduce : nil) else { return false }
            carry.reduce = choice
            draft.set(key, why: choice ? whyOn : "Follows your device again") {
                if key == .reduceMotion { $0.reduceMotion = choice } else { $0.reduceTransparency = choice }
            }
            return true
        }
    }

    static func sounds(_ clause: String, _ dir: Bool?, _ draft: Draft, _: inout Carry, _: Bool) -> Bool {
        // Not "quiet": "a quiet reminder at 9" is about the reminder.
        guard clause.jsTest(#"\b(sounds?|audio|mute|unmute|silent|silence|chimes?)\b"#) else { return false }
        let on = clause.jsTest(#"\bunmute\b"#) || (!clause.jsTest(#"\b(mute|silent|silence)\b"#) && dir != false)
        draft.set(.sounds, why: on ? "Saro has no sounds yet; this lets them play when it does" : "Keeps Saro quiet") { $0.sounds = on }
        return true
    }

    static func haptics(_ clause: String, _ dir: Bool?, _ draft: Draft, _: inout Carry, _: Bool) -> Bool {
        guard clause.jsTest(#"\b(haptics?|vibrat\w*)\b|\bbuzz(?!\s+me\b)\w*"#) else { return false }
        let on = dir != false
        draft.set(.haptics, why: on ? "A light tap on the trackpad when cards snap into place" : "Keeps Saro still") { $0.haptics = on }
        return true
    }

    // A palette is named, not switched: only the clause's own "off" flips it ("dark mode off"), never a neighbour's.
    static func theme(_ clause: String, _: Bool?, _ draft: Draft, _ carry: inout Carry, _: Bool) -> Bool {
        let dir = direction(clause)
        let named = clause.jsTest(#"\b(mode|theme|palette|appearance|colou?rs?|screen|background)\b"#)
        // "Auto" alone or with a palette word; "automatic reminders" isn't about the palette.
        let auto = clause.jsTest(#"follow(s|ing)? the (day|sun|clock|time)|\bby the (hour|clock)\b"#)
            || (clause.jsTest(#"\bauto(matic)?\b"#) && (named || clause.jsTest(#"^(?:(?:go|set it to|back to|switch to|make it) )?auto(?:matic)?$"#)))
        // "When it gets dark" is a time and "light and playful" is a voice: only a named palette overrides either.
        let bareWord = named || !(carry.talk || clause.jsTest(dusk) || clause.jsTest(talk))
        let dark = bareWord && clause.jsTest(#"\b(dark|darker)\b|\bnight (mode|palette|theme)\b"#)
        let light = bareWord && clause.jsTest(#"\b(light|lighter)\b|\bday (mode|palette|theme)\b"#)
        guard auto || dark || light else { return false }
        let pick: SettingsValues.Appearance = auto ? .clock : dark ? (dir == false ? .light : .dark) : dir == false ? .dark : .light
        let why = pick == .clock ? "Night palette from 8 pm, day from 6 am" : pick == .light ? "The day palette at every hour" : "The night palette at every hour"
        draft.set(.theme, why: why) { $0.theme = pick }
        return true
    }

    static func textSize(_ clause: String, _: Bool?, _ draft: Draft, _: inout Carry, _: Bool) -> Bool {
        let sized = clause.jsTest(#"\b(text|font|fonts|type|letters|words|size|everything|zoom)\b"#)
        // "Up" and "down" only count next to a size word ("set up a reminder" isn't about text).
        let grow = clause.jsTest(#"\b(bigger|larger|increase|grow|enlarge)\b"#) || (sized && clause.jsTest(#"\b(zoom in|up)\b"#))
        let shrink = clause.jsTest(#"\b(smaller|decrease|shrink)\b"#) || (sized && clause.jsTest(#"\b(zoom out|down)\b"#))
        guard sized || grow || shrink || clause.jsTest(#"\b(biggest|largest|smallest)\b"#) else { return false }
        let scales = Prefs.textScales
        let current = draft.values.textScale
        let index = scales.firstIndex(of: current) ?? 1
        var next: Double?
        if let p = clause.jsMatch(#"(\d{2,3}(?:\.\d+)?)\s*(%|percent)"#), let want = Double(p[1] ?? "").map({ $0 / 100 }) {
            next = scales.reduce(scales[0]) { abs($1 - want) < abs($0 - want) ? $1 : $0 }
        } else if clause.jsTest(#"\b(biggest|largest|max|maximum)\b"#) { next = scales.last
        } else if clause.jsTest(#"\b(smallest|minimum)\b"#) { next = scales.first
        } else if grow { next = scales[min(scales.count - 1, index + 1)]
        } else if shrink { next = scales[max(0, index - 1)]
        } else if clause.jsTest(#"\b(normal|default|reset|regular|standard|usual)\b"#) { next = 1 }
        guard let next else { return false }
        if next == current, grow || shrink {
            draft.addNote(grow ? "Text is already at its largest, \(pct(current))." : "Text is already at its smallest, \(pct(current)).")
            return true
        }
        draft.set(.textScale, why: "Every screen, on this Mac") { $0.textScale = next }
        return true
    }

    static func tone(_ clause: String, _: Bool?, _ draft: Draft, _: inout Carry, _: Bool) -> Bool {
        // The saved tone, not the draft's: "keep it light and playful" is asked twice and must read the same both times.
        guard let saved = draft.current.tone else { return false }
        let less = clause.jsMatch(#"\bless (gentle|soft|kind|warm|direct|blunt)\b"#)
        let named = toneWords.first { clause.jsTest($0.1) }?.0
        if less == nil, named == nil, clause.jsTest(playful) {
            if saved == .gentle { draft.addNote("Saro has no playful tone yet. Gentle is the closest, and it’s already on.") }
            else { draft.set(.tone, why: "The closest to playful; Saro has no playful tone yet") { $0.tone = .gentle } }
            return true
        }
        guard let pick = less.map({ ($0[1] ?? "").jsTest("gentle|soft|kind|warm") ? Tone.direct : .gentle }) ?? named else { return false }
        draft.set(.tone, why: toneWhy[pick] ?? "") { $0.tone = pick }
        return true
    }

    static func unreadable(_ words: String) -> String { "I couldn’t read “\(words)” as a time. Try 9:30 pm or 21:30." }

    /// Words after "at" that no rule read as a time ("at teatime", "at half past"), to say back rather than ignore.
    static func unreadTime(_ clause: String) -> String? {
        clause.jsMatch(#"\b(?:at|around|by)\s+(?!\d)([a-z'-]+(?:\s+(?!(?:in|on|every|each|and)\b)[a-z'-]+)?)"#)?[1]
    }

    /// Sets the reminder or the letter from the time in `clause`: a clock time, a shift, "when it gets dark", "in the
    /// morning", or on/off.
    static func setTime(letter: Bool, _ clause: String, _ dir: Bool?, _ draft: Draft) -> Bool {
        let shift = parseShift(clause)
        let rest = shift?.rest ?? clause
        let clock = parseClock(rest)
        if case .invalid(let words) = clock {
            draft.addNote(unreadable(words))
            return true
        }
        var minutes: Int?
        var assumedPm = false
        if case .time(let m, let pm) = clock { (minutes, assumedPm) = (m, pm) }
        let isDusk = minutes == nil && clause.jsTest(dusk)
        let period = minutes != nil || isDusk ? nil : periodOf(rest)
        let current = letter ? draft.values.letterMinutes : draft.values.reminderMinutes
        let at = minutes ?? (isDusk ? duskMinutes : period.map { periodTime($0, current: current) })
        let why: String? = if let minutes, assumedPm {
            "Read as \(minutes < 17 * 60 ? "afternoon" : "evening"): \(Rhythm.formatClock(minutes)), not morning"
        } else if isDusk {
            "When Saro turns to its night palette"
        } else if let period {
            "In the \(period.rawValue). Say a time to pick another"
        } else { nil }
        let unread = at == nil && shift == nil ? unreadTime(clause) : nil

        if letter {
            let next = at ?? shift.map { current + $0.minutes }
            if let at { draft.set(.letterTime, why: why ?? "The evening letter waits until then") { $0.letterMinutes = Rhythm.mod(at) } }
            else if let shift { draft.set(.letterTime, why: shiftWhy(shift.minutes)) { $0.letterMinutes = Rhythm.mod(current + shift.minutes) } }
            else if let unread { draft.addNote(unreadable(unread)) }
            else { return false }
            // The letter is written from the day, so before 5 pm it opens with most of the day still to come.
            if let next, Rhythm.mod(next) < periodSpan[.evening]!.from {
                draft.addNote("The evening letter is written from your day. At \(Rhythm.formatClock(next)) it opens before most of the day has happened.")
            }
            return true
        }

        // "Don't remind me at 9" is off, whatever the time says.
        if dir == false, shift == nil { draft.set(.reminder, why: "No daily nudge") { $0.reminderOn = false } }
        else if let at { draft.set(.reminder, why: why ?? "A daily nudge, even when Saro is closed") { ($0.reminderOn, $0.reminderMinutes) = (true, Rhythm.mod(at)) } }
        else if let shift {
            draft.set(.reminder, why: "\(shiftWhy(shift.minutes)) than \(Rhythm.formatClock(current))") {
                ($0.reminderOn, $0.reminderMinutes) = (true, Rhythm.mod(current + shift.minutes))
            }
        } else if let unread { draft.addNote(unreadable(unread)) }
        else { draft.set(.reminder, why: "A daily nudge, even when Saro is closed") { $0.reminderOn = true } }
        return true
    }

    static func times(_ clause: String, _ dir: Bool?, _ draft: Draft, _: inout Carry, _: Bool) -> Bool {
        if clause.jsTest(#"\bletters?\b"#) { return setTime(letter: true, clause, dir, draft) }
        if clause.jsTest(reminderWords) { return setTime(letter: false, clause, dir, draft) }
        return false
    }

    static func focus(_ clause: String, _: Bool?, _ draft: Draft, _ carry: inout Carry, _ claimed: Bool) -> Bool {
        let picks = focusWords.filter { clause.jsTest($0.1) }.map(\.0)
        let named = clause.jsTest(#"\b(focus\w*|lens|aim)\b"#)
        // "Drop habits", "add sleep": a pick verb is enough when nothing else claimed the clause.
        if picks.isEmpty || (!named && carry.focus == nil && (claimed || !clause.jsTest(#"\b(add|drop|remove|unpick)\b"#))) { return false }
        guard let current = draft.values.focus else { return false }
        let mode: Carry.FocusMode = clause.jsTest(#"\b(remove|drop|stop|no longer|less|unpick|without|not|don't|take off|off)\b"#) ? .remove
            : clause.jsTest(#"\b(only|just)\b"#) ? .only
            : named ? .add
            : carry.focus == .remove ? .remove : .add
        carry.focus = mode == .only ? .add : mode
        var next = mode == .only ? [] : current
        if mode == .remove {
            next.removeAll { picks.contains($0) }
        } else {
            for key in picks where !next.contains(key) {
                if next.count >= maxFocus {
                    draft.addNote("You can pick 3. Drop one first.")
                    break
                }
                next.append(key)
            }
        }
        let order = FocusArea.allCases
        next.sort { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
        draft.set(.focus, why: "What Saro looks for in your entries, up to 3") { [next] in $0.focus = next }
        return true
    }

    /// "At 9:30", "an hour later", "when it gets dark": a time on its own moves the reminder.
    static func bareTime(_ clause: String, _ dir: Bool?, _ draft: Draft, _: inout Carry, _ claimed: Bool) -> Bool {
        guard !claimed, parseShift(clause) != nil || clause.jsTest(timeAsked) || clause.jsTest(dusk) else { return false }
        return setTime(letter: false, clause, dir, draft)
    }

    static let matchers: [Matcher] = [
        memory, captions,
        reduceMatcher(.reduceMotion, object: #"\b(motion|animat\w*|movement|transitions?)\b"#, whyOn: "Things fade instead of moving"),
        reduceMatcher(.reduceTransparency, object: #"\b(transparen\w*|translucen\w*|blur\w*|glass\w*|frost\w*|see-through|solid|opaque)\b"#,
                      whyOn: "Solid surfaces instead of frosted glass"),
        sounds, haptics, theme, textSize, tone, times, focus, bareTime,
    ]

    // MARK: Parse

    /// What someone asked for, as proposed changes against `current`. Never writes anything.
    public static func parse(_ text: String, current: SettingsValues) -> Result {
        let raw = normalize(text)
        if raw.isEmpty { return .none }
        if raw.jsTest(needsYou) { return .needsYou }

        let clauses = raw.jsSplit(split).filter { !$0.isEmpty }
        let dirs = fillDirections(clauses)
        let draft = Draft(current)
        var carry = Carry(talk: raw.jsTest(playful))
        for (i, clause) in clauses.enumerated() {
            var claimed = false
            for match in matchers where match(clause, dirs[i], draft, &carry, claimed) { claimed = true }
        }

        var changes: [Change] = []
        var already: [String] = []
        for key in draft.order {
            guard let from = format(key, current), let to = format(key, draft.values) else { continue }
            if same(key, current, draft.values) { already.append(Self.already(key, draft.values)); continue }
            changes.append(Change(key: key, label: label(key), why: draft.whys[key] ?? "", from: from, to: to))
        }
        // Alongside real changes, a part that's already set is still said, not dropped.
        let note = (draft.notes + (changes.isEmpty ? [] : already)).joined(separator: " ")
        if !changes.isEmpty { return .changes(changes, note: note.isEmpty ? nil : note, proposed: draft.values) }
        let message = note.isEmpty ? already.prefix(2).joined(separator: " ") : note
        return message.isEmpty ? .none : .alreadySet(message)
    }

    /// Whether a value a model proposed is one these specs allow, so a fallback is checked as strictly as the rules.
    public static func valid(_ v: SettingsValues) -> Bool {
        (0..<Rhythm.dayMinutes).contains(v.reminderMinutes) && (0..<Rhythm.dayMinutes).contains(v.letterMinutes)
            && Prefs.textScales.contains(v.textScale) && (v.focus?.count ?? 0) <= maxFocus && Set(v.focus ?? []).count == (v.focus?.count ?? 0)
    }
}
