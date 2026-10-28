import SaroKit
import SwiftUI

/// Saro's voice at the top of the moment frame (VideoReflectionScreen.tsx SaroVoice): the orb, then the prompt, or at a
/// checkpoint "SARO ASKS", the observation line and the question arriving word by word. Swaps with a 6 pt blur crossfade.
struct SaroVoice: View {
    let question: String
    var observation: String?
    var followUp = false
    var dimmed = false
    var orb: SaroOrb.State = .idle
    var compact = false
    /// A checkpoint started from the keyboard shows its question at once (the frequency rule).
    var instant = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: compact ? 6 : 12) {
            if !compact {
                SaroOrb(level: { CaptureController.shared.level }, state: orb)
                    .frame(width: 44, height: 44)
            }
            VStack(spacing: compact ? 4 : 8) {
                Text(followUp ? "Saro asks" : "Today’s prompt")
                    .font(Typo.ui(compact ? 10 : 11, .medium)).tracking(compact ? 1.2 : 1.32).textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.75))
                if let observation {
                    Text(observation)
                        .font(Typo.serif(compact ? 14 : 17, italic: true))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Group {
                    if followUp {
                        ArrivingWords(text: question, instant: instant || reduceMotion, rises: !reduceMotion)
                    } else {
                        Text(question)
                    }
                }
                .font(Typo.serif(compact ? 16 : 22))
                .lineSpacing(compact ? 1 : 4.8)
                .tracking(compact ? 0 : -0.22)
                .foregroundStyle(followUp ? Tok.voiceBright : .white)
                .lineLimit(compact ? 2 : 4)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: compact ? 340 : 576)
            .id("\(followUp)\(question)")
            .transition(reduceMotion ? .opacity : AnyTransition(BlurSwap(radius: 6)))
        }
        .legible()
        .opacity(dimmed ? 0.55 : 1)
        .animation(CaptureMotion.out(0.2), value: dimmed)
        .animation(CaptureMotion.out(0.3), value: "\(followUp)\(question)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(followUp ? "Saro asks: \([observation, question].compactMap { $0 }.joined(separator: " "))" : "Today’s prompt: \(question)")
        .allowsHitTesting(false)
    }
}

/// Saro's line arriving a word at a time: each word rises 0.2 em and fades in over 0.3 s, 30 ms apart after 50 ms.
/// One Text, so it wraps and reads as one line; the renderer only moves each word's glyphs.
struct ArrivingWords: View {
    let text: String
    var instant = false
    var rises = true
    @State private var shown = false

    private var words: [String] { text.split(whereSeparator: \.isWhitespace).map(String.init) }
    private var total: Double { 0.05 + Double(words.count) * 0.03 + 0.3 }

    var body: some View {
        let line = words.enumerated().reduce(Text(verbatim: "")) { acc, w in
            Text("\(acc)\(Text(verbatim: w.offset == 0 ? w.element : " " + w.element).customAttribute(WordIndex(index: w.offset)))")
        }
        line
            .textRenderer(Arrival(elapsed: shown || instant ? total : 0, rises: rises))
            .animation(instant ? nil : .linear(duration: total), value: shown)
            .onAppear { shown = true }
    }
}

private struct WordIndex: TextAttribute {
    let index: Int
}

private struct Arrival: TextRenderer, Animatable {
    var elapsed: Double
    let rises: Bool

    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            for run in line {
                let i = run[WordIndex.self]?.index ?? 0
                let t = min(max((elapsed - 0.05 - Double(i) * 0.03) / 0.3, 0), 1)
                let p = CaptureMotion.outCurve.value(at: t)
                var c = ctx
                c.opacity = p
                if rises { c.translateBy(x: 0, y: (1 - p) * run.typographicBounds.rect.height * 0.2) }
                c.draw(run)
            }
        }
    }
}

/// Opacity with a blur, for Saro's lines swapping.
struct BlurSwap: Transition {
    var radius: CGFloat = 4

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.opacity(phase.isIdentity ? 1 : 0).blur(radius: phase.isIdentity ? 0 : radius)
    }
}

/// The prompt a page or a voice note starts from, as a quiet header in Saro's voice (never editable).
struct PromptHeader: View {
    let question: String
    var night = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today’s prompt").monoCaps(10, tracking: 0.12).foregroundStyle(night ? Night.ink3 : Tok.ink3)
            Text(question).font(Typo.serif(night ? 15 : 18, italic: true)).foregroundStyle(night ? Night.ink : Tok.voice)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
