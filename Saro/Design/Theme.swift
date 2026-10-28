import AppKit
import CoreText
import SwiftUI

/// Saro's Evergreen tokens, ported from `saro/frontend/app/globals.css` (day and night).
enum Tok {
    static let bg = Color(0xF1F1EC, 0x0E1411)
    static let surface = Color(0xFAFAF6, 0x16201B)
    static let surfaceAlt = Color(0xFDFDFB, 0x1C2822)
    static let ink = Color(0x13201A, 0xE3EBE6)
    static let ink2 = Color(0x4D5A53, 0x9FB0A7)
    static let ink3 = Color(0x5C6961, 0x92A399)
    /// Decorative and disabled only, never body text.
    static let ink4 = Color(0x9AA69F, 0x56655D)
    static let border = Color(0xDDE1DA, 0x25312B)
    static let borderStrong = Color(0xC5CCC4, 0x34443C)
    static let sage = Color(0x1E4A38, 0x7FBFA0)
    static let sageDark = Color(0x173A2C, 0x95CCB1)
    static let sageTeal = Color(0x2F6B52, 0x79C3A0)
    static let sageSoft = Color(0x7FA792, 0x4F7A66)
    static let onPrimary = Color(0xFFFFFF, 0x0E1411)
    static let mint = Color(0xA8E6C6, 0xA8E6C6)
    /// Saro's own voice (text-safe on each ground).
    static let voice = Color(0xB0501F, 0xF2A078)
    static let voiceBright = Color(0xF2A078, 0xF2A078)
    static let danger = Color(0x9B3A3A, 0xE38E8B)
    static let dangerBg = Color(0xFDF4F4, 0x2A1A1A)
    static let dangerBorder = Color(0xE8CECE, 0x4A2B2B)
    static let warning = Color(0xC0824A, 0xD8A06A)
    static let glass = Color(0xFFFFFF, 0x2A3831)
    /// Floating glass fill.
    static let paper = Color(0xF1F1EC, 0x16201B)
    static let rim = Color(0xFFFFFF, 0x3F4F47)
    static let shadow = Color(0x13201A, 0x000000)
    /// Drag guides: moment green by day, echo violet at night (DragGuides.tsx).
    static let guide = Color(0x2F7A5A, 0xA7A2EC)
    static let line = Color(0xDDE1DA, 0x25312B)

    static let moment = Color(0x2F7A5A, 0x79C3A0)
    static let echo = Color(0x6560B8, 0xA7A2EC)
    static let still = Color(0xB85C45, 0xEC9A86)
    static let reflection = Color(0x8E6B1F, 0xD8B062)
    static let music = Color(0x356FA8, 0x86B7EA)
    static let momentInk = Color(0x276A4E, 0x79C3A0)
    static let echoInk = Color(0x5A55A8, 0xA7A2EC)
    static let stillInk = Color(0xA24E3A, 0xEC9A86)
    static let reflectionInk = Color(0x7D5E1A, 0xD8B062)
    static let musicInk = Color(0x2F6396, 0x86B7EA)
}

extension Color {
    /// A colour that follows the window's light or dark appearance.
    init(_ light: UInt32, _ dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Geist for UI and the user's words, Geist Mono for times and labels, Newsreader for Saro's voice. Every size follows
/// Settings → Comfort → Text size; read inside a view's body, a change re-renders it.
@MainActor
enum Typo {
    static func registerFonts() {
        guard let dir = Bundle.main.url(forResource: "Fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }

    static var geistAvailable: Bool { NSFont(name: "Geist-Regular", size: 12) != nil }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let size = size * PrefsStore.shared.textScale
        guard geistAvailable else { return .system(size: size, weight: weight) }
        let name = switch weight {
        case .medium: "Geist-Medium"
        case .semibold: "Geist-SemiBold"
        case .bold, .heavy, .black: "Geist-Bold"
        case .light, .thin, .ultraLight: "Geist-Light"
        default: "Geist-Regular"
        }
        return .custom(name, size: size)
    }

    /// Mono caps labels (metadata, shortcuts, dev notes).
    static func mono(_ size: CGFloat = 10.5, _ weight: Font.Weight = .medium) -> Font {
        let size = size * PrefsStore.shared.textScale
        guard geistAvailable else { return .system(size: size, weight: weight, design: .monospaced) }
        return .custom(weight == .regular ? "GeistMono-Regular" : "GeistMono-Medium", size: size)
    }

    static var newsreaderAvailable: Bool { NSFont(name: "Newsreader16pt-Regular", size: 12) != nil }

    /// Newsreader is Saro's voice (questions, prompts, the letter, quotes); New York if it isn't registered.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        let size = size * PrefsStore.shared.textScale
        guard newsreaderAvailable else {
            let f = Font.system(size: size, weight: weight, design: .serif)
            return italic ? f.italic() : f
        }
        let name = switch (weight, italic) {
        case (.medium, false): "NewsreaderRoman-Medium"
        case (.semibold, false), (.bold, false): "NewsreaderRoman-SemiBold"
        case (.light, false): "NewsreaderRoman-Light"
        case (_, false): "Newsreader16pt-Regular"
        case (.medium, true): "NewsreaderItalic-Medium"
        case (.semibold, true), (.bold, true): "NewsreaderItalic-SemiBold"
        case (.light, true): "NewsreaderItalic-Light"
        case (_, true): "Newsreader16pt-Italic"
        }
        return .custom(name, size: size)
    }
}

/// Motion tokens from the web build (`lib/motion.ts`), converted to SwiftUI springs (bounce 0 → dampingFraction 1;
/// response = 2π·duration/9.23). Reduce Motion swaps movement for short crossfades.
enum Motion {
    /// Overlays, sheets, big morphs, the day slide.
    static let surface = Animation.spring(response: 0.272, dampingFraction: 1)
    /// Menus, pills, chips, small morphs.
    static let small = Animation.spring(response: 0.170, dampingFraction: 1)
    /// A picked-up card.
    static let lift = Animation.spring(response: 0.204, dampingFraction: 1)
    static let press = Animation.spring(response: 0.102, dampingFraction: 1)
    /// A thrown card settling; the only bounce, because the gesture carried momentum.
    static let release = Animation.spring(response: 0.3, dampingFraction: 0.85)
    /// ease.out (0.23, 1, 0.32, 1) for entrances and exits.
    static func easeOut(_ seconds: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: seconds) }
    static let fade = Animation.easeOut(duration: 0.16)

    // Names the canvas used before the web tokens; kept as aliases.
    static let open = surface
    static let close = surface
    static let arrange = small
    static let fan = surface

    static func pick(_ animation: Animation, reduce: Bool) -> Animation { reduce ? fade : animation }

    /// The frequency rule: what a key started doesn't animate. Read it inside the action (or the update) the input caused.
    /// A key-up counts: Space's tap acts on it.
    @MainActor static var byKey: Bool { NSApp.currentEvent.map { [.keyDown, .keyUp].contains($0.type) } ?? false }
}

/// Radii (`tailwind.config.js`): control 8, field 10, card 14, panel 20, sheet 28.
enum Radius {
    static let control: CGFloat = 8, field: CGFloat = 10, card: CGFloat = 14, panel: CGFloat = 20, sheet: CGFloat = 28
}

/// The web shadow scale (CSS blur ÷ 2 = SwiftUI radius), tinted with the ink shadow colour (black at night).
enum Elevation {
    case lift, card, raise, float, panel, overlay

    var spec: (opacity: Double, radius: CGFloat, y: CGFloat) {
        switch self {
        case .lift: (0.07, 5, 2)
        case .card: (0.06, 12, 4)
        case .raise: (0.10, 8, 4)
        case .float: (0.14, 16, 12)
        case .panel: (0.16, 28, 20)
        case .overlay: (0.24, 40, 32)
        }
    }
}

extension View {
    func elevation(_ e: Elevation) -> some View {
        let s = e.spec
        return shadow(color: Tok.shadow.opacity(s.opacity), radius: s.radius, y: s.y)
    }

    /// Mono caps label (eyebrow 11 pt at 0.12em, label 10.5 at 0.11em): times, dates, counts, key hints.
    func monoCaps(_ size: CGFloat = 10.5, tracking: CGFloat = 0.11) -> some View {
        font(Typo.mono(size)).tracking(size * tracking).textCase(.uppercase)
    }

    /// glass-panel: paper 95%, a lit rim, float shadow, no blur.
    func glassPanel(radius: CGFloat = Radius.panel) -> some View {
        background(Tok.paper.opacity(0.95), in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Tok.rim.opacity(0.6), lineWidth: 1))
            .elevation(.float)
    }
}

extension View {
    /// The card and panel surface: Evergreen surface, a hairline border and a soft ink-tinted shadow.
    func saroSurface(radius: CGFloat = 14, lifted: Bool = false) -> some View {
        background(Tok.surface, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Tok.border, lineWidth: 1))
            .shadow(color: Tok.shadow.opacity(lifted ? 0.16 : 0.07), radius: lifted ? 18 : 8, y: lifted ? 8 : 3)
    }
}
