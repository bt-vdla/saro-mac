import AVFoundation
import Observation
import SaroKit
import Synchronization

/// The one owner of the camera and microphone. The in-window recorder and the floating panel share `shared`.
/// A recording is a session of turns: each turn is its own fragmented file whose rows exist before its first frame.
@Observable @MainActor
final class CaptureController {
    static let shared = CaptureController()

    enum State: Equatable {
        case idle, preparing, previewing, recording, paused, finishing
        case needsAccess(Access)
        case failed(String)
    }

    enum Access {
        case camera, microphone

        var settingsURL: URL {
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(self == .camera ? "Camera" : "Microphone")")!
        }
    }

    enum Surface { case window, panel }

    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
        let isPhone: Bool
    }

    private(set) var state: State = .idle
    private(set) var kind: EntryKind = .moment
    private(set) var owner: Surface?
    private(set) var cameras: [Device] = []
    private(set) var mics: [Device] = []
    private(set) var cameraID: String?
    private(set) var micID: String?
    /// 0…1, refreshed at 20 Hz while the session runs (previewing included, so the mic can be checked first).
    private(set) var level = 0.0
    /// Across every turn of the session.
    private(set) var elapsed: Duration = .zero
    private(set) var turn = 0
    private(set) var starting = false
    private(set) var closing = false

    let engine = CaptureEngine()
    @ObservationIgnored private var model: AppModel?
    @ObservationIgnored private var sessionId = ""
    @ObservationIgnored private var day: String?
    @ObservationIgnored private var current: TurnTicket?
    @ObservationIgnored private var pending: [URL: TurnTicket] = [:]
    @ObservationIgnored private var banked: Duration = .zero
    @ObservationIgnored private var savedTurns = 0
    @ObservationIgnored private var turnStarted: ContinuousClock.Instant?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var ended: [CheckedContinuation<Void, Never>] = []

    private init() {
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { CaptureController.shared.devicesChanged() }
            }
        }
    }

    /// False while the other surface holds the recorder, or this one is still saving its last session.
    func isAvailable(to surface: Surface) -> Bool { owner == nil || (owner == surface && !closing) }

    func hasSession(_ surface: Surface) -> Bool { owner == surface && turn > 0 }

    var canToggle: Bool { !starting && [.previewing, .recording, .paused].contains(state) }

    // MARK: Lifecycle

    /// Asks for access on first use (never at launch), picks devices and starts the preview.
    func prepare(_ kind: EntryKind, for surface: Surface, model: AppModel) async {
        guard isAvailable(to: surface), turn == 0 else { return }
        owner = surface
        self.model = model
        self.kind = kind
        state = .preparing
        let camera = kind == .voice ? true : await Self.access(.video)
        let mic = await Self.access(.audio)
        guard owner == surface, !closing, self.kind == kind else { return }
        if !camera { state = .needsAccess(.camera); return }
        if !mic { state = .needsAccess(.microphone); return }
        refreshDevices()
        await configure()
    }

    /// Done, or the surface went away: stops the current turn, lets every turn save, then turns the camera off.
    func finish(_ surface: Surface) {
        guard owner == surface else { return }
        closing = true
        if current != nil {
            bank()
            engine.stopRecording()
        }
        state = .finishing
        teardownIfDone()
    }

    /// `finish`, then waits for every turn to save. True when at least one turn's file was written.
    func end(_ surface: Surface) async -> Bool {
        finish(surface)
        if owner == surface { await withCheckedContinuation { ended.append($0) } }
        return savedTurns > 0
    }

    // MARK: Recording

    /// Space: record, pause, resume.
    func toggle() {
        guard canToggle else { return }
        switch state {
        case .previewing: begin(first: true)
        case .recording: pause()
        case .paused: begin(first: false)
        default: break
        }
    }

    private func begin(first: Bool) {
        guard let model else { return }
        if first {
            sessionId = UUID().uuidString
            day = owner == .panel ? LocalDay.today() : model.day
            banked = .zero
            savedTurns = 0
        }
        turn += 1
        starting = true
        state = .recording
        let n = turn
        Task {
            do {
                let ticket = try await model.beginTurn(kind: kind, sessionId: sessionId, turn: n, day: day)
                starting = false
                if closing {
                    // ponytail: a Done inside the few-ms row insert leaves this turn's rows marked failed.
                    await model.finishTurn(ticket, durationMs: 0, error: nil)
                    teardownIfDone()
                    return
                }
                current = ticket
                pending[ticket.url] = ticket
                turnStarted = .now
                engine.startRecording(to: ticket.url)
            } catch {
                starting = false
                turn -= 1
                state = turn == 0 ? .previewing : .paused
                model.show(Toast("Couldn't start recording: \(error.localizedDescription)", style: .error))
                teardownIfDone()
            }
        }
    }

    private func pause() {
        guard current != nil else { return }
        bank()
        engine.stopRecording()
        state = .paused
    }

    private func bank() {
        if let turnStarted { banked += turnStarted.duration(to: .now) }
        turnStarted = nil
        current = nil
    }

    /// Called by the engine when a turn's file is complete (stopped by us, or by AVFoundation on device loss or a full disk).
    func turnFinished(_ url: URL, error: (any Error)?) async {
        guard let ticket = pending[url] else { return }
        if current?.url == url {
            bank()
            if state == .recording { state = .paused }
            model?.show(Toast("Recording paused: \(error?.localizedDescription ?? "the camera or microphone stopped")", style: .error))
            Task { await configure() }
        }
        let duration = try? await AVURLAsset(url: url).load(.duration)
        let ms = duration.flatMap { $0.isNumeric ? Int($0.seconds * 1000) : nil } ?? 0
        await model?.finishTurn(ticket, durationMs: ms, error: error)
        // The test finishTurn uses to mark the turn ready rather than failed.
        if FileManager.default.fileExists(atPath: url.path) { savedTurns += 1 }
        pending[url] = nil
        teardownIfDone()
    }

    private func teardownIfDone() {
        guard closing, !starting, current == nil, pending.isEmpty else { return }
        ticker?.cancel()
        ticker = nil
        engine.stop()
        state = .idle
        owner = nil
        closing = false
        turn = 0
        level = 0
        elapsed = .zero
        banked = .zero
        for done in ended { done.resume() }
        ended = []
    }

    // MARK: Devices

    func select(camera id: String) {
        UserDefaults.standard.set(id, forKey: "captureCameraID")
        cameraID = id
        if state == .previewing || state == .paused { Task { await configure() } }
    }

    func select(mic id: String) {
        UserDefaults.standard.set(id, forKey: "captureMicID")
        micID = id
        if state == .previewing || state == .paused { Task { await configure() } }
    }

    private func refreshDevices() {
        cameras = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
                                                   mediaType: .video, position: .unspecified).devices.map(Device.init)
        mics = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                                mediaType: .audio, position: .unspecified).devices.map(Device.init)
        let saved = UserDefaults.standard
        cameraID = Self.pick([saved.string(forKey: "captureCameraID"), cameraID, AVCaptureDevice.systemPreferredCamera?.uniqueID], in: cameras)
        micID = Self.pick([saved.string(forKey: "captureMicID"), micID, AVCaptureDevice.default(for: .audio)?.uniqueID], in: mics)
    }

    private static func pick(_ ids: [String?], in devices: [Device]) -> String? {
        ids.compactMap { $0 }.first { id in devices.contains { $0.id == id } } ?? devices.first?.id
    }

    private func devicesChanged() {
        let before = (cameraID, micID)
        refreshDevices()
        guard owner != nil, !starting, current == nil else { return }
        switch state {
        case .previewing, .paused: if before != (cameraID, micID) { Task { await configure() } }
        case .failed: Task { await configure() }
        default: break
        }
    }

    private func configure() async {
        if kind == .moment, cameraID == nil { state = .failed("No camera is connected."); return }
        guard micID != nil else { state = .failed("No microphone is connected."); return }
        let hd = UserDefaults.standard.string(forKey: "videoQuality") == "1080p"
        let error = await engine.configure(camera: kind == .moment ? cameraID : nil, mic: micID,
                                           preset: hd ? .hd1920x1080 : .hd1280x720)
        guard owner != nil, !closing else { return }
        if let error { state = .failed(error); return }
        // A device back mid-session resumes the same session (and day), never a new one.
        if state != .paused { state = turn > 0 ? .paused : .previewing }
        startTicker()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task {
            while !Task.isCancelled {
                let db = Double(engine.powerLevel)
                let l = max(min(max((db + 50) / 50, 0), 1), level * 0.8)
                if l != level { level = l }
                let e = banked + (turnStarted?.duration(to: .now) ?? .zero)
                if e != elapsed { elapsed = e }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private static func access(_ media: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: media)
        default: false
        }
    }
}

extension CaptureController.Device {
    init(_ device: AVCaptureDevice) {
        self.init(id: device.uniqueID, name: device.localizedName, isPhone: device.isContinuityCamera)
    }
}

/// The AVFoundation side. Everything here runs on `queue`, except the immutable `session` reference the preview layer reads.
final class CaptureEngine: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "saro.capture.session")
    private let movie = AVCaptureMovieFileOutput()
    private let audio = AVCaptureAudioDataOutput()
    private let power = Mutex<Float>(-160)

    /// Loudest channel's average power in dB, as of the last audio buffer.
    var powerLevel: Float { power.withLock { $0 } }

    /// Swaps inputs inside one configuration and starts the session. Returns a message on failure.
    func configure(camera: String?, mic: String?, preset: AVCaptureSession.Preset) async -> String? {
        await withCheckedContinuation { done in
            queue.async { done.resume(returning: self.apply(camera: camera, mic: mic, preset: preset)) }
        }
    }

    func startRecording(to url: URL) { queue.async { self.movie.startRecording(to: url, recordingDelegate: self) } }
    func stopRecording() { queue.async { self.movie.stopRecording() } }
    func stop() { queue.async { self.session.stopRunning() } }

    private func apply(camera: String?, mic: String?, preset: AVCaptureSession.Preset) -> String? {
        session.beginConfiguration()
        for input in session.inputs { session.removeInput(input) }
        for id in [camera, mic].compactMap({ $0 }) {
            guard let device = AVCaptureDevice(uniqueID: id) else {
                session.commitConfiguration()
                return "That camera or microphone was disconnected."
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else { throw CaptureError("\(device.localizedName) is in use by another app.") }
                session.addInput(input)
            } catch {
                session.commitConfiguration()
                return error.localizedDescription
            }
        }
        if session.outputs.isEmpty {
            movie.movieFragmentInterval = CMTime(value: 2, timescale: 1)
            audio.setSampleBufferDelegate(self, queue: DispatchQueue(label: "saro.capture.meter"))
            for output in [movie, audio] as [AVCaptureOutput] where session.canAddOutput(output) { session.addOutput(output) }
        }
        session.sessionPreset = session.canSetSessionPreset(preset) ? preset : .high
        if let video = movie.connection(with: .video) {
            // ponytail: encoder-default HEVC bitrate; add AVVideoCompressionPropertiesKey (~2.5 Mbps at 1080p) once checked on device.
            movie.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: video)
        }
        session.commitConfiguration()
        if !session.isRunning { session.startRunning() }
        return nil
    }
}

extension CaptureEngine: AVCaptureFileOutputRecordingDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: (any Error)?) {
        Task { @MainActor in await CaptureController.shared.turnFinished(url, error: error) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let db = connection.audioChannels.map(\.averagePowerLevel).max() ?? -160
        power.withLock { $0 = db }
    }
}

struct CaptureError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
