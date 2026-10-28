import Foundation

/// Saro's hello for a local hour (lib/auth/email.ts greetingFor), shared by the welcome door and the lock screen.
public enum Greeting {
    static let bands: [(from: Double, eyebrow: String, line: String)] = [
        (0, "Small hours", "Still up."),
        (4.5, "Before dawn", "Up before the light."),
        (6, "Morning", "Good morning."),
        (10, "Late morning", "The day is still open."),
        (12, "Afternoon", "Good afternoon."),
        (15, "Late afternoon", "The light is turning."),
        (17.5, "Evening", "Good evening."),
        (20, "Night", "The day is settling."),
        (22.5, "Late", "The quiet hours."),
    ]

    /// The band (0–8) for an hour of 0–24, fractional; it changes only when the words do.
    public static func band(hour: Double) -> Int {
        let h = (hour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
        return bands.lastIndex { h >= $0.from } ?? 0
    }

    public static func line(hour: Double) -> String { bands[band(hour: hour)].line }

    /// The band's mono eyebrow, e.g. 'Late morning'.
    public static func eyebrow(hour: Double) -> String { bands[band(hour: hour)].eyebrow }

    public static func line(at date: Date = .now) -> String { line(hour: Sky.localHour(date)) }
}
