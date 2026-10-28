import AVFoundation
import SaroKit
import SwiftUI

/// "Find your light" (FindLightScreen.tsx): the camera and mic check as a mirror, with live readings of the light,
/// its direction, the framing and the mic. Nothing is recorded; the camera stays off until asked.
struct FindLightView: View {
    @Environment(AppModel.self) private var model
    @Environment(OnboardingFlow.self) private var flow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @AccessibilityFocusState private var headingFocused: Bool
    @FocusState private var primaryFocused: Bool

    private var light: LightCheck { flow.light }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    StepMark().padding(.bottom, 40).rise(shown, delay: 0, reduce: reduceMotion)
                    HStack(alignment: .center, spacing: 64) {
                        MirrorView(light: light)
                            .frame(maxWidth: 560)
                            .rise(shown, delay: 0.1, reduce: reduceMotion)
                        panel.frame(width: 340)
                    }
                    .frame(maxWidth: 964)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
        }
        .background {
            // Esc turns everything off.
            Button("Turn everything off") { turnOff() }.keyboardShortcut(.cancelAction).disabled(light.phase == .idle)
                .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
        .onAppear {
            shown = true
            headingFocused = true
            flow.prepareSpeech()
        }
        .onDisappear {
            if !flow.leaving { light.stop() }
        }
        .announces(tip.map { "\($0.title) \($0.body)" } ?? "")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Camera and microphone").monoCaps(10.5).foregroundStyle(Tok.ink2).padding(.bottom, 12)
                .rise(shown, delay: 0.05, reduce: reduceMotion)
            Text("Let’s find your \(Text("light.").font(Typo.serif(44, italic: true)).foregroundStyle(Tok.sage))")
                .font(Typo.serif(44)).foregroundStyle(Tok.ink).tracking(-1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
                .padding(.bottom, 18)
                .rise(shown, delay: 0.05, reduce: reduceMotion)
            VStack(alignment: .leading, spacing: 0) {
                tipView.frame(minHeight: 72, alignment: .topLeading).padding(.bottom, 12)
                rows.padding(.bottom, 14)
                primary
                links
                Text("NOTHING IS RECORDED DURING THIS CHECK").font(Typo.mono(10.5)).tracking(1.1).foregroundStyle(Tok.ink2).padding(.top, 10)
                ReadinessCard(speech: flow.speech).padding(.top, 18)
            }
            .rise(shown, delay: 0.15, reduce: reduceMotion)
        }
    }

    // MARK: Tip

    private var tip: (title: String, body: String)? {
        switch light.phase {
        case .settling: ("Checking your light…", "")
        case .live: light.verdict.map(LightRead.tip) ?? ("Checking your light…", "")
        case .voice: ("Your camera is off, and that’s fine.", "You can reflect with just your voice.")
        default: nil
        }
    }

    private var tipView: some View {
        ZStack(alignment: .topLeading) {
            if let tip {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tip.title).font(Typo.serif(20)).foregroundStyle(Tok.ink)
                    if !tip.body.isEmpty { Text(tip.body).font(Typo.ui(14)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true) }
                }
                .id(tip.title)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: reduceMotion ? 0 : 4)).animation(Motion.small),
                                        removal: .opacity.animation(.easeOut(duration: 0.16))))
            }
        }
        .animation(Motion.small, value: tip?.title)
    }

    // MARK: Status rows

    private enum Dot { case good, warn, off }

    private var rows: some View {
        let phase = light.phase
        let camera = light.camera
        let heard = camera || phase == .voice
        let error = [.denied, .busy, .ended].contains(phase)
        let notYet = "Not checked yet."
        let cameraText: String = switch phase {
        case .live, .settling: light.cameraName
        case .requesting: "Asking macOS…"
        case .none: "None found"
        case .denied: "Blocked"
        case .busy: "In use by another app"
        case .ended: "Stopped"
        default: "Off"
        }
        let lightText = phase == .live && light.verdict != nil
            ? LightRead.row(light.verdict!) + (light.side.map { " " + LightRead.row($0) } ?? "")
            : camera ? "Checking…" : notYet
        let framingText = phase != .live ? (camera ? "Checking…" : notYet) : light.framing.map(LightRead.row) ?? "Looking for you…"
        let micText = heard ? (light.hasMic ? LightRead.row(light.mic) : "None found") : phase == .none ? "None found" : phase == .denied ? "Blocked" : notYet
        return VStack(spacing: 0) {
            row("Camera", camera ? .good : error ? .warn : .off, cameraText, action: camera ? "Turn camera and microphone off" : nil)
            row("Light", phase == .live ? (light.verdict == .good ? .good : light.verdict == nil ? .off : .warn) : .off, lightText)
            row("Framing", phase == .live && light.framing != nil ? (light.framing == .good ? .good : .warn) : .off, framingText)
            row("Microphone", heard ? (light.mic == .heard ? .good : light.mic == .silent ? .warn : .off) : phase == .denied ? .warn : .off, micText,
                action: phase == .voice ? "Turn microphone off" : nil)
            if camera, light.cameras.count > 1 { cameraPicker }
        }
    }

    private func row(_ term: String, _ dot: Dot, _ text: String, action: String? = nil) -> some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(dot == .good ? Tok.sage : dot == .warn ? Tok.warning : Tok.ink4).frame(width: 6, height: 6)
                    .animation(Motion.easeOut(0.24), value: dot)
                Text(term).monoCaps(10.5).foregroundStyle(Tok.ink2)
            }
            .frame(width: 112, alignment: .leading)
            Text(text).font(Typo.ui(13)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(Motion.fade, value: text)
            Spacer(minLength: 8)
            if let action {
                Button("Turn off") { turnOff() }.buttonStyle(LinkStyle(size: 12)).accessibilityLabel(action)
            }
        }
        .frame(minHeight: 40)
        .overlay(alignment: .top) { Rectangle().fill(Tok.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private var cameraPicker: some View {
        Menu {
            ForEach(light.cameras) { cam in
                Button { light.select(camera: cam.id) } label: {
                    if cam.id == light.cameraID { Label(cam.name, systemImage: "checkmark") } else { Text(cam.name) }
                }
            }
        } label: {
            Label("Use another camera", systemImage: light.cameras.first { $0.id == light.cameraID }?.isPhone == true ? "iphone" : "web.camera")
                .font(Typo.ui(12, .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Tok.line).frame(height: 1) }
    }

    // MARK: Actions

    private var cta: String {
        switch light.phase {
        case .idle, .ended: "Turn on camera and mic"
        case .requesting: "Waiting for macOS…"
        case .settling: "Let’s begin"
        case .live: light.verdict == .good ? "Looks good, let’s begin" : light.verdict != nil ? "Begin anyway" : "Let’s begin"
        case .voice: "Continue with voice"
        case .none: "Continue by writing"
        case .denied, .busy: "Try again"
        }
    }

    private var primary: some View {
        let hidden = light.phase == .settling
        return Button(action: go) {
            Text(cta).font(Typo.ui(14, .semibold)).frame(maxWidth: .infinity).frame(height: 46)
                .contentTransition(.opacity)
        }
        .buttonStyle(PrimaryStyle())
        .keyboardShortcut(light.phase == .live ? .defaultAction : nil)
        .focused($primaryFocused)
        .opacity(hidden ? 0 : 1)
        .offset(y: hidden && !reduceMotion ? 6 : 0)
        .allowsHitTesting(!hidden && light.phase != .requesting)
        .accessibilityHidden(hidden)
        .animation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.7), value: hidden)
        .animation(Motion.fade, value: cta)
    }

    @ViewBuilder private var links: some View {
        HStack(spacing: 24) {
            if light.phase != .voice, light.phase != .none {
                Button("Voice only") { leave(.voice) }.buttonStyle(LinkStyle(size: 12))
            }
            if light.phase != .none {
                Button("I’d rather write") { leave(.write) }.buttonStyle(LinkStyle(size: 12))
            }
            if light.phase == .denied {
                Button("Open System Settings") { NSWorkspace.shared.open(CaptureController.Access.camera.settingsURL) }.buttonStyle(LinkStyle(size: 12))
            }
        }
        .padding(.top, 4)
    }

    private func go() {
        switch light.phase {
        case .live: leave(.moment)
        case .voice: leave(.voice)
        case .none: leave(.write)
        case .requesting, .settling: break
        default: light.start()
        }
    }

    private func leave(_ mode: AppModel.FirstMode) {
        Task { await flow.finish(mode, model: model) }
    }

    /// Turn off goes away as it's pressed, so focus moves first, to the button that turns things back on.
    private func turnOff() {
        primaryFocused = true
        light.stop()
    }
}

/// The mirror: mirrored video in the camera's own shape, an oval guide whose rim grows with the mic, a quarter-arc of
/// light turned toward the brightest side, and two eye-line marks.
private struct MirrorView: View {
    let light: LightCheck
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var message: String? {
        switch light.phase {
        case .none: "No camera or mic. That’s okay. Writing works just as well."
        case .denied: "Camera and mic are blocked. Turn them on in System Settings → Privacy & Security → Camera and Microphone, then try again, or carry on by voice or by writing."
        case .busy: "Another app is using your camera. Close it, then try again."
        case .ended: "Your camera stopped. Turn it on again."
        default: nil
        }
    }

    var body: some View {
        let camera = light.camera
        ZStack {
            RoundedRectangle(cornerRadius: Radius.panel).fill(Tok.surface)
            MirrorPreview(session: light.engine.session)
                .opacity(camera && light.hasFrames ? 1 : 0)
                .animation(Motion.easeOut(0.4), value: camera && light.hasFrames)
                .accessibilityHidden(true)
            if camera || light.phase == .voice { overlay(camera: camera) }
            if light.phase == .idle {
                Text("Your camera stays off until you ask.").font(Typo.serif(18, italic: true)).foregroundStyle(Tok.ink2).multilineTextAlignment(.center).padding(24)
            }
            if let message {
                Text(message).font(Typo.ui(14)).foregroundStyle(Tok.ink2).multilineTextAlignment(.center).padding(28)
                    .accessibilityAddTraits([.isStaticText])
            }
        }
        .aspectRatio(light.aspect, contentMode: .fit)
        .clipShape(.rect(cornerRadius: Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Tok.line))
        .elevation(.card)
        .announces([.denied, .busy, .ended].contains(light.phase) ? message ?? "" : "")
    }

    private func overlay(camera: Bool) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let oval = CGRect(x: w * 0.31, y: h * 0.06, width: w * 0.38, height: h * 0.76)
            ZStack(alignment: .topLeading) {
                Ellipse().strokeBorder(camera ? Color.white.opacity(0.45) : Tok.ink.opacity(0.25), lineWidth: 1)
                    .frame(width: oval.width, height: oval.height).offset(x: oval.minX, y: oval.minY)
                Ellipse().strokeBorder(Tok.voiceBright, lineWidth: 2)
                    .opacity(0.15 + light.level * 0.85)
                    .scaleEffect(reduceMotion ? 1 : 1 + light.level * 0.035)
                    .frame(width: oval.width, height: oval.height).offset(x: oval.minX, y: oval.minY)
                if camera {
                    LightArc(angle: light.angle)
                        .stroke(Tok.voiceBright.opacity(0.25), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .overlay(LightArc(angle: light.angle).stroke(Tok.voiceBright, style: StrokeStyle(lineWidth: 3, lineCap: .round)))
                        .opacity(LightRead.arcOpacity(light.strength))
                        .frame(width: oval.width, height: oval.height).offset(x: oval.minX, y: oval.minY)
                        .animation(reduceMotion ? nil : Motion.surface, value: light.angle)
                        .animation(reduceMotion ? nil : Motion.surface, value: light.strength)
                    ForEach([0.26, 0.74 - 14 / w], id: \.self) { x in
                        Capsule().fill(Color.white.opacity(0.45)).frame(width: 14, height: 2).offset(x: w * x, y: h * 0.36)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A quarter of the oval centred on `angle` (0 = their right in the mirror, 90 = below).
private struct LightArc: Shape {
    var angle: Double
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: .zero, radius: 1, startAngle: .degrees(angle - 45), endAngle: .degrees(angle + 45), clockwise: false)
        return p.applying(CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: rect.width / 2, y: rect.height / 2))
    }
}

/// The camera's preview, mirrored like Photo Booth; the check never records it.
private struct MirrorPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = PreviewView()
        view.preview.session = session
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class PreviewView: NSView {
        let preview = AVCaptureVideoPreviewLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            preview.videoGravity = .resizeAspectFill
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
}

/// Whether Apple Intelligence and speech are ready on this Mac, each with its own honest line (FR-ONB-05). Saro
/// works either way.
struct ReadinessCard: View {
    let speech: Readiness.SpeechState?
    @State private var model = Readiness.model()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            line(symbol: "sparkles", ok: model.isReady, text: model.line)
            if let url = model.settingsURL {
                Button("Open Apple Intelligence & Siri Settings") { NSWorkspace.shared.open(url) }.buttonStyle(LinkStyle(size: 12)).padding(.leading, 22)
            }
            if let speech {
                line(symbol: "waveform", ok: speech == .installed, text: speech.line)
                if case .downloading(let f) = speech {
                    ProgressView(value: f ?? 0).progressViewStyle(.linear).tint(Tok.sage).padding(.leading, 22)
                        .opacity(f == nil ? 0 : 1)
                        .accessibilityLabel("Speech download")
                }
            }
        }
        .padding(14)
        .background(Tok.surface.opacity(0.7), in: .rect(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Tok.line))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model = Readiness.model() }
    }

    private func line(symbol: String, ok: Bool, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(ok ? Tok.sageTeal : Tok.ink3).frame(width: 14)
            Text(text).font(Typo.ui(12)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
