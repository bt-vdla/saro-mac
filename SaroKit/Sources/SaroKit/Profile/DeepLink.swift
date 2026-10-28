import Foundation

/// The `saro://` links a notification, a Shortcut or a letter quote can open (BRD Shell: ritual reminders with deep links).
public enum DeepLink: Sendable, Hashable {
    /// `.moment`, `.voice`, or `.reflection` for writing.
    case capture(EntryKind)
    case day(String)
    case entry(String)
    case letter(String)
    /// A Settings section's raw name, or nil for the top.
    case settings(String?)
    case knows(query: String?)

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == "saro", let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = c.host?.lowercased() else { return nil }
        let arg = c.path.split(separator: "/").first.map(String.init)
        switch (host, arg) {
        case ("capture", "moment"): self = .capture(.moment)
        case ("capture", "voice"): self = .capture(.voice)
        case ("capture", "write"): self = .capture(.reflection)
        case ("day", let d?) where LocalDay.isValid(d): self = .day(d)
        case ("entry", let id?): self = .entry(id)
        case ("letter", let d?) where LocalDay.isValid(d): self = .letter(d)
        case ("settings", let s): self = .settings(s)
        case ("knows", nil): self = .knows(query: c.queryItems?.first { $0.name == "q" }?.value.flatMap { $0.isEmpty ? nil : $0 })
        default: return nil
        }
    }

    public var url: URL {
        var c = URLComponents()
        c.scheme = "saro"
        switch self {
        case .capture(let kind):
            c.host = "capture"
            c.path = "/" + (kind == .moment ? "moment" : kind == .voice ? "voice" : "write")
        case .day(let d): (c.host, c.path) = ("day", "/\(d)")
        case .entry(let id): (c.host, c.path) = ("entry", "/\(id)")
        case .letter(let d): (c.host, c.path) = ("letter", "/\(d)")
        case .settings(let s): (c.host, c.path) = ("settings", s.map { "/\($0)" } ?? "")
        case .knows(let q):
            c.host = "knows"
            if let q { c.queryItems = [URLQueryItem(name: "q", value: q)] }
        }
        return c.url!
    }
}

extension LocalDay {
    /// A real `YYYY-MM-DD` day (not 2026-02-31).
    static func isValid(_ s: String) -> Bool {
        s.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil && date(s).map { string(for: $0) == s } == true
    }
}
