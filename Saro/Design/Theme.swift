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
    static let rim = Color(0xFFFFFF, 0x3F4F47)
    static let shadow = Color(0x13201A, 0x000000)

    static let moment = Color(0x2F7A5A, 0x79C3A0)
    static let echo = Color(0x6560B8, 0xA7A2EC)
    static let still = Color(0xB85C45, 0xEC9A86)
    static let reflection = Color(0x8E6B1F, 0xD8B062)
    static let music = Color(0x356FA8, 0x86B7EA)
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

/// Geist for UI, Geist Mono for labels, New York (system serif) for Saro's voice.
enum Typo {
    static func registerFonts() {
        guard let dir = Bundle.main.url(forResource: "Fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }

    static var geistAvailable: Bool { NSFont(name: "Geist-Regular", size: 12) != nil }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
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
        guard geistAvailable else { return .system(size: size, weight: weight, design: .monospaced) }
        return .custom(weight == .regular ? "GeistMono-Regular" : "GeistMono-Medium", size: size)
    }

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

/// Springs from `brd/final_s14_canvas.md` (Native build notes). Reduce Motion swaps each for a 150 ms crossfade.
enum Motion {
    static let open = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let close = Animation.spring(response: 0.22, dampingFraction: 0.75)
    static let arrange = Animation.spring(response: 0.18, dampingFraction: 0.9)
    static let fan = Animation.spring(response: 0.3, dampingFraction: 0.86)
    static let fade = Animation.easeInOut(duration: 0.15)

    static func pick(_ animation: Animation, reduce: Bool) -> Animation { reduce ? fade : animation }
}

extension View {
    /// The card and panel surface: Evergreen surface, a hairline border and a soft ink-tinted shadow.
    func saroSurface(radius: CGFloat = 14, lifted: Bool = false) -> some View {
        background(Tok.surface, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Tok.border, lineWidth: 1))
            .shadow(color: Tok.shadow.opacity(lifted ? 0.16 : 0.07), radius: lifted ? 18 : 8, y: lifted ? 8 : 3)
    }
}
