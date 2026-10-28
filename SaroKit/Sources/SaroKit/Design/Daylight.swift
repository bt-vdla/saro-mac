import Foundation

/// The light that follows the day, ported from `saro/frontend/lib/daylight.ts`: where the hour's light falls on the
/// ground, its colour and strength, and how far the Evergreen palette has moved toward night. Pure and deterministic.
/// Colours are linear RGB; keyframes are OKLCH, eased with smoothstep and mixed in OKLab.
public enum Sky {
    /// What the ground shader draws at an hour.
    public struct Ground: Sendable, Equatable {
        /// Centre of the pool of light, as a fraction of the view (x from the left, y from the top); it may sit off-screen.
        public var sun: SIMD2<Double>
        public var light: SIMD3<Double>
        public var power: Double
        public var spread: Double
        public var stretch: Double
        /// The horizon band's colour, a glow along the bottom edge at dawn and dusk.
        public var accent: SIMD3<Double>
        public var accentPower: Double
        /// How strongly the light colours the ground at the same brightness.
        public var cast: Double
        public var falloff: Double
        public var stars: Double
        /// Night grain amplitude (sRGB code values), its softness, then the day grain's Weber contrast.
        public var grain: SIMD3<Double>
        /// The ground's mix between the Evergreen light and dark grounds, in linear light.
        public var mix: Double
        public var hazeLift: SIMD3<Double>
        public var hazeCast: Double

        /// The ground colour under the light.
        public var ground: SIMD3<Double> { Sky.groundLight + (Sky.groundDark - Sky.groundLight) * mix }
    }

    /// The light at an hour before it meets a ground (the web's `Daylight`).
    struct Hour: Equatable {
        var sun: SIMD2<Double>, light: SIMD3<Double>, power, spread, stretch: Double
        var accent: SIMD3<Double>, accentPower, cast, haze, falloff, stars: Double
        var grain: SIMD3<Double>, dark: Double
    }

    struct Key {
        let h: Double, sun: SIMD2<Double>, light: SIMD3<Double>, power, spread, stretch: Double
        let accent: SIMD3<Double>, accentPower, cast, haze, falloff, stars: Double, grain: SIMD3<Double>, dark: Double

        func at(_ h: Double, _ sun: SIMD2<Double>) -> Key {
            Key(h: h, sun: sun, light: light, power: power, spread: spread, stretch: stretch, accent: accent, accentPower: accentPower,
                cast: cast, haze: haze, falloff: falloff, stars: stars, grain: grain, dark: dark)
        }
    }

    /// Mirrors `Tok.bg` (light and dark), linear.
    public static let groundLight = linear(0xF1F1EC)
    public static let groundDark = linear(0x0E1411)
    public static let hazeColor = oklchToLinear([0.95, 0.025, 235])
    /// Brightest a star speck gets, per unit of `stars`.
    public static let starPeak = 0.024
    /// The darkest a day grain speck may take the ground, as luminance: where `Tok.ink3` (#5C6961) still reads at 4.6:1.
    public static let dayGrainFloor = 4.6 * (luminance(linear(0x5C6961)) + 0.05) - 0.05

    static let duskCeil = 0.2, dayFalloffFloor = 0.8, nightFloor = 0.992, moonlight = 0.036

    static let night = Key(h: 0, sun: [0.86, 0.22], light: [0.8, 0.07, 262], power: 0.045, spread: 0.8, stretch: 1,
                           accent: [0.55, 0.1, 270], accentPower: 0, cast: 0.25, haze: 0, falloff: 0.76, stars: 0.5,
                           grain: [0.026, 0.1, 0.04], dark: 1)

    static let keys: [Key] = [
        night,
        Key(h: 2, sun: [0.9, 0.38], light: [0.74, 0.06, 268], power: 0.035, spread: 0.72, stretch: 1, accent: [0.5, 0.09, 272], accentPower: 0, cast: 0.2, haze: 0, falloff: 0.7, stars: 0.3, grain: [0.024, 0.2, 0.04], dark: 1),
        Key(h: 4.5, sun: [0.1, 0.97], light: [0.7, 0.1, 290], power: 0.05, spread: 0.95, stretch: 1.3, accent: [0.6, 0.13, 292], accentPower: 0.1, cast: 0.35, haze: 0, falloff: 0.74, stars: 0.15, grain: [0.024, 0.3, 0.04], dark: 1),
        Key(h: 5.5, sun: [0.1, 0.92], light: [0.78, 0.09, 330], power: 0.08, spread: 1, stretch: 1.4, accent: [0.72, 0.12, 355], accentPower: 0.14, cast: 0.4, haze: 0, falloff: 0.76, stars: 0.04, grain: [0.022, 0.5, 0.04], dark: 1),
        Key(h: 6.35, sun: [0.12, 0.86], light: [0.84, 0.095, 60], power: 0.22, spread: 1.1, stretch: 1.6, accent: [0.8, 0.11, 55], accentPower: 0.2, cast: 0.45, haze: 0.05, falloff: 0.8, stars: 0, grain: [0.02, 0.7, 0.04], dark: 0.4),
        Key(h: 7.5, sun: [0.2, 0.46], light: [0.94, 0.035, 85], power: 0.1, spread: 1.4, stretch: 1.2, accent: [0.88, 0.06, 70], accentPower: 0.04, cast: 0.15, haze: 0.22, falloff: 0.9, stars: 0, grain: [0.016, 1, 0.03], dark: 0),
        Key(h: 9.5, sun: [0.3, 0.18], light: [0.95, 0.03, 82], power: 0.13, spread: 1.25, stretch: 1, accent: [0.9, 0.04, 80], accentPower: 0, cast: 0.1, haze: 0.1, falloff: 0.86, stars: 0, grain: [0.02, 0.6, 0.035], dark: 0),
        Key(h: 12.5, sun: [0.52, -0.1], light: [0.975, 0.012, 95], power: 0.12, spread: 1, stretch: 1, accent: [0.9, 0.02, 90], accentPower: 0, cast: 0.03, haze: 0, falloff: 0.83, stars: 0, grain: [0.022, 0, 0.04], dark: 0),
        Key(h: 15, sun: [0.75, 0.12], light: [0.92, 0.05, 75], power: 0.16, spread: 1.1, stretch: 1.25, accent: [0.88, 0.06, 70], accentPower: 0.03, cast: 0.18, haze: 0, falloff: 0.82, stars: 0, grain: [0.022, 0.1, 0.04], dark: 0),
        Key(h: 17.5, sun: [0.96, 0.6], light: [0.82, 0.11, 60], power: 0.24, spread: 1.15, stretch: 2, accent: [0.77, 0.12, 52], accentPower: 0.14, cast: 0.36, haze: 0, falloff: 0.8, stars: 0, grain: [0.022, 0.1, 0.045], dark: 0.12),
        Key(h: 18.75, sun: [0.96, 0.84], light: [0.78, 0.125, 38], power: 0.26, spread: 1.1, stretch: 1.7, accent: [0.72, 0.125, 24], accentPower: 0.2, cast: 0.45, haze: 0, falloff: 0.8, stars: 0, grain: [0.022, 0.1, 0.05], dark: 0.3),
        Key(h: 19.75, sun: [0.93, 0.88], light: [0.68, 0.11, 298], power: 0.2, spread: 1, stretch: 1.4, accent: [0.6, 0.13, 288], accentPower: 0.2, cast: 0.4, haze: 0, falloff: 0.78, stars: 0.05, grain: [0.024, 0.1, 0.05], dark: 0.8),
        Key(h: 20.75, sun: [0.88, 0.62], light: [0.64, 0.12, 278], power: 0.14, spread: 0.95, stretch: 1.2, accent: [0.52, 0.13, 272], accentPower: 0.14, cast: 0.35, haze: 0, falloff: 0.76, stars: 0.25, grain: [0.025, 0.1, 0.045], dark: 1),
        night.at(22, [0.82, 0.28]),
        night.at(24, [0.86, 0.22]),
    ]

    /// The local time of day, 0–24, to the minute.
    public static func localHour(_ date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    /// Night palette from 8 pm to 6 am local time.
    public static func isNight(_ hour: Double) -> Bool {
        let h = wrap(hour)
        return h >= 20 || h < 6
    }

    /// The light at a local hour (0–24, fractional), eased between keyframes, with a slow drift of a percent or so.
    static func hour(_ hour: Double) -> Hour {
        let h = wrap(hour)
        var i = 0
        while i < keys.count - 2, h > keys[i + 1].h { i += 1 }
        let a = keys[i], b = keys[i + 1]
        let raw = (h - a.h) / (b.h - a.h)
        let t = raw * raw * (3 - 2 * raw)
        func at(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        func at(_ x: SIMD3<Double>, _ y: SIMD3<Double>) -> SIMD3<Double> { x + (y - x) * t }
        let tau = 2 * Double.pi
        return Hour(
            sun: [at(a.sun.x, b.sun.x) + 0.012 * sin(tau * 5 * h / 24), at(a.sun.y, b.sun.y) + 0.009 * sin(tau * 7 * h / 24 + 1.3)],
            light: oklabToLinear(at(oklab(a.light), oklab(b.light))), power: at(a.power, b.power), spread: at(a.spread, b.spread),
            stretch: at(a.stretch, b.stretch), accent: oklabToLinear(at(oklab(a.accent), oklab(b.accent))),
            accentPower: at(a.accentPower, b.accentPower), cast: at(a.cast, b.cast), haze: at(a.haze, b.haze),
            falloff: at(a.falloff, b.falloff), stars: at(a.stars, b.stars), grain: at(a.grain, b.grain), dark: at(a.dark, b.dark))
    }

    /// The hour's light on the light or dark ground. Following the day, dusk dims the day ground and dawn lifts the night
    /// one (inside the band where text stays AA); a chosen palette keeps its own ground exactly.
    public static func ground(at hour: Double, dark: Bool, followsDay: Bool = true) -> Ground {
        let l = Self.hour(hour)
        if !dark {
            return Ground(sun: l.sun, light: l.light, power: l.power, spread: l.spread, stretch: l.stretch, accent: l.accent,
                          accentPower: l.accentPower, cast: l.cast, falloff: max(l.falloff, dayFalloffFloor), stars: 0, grain: l.grain,
                          mix: followsDay ? min(l.dark, duskCeil) : 0, hazeLift: .zero, hazeCast: l.haze)
        }
        // Everything the light adds dims together until it fits the moonlight budget, so light text never fades.
        let lift = hazeColor * l.haze * 0.3
        var g = Ground(sun: l.sun, light: l.light, power: l.power, spread: l.spread, stretch: l.stretch, accent: l.accent,
                       accentPower: l.accentPower, cast: l.cast * 0.5, falloff: l.falloff, stars: l.stars, grain: l.grain,
                       mix: followsDay ? max(l.dark, nightFloor) : 1, hazeLift: lift, hazeCast: 0)
        let k = min(1, moonlight / peakAddedLuminance(g))
        g.power *= k
        g.accentPower *= k
        g.hazeLift *= k
        g.stars *= k
        return g
    }

    /// The most luminance the light adds anywhere: pool, horizon band, haze and a star, all at their peak.
    static func peakAddedLuminance(_ g: Ground) -> Double {
        g.power * luminance(g.light) + g.accentPower * luminance(g.accent) + luminance(g.hazeLift) + g.stars * starPeak
    }

    /// A muted mood colour (sRGB hex) for the mood ribbon, legible as a small bar on both grounds; unknown labels are neutral.
    public static func moodColor(_ label: String) -> UInt32 {
        switch label.trimmingCharacters(in: .whitespaces).lowercased() {
        case "calm": 0x8FB9A8
        case "reflective": 0xA3AADB
        case "grateful": 0xE9C27A
        case "frustrated": 0xD69A8C
        case "tender": 0xE3A6B8
        case "anxious": 0xB3A8D6
        case "energised", "energized": 0xC2D39A
        case "bittersweet": 0xC9A7C7
        case "surprised": 0xE8B48F
        case "overwhelmed": 0x93A2C2
        case "inspired": 0x9FC9C4
        default: 0x9A9EA8
        }
    }

    // MARK: Colour

    public static func luminance(_ c: SIMD3<Double>) -> Double { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }

    public static func linear(_ hex: UInt32) -> SIMD3<Double> {
        SIMD3(Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF)).map { c in
            let s = c / 255
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
    }

    /// Linear RGB as sRGB 0–1, clamped.
    public static func srgb(_ c: SIMD3<Double>) -> SIMD3<Double> {
        c.map { x in
            let v = min(1, max(0, x))
            return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
    }

    /// OKLCH (lightness 0–1, chroma, hue in degrees) in linear RGB, clamped to sRGB.
    public static func oklchToLinear(_ c: SIMD3<Double>) -> SIMD3<Double> { oklabToLinear(oklab(c)) }

    static func oklab(_ c: SIMD3<Double>) -> SIMD3<Double> {
        [c.x, c.y * cos(c.z * .pi / 180), c.y * sin(c.z * .pi / 180)]
    }

    static func oklabToLinear(_ c: SIMD3<Double>) -> SIMD3<Double> {
        let l = pow(c.x + 0.3963377774 * c.y + 0.2158037573 * c.z, 3)
        let m = pow(c.x - 0.1055613458 * c.y - 0.0638541728 * c.z, 3)
        let s = pow(c.x - 0.0894841775 * c.y - 1.291485548 * c.z, 3)
        return SIMD3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                     -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                     -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s).map { min(1, max(0, $0)) }
    }

    static func wrap(_ hour: Double) -> Double { (hour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24) }
}

private extension SIMD3<Double> {
    func map(_ f: (Double) -> Double) -> SIMD3<Double> { SIMD3(f(x), f(y), f(z)) }
}
