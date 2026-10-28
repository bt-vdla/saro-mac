import AVFoundation
import SaroKit
import SwiftUI

/// The recording ritual from the web build (VideoReflectionScreen, CountdownOverlay, VoiceEchoOverlay).
/// In the window a moment records in a large frame over the dimmed, blurred canvas and a voice note in a night pill
/// pinned to the bottom; in the capture panel either one fills the panel.
/// Space records, pauses and resumes (and skips the countdown); Return is Done; Esc closes before anything is recorded.
struct RecorderView: View {
    let kind: EntryKind
    var surface: CaptureController.Surface = .window
    /// The bar button a click opened it from: the surface grows out of it and closes back into it (morph.ts).
    var origin: Anchor<CGRect>?
    /// Called instead of `onClose` when Done ends a session that saved at least one turn.
    var onSaved: (() -> Void)?
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A key brings the recorder up at once (the frequency rule).
    @State private var appeared = Motion.byKey
    /// 0 on the bar button, 1 where the surface rests.
    @State private var grown = 0.0
    /// The flight out landed before any close, so going back crossfades the other way (mid-flight it just turns round).
    @State private var landed = false
    @State private var leaving = false
    /// Hidden at once: closed by a key, or back in its button.
    @State private var gone = false
    /// The pill's height, measured (its recording step until then).
    @State private var pillHeight: CGFloat = 98
    @State private var countdown: Int?
    @State private var developing = false
    /// Done in the panel, waiting for the last turn to save.
    @State private var ending = false
    /// The countdown, the develop flash before Done closes, or that wait.
    @State private var ritual: Task<Void, Never>?

    private var capture: CaptureController { .shared }
    private var compact: Bool { surface == .panel }
    private var available: Bool { capture.isAvailable(to: surface) }
    private var inSession: Bool { capture.hasSession(surface) }

    var body: some View {
        Group {
            if compact {
                stage(radius: 20)
            } else {
                GeometryReader { geo in
                    let button = from.map { geo[$0] }
                    if kind == .moment { momentFrame(geo.size, from: button) } else { voicePill(geo.size, from: button) }
                }
            }
        }
        .task(id: available && !ending ? kind : nil) {
            if available, !ending { await capture.prepare(kind, for: surface, model: model) }
        }
        .onAppear {
            appeared = true
            // Without a flight it is already there, so turning Reduce Motion off later can't fold it into the button.
            guard from != nil else { grown = 1; landed = true; return }
            withAnimation(flightSpring) { grown = 1 } completion: { if !leaving { landed = true } }
        }
        // A moment's 3-2-1 must not go on to start whatever kind replaced it.
        .onChange(of: kind) { if countdown != nil { cancelCountdown() } }
        .onDisappear {
            ritual?.cancel()
            capture.finish(surface)
        }
        .allowsHitTesting(!leaving)
        .opacity(gone ? 0 : 1)
        .animation(nil, value: gone)
        // In the window the surface brings itself in (or, for a key, doesn't).
        .transition(compact ? .opacity.animation(CaptureMotion.out(0.2))
            : .asymmetric(insertion: .identity, removal: .opacity.animation(CaptureMotion.out(0.2))))
    }

    private var from: Anchor<CGRect>? { reduceMotion ? nil : origin }

    /// MorphLayer.tsx: a flight over a big share of the window takes the surface spring, a small one the small spring.
    private var flightSpring: Animation { kind == .moment ? Motion.surface : Motion.small }

    private func flight(from button: CGRect?, to rest: CGRect) -> GrowFlight {
        GrowFlight(v: button == nil ? 1 : grown, from: button ?? rest, to: rest, outbound: !(leaving && landed), face: .of(kind))
    }

    // MARK: Layouts

    /// Inset 16 (24 on wide canvases), radius 28, over black/45 and a blur.
    private func momentFrame(_ size: CGSize, from button: CGRect?) -> some View {
        let inset: CGFloat = size.width >= 1024 ? 24 : 16
        let lit = appeared && !leaving
        return ZStack {
            Rectangle().fill(.frosted(solid: Night.bg))
                .overlay(Color.black.opacity(0.45))
                .environment(\.colorScheme, .dark)
                .contentShape(.rect)
                .onTapGesture {}
                .opacity(lit ? 1 : 0)
                .animation(CaptureMotion.out(0.3), value: lit)
            stage(radius: 28)
                .background(RoundedRectangle(cornerRadius: 28).fill(.black).shadow(color: .black.opacity(0.24), radius: 40, y: 32))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.1)))
                .modifier(flight(from: button, to: CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)))
                .padding(inset)
                .scaleEffect(appeared || reduceMotion || button != nil ? 1 : 0.96, anchor: .bottom)
                .opacity(appeared || button != nil ? 1 : 0)
                .animation(reduceMotion ? Motion.fade : CaptureMotion.surface, value: appeared)
        }
    }

    /// min(380, width − 32) wide, 8 pt above the bottom of the canvas.
    private func voicePill(_ size: CGSize, from button: CGRect?) -> some View {
        let width = max(0, min(380, size.width - 32))
        return VoicePill(notice: notice, inSession: inSession, grows: button != nil, prompt: model.handoffPrompt, toggle: primary, done: done, close: close)
            .frame(width: width)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pillHeight = $0 }
            .modifier(flight(from: button, to: CGRect(x: (size.width - width) / 2, y: size.height - 8 - pillHeight, width: width, height: pillHeight)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 8)
    }

    /// The frame's content: the live camera (or, for a voice note in the panel, the meter) under the HUD, or a state card.
    private func stage(radius: CGFloat) -> some View {
        let notice = notice
        return ZStack {
            if kind == .moment {
                Color.black
                if notice == nil { CameraPreview(session: capture.engine.session) }
            } else {
                Night.surface
            }
            if notice == nil {
                hud
                    .environment(\.colorScheme, .dark)
                    .opacity(developing ? 0 : 1)
                    .animation(CaptureMotion.out(0.2), value: developing)
            }
            if kind == .moment, !compact { flash }
            if let notice {
                StateCard(notice: notice, compact: compact, close: close,
                          voiceInstead: notice.voiceInstead ? { model.recorderKind = .voice } : nil)
                    .transition(.opacity)
            }
        }
        .clipShape(.rect(cornerRadius: radius))
        // The brand card fades into the camera, as the web build's loading screen does.
        .animation(CaptureMotion.out(0.6), value: notice == nil)
    }

    private var hud: some View {
        ZStack {
            if kind == .moment {
                // Legibility shades: 45% from the top, half from the bottom.
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.55), location: 0), .init(color: .black.opacity(0.15), location: 0.225),
                    .init(color: .clear, location: 0.45), .init(color: .clear, location: 0.5),
                    .init(color: .black.opacity(0.2), location: 0.75), .init(color: .black.opacity(0.65), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
                if !compact, let prompt = model.handoffPrompt { MomentPrompt(prompt: prompt, dimmed: countdown != nil) }
            } else {
                LevelMeter(height: 56, color: Night.echo, live: capture.state != .paused)
                    .opacity(capture.state == .recording ? 1 : 0.4)
                    .animation(CaptureMotion.out(0.24), value: capture.state)
            }
            if let countdown {
                Countdown(count: countdown)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                                                     removal: .opacity.combined(with: .scale(scale: 1.04))))
            }
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomBar
            }
            if !compact {
                Image("Logo").resizable().scaledToFit()
                    .frame(width: 56, height: 56)
                    .opacity(0.8)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 8) {
            if !compact { DatePill() }
            devicePills
            Spacer(minLength: 8)
            if inSession {
                Button("Done", action: done)
                    .buttonStyle(CaptureButtonStyle.glass(padding: 24, compact: compact))
                    .keyboardShortcut(.defaultAction)
                    .disabled(capture.starting || developing)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
            } else {
                Button("Close") { countdown == nil ? close() : cancelCountdown() }
                    .buttonStyle(CaptureButtonStyle.glass(compact: compact))
                    .keyboardShortcut(.cancelAction)
                    .opacity(countdown == nil ? 1 : 0)
                    .allowsHitTesting(countdown == nil)
                    .transition(.opacity)
            }
        }
        .padding(compact ? 12 : 24)
        .animation(reduceMotion ? Motion.fade : CaptureMotion.small, value: inSession)
        .animation(CaptureMotion.out(0.2), value: countdown == nil)
    }

    private var bottomBar: some View {
        HStack(alignment: .top, spacing: compact ? 8 : 24) {
            // A stack, not a Group: the column must keep its width before the first turn.
            VStack { if inSession { timer.transition(.opacity) } }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 20)
            recordButton
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, compact ? 14 : 24)
        .animation(CaptureMotion.out(0.25), value: inSession)
    }

    /// Elapsed across turns in Geist Mono, with the turn count under it.
    private var timer: some View {
        let paused = capture.state == .paused
        return VStack(alignment: .trailing, spacing: 2) {
            ElapsedText()
                .font(Typo.mono(12.5, .regular))
                .tracking(0.75)
                .foregroundStyle(.white.opacity(paused ? 0.6 : 1))
            Text(paused ? "Paused · turn \(capture.turn)" : "Turn \(capture.turn)")
                .font(Typo.ui(11, .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .legible()
        .accessibilityElement(children: .combine)
    }

    private var recordButton: some View {
        let look: RecordLook = countdown != nil ? .armed
            : capture.state == .recording ? .recording : capture.state == .paused ? .paused : .idle
        let wash: Color = look == .recording ? .black.opacity(0.2) : .white.opacity(0.1)
        return VStack(spacing: 6) {
            Button(action: primary) { RecordDisc(look: look) }
                .buttonStyle(CaptureButtonStyle(fill: wash, hover: look == .recording ? wash : .white.opacity(0.2),
                                                ink: .white, diameter: 64))
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!capture.canToggle || developing)
                .accessibilityLabel(look.label)
                .help("\(look.label) (Space)")
                .tourAnchor(.recordButton)
            Text(look.caption)
                .font(Typo.ui(11, .medium))
                .foregroundStyle(.white.opacity(0.8))
                .legible()
                .accessibilityHidden(true)
        }
    }

    /// Camera and microphone as quiet glass pills; locked while a turn records.
    private var devicePills: some View {
        let recording = capture.state == .recording
        return HStack(spacing: 8) {
            if kind == .moment, let camera = capture.cameras.first(where: { $0.id == capture.cameraID }) {
                devicePill("Camera", icon: camera.isPhone ? "iphone" : "web.camera", current: camera.name,
                           devices: capture.cameras, selection: camera.id) { CaptureController.shared.select(camera: $0) }
            }
            if let mic = capture.mics.first(where: { $0.id == capture.micID }) {
                devicePill("Microphone", icon: "mic", current: mic.name, devices: capture.mics, selection: mic.id) {
                    CaptureController.shared.select(mic: $0)
                }
            }
        }
        .disabled(recording)
        .opacity(recording ? 0.35 : 1)
        .animation(CaptureMotion.out(0.2), value: recording)
    }

    private func devicePill(_ title: String, icon: String, current: String, devices: [CaptureController.Device],
                            selection: String, select: @escaping @MainActor @Sendable (String) -> Void) -> some View {
        Menu {
            Picker(title, selection: Binding(get: { selection }, set: select)) {
                ForEach(devices) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                if !compact { Text(current).lineLimit(1).frame(maxWidth: 150) }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .font(Typo.ui(12, .medium))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, compact ? 10 : 12)
        .frame(height: 28)
        .frosted()
        .help(current)
        .accessibilityLabel("\(title): \(current)")
    }

    /// A develop flash on Done: the frame washes bright and settles back, like a print, before it closes.
    private var flash: some View {
        Color(red: 1, green: 0.97, blue: 0.9)
            .keyframeAnimator(initialValue: 0.0, trigger: developing) { view, value in view.opacity(value) } keyframes: { _ in
                LinearKeyframe(0.55, duration: 0.12, timingCurve: CaptureMotion.outCurve)
                LinearKeyframe(0, duration: 0.88, timingCurve: .easeInOut)
            }
            .allowsHitTesting(false)
    }

    // MARK: State

    /// What to show instead of the live recorder; nil once the preview runs. No icon means a spinner.
    private var notice: RecorderNotice? {
        if ending { return RecorderNotice(title: "Saving your last recording…") }
        if !available {
            if capture.owner == surface { return RecorderNotice(title: "Saving your last recording…") }
            return RecorderNotice(icon: "record.circle",
                                  title: capture.owner == .panel ? "Saro is recording in the capture panel." : "The recorder is open in Saro's window.",
                                  detail: "Finish there, then come back.", alarm: false)
        }
        switch capture.state {
        case .previewing, .recording, .paused:
            return nil
        case .needsAccess(let access):
            let camera = access == .camera
            return RecorderNotice(icon: camera ? "video.slash" : "mic.slash",
                                  title: camera ? "Saro needs your camera to record a moment." : "Saro needs your microphone to record.",
                                  detail: "Turn it on in System Settings → Privacy & Security → \(camera ? "Camera" : "Microphone"), then reopen the recorder.",
                                  settings: access.settingsURL, voiceInstead: camera && !compact)
        case .failed(let text):
            // Mid-session the controller keeps recording the session's kind, so a switch would record video behind a voice pill.
            return RecorderNotice(icon: "exclamationmark.triangle", title: text, voiceInstead: kind == .moment && !compact && !inSession)
        default:
            return kind == .moment
                ? RecorderNotice(title: "Getting your camera ready…", detail: "If macOS asks, allow the camera and microphone.",
                                 quote: compact ? nil : model.handoffPrompt)
                : RecorderNotice(title: "Starting the microphone…")
        }
    }

    // MARK: Actions

    /// The record button: a moment's first turn waits for a 3-2-1, which the button (or Space) skips.
    private func primary() {
        // Space while it flies back into its button must not start a turn.
        guard !leaving else { return }
        if countdown != nil { return startNow() }
        if kind == .moment, capture.state == .previewing, !inSession { return startCountdown() }
        capture.toggle()
    }

    private func startCountdown() {
        ritual = Task {
            for n in [3, 2, 1] {
                withAnimation(reduceMotion ? Motion.fade : CaptureMotion.out(n == 3 ? 0.3 : 0.35)) { countdown = n }
                AccessibilityNotification.Announcement("\(n)").post()
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            startNow()
        }
    }

    private func startNow() {
        cancelCountdown()
        capture.toggle()
    }

    private func cancelCountdown() {
        ritual?.cancel()
        ritual = nil
        withAnimation(reduceMotion ? Motion.fade : CaptureMotion.out(0.3)) { countdown = nil }
    }

    private func done() {
        let saved = inSession
        guard saved, kind == .moment, !compact, !reduceMotion else { return finish(saved) }
        // Stop this turn now; the preview stays live under the flash.
        if capture.state == .recording { capture.toggle() }
        developing = true
        ritual = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { finish(saved) }
        }
    }

    private func finish(_ saved: Bool) {
        guard saved, let onSaved else {
            capture.finish(surface)
            return onClose()
        }
        // "Saved to today." only once the last turn is on disk, and only if some turn made it there.
        ending = true
        ritual = Task {
            let wrote = await capture.end(surface)
            guard !Task.isCancelled else { return }
            if wrote { onSaved() } else { onClose() }
        }
    }

    private func close() {
        guard !leaving else { return }
        ritual?.cancel()
        let key = Motion.byKey
        guard from != nil, !key else {
            if key { gone = true }
            return shut()
        }
        // Back into the button as the scrim lifts; the camera stops once it's there, so its last frames go back with it.
        leaving = true
        withAnimation(flightSpring) { grown = 0 } completion: { land() }
        // If frames stall (a minimised window), it lands anyway, as MorphLayer's watchdog does.
        ritual = Task {
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { land() }
        }
    }

    /// In its button: the button shows again as the surface goes, with nothing left to fade.
    private func land() {
        guard !gone else { return }
        gone = true
        shut()
    }

    private func shut() {
        capture.finish(surface)
        onClose()
    }
}

struct RecorderNotice: Equatable {
    var icon: String?
    var title: String
    var detail: String?
    var settings: URL?
    var voiceInstead = false
    /// Permission and failure states get the danger disc; a busy hand-off doesn't.
    var alarm = true
    /// The first reflection's question, under the camera's loading state.
    var quote: String?
}

/// The flight between a bar button and the recorder surface it opened (morph.ts, MorphLayer.tsx): a box flying from the
/// button to where the surface rests, holding the surface and a copy of the button's face, each scaled uniformly to cover
/// it (centred across, from the top) as they crossfade. The surface keeps its layout; once landed nothing is clipped.
struct GrowFlight: ViewModifier, @MainActor Animatable {
    var v: Double
    let from: CGRect
    let to: CGRect
    /// Out of the button; false on the way back from rest.
    let outbound: Bool
    let face: CaptureFace

    var animatableData: Double {
        get { v }
        set { v = newValue }
    }

    func body(content: Content) -> some View {
        let box = CanvasMath.flightBox(from: from, to: to, v: v).offsetBy(dx: -to.minX, dy: -to.minY)
        let fades = CanvasMath.flightFades(outbound ? v : 1 - v)
        ZStack(alignment: .topLeading) {
            content
                .opacity(outbound ? fades.arriving : fades.leaving)
                .scaleEffect(max(box.width / max(to.width, 1), box.height / max(to.height, 1)), anchor: .top)
                .offset(x: box.midX - to.width / 2, y: box.minY)
            face.frame(width: from.width, height: from.height)
                .scaleEffect(max(box.width / from.width, box.height / from.height), anchor: .top)
                .offset(x: box.midX - from.width / 2, y: box.minY)
                .opacity(outbound ? fades.leaving : fades.arriving)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .clipShape(FlightClip(box: v < 1 ? box : nil, radius: Radius.panel + (Radius.sheet - Radius.panel) * v))
    }
}

/// The flight's box, rounded from the button's 20 to the surface's 28.
private struct FlightClip: Shape {
    let box: CGRect?
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        // ponytail: landed, it clips to well past the surface's shadow (≤ 80 pt) rather than not at all, so the surface
        // keeps one structure and its camera view isn't rebuilt.
        guard let box else { return Path(rect.insetBy(dx: -200, dy: -200)) }
        return RoundedRectangle(cornerRadius: min(radius, box.width / 2, box.height / 2)).path(in: box)
    }
}

/// The web build's motion tokens (lib/motion.ts).
enum CaptureMotion {
    /// Overlays, sheets, big surfaces.
    static let surface = Animation.spring(response: 0.272, dampingFraction: 1)
    /// Pills, chips, small surfaces.
    static let small = Animation.spring(response: 0.170, dampingFraction: 1)
    static let press = Animation.spring(response: 0.102, dampingFraction: 1)
    /// ease.out, cubic-bezier(0.23, 1, 0.32, 1): entrances and exits.
    static let outCurve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.23, y: 1), endControlPoint: UnitPoint(x: 0.32, y: 1))
    static func out(_ duration: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
}

/// The web build's buttons: 44 pt pills (or discs) with a hover fill, pressing to 0.96 on the press spring.
struct CaptureButtonStyle: ButtonStyle {
    var fill: Color
    var hover: Color
    var ink: Color
    var line: Color = .clear
    var shadow: Color = .clear
    var frosted = false
    var padding: CGFloat = 20
    var size: CGFloat = 14
    var height: CGFloat = 44
    /// A disc of this size instead of a pill.
    var diameter: CGFloat?

    static var primary: Self { Self(fill: Tok.sage, hover: Tok.sageDark, ink: Tok.onPrimary, shadow: Tok.sage.opacity(0.22)) }
    static var secondary: Self { Self(fill: Tok.surfaceAlt, hover: Tok.bg, ink: Tok.ink, line: Tok.border) }

    /// Frosted glass over video: black/30 on a blur, a white/20 hairline.
    static func glass(padding: CGFloat = 20, compact: Bool = false) -> Self {
        Self(fill: .black.opacity(0.3), hover: .white.opacity(0.2), ink: .white, line: .white.opacity(0.2),
             shadow: .black.opacity(0.1), frosted: true, padding: compact ? 14 : padding, size: compact ? 13 : 14,
             height: compact ? 32 : 44)
    }

    func makeBody(configuration: Configuration) -> some View { Styled(style: self, configuration: configuration) }

    private struct Styled: View {
        let style: CaptureButtonStyle
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Typo.ui(style.size, .medium))
                .foregroundStyle(style.ink)
                .padding(.horizontal, style.diameter == nil ? style.padding : 0)
                .frame(width: style.diameter, height: style.diameter ?? style.height)
                .background(hovering && enabled ? style.hover : style.fill, in: .capsule)
                .background { if style.frosted { Capsule().fill(.frosted(solid: Night.surface)) } }
                .overlay(Capsule().strokeBorder(style.line))
                .shadow(color: style.shadow, radius: 10, y: 4)
                .contentShape(.capsule)
                .opacity(enabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(CaptureMotion.press, value: configuration.isPressed)
                .animation(CaptureMotion.out(0.16), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

extension View {
    /// The web build's `breathe` keyframe: opacity 1 → 0.5 and scale 1 → 0.8 and back, every 2.4 s.
    @ViewBuilder func breathing(_ active: Bool) -> some View {
        if active {
            phaseAnimator([false, true]) { view, inhale in
                view.opacity(inhale ? 0.5 : 1).scaleEffect(inhale ? 0.8 : 1)
            } animation: { _ in .easeInOut(duration: 1.2) }
        } else {
            self
        }
    }

    /// Glass over video for pills that aren't buttons.
    fileprivate func frosted() -> some View {
        background(.black.opacity(0.3), in: .capsule)
            .background(.frosted(solid: Night.surface), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 5)
    }

    /// White text that stays readable on any frame of video.
    fileprivate func legible() -> some View {
        shadow(color: .black.opacity(0.55), radius: 1, y: 1).shadow(color: .black.opacity(0.35), radius: 14)
    }
}

// MARK: - Parts

/// SaroVoice (VideoReflectionScreen.tsx): the first reflection's question at the top of the moment frame, dimmed by the 3-2-1.
struct MomentPrompt: View {
    let prompt: String
    let dimmed: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text("Today’s prompt").monoCaps(11, tracking: 0.12).foregroundStyle(.white.opacity(0.75))
            Text(prompt).font(Typo.serif(28)).tracking(-0.28).lineSpacing(6).foregroundStyle(.white)
        }
        .multilineTextAlignment(.center)
        .legible()
        .frame(maxWidth: 576)
        .padding(.horizontal, 24)
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(dimmed ? 0.55 : 1)
        .animation(CaptureMotion.out(0.2), value: dimmed)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

/// Elapsed time across turns; re-renders at 20 Hz on its own.
struct ElapsedText: View {
    var body: some View {
        let elapsed = CaptureController.shared.elapsed
        Text(elapsed.formatted(.time(pattern: elapsed >= .seconds(3600) ? .hourMinuteSecond : .minuteSecond(padMinuteToLength: 2))))
            .monospacedDigit()
    }
}

private enum RecordLook: Equatable {
    case idle, armed, recording, paused

    var caption: String {
        switch self {
        case .idle: "Record"
        case .armed: "Skip"
        case .recording: "Pause"
        case .paused: "Resume"
        }
    }

    var label: String {
        switch self {
        case .idle: "Start recording"
        case .armed: "Skip the countdown"
        case .recording: "Pause recording"
        case .paused: "Resume recording"
        }
    }
}

/// 64 pt: a white/80 ring around a 48 pt circle that shrinks to an apricot square while recording
/// (a smaller circle while paused), with a breathing halo.
private struct RecordDisc: View {
    let look: RecordLook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let hot = look == .recording || look == .armed
        let radius: CGFloat = hot ? 12 : 24
        ZStack {
            if look == .recording {
                Circle().strokeBorder(Tok.voiceBright.opacity(0.6), lineWidth: 2)
                    .frame(width: 76, height: 76)
                    .breathing(!reduceMotion)
                    .transition(.opacity)
            }
            Circle().strokeBorder(.white.opacity(look == .recording ? 0.6 : 0.8), lineWidth: 4)
            RoundedRectangle(cornerRadius: radius)
                .fill(look == .idle ? .clear : Tok.voiceBright.opacity(look == .paused ? 0.9 : 1))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(look == .idle ? 0.5 : 0), lineWidth: 2))
                .frame(width: 48, height: 48)
                .scaleEffect(hot ? 0.5 : look == .paused ? 0.83 : 1)
        }
        .frame(width: 64, height: 64)
        .animation(reduceMotion ? Motion.fade : CaptureMotion.out(0.15), value: look)
    }
}

/// The soft 3-2-1 before a moment's first turn: a thin 144 pt ring drains once a second around the number.
private struct Countdown: View {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ring = 1.0

    var body: some View {
        ZStack {
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 1.8)
                Circle().trim(from: 0, to: reduceMotion ? Double(count) / 3 : ring)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(4.3)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            Text("\(count)")
                .font(Typo.ui(56, .light))
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
                .id(count)
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(NumberSwap()))
        }
        .frame(width: 144, height: 144)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if !reduceMotion { withAnimation(.linear(duration: 3)) { ring = 0 } } }
    }
}

/// Numbers enter from blur 6 and scale 0.92, and leave to blur 6 and scale 1.08.
private struct NumberSwap: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : 6)
            .scaleEffect(phase == .willAppear ? 0.92 : phase == .didDisappear ? 1.08 : 1)
    }
}

/// "TUE 27 OCT · 8:10 PM" in Geist Mono on glass.
private struct DatePill: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            let d = context.date
            let day = "\(d.formatted(.dateTime.weekday(.abbreviated))) \(d.formatted(.dateTime.day())) \(d.formatted(.dateTime.month(.abbreviated)))"
            Text("\(day) · \(d.formatted(.dateTime.hour().minute()))".uppercased())
        }
        .font(Typo.mono(11.5, .regular))
        .tracking(0.58)
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 14)
        .frame(height: 28)
        .frosted()
    }
}

/// The loading, permission and busy states on the brand ground, filling the frame.
private struct StateCard: View {
    let notice: RecorderNotice
    let compact: Bool
    let close: () -> Void
    let voiceInstead: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Tok.bg
            VStack(spacing: 0) {
                Group {
                    if let icon = notice.icon {
                        Image(systemName: icon)
                            .font(.system(size: compact ? 20 : 26, weight: .medium))
                            .foregroundStyle(notice.alarm ? Tok.danger : Tok.ink3)
                            .frame(width: compact ? 48 : 64, height: compact ? 48 : 64)
                            .background(notice.alarm ? Tok.dangerBg : Tok.surfaceAlt, in: .circle)
                            .overlay(Circle().strokeBorder(notice.alarm ? Tok.dangerBorder : Tok.border))
                    } else {
                        Spinner()
                    }
                }
                .padding(.bottom, compact ? 16 : 24)
                Text(notice.title)
                    .font(Typo.ui(compact ? 15 : 20, .medium))
                    .tracking(compact ? 0 : -0.2)
                    .foregroundStyle(Tok.ink)
                if let detail = notice.detail {
                    Text(detail)
                        .font(Typo.ui(compact ? 13 : 14))
                        .lineSpacing(compact ? 2 : 4)
                        .foregroundStyle(Tok.ink2)
                        .padding(.top, 8)
                }
                if let quote = notice.quote {
                    Text("“\(quote)”").font(Typo.serif(18, italic: true)).lineSpacing(5).foregroundStyle(Tok.ink2).padding(.top, 32)
                }
                if notice.settings != nil || voiceInstead != nil {
                    VStack(spacing: 12) {
                        if let url = notice.settings {
                            Button { NSWorkspace.shared.open(url) } label: { Text("Open System Settings").frame(maxWidth: .infinity) }
                                .buttonStyle(CaptureButtonStyle.primary)
                                .keyboardShortcut(.defaultAction)
                        }
                        if let voiceInstead {
                            Button(action: voiceInstead) { Text("Record a voice note instead").frame(maxWidth: .infinity) }
                                .buttonStyle(CaptureButtonStyle.secondary)
                        }
                    }
                    .padding(.top, compact ? 16 : 24)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 448)
            .padding(compact ? 20 : 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: close) { Image(systemName: "xmark").font(.system(size: compact ? 12 : 15, weight: .semibold)) }
                .buttonStyle(CaptureButtonStyle(fill: Tok.surfaceAlt, hover: Tok.surface, ink: Tok.ink2, line: Tok.border,
                                                diameter: compact ? 32 : 44))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .padding(compact ? 12 : 24)
        }
    }
}

/// A 40 pt sage ring with one bright quarter, turning.
private struct Spinner: View {
    @State private var turning = false

    var body: some View {
        Circle().trim(from: 0, to: 0.25)
            .stroke(Tok.sage, lineWidth: 3)
            .background(Circle().stroke(Tok.sage.opacity(0.25), lineWidth: 3))
            .frame(width: 37, height: 37)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
            .accessibilityLabel("Loading")
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
