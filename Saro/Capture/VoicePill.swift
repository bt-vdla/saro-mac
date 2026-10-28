import AppKit
import SwiftUI

/// The web build's voice note pill (VoiceEchoOverlay): a night surface in either appearance, like a Dynamic Island,
/// with a 24-bar level meter, the elapsed time, record or pause, and Done. Steps swap with a 4 pt blur crossfade.
struct VoicePill: View {
    let notice: RecorderNotice?
    let inSession: Bool
    /// Growing out of the Voice button, which is its entrance.
    var grows = false
    /// The first reflection's question, on a card 16 pt above the pill (FirstEntry.tsx); it rises in with the pill.
    var prompt: String?
    let toggle: () -> Void
    let done: () -> Void
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A key brings the pill up at once (the frequency rule).
    @State private var appeared = Motion.byKey

    private var capture: CaptureController { .shared }
    /// A notice with an icon replaces the recorder; a spinner notice keeps it, as the web pill's "starting" step does.
    private var message: RecorderNotice? { notice?.icon == nil ? nil : notice }

    var body: some View {
        let step: AnyTransition = reduceMotion ? .opacity : AnyTransition(BlurFade())
        VStack(spacing: 16) {
            if let prompt { promptCard(prompt) }
            ZStack {
                if let message { messageStep(message).transition(step) } else { recordingStep.transition(step) }
            }
            .animation(CaptureMotion.out(0.2), value: message)
            .frame(maxWidth: .infinity)
            .background(Night.surface.opacity(0.95))
            .background(.frosted(solid: Night.surface))
            .clipShape(.rect(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.24), radius: 40, y: 32)
        }
        .environment(\.colorScheme, .dark)
        .offset(y: appeared || grows || reduceMotion ? 0 : 16)
        .scaleEffect(appeared || grows || reduceMotion ? 1 : 0.96, anchor: .bottom)
        .opacity(appeared || grows ? 1 : 0)
        .animation(reduceMotion ? Motion.fade : CaptureMotion.surface, value: appeared)
        .onAppear { appeared = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(inSession ? "Recording a voice note" : "Voice note")
    }

    private var recordingStep: some View {
        let recording = capture.state == .recording
        return VStack(alignment: .leading, spacing: 6) {
            status
                .frame(height: 24)
                .padding(.horizontal, 4)
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(recording ? Tok.voiceBright : Night.ink4)
                        .frame(width: 8, height: 8)
                        .breathing(recording && !reduceMotion)
                    ElapsedText()
                        .font(Typo.mono(13, .regular))
                        .tracking(0.52)
                        .foregroundStyle(Night.ink)
                }
                .frame(width: 68, alignment: .leading)
                .padding(.leading, 4)
                LevelMeter(color: Night.echo, live: notice == nil && capture.state != .paused)
                    .opacity(recording ? 1 : 0.4)
                    .animation(CaptureMotion.out(0.24), value: recording)
                    .frame(maxWidth: .infinity)
                    .clipped()
                leftButton
                rightButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var status: some View {
        HStack(spacing: 8) {
            if let notice {
                Text(notice.title).font(Typo.ui(12)).foregroundStyle(Night.ink2)
            } else if capture.state == .paused {
                Circle().fill(Night.ink3).frame(width: 6, height: 6)
                Text("Paused").font(Typo.ui(12)).foregroundStyle(Night.ink2)
            } else {
                Text(capture.state == .recording ? "Listening…" : "Ready when you are.")
                    .font(Typo.serif(15, italic: true))
                    .foregroundStyle(Night.ink3)
            }
            Spacer(minLength: 8)
            if notice == nil {
                Text(inSession ? "↵ TO SAVE" : "SPACE TO RECORD")
                    .font(Typo.mono(10.5))
                    .tracking(1.15)
                    .foregroundStyle(Night.ink3)
            }
        }
        .lineLimit(1)
    }

    /// Close until the first turn, then pause and resume (Space).
    private var leftButton: some View {
        let paused = capture.state == .paused
        return Button(action: inSession ? toggle : close) {
            Image(systemName: !inSession ? "xmark" : paused ? "play.fill" : "pause.fill")
                .font(.system(size: inSession ? 14 : 16, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(CaptureButtonStyle.nightIcon)
        .keyboardShortcut(inSession ? KeyboardShortcut(.space, modifiers: []) : .cancelAction)
        .disabled(inSession && !capture.canToggle)
        .accessibilityLabel(!inSession ? "Close" : paused ? "Resume recording" : "Pause recording")
        .help(!inSession ? "Close (Esc)" : paused ? "Resume (Space)" : "Pause (Space)")
    }

    /// Record (Space) until the first turn, then Done (Return): the dot squares off into a stop.
    private var rightButton: some View {
        Button(action: inSession ? done : toggle) {
            RoundedRectangle(cornerRadius: inSession ? 3 : 7)
                .fill(Night.bg)
                .frame(width: 14, height: 14)
                .animation(reduceMotion ? Motion.fade : CaptureMotion.small, value: inSession)
        }
        .buttonStyle(CaptureButtonStyle(fill: Tok.voiceBright, hover: Tok.voiceBright.opacity(0.9), ink: Night.bg, diameter: 44))
        .keyboardShortcut(inSession ? .defaultAction : KeyboardShortcut(.space, modifiers: []))
        .disabled(inSession ? capture.starting : !capture.canToggle)
        .accessibilityLabel(inSession ? "Done" : "Start recording")
        .help(inSession ? "Done (Return)" : "Record (Space)")
        .tourAnchor(.recordButton)
    }

    private func promptCard(_ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today’s prompt").monoCaps(11, tracking: 0.12).foregroundStyle(Night.ink2)
            Text(prompt).font(Typo.serif(22)).tracking(-0.22).lineSpacing(4).foregroundStyle(Night.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Night.surface, in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.24), radius: 40, y: 32)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private func messageStep(_ message: RecorderNotice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(message.title).font(Typo.ui(13)).foregroundStyle(Night.ink)
                if let detail = message.detail { Text(detail).font(Typo.ui(12)).foregroundStyle(Night.ink2) }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("Close", action: close)
                    .buttonStyle(CaptureButtonStyle(fill: .clear, hover: Night.glass.opacity(0.6), ink: Night.ink2, padding: 16, size: 13))
                    .keyboardShortcut(.cancelAction)
                if let url = message.settings {
                    Button("Open System Settings") { NSWorkspace.shared.open(url) }
                        .buttonStyle(CaptureButtonStyle(fill: Night.sage, hover: Night.sageDark, ink: Night.bg, padding: 16, size: 13))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The rolling mic level as 3 pt bars 3 pt apart, sampled from `CaptureController.level` every 60 ms;
/// each sample nudges the row in from the right, so it reads as scrolling.
struct LevelMeter: View {
    let height: CGFloat
    let color: Color
    /// Samples while true; freezes (as when paused) while false.
    let live: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var levels: [Double]
    @State private var tick = 0

    init(bars: Int = 24, height: CGFloat = 28, color: Color, live: Bool) {
        self.height = height
        self.color = color
        self.live = live
        _levels = State(initialValue: Array(repeating: Self.flat, count: bars))
    }

    private static let flat = 0.08

    var body: some View {
        let nudge: Double = reduceMotion ? 0 : 6
        HStack(spacing: 3) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule().fill(color).frame(width: 3, height: height).scaleEffect(y: levels[i])
            }
        }
        .frame(height: height)
        .keyframeAnimator(initialValue: 0.0, trigger: tick) { row, x in row.offset(x: x) } keyframes: { _ in
            MoveKeyframe(nudge)
            LinearKeyframe(0, duration: 0.066)
        }
        .task(id: live) {
            while live, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                levels.removeFirst()
                levels.append(max(Self.flat, CaptureController.shared.level))
                tick &+= 1
            }
        }
        .accessibilityHidden(true)
    }
}

/// The night palette (globals.css `.dark`), fixed so the pill reads the same in either appearance.
enum Night {
    static let bg = Color(0x0E1411, 0x0E1411)
    static let surface = Color(0x16201B, 0x16201B)
    static let ink = Color(0xE3EBE6, 0xE3EBE6)
    static let ink2 = Color(0x9FB0A7, 0x9FB0A7)
    static let ink3 = Color(0x92A399, 0x92A399)
    static let ink4 = Color(0x56655D, 0x56655D)
    static let glass = Color(0x2A3831, 0x2A3831)
    static let sage = Color(0x7FBFA0, 0x7FBFA0)
    static let sageDark = Color(0x95CCB1, 0x95CCB1)
    static let echo = Color(0xA7A2EC, 0xA7A2EC)
}

extension CaptureButtonStyle {
    /// The pill's 44 pt icon discs (`bg-white/80` in the night scope).
    static var nightIcon: Self { Self(fill: Night.glass.opacity(0.8), hover: Night.glass, ink: Night.ink, diameter: 44) }
}

/// Opacity with a 4 pt blur, for the pill's steps.
private struct BlurFade: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.opacity(phase.isIdentity ? 1 : 0).blur(radius: phase.isIdentity ? 0 : 4)
    }
}
