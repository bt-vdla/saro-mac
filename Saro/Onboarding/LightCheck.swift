import AVFoundation
import Observation
import SaroKit
import Synchronization
import Vision

/// The camera and mic check behind Find your light (useLightCheck.ts), on its own preview-only session: frames are read
/// into a 64×36 thumbnail and dropped, and there is no movie output, so nothing is recorded. Vision reads the framing on
/// this Mac. The recorder's CaptureController is never touched; the check lets the camera go before it opens.
@Observable @MainActor
final class LightCheck {
    enum Phase: Equatable { case idle, requesting, settling, live, voice, none, denied, busy, ended }

    private(set) var phase: Phase = .idle
    private(set) var verdict: LightRead.Verdict?
    private(set) var side: LightRead.Side?
    private(set) var framing: LightRead.Framing?
    private(set) var mic: LightRead.Mic = .waiting
    /// 0…1, smoothed: a fast attack and a slow release.
    private(set) var level = 0.0
    /// Where the light comes from, in degrees for the mirrored view; it turns the short way round.
    private(set) var angle = 0.0
    private(set) var strength = 0.0
    private(set) var cameras: [CaptureController.Device] = []
    private(set) var cameraID: String?
    private(set) var hasMic = true
    /// The camera's own shape, so the mirror shows the frame the recording will see.
    private(set) var aspect: CGFloat = 16 / 9
    private(set) var hasFrames = false

    let engine = LightEngine()
    @ObservationIgnored private var token = 0
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// Removed in deinit, so each replay's check doesn't leave its observers behind.
    @ObservationIgnored nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    var cameraName: String { cameras.first { $0.id == cameraID }?.name ?? "Camera" }
    var camera: Bool { phase == .live || phase == .settling }

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: engine.session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.ended() }
        })
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let id = (note.object as? AVCaptureDevice)?.uniqueID
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let lost = name == AVCaptureDevice.wasDisconnectedNotification && id == self.cameraID && self.camera
                    self.refreshDevices()
                    if lost { self.ended() }
                }
            })
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// Turn on camera and mic, or Try again: asks macOS on first use, then settles the exposure for 1.2 s.
    func start() {
        token += 1
        let t = token
        Task { await run(t) }
    }

    private func run(_ t: Int) async {
        ticker?.cancel()
        await engine.stop()
        guard t == token else { return }
        verdict = nil
        side = nil
        framing = nil
        mic = .waiting
        hasFrames = false
        phase = .requesting
        let video = await Self.access(.video)
        let audio = await Self.access(.audio)
        guard t == token else { return }
        refreshDevices()
        let micID = UserDefaults.standard.string(forKey: "captureMicID").flatMap { AVCaptureDevice(uniqueID: $0)?.uniqueID }
            ?? AVCaptureDevice.default(for: .audio)?.uniqueID
        hasMic = micID != nil
        guard audio else {
            phase = .denied
            return
        }
        // Camera blocked or missing, the mic allowed: carry on by voice, with no second ask.
        guard video, let id = cameraID, let device = AVCaptureDevice(uniqueID: id) else {
            guard hasMic else {
                phase = .none
                return
            }
            let failed = await engine.configure(camera: nil, mic: micID, width: 0, height: 0) != nil
            guard t == token else { return await engine.stop() }
            phase = failed ? .busy : .voice
            if !failed { tick(t, sampling: false) }
            return
        }
        if device.isInUseByAnotherApplication {
            phase = .busy
            return
        }
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        if dims.width > 0, dims.height > 0 { aspect = CGFloat(dims.width) / CGFloat(dims.height) }
        let failed = await engine.configure(camera: id, mic: micID, width: 320, height: Int((320 / aspect).rounded())) != nil
        guard t == token, !failed else {
            await engine.stop()
            if t == token { phase = .busy }
            return
        }
        phase = .settling
        // Cameras take about a second to settle their exposure; judging before that would always say "dark".
        try? await Task.sleep(for: .milliseconds(LightRead.Light.settleMs))
        guard t == token else { return }
        phase = .live
        tick(t, sampling: true)
    }

    /// The level every 55 ms; light, direction and framing on every third tick (166 ms), framing on every third read.
    private func tick(_ t: Int, sampling: Bool) {
        ticker?.cancel()
        ticker = Task {
            let started = ContinuousClock.now
            func ms() -> Double {
                let d = started.duration(to: .now)
                return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
            }
            var lightHold = LightRead.Hold<LightRead.Verdict>()
            var sideHold = LightRead.Hold<String>()
            var framingHold = LightRead.Hold<LightRead.Framing>(hold: 2, minMs: 0)
            var lastHeard: Double?
            var n = 0
            while !Task.isCancelled, t == token {
                let raw = min(1, max(0, (Double(engine.powerLevel) + 50) / 50))
                level += (raw - level) * (raw > level ? 0.5 : 0.08)
                let now = ms()
                if raw > 0.12, hasMic { lastHeard = now / 1000 }
                let m = LightRead.mic(now: now / 1000, started: 0, lastHeard: lastHeard)
                if m != mic { mic = m }
                if sampling, n % 3 == 0, let read = await engine.read(face: n % 9 == 0), t == token {
                    hasFrames = true
                    if let v = lightHold(LightRead.readLight(read.rgba), now: now), v != verdict { verdict = v }
                    let dir = LightRead.lightDirection(read.rgba)
                    if dir.strength > 0.04 { angle += ((dir.angle - angle).truncatingRemainder(dividingBy: 360) + 540).truncatingRemainder(dividingBy: 360) - 180 }
                    strength = dir.strength
                    let held = sideHold(dir.strength > LightRead.sideStrength ? dir.side.rawValue : "even", now: now)
                    let s = held.flatMap(LightRead.Side.init)
                    if s != side { side = s }
                    if let face = read.face, let f = framingHold(LightRead.readFraming(face), now: now), f != framing { framing = f }
                }
                n += 1
                try? await Task.sleep(for: .milliseconds(55))
            }
        }
    }

    /// Turn off, or Esc: everything off, the camera light with it.
    func stop() {
        token += 1
        ticker?.cancel()
        level = 0
        phase = .idle
        verdict = nil
        side = nil
        framing = nil
        Task { await engine.stop() }
    }

    /// Lets the camera and mic go, keeping the phase, so the recorder can take them.
    func release() async {
        token += 1
        ticker?.cancel()
        level = 0
        await engine.stop()
    }

    private func ended() {
        guard camera || phase == .voice else { return }
        token += 1
        ticker?.cancel()
        level = 0
        phase = .ended
        Task { await engine.stop() }
    }

    func select(camera id: String) {
        UserDefaults.standard.set(id, forKey: "captureCameraID")
        cameraID = id
        if camera { start() }
    }

    private func refreshDevices() {
        cameras = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
                                                   mediaType: .video, position: .unspecified).devices.map(CaptureController.Device.init)
        let ids = [UserDefaults.standard.string(forKey: "captureCameraID"), cameraID, AVCaptureDevice.systemPreferredCamera?.uniqueID]
        cameraID = ids.compactMap { $0 }.first { id in cameras.contains { $0.id == id } } ?? cameras.first?.id
    }

    private static func access(_ media: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: media)
        default: false
        }
    }
}

/// The AVFoundation side; everything runs on its queues. There is no movie output: frames and audio are read and dropped.
final class LightEngine: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "saro.lightcheck.session")
    private let frames = DispatchQueue(label: "saro.lightcheck.frames")
    private let video = AVCaptureVideoDataOutput()
    private let audio = AVCaptureAudioDataOutput()
    private let power = Mutex<Float>(-160)
    /// Only touched on `frames`.
    private var latest: CVPixelBuffer?

    var powerLevel: Float { power.withLock { $0 } }

    /// The inputs and outputs, then the session running. A message on failure.
    func configure(camera: String?, mic: String?, width: Int, height: Int) async -> String? {
        await withCheckedContinuation { done in queue.async { done.resume(returning: self.apply(camera: camera, mic: mic, width: width, height: height)) } }
    }

    private func apply(camera: String?, mic: String?, width: Int, height: Int) -> String? {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        for id in [camera, mic].compactMap({ $0 }) {
            guard let device = AVCaptureDevice(uniqueID: id) else { return "That camera or microphone was disconnected." }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else { return "\(device.localizedName) is in use by another app." }
                session.addInput(input)
            } catch {
                return error.localizedDescription
            }
        }
        if camera != nil {
            video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                   kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height]
            video.alwaysDiscardsLateVideoFrames = true
            video.setSampleBufferDelegate(self, queue: frames)
            if session.canAddOutput(video) { session.addOutput(video) }
            if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        }
        if mic != nil {
            audio.setSampleBufferDelegate(self, queue: DispatchQueue(label: "saro.lightcheck.meter"))
            if session.canAddOutput(audio) { session.addOutput(audio) }
        }
        queue.async { if !self.session.isRunning { self.session.startRunning() } }
        return nil
    }

    func stop() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                self.session.stopRunning()
                self.session.beginConfiguration()
                for input in self.session.inputs { self.session.removeInput(input) }
                self.session.commitConfiguration()
                self.frames.sync { self.latest = nil }
                self.power.withLock { $0 = -160 }
                done.resume()
            }
        }
    }

    /// The latest frame as a 64×36 RGBA thumbnail, and (when asked) the face box Vision finds in it, origin top left.
    func read(face: Bool) async -> (rgba: [UInt8], face: CGRect?)? {
        await withCheckedContinuation { done in
            frames.async {
                guard let buffer = self.latest else { return done.resume(returning: nil) }
                let rgba = Self.thumbnail(buffer)
                var box: CGRect?
                if face {
                    let request = VNDetectFaceRectanglesRequest()
                    try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
                    box = request.results?.first.map { CGRect(x: $0.boundingBox.minX, y: 1 - $0.boundingBox.maxY, width: $0.boundingBox.width, height: $0.boundingBox.height) }
                }
                done.resume(returning: (rgba, face ? box : nil))
            }
        }
    }

    /// Box-averages a BGRA frame down to 64×36 RGBA.
    private static func thumbnail(_ buffer: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
        let sw = LightRead.width, sh = LightRead.height
        var out = [UInt8](repeating: 255, count: sw * sh * 4)
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self), w >= sw, h >= sh else { return out }
        for y in 0..<sh {
            for x in 0..<sw {
                var r = 0, g = 0, b = 0, n = 0
                for py in stride(from: y * h / sh, to: (y + 1) * h / sh, by: 2) {
                    for px in stride(from: x * w / sw, to: (x + 1) * w / sw, by: 2) {
                        let p = base + py * row + px * 4
                        b += Int(p[0]); g += Int(p[1]); r += Int(p[2]); n += 1
                    }
                }
                let i = (y * sw + x) * 4
                if n > 0 { (out[i], out[i + 1], out[i + 2]) = (UInt8(r / n), UInt8(g / n), UInt8(b / n)) }
            }
        }
        return out
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureVideoDataOutput {
            latest = CMSampleBufferGetImageBuffer(sampleBuffer)
        } else {
            let db = connection.audioChannels.map(\.averagePowerLevel).max() ?? -160
            power.withLock { $0 = db }
        }
    }
}
