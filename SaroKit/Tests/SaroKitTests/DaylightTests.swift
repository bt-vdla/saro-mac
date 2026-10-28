import Foundation
import Testing
@testable import SaroKit

private func gap<V: SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar: FloatingPoint { let d = a - b; return max(d.max(), -d.min()) }
private func contrast(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }

@Test func daylightLandsOnItsKeyframes() {
    let noon = Sky.hour(12.5)
    #expect(abs(noon.power - 0.12) < 1e-9 && abs(noon.falloff - 0.83) < 1e-9)
    #expect(gap(noon.light, Sky.oklchToLinear([0.975, 0.012, 95])) < 1e-9)
    #expect(abs(noon.sun.x - 0.52) < 0.02 && abs(noon.sun.y + 0.1) < 0.02)
    #expect(abs(Sky.hour(18.75).dark - 0.3) < 1e-9)
    // Noon is a near-white warm light; midnight a dim blue moon.
    let midnight = Sky.hour(0)
    #expect(noon.light.x > 0.9 && noon.light.z > 0.85)
    #expect(midnight.light.z > midnight.light.x && Sky.luminance(midnight.light) < Sky.luminance(noon.light))
}

@Test func daylightWrapsAndEasesWithoutJumps() {
    #expect(Sky.hour(24) == Sky.hour(0))
    #expect(Sky.hour(-1) == Sky.hour(23))
    for minute in 0..<(24 * 60) {
        let a = Sky.hour(Double(minute) / 60), b = Sky.hour(Double(minute + 1) / 60)
        #expect(gap(a.sun, b.sun) < 0.01 && abs(a.dark - b.dark) < 0.02 && abs(a.power - b.power) < 0.01)
        #expect(gap(a.light, b.light) < 0.02 && gap(a.accent, b.accent) < 0.02)
    }
}

@Test func nightRunsFromEightToSix() {
    #expect(!Sky.isNight(19.99) && Sky.isNight(20) && Sky.isNight(5.99) && !Sky.isNight(6))
}

@Test func eachGroundKeepsSecondaryTextAA() {
    let inkDay = Sky.luminance(Sky.linear(0x4D5A53)), inkNight = Sky.luminance(Sky.linear(0x9FB0A7))
    for quarter in 0..<96 {
        let hour = Double(quarter) / 4
        for followsDay in [true, false] {
            let day = Sky.ground(at: hour, dark: false, followsDay: followsDay)
            #expect(contrast(inkDay, castFloor(day, Sky.luminance(day.ground))) >= 4.5, "day ground too dim at \(hour)")
            #expect(day.stars == 0 && day.falloff >= 0.8)
            let night = Sky.ground(at: hour, dark: true, followsDay: followsDay)
            #expect(contrast(inkNight, Sky.luminance(night.ground) + Sky.peakAddedLuminance(night)) >= 4.5, "night too bright at \(hour)")
            if !followsDay { #expect(day.mix == 0 && night.mix == 1) }
        }
    }
    #expect(Sky.ground(at: 19, dark: false).mix > 0 && Sky.ground(at: 5.85, dark: true).mix < 1)
    #expect(contrast(Sky.luminance(Sky.linear(0x5C6961)), Sky.dayGrainFloor) >= 4.5)
}

@Test func moodColorKnowsTheCatalogue() {
    #expect(Sky.moodColor("Calm") == 0x8FB9A8 && Sky.moodColor(" grateful ") == 0xE9C27A)
    #expect(Sky.moodColor("Energized") == Sky.moodColor(Mood.energised.rawValue))
    #expect(Sky.moodColor("Wistful") == Sky.moodColor("Neutral"))
}

/// The shader's hue cast: `strength` of the way toward `color` at the same brightness, where a vivid colour can be that bright.
private func castLuminance(_ color: SIMD3<Double>, _ lum: Double, _ strength: Double) -> Double {
    let k = lum / max(Sky.luminance(color), 1e-4)
    let target = Sky.luminance(SIMD3(min(1, color.x * k), min(1, color.y * k), min(1, color.z * k)))
    return lum + (target - lum) * strength
}

private func castFloor(_ g: Sky.Ground, _ lum: Double) -> Double {
    castLuminance(Sky.hazeColor, castLuminance(g.accent, castLuminance(g.light, lum, g.cast), g.cast), g.hazeCast)
}
