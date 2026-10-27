import AVFoundation
import SaroKit
import SwiftUI

/// The recorder: live preview (or a voice level), device pickers, timer and turn count, record/pause/resume and Done.
/// In the window it floats as a centred card over the canvas; in the capture panel it fills the panel.
/// Space records, pauses and resumes; Return is Done; Esc closes before anything is recorded.
struct RecorderView: View {
    let kind: EntryKind
    var surface: CaptureController.Surface = .window
    /// Called instead of `onClose` when Done ends a session that saved at least one turn.
    var onSaved: (() -> Void)?
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var capture: CaptureController { .shared }
    private var compact: Bool { surface == .panel }
    private var available: Bool { capture.isAvailable(to: surface) }
    private var inSession: Bool { capture.hasSession(surface) }
    private var live: Bool { available && [.previewing, .recording, .paused].contains(capture.state) }

    var body: some View {
        let card = VStack(spacing: 14) {
            header
            stage
            if compact, live { pickers }
            controls
        }
        .task(id: available ? kind : nil) {
            if available { await capture.prepare(kind, for: surface, model: model) }
        }
        .onDisappear { capture.finish(surface) }
        .animation(Motion.pick(Motion.fade, reduce: reduceMotion), value: capture.state)

        if compact {
            card
        } else {
            card
                .padding(18)
                .frame(width: 620)
                .saroSurface(radius: 20, lifted: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tok.bg.opacity(0.55))
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 8) {
            Text(kind == .moment ? "MOMENT" : "VOICE NOTE")
                .font(Typo.mono(10.5))
                .tracking(0.8)
                .foregroundStyle(Tok.ink3)
            Spacer()
            if live { RecorderClock() }
        }
    }

    @ViewBuilder private var stage: some View {
        if !available {
            message(icon: "record.circle", capture.owner == surface ? "Saving your last recording…"
                    : capture.owner == .panel ? "Saro is recording in the capture panel." : "The recorder is open in Saro's window.")
        } else if case .needsAccess(let access) = capture.state {
            message(icon: access == .camera ? "video.slash" : "mic.slash",
                    access == .camera ? "Saro needs your camera to record a moment." : "Saro needs your microphone to record.",
                    detail: "Turn it on in System Settings → Privacy & Security, then reopen the recorder.") {
                Button("Open System Settings") { NSWorkspace.shared.open(access.settingsURL) }
                if access == .camera { voiceInstead }
            }
        } else if case .failed(let text) = capture.state {
            message(icon: "exclamationmark.triangle", text) { if kind == .moment { voiceInstead } }
        } else if !live {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: compact ? 150 : 200, maxHeight: compact ? .infinity : nil)
        } else if kind == .moment {
            CameraPreview(session: capture.engine.session)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    LevelBars(bars: 14, height: 14, color: Tok.mint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.35), in: .capsule)
                        .padding(10)
                }
        } else {
            LevelBars(bars: compact ? 36 : 60, height: compact ? 96 : 140, color: Tok.sage)
                .frame(maxWidth: .infinity, minHeight: compact ? 150 : 200, maxHeight: compact ? .infinity : nil)
                .background(Tok.surfaceAlt, in: .rect(cornerRadius: 12))
        }
    }

    /// Only the window offers this; the panel has its own Voice tab.
    @ViewBuilder private var voiceInstead: some View {
        if !compact { Button("Record a voice note instead") { model.recorderKind = .voice } }
    }

    private func message<Actions: View>(icon: String, _ text: String, detail: String? = nil,
                                        @ViewBuilder actions: () -> Actions = { EmptyView() }) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Tok.ink3)
            Text(text).font(Typo.ui(13, .medium)).foregroundStyle(Tok.ink)
            if let detail { Text(detail).font(Typo.ui(12)).foregroundStyle(Tok.ink2) }
            HStack { actions() }.controlSize(.small).padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: compact ? 150 : 200, maxHeight: compact ? .infinity : nil)
        .background(Tok.surfaceAlt, in: .rect(cornerRadius: 12))
    }

    private var pickers: some View {
        HStack(spacing: 8) {
            if kind == .moment, !capture.cameras.isEmpty {
                Picker("Camera", selection: Binding(get: { capture.cameraID ?? "" }, set: { capture.select(camera: $0) })) {
                    ForEach(capture.cameras) { Label($0.name, systemImage: $0.isPhone ? "iphone" : "web.camera").tag($0.id) }
                }
            }
            Picker("Microphone", selection: Binding(get: { capture.micID ?? "" }, set: { capture.select(mic: $0) })) {
                ForEach(capture.mics) { Label($0.name, systemImage: "mic").tag($0.id) }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
        .disabled(capture.state == .recording)
    }

    private var controls: some View {
        HStack {
            Group { if !compact, live { pickers } }
                .frame(maxWidth: .infinity, alignment: .leading)
            if live { recordButton }
            Group {
                if inSession {
                    Button("Done", action: done)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .tint(Tok.sage)
                        .disabled(capture.starting)
                } else {
                    Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var recordButton: some View {
        let recording = capture.state == .recording
        let size: CGFloat = compact ? 48 : 58
        return Button { capture.toggle() } label: {
            Image(systemName: recording ? "pause.fill" : "circle.fill")
                .font(.system(size: recording ? size * 0.36 : size * 0.6))
                .foregroundStyle(Tok.voice)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Tok.voice.opacity(0.35), lineWidth: 2))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .disabled(!capture.canToggle)
        .opacity(capture.canToggle ? 1 : 0.4)
        .accessibilityLabel(recording ? "Pause" : inSession ? "Resume" : "Record")
        .help(recording ? "Pause (Space)" : inSession ? "Resume (Space)" : "Record (Space)")
        .tourAnchor(.recordButton)
    }

    private func done() {
        let saved = inSession
        capture.finish(surface)
        if saved, let onSaved { onSaved() } else { onClose() }
    }

    private func close() {
        capture.finish(surface)
        onClose()
    }
}

/// Elapsed time across turns and the turn count; re-renders at 20 Hz on its own.
private struct RecorderClock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let capture = CaptureController.shared
        let elapsed = capture.elapsed
        HStack(spacing: 6) {
            if capture.state == .recording {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Tok.voice)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
            }
            Text(elapsed.formatted(.time(pattern: elapsed >= .seconds(3600) ? .hourMinuteSecond : .minuteSecond(padMinuteToLength: 2))))
                .font(Typo.mono(12))
                .monospacedDigit()
                .foregroundStyle(Tok.ink)
            if capture.turn > 0 {
                Text("TURN \(capture.turn)").font(Typo.mono(10.5)).foregroundStyle(Tok.ink3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A rolling history of the mic level as bars.
private struct LevelBars: View {
    let bars: Int
    let height: CGFloat
    let color: Color
    @State private var history: [Double]

    init(bars: Int, height: CGFloat, color: Color) {
        self.bars = bars
        self.height = height
        self.color = color
        _history = State(initialValue: Array(repeating: 0, count: bars))
    }

    var body: some View {
        let level = CaptureController.shared.level
        HStack(spacing: 3) {
            ForEach(history.indices, id: \.self) { i in
                Capsule()
                    .fill(color.opacity(0.35 + 0.65 * history[i]))
                    .frame(width: 3, height: max(3, height * history[i]))
            }
        }
        .frame(height: height)
        .onChange(of: level) { _, new in
            history.removeFirst()
            history.append(new)
        }
        .accessibilityHidden(true)
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateNSView(_ view: PreviewView, context: Context) {}
}

private final class PreviewView: NSView {
    private let preview: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .black
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        preview.videoGravity = .resizeAspectFill
        // Mac cameras (built-in and Continuity) all face you but report `.unspecified`, so mirror every preview
        // like Photo Booth. The recorded file stays unmirrored.
        preview.transform = CATransform3DMakeScale(-1, 1, 1)
        layer?.addSublayer(preview)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.bounds = bounds
        preview.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }
}
