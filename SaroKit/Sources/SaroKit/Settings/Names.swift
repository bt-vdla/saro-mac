/// The name fields' rules (ProfileSheet.tsx capName, ProfileAvatar.tsx initialsOf), on grapheme boundaries, so an
/// emoji or an accented letter is never split.
public enum Names {
    public static let max = 60

    /// Trimmed, then capped at 60 characters, then trimmed again, so capping twice changes nothing.
    public static func cap(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first letters of the first and last words, or "—" with no name.
    public static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard let first = words.first?.first else { return "—" }
        let last = words.count > 1 ? words.last?.first.map(String.init) ?? "" : ""
        return (String(first) + last).uppercased()
    }
}
