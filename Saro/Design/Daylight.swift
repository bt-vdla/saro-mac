import AppKit
import SaroKit
import SwiftUI

/// The day/night palette (the web's hooks/useDaylight.ts): follow the clock (night from 8 pm to 6 am, the default),
/// the system, or always light or dark. Applied app-wide through `NSApplication.appearance`, so every `Tok` colour
/// follows. Saved on this Mac.
@Observable @MainActor
final class Daylight {
    enum Mode: String, CaseIterable { case clock, system, light, dark }

    static let shared = Daylight()

    var mode = Mode(rawValue: UserDefaults.standard.string(forKey: "daylight") ?? "") ?? .clock {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "daylight")
            apply(fade: 0.45)
        }
    }

    /// A day replay's playhead (0–24): the light of that hour, and at night the dark palette while the palette follows
    /// the day. Nil goes back to the real clock.
    @ObservationIgnored var replayHour: Double? { didSet { if replayHour != oldValue { apply(fade: 0.45) } } }

    /// The Light Lab's clock (or `-SaroHour 19.5` in dogfood builds), standing in for the real one everywhere the ground
    /// and palette read it.
    var pinnedHour: Double? = Daylight.launchHour {
        didSet { if pinnedHour != oldValue { apply(fade: 0.45) } }
    }

    private static var launchHour: Double? {
        #if DOGFOOD
        UserDefaults.standard.string(forKey: "SaroHour").flatMap(Double.init)
        #else
        nil
        #endif
    }

    /// The hour the ground is lit for when nothing pins its own.
    func hour(at date: Date) -> Double { pinnedHour ?? Sky.localHour(date) }

    @ObservationIgnored private var ticking = false

    /// Sets the palette and re-checks it on every minute. Call once at launch, before the first window shows.
    func start() {
        apply(fade: 0)
        guard !ticking else { return }
        ticking = true
        // ponytail: runs for the app's lifetime; the continuous clock fires straight after a wake from sleep.
        Task {
            while true {
                let now = Date.now.timeIntervalSinceReferenceDate
                try? await Task.sleep(for: .seconds(60 - now.truncatingRemainder(dividingBy: 60) + 0.05))
                apply(fade: 1.4)
            }
        }
    }

    /// A slow dusk when the clock flips the palette, a quick fade when the person picks one.
    private func apply(fade: Double) {
        let next: NSAppearance? = switch mode {
        case .clock: NSAppearance(named: Sky.isNight(replayHour ?? hour(at: .now)) ? .darkAqua : .aqua)
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        let app = NSApplication.shared
        guard app.appearance?.name != next?.name else { return }
        if fade > 0 {
            // The fade snapshots each window as it is and dissolves into the new palette as SwiftUI redraws it.
            for window in app.windows where window.isVisible {
                let t = CATransition()
                t.type = .fade
                t.duration = fade
                t.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
                (window.contentView?.superview?.layer ?? window.contentView?.layer)?.add(t, forKey: nil)
            }
        }
        app.appearance = next
    }
}

/// Settings → Appearance.
struct DaylightPicker: View {
    var body: some View {
        @Bindable var daylight = Daylight.shared
        Picker("Appearance", selection: $daylight.mode) {
            Text("Follow the day").tag(Daylight.Mode.clock)
            Text("System").tag(Daylight.Mode.system)
            Text("Light").tag(Daylight.Mode.light)
            Text("Dark").tag(Daylight.Mode.dark)
        }
        .pickerStyle(.segmented)
        Text(note).font(Typo.ui(12)).foregroundStyle(Tok.ink2)
    }

    private var note: String {
        switch Daylight.shared.mode {
        case .clock: "Evenings turn to the night palette at 8 pm, and mornings back at 6 am."
        case .system: "Light or dark as macOS is."
        case .light: "The day palette, at every hour."
        case .dark: "The night palette, at every hour."
        }
    }
}
