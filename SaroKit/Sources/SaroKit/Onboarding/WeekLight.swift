import Foundation

/// Seven Sunrises (firstWeekLight.ts and firstWeek.ts): the week's light at the ritual hour, a light under each day
/// brighter day by day to the letter's, and the entrance's one clock, in seconds. Pure and deterministic.
public enum WeekLight {
    /// The ground sweeps from now to the ritual hour.
    public static let sweep = 1.1
    static let horizonAt = 0.3, horizonFor = 0.7, igniteAt = 0.95
    /// Between one day's ignition and the next: 120 ms in a wide window, 90 ms in a narrow one.
    public static let stepWide = 0.12, stepNarrow = 0.09
    static let flashUp = 0.06, flashPeak = 1.8, glowPeak = 1.5, flashSettle = 0.55
    static let haloFrom = 0.55, haloFor = 0.4, crestFor = 0.6
    static let surgePeak = 1.2, surgeUp = 0.12, surgeSettle = 0.5

    /// When day `i` ignites.
    public static func dayAt(_ i: Int, step: Double) -> Double { igniteAt + step * Double(i) }
    /// When the ritual, the preview and the way on rise.
    public static func restAt(step: Double) -> Double { dayAt(6, step: step) + 0.28 }
    /// When the last light has settled; nothing runs after.
    public static func entranceEnd(step: Double) -> Double {
        dayAt(6, step: step) + max(surgeUp + surgeSettle, flashUp + flashSettle, crestFor)
    }

    /// A CSS cubic-bezier as a function of progress (0–1).
    public static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> @Sendable (Double) -> Double {
        let at: @Sendable (Double, Double, Double) -> Double = { a, b, s in 3 * a * s * (1 - s) * (1 - s) + 3 * b * s * s * (1 - s) + s * s * s }
        return { x in
            if x <= 0 { return 0 }
            if x >= 1 { return 1 }
            var lo = 0.0, hi = 1.0
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if at(x1, x2, mid) < x { lo = mid } else { hi = mid }
            }
            return at(y1, y2, (lo + hi) / 2)
        }
    }

    /// ease.out and ease.inOut (lib/motion.ts).
    public static let easeOut = bezier(0.23, 1, 0.32, 1)
    public static let easeInOut = bezier(0.77, 0, 0.175, 1)

    /// A critically damped spring (bounce 0) from 0 to 1, settled at `duration`.
    static func settle(_ dt: Double, _ duration: Double) -> Double {
        if dt <= 0 { return 0 }
        if dt >= duration { return 1 }
        let w = 7 / duration * dt
        return 1 - (1 + w) * exp(-w)
    }

    /// Up to `peak` in the first 60 ms (linear), then down to 1 on a spring.
    static func flash(_ dt: Double, _ peak: Double) -> Double {
        dt <= 0 ? 0 : dt < flashUp ? peak * dt / flashUp : 1 + (peak - 1) * (1 - settle(dt - flashUp, flashSettle))
    }

    public struct DayIgnition: Sendable, Equatable {
        /// The halo's strength: pulses to 1.5 as the day ignites, settles at 1.
        public var glow: Double
        /// The white-hot core: flashes to 1.8, settles at 1.
        public var core: Double
        /// The halo's size, 0.55 → 1.
        public var size: Double
    }

    public struct Ignition: Sendable, Equatable {
        /// How much of the horizon is drawn, outward from the centre (0–1).
        public var horizon: Double
        public var days: [DayIgnition]
        /// The eighth sun past the week: 0 below the horizon, 1 risen.
        public var crest: Double
        /// Everything's brightness: surges to 1.2 as the last day lights, settles at 1.
        public var surge: Double
    }

    /// The light `t` seconds into the entrance; `.infinity` is at rest.
    public static func ignition(_ t: Double, step: Double) -> Ignition {
        let days = (0..<7).map { i -> DayIgnition in
            let dt = t - dayAt(i, step: step)
            return DayIgnition(glow: flash(dt, glowPeak), core: flash(dt, flashPeak), size: haloFrom + (1 - haloFrom) * settle(dt, haloFor))
        }
        let dt6 = t - dayAt(6, step: step)
        let surge = dt6 <= 0 ? 1 : dt6 < surgeUp ? 1 + (surgePeak - 1) * dt6 / surgeUp : 1 + (surgePeak - 1) * (1 - settle(dt6 - surgeUp, surgeSettle))
        return Ignition(horizon: easeOut(min(1, max(0, (t - horizonAt) / horizonFor))), days: days, crest: settle(dt6, crestFor), surge: surge)
    }

    // MARK: At rest

    private static let glow = [0.7, 0.74, 0.78, 0.82, 0.86, 0.9, 1]

    /// How strongly a day's light burns at rest, 0–1: brighter day by day toward the letter; a skipped day is an ember.
    public static func dayGlow(_ index: Int, on: Bool) -> Double { on ? glow.indices.contains(index) ? glow[index] : glow[0] : 0.12 }

    public struct DayLevel: Sendable, Equatable {
        public var power: Double, size: Double, sink: Double
        /// 1 on, 0 skipped.
        public var on: Double
    }

    public static func dayLevel(_ index: Int, on: Bool) -> DayLevel {
        DayLevel(power: dayGlow(index, on: on), size: on ? 1 : 0.6, sink: on ? 0 : 6, on: on ? 1 : 0)
    }

    public struct DayLight: Sendable, Equatable {
        /// The day's light on the night palette, sRGB 0–255.
        public var night: SIMD3<Int>
        /// The day's colour cast on the day palette, a step warmer.
        public var day: SIMD3<Int>
    }

    static let voice = Sky.linear(0xF2A078)
    // Every day's light has a colour of its own, however grey the hour's light is, and burns as bright as the voice
    // however dim that hour's hue is, so a dark numeral always stands out against it.
    static let minChroma = 0.1, minLightness = 0.77

    /// A linear RGB colour in OKLCH.
    static func oklch(_ c: SIMD3<Double>) -> SIMD3<Double> {
        let l = cbrt(0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z)
        let m = cbrt(0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z)
        let s = cbrt(0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z)
        let a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
        let b = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
        return [0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s, hypot(a, b), atan2(b, a) * 180 / .pi]
    }

    static func srgb255(_ c: SIMD3<Double>) -> SIMD3<Int> {
        let s = Sky.srgb(c)
        return SIMD3(Int((s.x * 255).rounded()), Int((s.y * 255).rounded()), Int((s.z * 255).rounded()))
    }

    /// The seven days' light at the ritual hour, day 0 first: from the hour's own light the short way round the hue
    /// wheel to Saro's voice (at night, blue through violet and rose to apricot), so the week warms day by day.
    public static func dayLights(hour: Double) -> [DayLight] {
        let from = oklch(Sky.hour(hour).light), to = oklch(voice)
        let turn = ((to.z - from.z).truncatingRemainder(dividingBy: 360) + 540).truncatingRemainder(dividingBy: 360) - 180
        func at(_ t: Double) -> SIMD3<Double> {
            t >= 1 ? voice : Sky.oklchToLinear([max(from.x + (to.x - from.x) * t, minLightness), max(from.y + (to.y - from.y) * t, minChroma),
                                                from.z + turn * t])
        }
        return (0..<7).map { i in DayLight(night: srgb255(at(Double(i) / 6)), day: srgb255(at(0.35 + 0.65 * Double(i) / 6))) }
    }
}
