import Foundation

/// The toast stack's rules (use-toast.ts): at most three, newest first; same-title toasts within a second fold into
/// one that counts them; past the limit the oldest without an action close, and one with an action never does.
public enum ToastRules {
    public static let limit = 3
    public static let foldWindow: TimeInterval = 1

    public struct Shown: Sendable, Hashable {
        public var title: String
        public var destructive: Bool
        public var at: Date
        public var hasAction: Bool
        public var count: Int

        public init(title: String, destructive: Bool, at: Date, hasAction: Bool, count: Int = 1) {
            (self.title, self.destructive, self.at, self.hasAction, self.count) = (title, destructive, at, hasAction, count)
        }
    }

    /// For a toast arriving over `shown` (newest first): the indexes that fold into it, its count, and those that close.
    public static func arrive(_ new: Shown, over shown: [Shown]) -> (twins: [Int], count: Int, closing: [Int]) {
        let twins = shown.indices.filter {
            shown[$0].title == new.title && shown[$0].destructive == new.destructive && new.at.timeIntervalSince(shown[$0].at) < foldWindow
        }
        let count = twins.reduce(1) { $0 + shown[$1].count }
        let open = shown.indices.filter { !twins.contains($0) }
        let excess = open.count - (limit - 1)
        let closing = excess > 0 ? Array(open.filter { !shown[$0].hasAction }.suffix(excess)) : []
        return (twins, count, closing)
    }

    public static func title(_ base: String, count: Int) -> String { count > 1 ? "\(base) (\(count))" : base }
}

/// Every user-content write, keyed by what it saves (save-status.ts): one card's failure can't be hidden by another's
/// success, and a deleted card's failure is forgotten.
public struct SaveTally: Sendable, Hashable {
    public private(set) var pending = 0
    public private(set) var failed: Set<String> = []

    public init() {}

    public mutating func begin() { pending += 1 }

    public mutating func end(_ key: String, saved: Bool) {
        pending = max(0, pending - 1)
        if saved { failed.remove(key) } else { failed.insert(key) }
    }

    public mutating func forget(_ key: String) { failed.remove(key) }

    /// What a screen reader hears, and the dot shows.
    public var label: String { pending > 0 ? "Saving…" : failed.isEmpty ? "Saved" : "Not saved" }
}

/// Trash's countdown (TrashModal.tsx timeLeft): hours on the last day, days before it.
public enum TrashClock {
    public static func left(until expiry: Date, now: Date = .now) -> String {
        let s = expiry.timeIntervalSince(now)
        if s < 86_400 {
            let hours = max(1, Int((s / 3600).rounded(.up)))
            return "\(hours) \(hours == 1 ? "hour" : "hours") left"
        }
        let days = Int((s / 86_400).rounded())
        return "\(days) \(days == 1 ? "day" : "days") left"
    }
}

public enum ShellText {
    /// The avatar's letters (ProfileAvatar.tsx initialsOf): the first word's first and the last word's first.
    public static func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        guard let first = parts.first?.first else { return "" }
        let last = parts.count > 1 ? parts.last?.first.map(String.init) ?? "" : ""
        return (String(first) + last).uppercased()
    }

    /// "27 Oct 2026", the same in every locale so names sort and read alike.
    public static func fileDay(_ day: String) -> String {
        guard let d = LocalDay.date(day) else { return day }
        return d.formatted(Date.VerbatimFormatStyle(format: "\(day: .defaultDigits) \(month: .abbreviated) \(year: .defaultDigits)",
                                                    locale: Locale(identifier: "en_GB"), timeZone: .current, calendar: Calendar(identifier: .gregorian)))
    }

    /// A readable name for an exported copy: "Saro moment, 27 Oct 2026.mov".
    public static func exportName(_ kind: EntryKind, day: String, ext: String) -> String {
        let noun = switch kind {
        case .moment: "moment"
        case .voice: "voice note"
        case .still: "still"
        case .reflection: "reflection"
        case .music: "song"
        }
        return "Saro \(noun), \(fileDay(day))" + (ext.isEmpty ? "" : ".\(ext)")
    }

    public static func dayImageName(_ day: String) -> String { "saro-\(day).png" }

    /// Where a song's link goes, as its card names it (lib/demo/music.ts sourceFor, MusicCard.tsx's labels).
    public static func musicSource(_ link: String) -> String {
        guard let host = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines))?.host()?.lowercased() else { return "Music link" }
        let on = { (domain: String) in host == domain || host.hasSuffix("." + domain) }
        if on("music.youtube.com") { return "YouTube Music" }
        if on("youtube.com") || on("youtu.be") || on("youtube-nocookie.com") { return "YouTube" }
        if on("spotify.com") || on("spotify.link") { return "Spotify" }
        if on("music.apple.com") { return "Apple Music" }
        if on("jiosaavn.com") { return "JioSaavn" }
        if on("soundcloud.com") { return "SoundCloud" }
        if on("tidal.com") { return "Tidal" }
        return "Music link"
    }

    /// Text laid out right to left when its first strong character is (dir="auto"): Hebrew, Arabic, Syriac, Thaana,
    /// N'Ko and their presentation forms. Digits, spaces and punctuation are weak and are skipped.
    public static func isRightToLeft(_ text: String) -> Bool {
        for s in text.unicodeScalars where s.properties.isAlphabetic {
            switch s.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF: return true
            default: return false
            }
        }
        return false
    }
}

/// Export Day as Image (Canvas.tsx): 48 pt around the cards, up to twice the points, the longest side at most 4096 px.
public enum DayImageMath {
    public static let pad: Double = 48
    public static let maxSide: Double = 4096

    public static func scale(for size: CGSize) -> Double {
        min(2, maxSide / max(1, max(size.width, size.height)))
    }

    /// The stage in whole points, so the ground reaches its last pixel row.
    public static func stage(_ size: CGSize) -> CGSize { CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up)) }

    /// The picture's whole pixels for a stage: never a row or column the ground only partly covers.
    public static func pixels(for stage: CGSize) -> (width: Int, height: Int) {
        let s = scale(for: stage)
        return (Int((stage.width * s + 1e-6).rounded(.down)), Int((stage.height * s + 1e-6).rounded(.down)))
    }
}

extension Prefs.LockAfter {
    /// How long Saro may be away or idle before it locks; nil locks only at launch and on sleep.
    public var seconds: TimeInterval? {
        switch self {
        case .immediately: 0
        case .fiveMinutes: 300
        case .hour: 3600
        case .never: nil
        }
    }
}

/// Plain words for a failed write, never the raw error (FR-SHELL): what to do here on this Mac.
public enum FailureCopy {
    public static func remedy(for error: Error) -> String {
        outOfSpace(error) ? "Your Mac may be out of space." : "Try again in a moment."
    }

    static func outOfSpace(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain && e.code == NSFileWriteOutOfSpaceError { return true }
        if e.domain == NSPOSIXErrorDomain && e.code == Int(ENOSPC) { return true }
        if let s = error as? SQLiteError, s.description.contains("full") { return true }
        return (e.userInfo[NSUnderlyingErrorKey] as? Error).map(outOfSpace) ?? false
    }

    /// Content-free, for the log and the Alpha report: the error's domain and code, never its message.
    public static func code(_ error: Error) -> String {
        let e = error as NSError
        return "\(e.domain) \(e.code)"
    }
}

/// Every shortcut, in one table: the menus, the palette and the Keyboard Shortcuts window all take their keys from here.
public struct Shortcut: Sendable, Hashable, Identifiable {
    public enum Group: String, Sendable, CaseIterable { case capture = "Capture", days = "Days", canvas = "Canvas", search = "Search", windows = "Windows" }
    public var group: Group
    public var title: String
    public var keys: String
    /// Only while this is open; shortcuts with a scope may reuse keys of the app-wide ones.
    public var scope: String?
    public var id: String { "\(group.rawValue)|\(title)" }

    init(_ group: Group, _ title: String, _ keys: String, scope: String? = nil) {
        (self.group, self.title, self.keys, self.scope) = (group, title, keys, scope)
    }

    /// One chord a menu item can carry: its modifiers and a key, which is a character or "delete", "return" or "escape".
    public struct Chord: Sendable, Hashable {
        public enum Modifier: Sendable, Hashable { case control, option, shift, command }
        public var modifiers: Set<Modifier>
        public var key: String
    }

    /// The keys as a chord; nil for what isn't one (← →, Space, ⇧F10).
    public var chord: Chord? {
        let glyphs: [Character: Chord.Modifier] = ["⌃": .control, "⌥": .option, "⇧": .shift, "⌘": .command]
        var modifiers = Set<Chord.Modifier>()
        var rest = Substring(keys)
        while let c = rest.first, let m = glyphs[c] {
            modifiers.insert(m)
            rest = rest.dropFirst()
        }
        let key: String? = switch rest {
        case "⌫": "delete"
        case "↵": "return"
        case "Esc": "escape"
        default: rest.count == 1 ? rest.lowercased() : nil
        }
        return key.map { Chord(modifiers: modifiers, key: $0) }
    }

    public static let recordMoment = Shortcut(.capture, "Record a moment", "⌘N")
    public static let voiceNote = Shortcut(.capture, "Leave a voice note", "⇧⌘N")
    public static let write = Shortcut(.capture, "Write", "⌥⌘W")
    public static let captureAnywhere = Shortcut(.capture, "Capture from anywhere", "⌃⌘J")
    public static let pasteStill = Shortcut(.capture, "Paste a photo as a still", "⌘V")
    public static let today = Shortcut(.days, "Today", "⌘T")
    public static let previousDay = Shortcut(.days, "Previous day", "⌘[")
    public static let nextDay = Shortcut(.days, "Next day", "⌘]")
    public static let showDays = Shortcut(.days, "Show days", "⌃⌘S")
    public static let noticed = Shortcut(.days, "What Saro noticed", "⌥⌘I")
    public static let letter = Shortcut(.days, "Evening letter", "⌥⌘L")
    public static let fitDay = Shortcut(.canvas, "Fit the day", "⌘0")
    public static let zoomIn = Shortcut(.canvas, "Zoom in", "⌘=")
    public static let zoomOut = Shortcut(.canvas, "Zoom out", "⌘-")
    public static let editDetails = Shortcut(.canvas, "Edit details", "⌘I")
    public static let exportCopy = Shortcut(.canvas, "Export a copy", "⇧⌘S")
    public static let showInFinder = Shortcut(.canvas, "Show in Finder", "⌥⌘R")
    public static let copyText = Shortcut(.canvas, "Copy text", "⇧⌘C")
    public static let stack = Shortcut(.canvas, "Stack", "⌘S")
    public static let grid = Shortcut(.canvas, "Grid", "⌘G")
    public static let moveToTrash = Shortcut(.canvas, "Move to Trash", "⌘⌫")
    public static let search = Shortcut(.search, "Search and commands", "⌘K")
    public static let whatSaroKnows = Shortcut(.windows, "What Saro knows", "⌥⌘K")
    public static let settings = Shortcut(.windows, "Settings", "⌘,")
    public static let shortcuts = Shortcut(.windows, "Keyboard shortcuts", "⌘/")
    public static let lock = Shortcut(.windows, "Lock Saro", "⌃⌘L")

    public static let all: [Shortcut] = [
        recordMoment, voiceNote, write, captureAnywhere, pasteStill,
        today, previousDay, nextDay, showDays, noticed, letter,
        Shortcut(.days, "Step through a replay", "← →", scope: "replay"),
        Shortcut(.days, "Play or pause a replay", "Space", scope: "replay"),
        fitDay, zoomIn, zoomOut,
        Shortcut(.canvas, "Open the selected card", "↵"),
        Shortcut(.canvas, "Card menu", "⇧F10"),
        editDetails, exportCopy, showInFinder, copyText, stack, grid, moveToTrash,
        Shortcut(.canvas, "Undo", "⌘Z"),
        search,
        Shortcut(.search, "Replay the row's day", "⌘↵", scope: "search"),
        Shortcut(.search, "Actions for the row", "⌘K", scope: "search"),
        Shortcut(.search, "Scope to a kind", "⌘P", scope: "search"),
        whatSaroKnows, settings, shortcuts, lock,
        Shortcut(.windows, "Close", "Esc"),
    ]
}
