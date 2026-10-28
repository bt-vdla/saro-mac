import SaroKit
import SwiftUI

/// The insight surface (InsightBar.tsx): one shape that is a 64 pt spine, then the 360 pt "What Saro noticed" panel,
/// then the 540 pt letter, morphing between them on the surface spring.
struct InsightSurface: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let height: CGFloat
    @State private var hover = false
    @State private var pressed = false

    private var size: CGSize {
        switch model.insight {
        case .spine: CGSize(width: 64, height: min(320, height))
        case .panel: CGSize(width: 360, height: min(640, height))
        case .letter: CGSize(width: 540, height: min(760, height))
        }
    }

    /// The spine sits centred on the canvas (web: 7.5vh + 42.5vh − 160); the panel and letter start at the top.
    // ponytail: recovers the canvas height from DayView's `height` (0.925·H − 120); pass H in if that layout changes.
    private var spineDrop: CGFloat {
        max(0, min((height + 120) / 0.925 * 0.425 - 160, height - size.height))
    }

    var body: some View {
        let folded = model.insight == .spine
        ZStack(alignment: .topLeading) {
            switch model.insight {
            case .spine: spine.transition(.opacity.animation(.easeOut(duration: 0.15).delay(0.12)))
            case .panel: NoticedView().transition(.opacity.animation(.easeOut(duration: 0.15).delay(0.12)))
            case .letter: LetterView().transition(.opacity.animation(.easeOut(duration: 0.15).delay(0.12)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Tok.paper.opacity(0.9), in: .rect(cornerRadius: model.insight == .spine ? 32 : Radius.sheet))
        .background(.regularMaterial, in: .rect(cornerRadius: model.insight == .spine ? 32 : Radius.sheet))
        .overlay(RoundedRectangle(cornerRadius: model.insight == .spine ? 32 : Radius.sheet).strokeBorder(Tok.rim.opacity(0.6)))
        .clipShape(.rect(cornerRadius: model.insight == .spine ? 32 : Radius.sheet))
        .shadow(color: .black.opacity(0.2), radius: 30, y: 24)
        .scaleEffect(folded && pressed ? 0.98 : 1)
        .offset(y: folded && hover && !reduceMotion ? -2 : 0)
        .animation(Motion.lift, value: hover)
        .animation(Motion.lift, value: pressed)
        .overlay(alignment: .topLeading) {
            if folded && model.dayStatus == .ready && model.dayReading != nil { letterButton.offset(x: -54, y: 16) }
        }
        .tourAnchor(.noticedButton)
        .padding(.top, folded ? spineDrop : 0)
        .animation(Motion.pick(Motion.surface, reduce: reduceMotion), value: model.insight)
    }

    /// The web's icon column: moment, echo and still marks over a rule and a plus.
    private var spine: some View {
        Button {
            hover = false
            pressed = false
            model.insight = .panel
        } label: {
            VStack(spacing: 20) {
                glyph("sun.max", Tok.moment)
                glyph("water.waves", Tok.echo)
                glyph("questionmark.circle", Tok.still)
                Rectangle().fill(Tok.ink.opacity(0.1)).frame(width: 20, height: 1)
                glyph("plus", Tok.moment)
            }
            .opacity(model.dayStatus == .empty ? 0.6 : 1)
            .frame(width: 64)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(PressReport(pressed: $pressed))
        .onHover { hover = $0 }
        .keyboardShortcut("i", modifiers: [.command, .option])
        .help("What Saro noticed  ⌥⌘I")
        .accessibilityLabel("What Saro noticed")
    }

    private func glyph(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint).frame(width: 20, height: 20)
    }

    /// Once there's a letter it tucks in beside the spine, a 44 pt round button of its own.
    private var letterButton: some View {
        Button { model.insight = .letter } label: {
            Image(systemName: "envelope").font(.system(size: 15)).foregroundStyle(Tok.voice)
                .frame(width: 44, height: 44)
                .background(Tok.paper.opacity(0.95), in: .circle)
                .overlay(Circle().strokeBorder(Tok.rim.opacity(0.8)))
                .elevation(.float)
                .contentShape(.circle)
        }
        .buttonStyle(PressStyle())
        .help("Open the evening letter")
    }
}

/// Hands the spine's press up, so the whole surface takes the 0.98 and not just its glyphs.
private struct PressReport: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.onChange(of: configuration.isPressed) { _, p in pressed = p }
    }
}
