import AppKit
import Observation
import SaroKit

/// Settings sections, in the rail's order; `saro://settings/<section>` opens one.
enum SettingsSection: String, CaseIterable, Hashable {
    case you, talk, rhythm, appearance, comfort, knows, intelligence, data
}

/// This Mac's preferences (DR-21), saved to UserDefaults on every change and read back through `Prefs`' sanitiser, so a
/// broken stored value falls back to its default. Read and write any `Prefs` field on it (`PrefsStore.shared.sounds`);
/// each field is observed on its own, so a view re-renders only for the fields it reads.
@MainActor @Observable @dynamicMemberLookup
final class PrefsStore {
    static let shared = PrefsStore()
    /// `-SaroDemo YES`: a throwaway journal keeps throwaway prefs, fresh each launch, so testing never changes the real ones.
    static let isDemo = UserDefaults.standard.bool(forKey: "SaroDemo")

    /// Every field at once, for code that isn't a view (scheduling, export). Views read the fields themselves.
    @ObservationIgnored private(set) var prefs: Prefs
    /// Where Settings opens or scrolls to. Not saved.
    var settingsSection: SettingsSection?
    private(set) var deviceReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private(set) var deviceReduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "saro.prefs"

    init() {
        defaults = Self.isDemo ? UserDefaults(suiteName: "SaroDemo.prefs") ?? .standard : .standard
        if Self.isDemo { defaults.removeObject(forKey: Self.key) }
        prefs = Prefs.decode(defaults.data(forKey: Self.key))
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.deviceReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self?.deviceReduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            }
        }
    }

    subscript<T>(dynamicMember field: WritableKeyPath<Prefs, T>) -> T {
        get {
            track(field)
            return prefs[keyPath: field]
        }
        set {
            withMutation(keyPath: Self.path(field)) { prefs[keyPath: field] = newValue }
            defaults.set(prefs.encoded, forKey: Self.key)
        }
    }

    /// Saro's switch, or the device's setting when the switch follows it.
    var reduceMotionEffective: Bool { self.reduceMotion || deviceReduceMotion }
    var reduceTransparencyEffective: Bool { self.reduceTransparency || deviceReduceTransparency }

    func letterDue(at date: Date = .now) -> Bool {
        track(\.letterMinutes)
        return prefs.letterDue(at: date)
    }

    /// The prefs as JSON for Export Everything. Nothing in them is a secret.
    func export() -> Data { prefs.encoded }

    /// Erase: every field back to its default, and nothing left in UserDefaults.
    func eraseAll() {
        withMutation(keyPath: \.prefs) { prefs = Prefs() }
        settingsSection = nil
        defaults.removeObject(forKey: Self.key)
    }

    /// A reader of one field hears that field's changes, and Erase's, which replaces them all.
    private func track<T>(_ field: WritableKeyPath<Prefs, T>) {
        access(keyPath: \.prefs)
        access(keyPath: Self.path(field))
    }

    private static func path<T>(_ field: WritableKeyPath<Prefs, T>) -> ReferenceWritableKeyPath<PrefsStore, T> {
        (\PrefsStore.prefs).appending(path: field)
    }
}
