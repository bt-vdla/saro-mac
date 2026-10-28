import SwiftUI

/// Saro's orb (orb.tsx): a lit sphere that listens to the real mic level, turns slowly while it thinks, and swells while
/// it talks. One component for the recorder (apricot), the voice pill and the voice card (lavender). Under Reduce Motion
/// it stays still and shows the level as a gentle ring.
struct SaroOrb: View {
    enum State: Equatable { case idle, listening, thinking, talking }

    struct Palette {
        let light: Color, mid: Color, deep: Color, glow: Color

        /// #F2A078 to #C4683A, with a soft apricot glow.
        static let saro = Palette(light: Color(0xF8C4A6, 0xF8C4A6), mid: Color(0xF2A078, 0xF2A078), deep: Color(0xC4683A, 0xC4683A),
                                  glow: Color(0xF2A078, 0xF2A078))
        /// The voice note's lavender (EchoOrb.tsx).
        static let echo = Palette(light: Color(0xD9D5F6, 0xD9D5F6), mid: Color(0xB4ADEA, 0xB4ADEA), deep: Color(0x8E87CF, 0x8E87CF),
                                  glow: Color(0xB4AEEA, 0xB4AEEA))
    }

    /// 0…1, read every frame while listening; nil for an orb with no microphone behind it.
    var level: (() -> Double)?
    var state: State = .idle
    var palette: Palette = .saro
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            TimelineView(.animation(paused: reduceMotion && state != .listening)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let l = state == .listening ? level?() ?? 0 : state == .talking ? 0.65 + sin(t * 4.8) * 0.22 : 0
                ZStack {
                    Circle()
                        .fill(RadialGradient(stops: [.init(color: palette.light, location: 0), .init(color: palette.mid, location: 0.45),
                                                     .init(color: palette.deep, location: 1)],
                                             center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: d * 0.55))
                    if !reduceMotion, state != .idle {
                        Circle()
                            .fill(AngularGradient(colors: [palette.mid, palette.deep, .white.opacity(0.9), palette.mid], center: .center,
                                                  angle: .radians(t * (state == .thinking ? 1.6 : 0.8))))
                            .blur(radius: d * 0.08)
                            .opacity(state == .thinking ? 0.7 : 0.45)
                            .clipShape(.circle)
                    }
                    Circle().strokeBorder(.white.opacity(0.12 + 0.33 * l), lineWidth: max(1, d * 0.03))
                        .scaleEffect(0.7 + 0.25 * l)
                }
                .scaleEffect(reduceMotion ? 1 : 1 + 0.06 * l + (state == .thinking ? 0.02 * sin(t * 2.6) : 0))
            }
            .frame(width: d, height: d)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .shadow(color: palette.glow.opacity(0.35), radius: 14)
        .accessibilityHidden(true)
    }
}
