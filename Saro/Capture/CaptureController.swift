import AVFoundation
import Observation
import SaroKit
import Synchronization

/// The one owner of the camera and microphone. The in-window recorder and the floating panel share `shared`.
/// A recording is a session of parts: each part is its own fragmented file whose rows exist before its first frame. A
/// pause keeps the part (the file pauses); a moment's part ends only at Pause & reflect or Finish, a voice note's at Stop.
/// A part is the take until it is kept (Keep going, Finish, Keep this); only the take can be discarded.
@Observable @MainActor
final class CaptureController {
    static let shared = CaptureController()

    enum State: Equatable {
        case idle, preparing, previewing, recording, paused
        /// A moment's part ended at Pause & reflect; Saro's question is up until Keep going or Finish.
        case checkpoint
        /// A voice note stopped, to listen back before keeping it.
        case review
        case finishing
        case needsAccess(Access)
        case failed(String)
    }

    enum Access {
        case camera, microphone

        var settingsURL: URL {
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(self == .camera ? "Camera" : "Microphone")")!
        }
    }

    /// The live transcript's status line (VideoReflectionScreen.tsx TRANSCRIPT_STATUS_COPY).
    enum Live: Equatable { case off, connecting, listening, unavailable }

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
    /// This part's recorded time.
    private(set) var elapsed: Duration = .zero
    /// The part under way, 1-based.
    private(set) var turn = 0
    private(set) var starting = false
    private(set) var closing = false
    /// The question this part answers: today's prompt, frozen at the first part, then Saro's follow-ups.
    private(set) var prompt = ""
    /// The part before ended at Pause & reflect, and how long it was ("Last part 00:42").
    private(set) var lastPart: Duration?
    /// The camera or microphone went away mid-part; what was recorded is kept.
    private(set) var interrupted = false
    /// Every level sample of this part, for the voice review's bars.
    private(set) var levels: [Double] = []
    /// What was heard live (FR-CAP-05): shown and gated, never stored or quoted.
    private(set) var words: [LiveWord] = []
    /// Where this part's words start in `words`.
    private(set) var partStart = 0
    private(set) var live: Live = .off
    /// Parts kept this session.
    private(set) var keptCount = 0
    /// The voice review's file transcript, once read (nil while it is read).
    private(set) var review: [TranscriptWord]?

    let engine = CaptureEngine()
    @ObservationIgnored private var model: AppModel?
    @ObservationIgnored private var sessionId = ""
    @ObservationIgnored private var day: String?
    /// The part recording now (or paused).
    @ObservationIgnored private var current: TurnTicket?
    /// The part not yet kept, recording or with its file closed.
    private(set) var take: TurnTicket?
    @ObservationIgnored private var kept: [String] = []
    @ObservationIgnored private var pending: [URL: TurnTicket] = [:]
    @ObservationIgnored private var banked: Duration = .zero
    @ObservationIgnored private var savedTurns = 0
    @ObservationIgnored private var turnStarted: ContinuousClock.Instant?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var transcriber: LiveTranscriber?
    @ObservationIgnored private var ended: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var closed: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var promptRow: (generator: String, runId: String?) = ("curated", nil)

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

    /// This part's live words, for the checkpoint's gate and question.
    var partText: String { words.dropFirst(partStart).map(\.text).joined(separator: " ") }
    var partWords: [LiveWord] { Array(words.dropFirst(partStart)) }
    /// The take's file once it has closed, for the voice review.
    var takeURL: URL? { take.flatMap { pending[$0.url] == nil ? $0.url : nil } }
    var hasKept: Bool { keptCount > 0 }
    /// The prompt as shown: none on a held day (SR-13), as a page's prompt row.
    var shownPrompt: String? { prompt.isEmpty || model?.isDayHeld != false ? nil : prompt }

    // MARK: Lifecycle

    /// Asks for access on first use (never at launch), picks devices and starts the preview. The prompt is read now and
    /// frozen for the first part.
    func prepare(_ kind: EntryKind, for surface: Surface, model: AppModel) async {
        guard isAvailable(to: surface), turn == 0 else { return }
        owner = surface
        self.model = model
        self.kind = kind
        // The first reflection's question, from the onboarding hand-off, before today's.
        prompt = (surface == .window ? model.handoffPrompt : nil) ?? model.todaysPrompt
        let reading = model.dayReading
        promptRow = prompt == model.starter?.firstPrompt ? ("heuristic", nil)
            : prompt == reading?.payload.reading.question ? (reading?.generator ?? "heuristic", reading?.runId) : ("curated", nil)
        state = .preparing
        let camera = kind == .voice ? true : await Self.access(.video)
        let mic = await Self.access(.audio)
        guard owner == surface, !closing, self.kind == kind else { return }
        if !camera { state = .needsAccess(.camera); return }
        if !mic { state = .needsAccess(.microphone); return }
        refreshDevices()
        await configure()
    }

    /// Try again after a failure: the devices are read again and the preview restarts.
    func retry() {
        guard case .failed = state else { return }
        state = .preparing
        refreshDevices()
        Task { await configure() }
    }

    /// Done, or the surface went away: stops the part, keeps it, lets every file save, then turns the camera off.
    func finish(_ surface: Surface) {
        guard owner == surface else { return }
        closing = true
        if current != nil {
            bank()
            engine.stopRecording()
        }
        keepTake()
        state = .finishing
        teardownIfDone()
    }

    /// `finish`, then waits for every part to save. True when at least one part's file was written.
    func end(_ surface: Surface) async -> Bool {
        finish(surface)
        if owner == surface { await withCheckedContinuation { ended.append($0) } }
        return savedTurns > 0
    }

    // MARK: Recording

    /// The record button and Space: record, pause, resume.
    func toggle() {
        guard canToggle else { return }
        switch state {
        case .previewing: begin()
        case .recording: pause()
        case .paused: resume()
        default: break
        }
    }

    /// The first part, or the next one after Keep going or Record again; no countdown.
    private func begin() {
        guard let model else { return }
        if turn == 0 {
            sessionId = UUID().uuidString
            day = owner == .panel ? LocalDay.today() : model.day
            savedTurns = 0
            startListening()
        }
        turn += 1
        starting = true
        state = .recording
        banked = .zero
        elapsed = .zero
        levels = []
        partStart = words.count
        interrupted = false
        let (n, question, row) = (turn, prompt, promptRow)
        Task {
            do {
                let ticket = try await model.beginTurn(kind: kind, sessionId: sessionId, turn: n, day: day, prompt: question,
                                                       generator: row.generator, aiRunId: row.runId)
                starting = false
                if closing {
                    // ponytail: a Done inside the few-ms row insert leaves this part's rows marked failed.
                    await model.finishTurn(ticket, durationMs: 0, error: nil)
                    teardownIfDone()
                    return
                }
                current = ticket
                take = ticket
                pending[ticket.url] = ticket
                turnStarted = .now
                transcriber?.setFeeding(true)
                engine.startRecording(to: ticket.url)
            } catch {
                starting = false
                turn -= 1
                state = turn == 0 ? .previewing : .checkpoint
                model.show(.failed("Couldn't start recording", error))
                teardownIfDone()
            }
        }
    }

    private func pause() {
        guard current != nil else { return }
        bank(keep: true)
        transcriber?.setFeeding(false)
        engine.pauseRecording()
        state = .paused
    }

    private func resume() {
        guard current != nil else { return }
        turnStarted = .now
        transcriber?.setFeeding(true)
        engine.resumeRecording()
        state = .recording
    }

    /// Pause & reflect (a moment) or Stop (a voice note): the part ends and its file closes, kept back as the take.
    /// Returns once the file is closed, with the part's live words.
    @discardableResult
    func endPart() async -> String {
        guard current != nil, [.recording, .paused].contains(state) else { return partText }
        let text = partText
        lastPart = elapsed
        bank()
        transcriber?.setFeeding(false)
        engine.stopRecording()
        state = kind == .voice ? .review : .checkpoint
        await filesClosed()
        if kind == .voice { readReview() }
        return text
    }

    /// Keep going: the take is kept, and the next part starts at once with Saro's question as its prompt.
    func keepGoing(prompt next: String?, generator: String, runId: String?) async {
        guard state == .checkpoint else { return }
        await filesClosed()
        keepTake()
        if let next {
            prompt = next
            promptRow = (generator, runId)
        }
        begin()
    }

    /// The voice review's Keep this: the note is kept and processed.
    func keepReview() {
        guard state == .review else { return }
        keepTake()
    }

    /// Discard: the take, its rows and its file, gone for good; kept parts stay. `again` records a new take at once
    /// (the voice pill's Record again).
    func discardTake(again: Bool = false) async {
        guard let model else { return }
        if current != nil {
            bank()
            engine.stopRecording()
        }
        await filesClosed()
        if let take {
            try? await model.ledger.discardTake(entryIds: [take.entryId])
            self.take = nil
            turn -= 1
            await model.reload()
        }
        review = nil
        lastPart = nil
        guard again else { return }
        state = .previewing
        begin()
    }

    private func keepTake() {
        guard let take, let model else { return }
        self.take = nil
        kept.append(take.entryId)
        keptCount = kept.count
        // A take whose file is still closing is processed by `turnFinished`.
        if pending[take.url] == nil { model.process(take.entryId) }
    }

    private func bank(keep: Bool = false) {
        if let turnStarted { banked += turnStarted.duration(to: .now) }
        turnStarted = nil
        elapsed = banked
        if !keep { current = nil }
    }

    /// Called by the engine when a part's file is complete (stopped by us, or by AVFoundation on device loss or a full disk).
    func turnFinished(_ url: URL, error: (any Error)?) async {
        guard let ticket = pending[url] else { return }
        if current?.url == url {
            // The device went away mid-part: what was said is kept and the session stops here.
            lastPart = elapsed
            bank()
            transcriber?.setFeeding(false)
            interrupted = true
            state = kind == .voice ? .review : .checkpoint
            // The finish dialog or the review says the device stopped; a write error (a full disk) also says what to do.
            if let error { model?.show(.failed("Recording stopped", error)) }
            Task { await configure() }
        }
        let duration = try? await AVURLAsset(url: url).load(.duration)
        let ms = duration.flatMap { $0.isNumeric ? Int($0.seconds * 1000) : nil } ?? 0
        await model?.finishTurn(ticket, durationMs: ms, error: error, process: kept.contains(ticket.entryId))
        // The test finishTurn uses to mark the part ready rather than failed.
        if FileManager.default.fileExists(atPath: url.path) { savedTurns += 1 }
        pending[url] = nil
        if pending.isEmpty {
            for c in closed { c.resume() }
            closed = []
        }
        if interrupted, kind == .voice { readReview() }
        teardownIfDone()
    }

    private func filesClosed() async {
        guard !pending.isEmpty else { return }
        await withCheckedContinuation { closed.append($0) }
    }

    /// The take's file transcript, read as Stop is pressed so the review seeks by real word times; saved as the transcript
    /// of record, so Keep doesn't read it twice.
    private func readReview() {
        guard let take, let model else { return }
        review = nil
        Task {
            let read = try? await Transcriber.transcribe(url: take.url)
            guard self.take == take else { return }
            if let read, !read.words.isEmpty {
                try? await model.ledger.setTranscript(mediaId: take.mediaId, words: read.words, extractorVersion: read.extractorVersion)
            }
            review = read?.words ?? []
        }
    }

    private func teardownIfDone() {
        guard closing, !starting, current == nil, pending.isEmpty else { return }
        ticker?.cancel()
        ticker = nil
        stopListening()
        engine.stop()
        state = .idle
        owner = nil
        closing = false
        turn = 0
        level = 0
        elapsed = .zero
        banked = .zero
        lastPart = nil
        interrupted = false
        levels = []
        kept = []
        keptCount = 0
        take = nil
        review = nil
        for done in ended { done.resume() }
        ended = []
    }

    // MARK: Live captions (FR-CAP-05)

    private func startListening() {
        guard listening == nil else { return }
        live = .connecting
        let t = LiveTranscriber()
        transcriber = t
        listening = Task {
            do {
                let stream = try await t.start()
                guard transcriber === t else { return }
                engine.live.withLock { $0 = t }
                live = .listening
                for await w in stream { words = w }
            } catch {
                if transcriber === t { live = .unavailable }
            }
        }
    }

    private func stopListening() {
        engine.live.withLock { $0 = nil }
        let t = transcriber
        transcriber = nil
        listening?.cancel()
        listening = nil
        Task { await t?.stop() }
        words = []
        partStart = 0
        live = .off
    }

    // MARK: Devices

    func select(camera id: String) {
        UserDefaults.standard.set(id, forKey: "captureCameraID")
        cameraID = id
        if [.previewing, .checkpoint, .review].contains(state) { Task { await configure() } }
    }

    func select(mic id: String) {
        UserDefaults.standard.set(id, forKey: "captureMicID")
        micID = id
        if [.previewing, .checkpoint, .review].contains(state) { Task { await configure() } }
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
        case .previewing, .checkpoint, .review: if before != (cameraID, micID) { Task { await configure() } }
        case .failed: Task { await configure() }
        default: break
        }
    }

    private func configure() async {
        if kind == .moment, cameraID == nil { state = .failed("No camera is connected."); return }
        guard micID != nil else {
            state = .failed(kind == .voice ? "No microphone found. Connect one and try again." : "No microphone is connected.")
            return
        }
        let hd = UserDefaults.standard.string(forKey: "videoQuality") == "1080p"
        let error = await engine.configure(camera: kind == .moment ? cameraID : nil, mic: micID,
                                           preset: hd ? .hd1920x1080 : .hd1280x720)
        guard owner != nil, !closing else { return }
        if let error {
            // A device back mid-session leaves the part where it is.
            if [.checkpoint, .review].contains(state) { return }
            state = .failed(kind == .voice ? "Couldn't start the microphone. Please try again." : error)
            return
        }
        // A device back mid-session resumes the same session (and day), never a new one.
        if ![.paused, .checkpoint, .review].contains(state) { state = turn > 0 ? .paused : .previewing }
        startTicker()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task {
            while !Task.isCancelled {
                let db = Double(engine.powerLevel)
                let l = max(min(max((db + 50) / 50, 0), 1), level * 0.8)
                if l != level { level = l }
                if state == .recording {
                    levels.append(l)
                    let e = banked + (turnStarted?.duration(to: .now) ?? .zero)
                    if e != elapsed { elapsed = e }
                }
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
    /// Live captions hear the same buffers the meter does.
    let live = Mutex<LiveTranscriber?>(nil)

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
    /// The part pauses in its own file, fragments and all.
    func pauseRecording() { queue.async { if self.movie.isRecording { self.movie.pauseRecording() } } }
    func resumeRecording() { queue.async { if self.movie.isRecordingPaused { self.movie.resumeRecording() } } }
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
        live.withLock { $0 }?.append(sampleBuffer)
    }
}

struct CaptureError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
