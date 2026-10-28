import SaroKit
import SwiftUI

/// Saro's ground, as the web draws it (components/ground/LitGround.tsx): a pool of light placed by the local hour, a
/// horizon band, a colour cast, haze, still star dust at night, a faint vignette and still grain, in the hour's palette.
/// A backdrop: put it under the canvas, not inside the pan and zoom. It redraws only on the minute, a resize or an
/// appearance change. Reduce Transparency and Increase Contrast get the flat `Tok.bg`.
struct LitGround: View {
    /// Pins the light to an hour (0–24) instead of the clock, for a day replay or snapshots.
    var hour: Double?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if reduceTransparency || contrast == .increased {
                Tok.bg
            } else {
                TimelineView(.everyMinute) { context in
                    let ground = Sky.ground(at: hour ?? Daylight.shared.hour(at: context.date), dark: scheme == .dark,
                                            followsDay: Daylight.shared.mode == .clock)
                    GeometryReader { geo in
                        Rectangle().colorEffect(shader(ground, size: geo.size))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func shader(_ g: Sky.Ground, size: CGSize) -> Shader {
        func v3(_ v: SIMD3<Double>) -> Shader.Argument { .float3(v.x, v.y, v.z) }
        return ShaderLibrary.litGround(
            .float2(size), .float(min(scale, 2)), .float2(g.sun.x, g.sun.y), .float(g.spread), .float(g.stretch),
            v3(g.ground), .float(g.falloff), v3(g.light), .float(g.power), v3(g.accent), .float(g.accentPower),
            .float(g.cast), v3(Sky.hazeColor), v3(g.hazeLift), .float(g.hazeCast), .float(g.stars), v3(g.grain),
            .float(Sky.starPeak), .float(Sky.dayGrainFloor))
    }
}
