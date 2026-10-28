import SaroKit
import SwiftUI

/// Finishing a moment (VideoReflectionScreen.tsx's finish dialog): on black/60 at radius 28, its steps crossfading with a
/// 4 pt blur. Finish (Return), Keep recording or Not yet (Esc), and a two-step Discard recording… under a rule.
struct FinishDialog: View {
    enum Step: Equatable { case confirm, discard, failed }

    let day: String
    /// Paused mid-part (Keep recording) rather than at a checkpoint (Not yet).
    let paused: Bool
    /// The camera or microphone went away; what was recorded is kept.
    let interrupted: Bool
    /// Parts already kept stay on the canvas whatever happens to this one.
    let keptParts: Bool
    @Binding var step: Step
    let finish: () -> Void
    let keepRecording: () -> Void
    let discard: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var destination: String { day == LocalDay.today() ? "today’s canvas" : "your canvas for \(LocalDay.date(day)?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? day)" }

    private var title: String {
        switch step {
        case .failed: "Couldn’t save your reflection"
        case .discard: "Discard this recording?"
        case .confirm: interrupted ? "Recording stopped" : "Finish this reflection?"
        }
    }

    private var detail: String {
        switch step {
        case .failed: "Saro couldn’t write the recording on this Mac. Your Mac may be out of space."
        case .discard: keptParts ? "The part you haven’t saved will be deleted. Parts you already saved stay on your canvas."
            : "This recording will be deleted. This can’t be undone."
        case .confirm: interrupted ? "Your camera or microphone disconnected. What you recorded so far is kept. Saro will save it to \(destination)."
            : "Saro will save it to \(destination)."
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).contentShape(.rect).onTapGesture {}
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Typo.ui(22, .semibold)).foregroundStyle(.white)
                Text(detail).font(Typo.ui(15)).lineSpacing(3).foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    buttons
                }
                .padding(.top, 32)
                if step == .confirm {
                    Rectangle().fill(.white.opacity(0.1)).frame(height: 1).padding(.top, 16)
                    Button("Discard recording…") { withAnimation(swap) { step = .discard } }
                        .buttonStyle(TertiaryStyle())
                        .padding(.top, 12)
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .background(.black.opacity(0.6), in: .rect(cornerRadius: Radius.sheet))
            .background(.frosted(.thinMaterial, solid: Night.bg), in: .rect(cornerRadius: Radius.sheet))
            .overlay(RoundedRectangle(cornerRadius: Radius.sheet).strokeBorder(.white.opacity(0.2)))
            .elevation(.overlay)
            .padding(16)
            .id(step)
            .transition(reduceMotion ? .opacity : AnyTransition(BlurSwap(radius: 4)))
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .animation(swap, value: step)
    }

    private var swap: Animation { reduceMotion ? Motion.fade : CaptureMotion.out(0.15) }

    @ViewBuilder private var buttons: some View {
        switch step {
        case .discard:
            Button("Keep it") { withAnimation(swap) { step = .confirm } }
                .buttonStyle(CaptureButtonStyle.ghost)
                .keyboardShortcut(.cancelAction)
            Button("Discard", action: discard)
                .buttonStyle(CaptureButtonStyle(fill: Tok.danger, hover: Tok.danger.opacity(0.85), ink: Tok.onPrimary, padding: 20))
        case .failed:
            Button("Close", action: keepRecording)
                .buttonStyle(CaptureButtonStyle.ghost)
                .keyboardShortcut(.cancelAction)
        case .confirm:
            if !interrupted {
                Button(paused ? "Keep recording" : "Not yet", action: keepRecording)
                    .buttonStyle(CaptureButtonStyle.ghost)
                    .keyboardShortcut(.cancelAction)
            }
            Button("Finish", action: finish)
                .buttonStyle(CaptureButtonStyle.primary)
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// A quiet text button on video: white/70, white and underlined on hover.
struct TertiaryStyle: ButtonStyle {
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.ui(14))
            .foregroundStyle(.white.opacity(hover ? 1 : 0.7))
            .underline(hover)
            .frame(minHeight: 44)
            .padding(.horizontal, 8)
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(CaptureMotion.press, value: configuration.isPressed)
            .onHover { hover = $0 }
    }
}

extension CaptureButtonStyle {
    /// A white/25 hairline pill on video (GHOST_BUTTON).
    static var ghost: Self { Self(fill: .clear, hover: .white.opacity(0.1), ink: .white, line: .white.opacity(0.25)) }
    /// The mint pill that replaces the record button after a checkpoint.
    static var mint: Self { Self(fill: Tok.mint, hover: Tok.mint.opacity(0.9), ink: Night.bg, shadow: .black.opacity(0.2), height: 48) }
}
