import AppKit
import SaroKit
import SwiftUI

/// The web build's voice note pill (VoiceEchoOverlay): a night surface in either appearance, like a Dynamic Island.
/// Opening it starts recording; Space stops into review, where Space plays and Return keeps the note. Esc asks before
/// anything is thrown away. Steps swap with a 4 pt blur crossfade, and review grows on the layout spring.
struct VoicePill: View {
    let notice: RecorderNotice?
    /// Growing out of the Voice button, which is its entrance.
    var grows = false
    var compact = false
    /// Keep this: true when the note's card flew out of the pill (given the pill's frame).
    let kept: (CGRect?) -> Bool
    /// Back into the button, with nothing kept.
    let close: () -> Void
    /// Closes, keeping what was kept.
    let shut: () -> Void

    enum Confirm { case discard, again }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A key brings the pill up at once (the frequency rule).
    @State private var appeared = Motion.byKey
    @State private var confirm: Confirm?
    @State private var marked = false
    @State private var frame: CGRect?
    @FocusState private var focused: Bool

    private var capture: CaptureController { .shared }
    /// A notice with an icon replaces the recorder; a spinner notice keeps it, as the web pill's "starting" step does.
    private var message: RecorderNotice? {
        if let notice, notice.icon != nil { return notice }
        if capture.state == .review, !capture.interrupted, (capture.lastPart ?? .zero) < .milliseconds(300) {
            return RecorderNotice(icon: "mic.slash", title: "Nothing was recorded. Check your microphone and try again.", retry: true)
        }
        return nil
    }

    private enum Step: Hashable { case message, recording, review, confirm, marked }

    private var step: Step {
        if marked { return .marked }
        if confirm != nil { return .confirm }
        if message != nil { return .message }
        return capture.state == .review ? .review : .recording
    }

    var body: some View {
        let swap: AnyTransition = reduceMotion ? .opacity : AnyTransition(BlurSwap(radius: 4))
        ZStack {
            switch step {
            case .message: messageStep(message!).transition(swap)
            case .recording: recordingStep.transition(swap)
            case .review: VoiceReview(again: { confirm = .again }, discard: { confirm = .discard }, keep: keep).transition(swap)
            case .confirm: confirmStep.transition(swap)
            case .marked:
                Text("Your voice leaves a mark.").font(Typo.serif(17)).foregroundStyle(Night.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 22)
                    .transition(swap)
            }
        }
        .animation(reduceMotion ? Motion.fade : step == .review ? Motion.surface : CaptureMotion.out(0.2), value: step)
        .frame(maxWidth: .infinity)
        .background(Night.surface.opacity(0.95))
        .background(.frosted(solid: Night.surface))
        .clipShape(.rect(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.24), radius: 40, y: 32)
        .environment(\.colorScheme, .dark)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DayView.space)) } action: { frame = $0 }
        .offset(y: appeared || grows || reduceMotion ? 0 : 16)
        .scaleEffect(appeared || grows || reduceMotion ? 1 : 0.96, anchor: .bottom)
        .opacity(appeared || grows ? 1 : 0)
        .animation(reduceMotion ? Motion.fade : CaptureMotion.surface, value: appeared)
        .onAppear { appeared = true }
        // Opening the pill starts recording, once the microphone is up.
        .onChange(of: capture.state, initial: true) { _, s in if s == .previewing, capture.turn == 0, confirm == nil { capture.toggle() } }
        // Esc asks before throwing anything away; the confirm and message steps have their own Esc buttons.
        .background {
            if step == .recording || step == .review { Button("", action: escape).keyboardShortcut(.cancelAction).hidden() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(step == .review ? "Listen back to your voice note" : "Voice note")
    }

    // MARK: Recording

    private var recordingStep: some View {
        let recording = capture.state == .recording
        let paused = capture.state == .paused
        let status = notice?.title ?? capture.live.line(paused: paused, voice: true)
        let always = PrefsStore.shared.captionsAlways
        return VStack(alignment: .leading, spacing: 8) {
            if !capture.prompt.isEmpty {
                Text(capture.prompt).font(Typo.serif(15, italic: true)).foregroundStyle(Night.ink2).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Today’s prompt: \(capture.prompt)")
                    .padding(.horizontal, 4)
            }
            Group {
                if let status, notice != nil || !paused || !always {
                    CaptionStatus(text: status, connecting: capture.live == .connecting || notice != nil, night: true)
                } else {
                    PillCaption(words: capture.partWords)
                }
            }
            .frame(height: 22)
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
                LevelMeter(color: Night.echo, live: notice == nil && !paused)
                    .opacity(recording ? 1 : 0.4)
                    .animation(CaptureMotion.out(0.24), value: recording)
                    .frame(maxWidth: .infinity)
                    .clipped()
                Button { capture.toggle() } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(CaptureButtonStyle.nightIcon)
                .disabled(!capture.canToggle || capture.turn == 0)
                .accessibilityLabel(paused ? "Resume recording" : "Pause recording")
                .help(paused ? "Resume" : "Pause")
                Button { Task { await capture.endPart() } } label: {
                    RoundedRectangle(cornerRadius: 3).fill(Night.bg).frame(width: 14, height: 14)
                }
                .buttonStyle(CaptureButtonStyle(fill: Tok.voiceBright, hover: Tok.voiceBright.opacity(0.9), ink: Night.bg, diameter: 44))
                .keyboardShortcut(.space, modifiers: [])
                .focused($focused)
                .disabled(capture.starting || capture.turn == 0 || !(recording || paused))
                .accessibilityLabel("Stop and listen back")
                .help("Stop  Space")
                .tourAnchor(.recordButton)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { focused = true }
    }

    // MARK: Confirm and messages

    private var confirmStep: some View {
        HStack(spacing: 8) {
            Text(confirm == .again ? "Discard this one and record again?" : "Discard this voice note?")
                .font(Typo.ui(13)).foregroundStyle(Night.ink).lineLimit(2)
            Spacer(minLength: 8)
            Button("Keep") { confirm = nil }
                .buttonStyle(CaptureButtonStyle(fill: .clear, hover: Night.glass.opacity(0.6), ink: Night.ink2, padding: 14, size: 13))
                .keyboardShortcut(.cancelAction)
            Button("Discard") { discard(again: confirm == .again) }
                .buttonStyle(CaptureButtonStyle(fill: Tok.danger, hover: Tok.danger.opacity(0.85), ink: Night.bg, padding: 14, size: 13))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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
                Button("Close") { capture.take == nil ? close() : discard(again: false) }
                    .buttonStyle(CaptureButtonStyle(fill: .clear, hover: Night.glass.opacity(0.6), ink: Night.ink2, padding: 16, size: 13))
                    .keyboardShortcut(.cancelAction)
                if let url = message.settings {
                    Button("Open System Settings") { NSWorkspace.shared.open(url) }
                        .buttonStyle(CaptureButtonStyle(fill: Night.sage, hover: Night.sageDark, ink: Night.bg, padding: 16, size: 13))
                        .keyboardShortcut(.defaultAction)
                } else if message.retry {
                    Button("Try again") {
                        if capture.take != nil { discard(again: true) } else { capture.retry() }
                    }
                    .buttonStyle(CaptureButtonStyle(fill: Night.sage, hover: Night.sageDark, ink: Night.bg, padding: 16, size: 13))
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    /// Esc backs out of a confirm; while recording or in review it asks first; before anything, it closes.
    private func escape() {
        if confirm != nil { confirm = nil; return }
        if capture.take != nil { confirm = .discard } else { close() }
    }

    private func discard(again: Bool) {
        confirm = nil
        Task {
            await capture.discardTake(again: again)
            if !again { close() }
        }
    }

    private func keep() {
        if kept(compact ? nil : frame) { return }
        marked = true
        AccessibilityNotification.Announcement("Your voice leaves a mark.").post()
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            shut()
        }
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
