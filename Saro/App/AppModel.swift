import AppKit
import Speech
import UniformTypeIdentifiers
import AVFoundation
import ImageIO
import Observation
import SaroKit
import SwiftUI

/// A recording turn whose rows exist before its first frame (DR-12).
struct TurnTicket: Sendable, Hashable {
    let entryId: String
    let mediaId: String
    let url: URL
}

enum Pane: Hashable {
    case day
    case trash
    case decisions
}

/// The app's root state. One per process; every surface reads it from the environment.
@Observable @MainActor
final class AppModel {
    let ledger: Ledger
    let ai = SaroAI()
    let pipeline: Pipeline
    var pane: Pane = .day
    var day: String = LocalDay.today()
    var days: [(day: String, count: Int)] = []
    var entries: [Entry] = []
    var media: [String: MediaAsset] = [:]
    var layouts: [String: CardLayout] = [:]
    var annotations: [String: EntryAnnotation] = [:]
    var verdicts: [String: SafetyVerdictRow] = [:]
    var selection: Set<String> = []
    var openEntryID: String?
    /// The stack fanned out in place, if any.
    var openStackID: String?
    var toast: Toast?
    enum Insight { case spine, panel, letter }
    var insight: Insight = .spine
    var showNoticed: Bool {
        get { insight != .spine }
        set { insight = newValue ? .panel : .spine }
    }
    var showLetter: Bool {
        get { insight == .letter }
        set { insight = newValue ? .letter : .panel }
    }
    var searchOpen = false
    var sidebarVisible = false
    /// −1 when the last day change went back in time, 1 when forward; the canvas slides that way.
    var slideDirection: CGFloat = 1
    /// The canvas's lean at tomorrow's edge.
    var lean: CGFloat = 0
    var week: [(day: String, mood: Mood?)] = []
    enum CameraCommand: Equatable { case fit(UUID), zoom(CGFloat, UUID) }
    var camera: CameraCommand?
    var devNotesVisible = false
    var screen: ScreenID = .canvas
    /// Non-nil while the in-window recorder is up.
    var recorderKind: EntryKind?

    var dayStatus: DayStatus = .empty
    var dayReading: (payload: DayPayload, generator: String, runId: String?)?
    private var queue: [String] = []
    private var working = false
    private var current: String?
    private var navigation = 0
    private static var swept = false

    init(ledger: Ledger) {
        self.ledger = ledger
        pipeline = Pipeline(ledger: ledger, ai: ai)
    }

    static func boot() -> Result<AppModel, Error> {
        Typo.registerFonts()
        do {
            // `-SaroDemo YES` opens a throwaway ledger with synthetic entries, so testing never touches the real journal.
            guard UserDefaults.standard.bool(forKey: "SaroDemo") else { return .success(AppModel(ledger: try Ledger())) }
            let root = URL.temporaryDirectory.appending(path: "SaroDemo-\(UUID().uuidString)")
            let model = AppModel(ledger: try Ledger(rootURL: root))
            Task { await model.seedDemo() }
            return .success(model)
        } catch {
            return .failure(error)
        }
    }

    var isDemo: Bool { ledger.rootURL.lastPathComponent.hasPrefix("SaroDemo") }

    /// Synthetic entries only (SR-28: real user text never enters fixtures).
    private func seedDemo() async {
        let texts = [
            "Long day at work. Shipped the onboarding flow finally. Had chai with Ravi and we talked about his move to Pune. Feeling tired but good.",
            "It's been a year since Dad died. I keep picking up the phone to call him on Sundays. Today I cried in the car outside the grocery store and couldn't go in.",
            "This deadline is killing me. If I have to sit through one more status meeting I'll die.\nAnyway, walked home the long way and the sky was pink over the park.",
        ]
        for (i, t) in texts.enumerated() {
            try? await ledger.insertEntry(Entry(kind: .reflection, body: t, capturedAt: .now.addingTimeInterval(Double(i - 3) * 3600)))
        }
        let ctx = CGContext(data: nil, width: 640, height: 420, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(srgbRed: 0.95, green: 0.63, blue: 0.47, alpha: 1), CGColor(srgbRed: 0.12, green: 0.29, blue: 0.22, alpha: 1)]
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 640, y: 420), options: [])
        if let img = ctx.makeImage(), let data = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) {
            await importStill(data, origin: "demo", at: nil)
        }
        // A synthetic voice note, spoken by the system voice, so the demo exercises transcription → gate → reading.
        let voice = Entry(kind: .voice, capturedAt: .now.addingTimeInterval(-1800), processingStatus: ProcessingStatus.pending)
        let asset = MediaAsset(fileName: "\(voice.localDay)/voice/\(voice.id).caf", kind: .audio, origin: "demo", state: "ready")
        if await DemoSpeech.write("I walked home through the park after work. The sky was pink, and I felt lighter than I have in weeks.",
                                  to: ledger.url(for: asset)) {
            var v = voice
            v.mediaId = asset.id
            try? await ledger.insertMedia(asset)
            try? await ledger.insertEntry(v)
        }
        await reload()
        for e in entries { process(e.id) }
    }

    var isToday: Bool { day == LocalDay.today() }

    func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }

    func mediaURL(for entry: Entry) -> URL? {
        guard let id = entry.mediaId, let m = media[id] else { return nil }
        return ledger.url(for: m)
    }

    // MARK: Loading

    /// Everything one day's canvas shows, loaded together so a day change swaps it in one step.
    struct DayData {
        var entries: [Entry] = []
        var layouts: [String: CardLayout] = [:]
        var annotations: [String: EntryAnnotation] = [:]
        var verdicts: [String: SafetyVerdictRow] = [:]
        var media: [String: MediaAsset] = [:]
        var status: DayStatus = .empty
        var reading: (payload: DayPayload, generator: String, runId: String?)?
    }

    private func load(_ day: String) async throws -> DayData {
        var d = DayData()
        d.entries = try await ledger.entries(day: day)
        d.layouts = try await ledger.layouts(day: day)
        d.annotations = try await ledger.annotations(day: day)
        d.verdicts = try await ledger.verdicts(day: day)
        for e in d.entries { if let id = e.mediaId, let a = try await ledger.media(id) { d.media[id] = a } }
        d.status = await pipeline.dayStatus(day)
        d.reading = d.status == .ready ? await pipeline.latestDayReading(day) : nil
        let live = Set(d.entries.map(\.id))
        d.reading?.payload.quotes.removeAll { !live.contains($0.entryId) }
        return d
    }

    private func apply(_ d: DayData) {
        entries = d.entries
        layouts = d.layouts
        annotations = d.annotations
        verdicts = d.verdicts
        media = d.media
        dayStatus = d.status
        dayReading = d.reading
        selection = selection.filter { id in entries.contains { $0.id == id } }
    }

    func reload() async {
        let target = day
        do {
            days = try await ledger.days()
            let data = try await load(target)
            // The day changed while this load was in flight: its data belongs to the old day.
            guard target == day else { return }
            apply(data)
            try await placeNewCards()
            week = await loadWeek()
        } catch {
            show(Toast("Couldn't read the journal: \(error.localizedDescription)", style: .error))
        }
    }

    /// The 7 days ending on the day on screen, each with its reading's mood unless the day is held (§13.2).
    private func loadWeek() async -> [(day: String, mood: Mood?)] {
        var out: [(day: String, mood: Mood?)] = []
        for i in (0..<7).reversed() {
            let d = LocalDay.adding(-i, to: day)
            let mood = await pipeline.dayStatus(d) == .ready ? await pipeline.latestDayReading(d)?.payload.reading.mood : nil
            out.append((d, mood))
        }
        return out
    }

    /// Switches day. Pointer-driven changes slide (the caller animates); keys switch instantly (the frequency rule).
    func go(to day: String, animation: Animation? = nil) {
        guard day != self.day || pane != .day else { return }
        let target = day
        navigation += 1
        let ticket = navigation
        Task {
            let data = try? await load(target)
            // A later day change won: drop this one so quick ⌘[ ⌘T can't land on the wrong day.
            guard ticket == navigation else { return }
            withAnimation(animation) {
                slideDirection = target > self.day ? 1 : -1
                self.day = target
                pane = .day
                openEntryID = nil
                openStackID = nil
                selection = []
                if let data { apply(data) }
            }
            await reload()
        }
    }

    func slide(_ by: Int) { slide(to: LocalDay.adding(by, to: day)) }

    func slide(to day: String) {
        guard day <= LocalDay.today() else {
            // At tomorrow the canvas leans 24 pt and comes back (daySlide.ts).
            withAnimation(Motion.small) { lean = 24 }
            Task {
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(Motion.small) { lean = 0 }
            }
            return
        }
        go(to: day, animation: UserDefaults.standard.bool(forKey: "reduceMotionOverride") ? Motion.fade : Motion.surface)
    }

    /// Adds photos chosen in an open panel as stills on the day on screen.
    func pickStill() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose photos to keep as stills. Location data is removed."
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task {
            for url in urls {
                if let data = try? Data(contentsOf: url) { await importStill(data, origin: "picked", at: nil) }
            }
        }
    }

    func goToday() { go(to: LocalDay.today()) }
    func goPrevious() { go(to: LocalDay.adding(-1, to: day)) }
    func goNext() {
        let next = LocalDay.adding(1, to: day)
        if next <= LocalDay.today() { go(to: next) }
    }

    // MARK: Capture

    /// Creates the media and entry rows (state `recording`) and returns where the turn's file goes:
    /// `Media/<local_day>/<session>/part-<n>.mov` for moments, `Media/<local_day>/voice/<entry>.mov` for voice notes.
    /// `day` defaults to the day on screen (a past day backdates); the floating panel passes today.
    func beginTurn(kind: EntryKind, sessionId: String, turn: Int, day: String? = nil) async throws -> TurnTicket {
        let entry = Entry(kind: kind, sessionId: sessionId, turnNumber: turn, localDay: day ?? self.day, processingStatus: ProcessingStatus.recording)
        let rel = kind == .moment ? "\(entry.localDay)/\(sessionId)/part-\(turn).mov" : "\(entry.localDay)/voice/\(entry.id).mov"
        let asset = MediaAsset(fileName: rel, kind: kind == .moment ? .video : .audio, origin: "recorded")
        var e = entry
        e.mediaId = asset.id
        let url = ledger.url(for: asset)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await ledger.insertMedia(asset)
        try await ledger.insertEntry(e)
        return TurnTicket(entryId: e.id, mediaId: asset.id, url: url)
    }

    /// Marks the turn's file ready (or failed) and starts processing it.
    func finishTurn(_ ticket: TurnTicket, durationMs: Int, error: Error?) async {
        let bytes = (try? ticket.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        let exists = FileManager.default.fileExists(atPath: ticket.url.path)
        try? await ledger.updateMedia(id: ticket.mediaId, state: exists ? "ready" : "failed", durationMs: durationMs, bytes: bytes)
        try? await ledger.setProcessingStatus(id: ticket.entryId, exists ? ProcessingStatus.pending : ProcessingStatus.failed)
        if let error, !exists { show(Toast("That recording couldn't be saved: \(error.localizedDescription)", style: .error)) }
        await reload()
        guard exists else { return }
        // Don't hold the recorder (and the camera) open while the Speech prompt waits for an answer.
        Task {
            await Self.askForSpeechOnce()
            process(ticket.entryId)
        }
    }

    /// A new, empty piece of writing on the current day.
    func newWriting(body: String = "", day: String? = nil) async -> Entry? {
        let e = Entry(kind: .reflection, body: body, localDay: day ?? self.day)
        do {
            try await ledger.insertEntry(e)
            await reload()
            return e
        } catch {
            show(Toast("Couldn't save: \(error.localizedDescription)", style: .error))
            return nil
        }
    }

    func saveWriting(id: String, body: String, title: String?) async {
        do {
            try await ledger.updateEntryText(id: id, body: body, titleUser: title)
            await reload()
            process(id)
        } catch {
            show(Toast("Couldn't save: \(error.localizedDescription)", style: .error))
        }
    }

    /// Queues an entry for transcription → SafetyGate → reading, one job at a time (§11.7), then re-reads the
    /// days those entries belong to.
    func process(_ entryId: String) {
        if !queue.contains(entryId) && entryId != current { queue.append(entryId) }
        drain()
    }

    /// Works the queue until it is empty, re-reading each touched day; work that arrives meanwhile is picked up.
    private func drain() {
        guard !working else { return }
        working = true
        Task {
            repeat {
                var days = Set<String>()
                while !queue.isEmpty {
                    let id = queue.removeFirst()
                    current = id
                    if let d = try? await ledger.entry(id)?.localDay { days.insert(d) }
                    await pipeline.process(entryId: id) { [weak self] in await self?.reload() }
                }
                current = nil
                for d in days { await pipeline.readDay(d) }
            } while !queue.isEmpty
            working = false
            await reload()
        }
    }

    /// On-device transcription may need the Speech permission; ask once, when there is first something to transcribe.
    /// A refusal doesn't stop anything: the recording is kept and shows "Transcript not ready" if Speech says no.
    /// Nonisolated so the handler, which Speech may call off the main queue, isn't main-actor-isolated (Swift 6 would trap).
    private nonisolated static func askForSpeechOnce() async {
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return }
        _ = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
    }

    /// Transcribes a recording again (Try again on "Transcript not ready" or a technical hold), then gates and reads it.
    func retranscribe(_ entry: Entry) {
        Task {
            if let id = entry.mediaId { try? await ledger.clearTranscript(mediaId: id) }
            try? await ledger.setProcessingStatus(id: entry.id, ProcessingStatus.pending)
            await reload()
            process(entry.id)
        }
    }

    /// After a trash or restore the day's reading may quote what's gone (or miss what's back): read it again.
    func rereadDay() {
        let d = day
        Task {
            if !working { await pipeline.readDay(d) }
            await reload()
        }
    }

    /// Reads the day when the inspector opens and nothing is stored yet (or the inputs changed).
    func refreshDayReading() {
        guard !working, dayStatus == .ready else { return }
        working = true
        Task {
            await pipeline.readDay(day)
            working = false
            if !queue.isEmpty { drain() }
            await reload()
        }
    }

    /// Launch sweep (DR-12): a turn that was recording when Saro quit is a finished file if it exists on disk
    /// (movie fragments survive a crash) and missing otherwise; unfinished entries go back on the queue.
    func sweep() async {
        // Once per launch: reopening the window mid-recording must not treat a live turn as crashed.
        guard !Self.swept else { return await reload() }
        Self.swept = true
        for m in (try? await ledger.allMedia()) ?? [] where m.state == "recording" {
            let url = ledger.url(for: m)
            if FileManager.default.fileExists(atPath: url.path) {
                let seconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
                try? await ledger.updateMedia(id: m.id, state: "ready", durationMs: Int(seconds * 1000), bytes: nil)
            } else {
                try? await ledger.updateMedia(id: m.id, state: "missing", durationMs: nil, bytes: nil)
            }
        }
        for e in (try? await ledger.unfinishedEntries()) ?? [] {
            if e.processingStatus == ProcessingStatus.recording { try? await ledger.setProcessingStatus(id: e.id, ProcessingStatus.pending) }
            process(e.id)
        }
        // Entries gated while Apple Intelligence was off go back through the gate now that it can run (SR-17).
        if ai.status == .available {
            for id in (try? await ledger.entryIDs(withLatestVerdictIn: ["unavailable_clear", "unavailable_caution"])) ?? [] { process(id) }
        }
        await reload()
    }

    // MARK: Canvas

    /// Cards on the canvas: single entries, and stacks of 2+ entries sharing a `stackId` (a recording session's turns
    /// or a user-made stack). Lower z first.
    var items: [CanvasItem] {
        var groups: [String: [Entry]] = [:]
        var order: [String] = []
        for e in entries {
            let key = layouts[e.id]?.stackId.map { "stack:\($0)" } ?? e.id
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(e)
        }
        return order.map { key in
            let members = groups[key] ?? []
            return members.count > 1 ? CanvasItem(id: key, entries: members) : CanvasItem(id: members[0].id, entries: members)
        }
        .sorted { z(of: $0) < z(of: $1) }
    }

    func position(of id: String) -> CGPoint {
        layouts[id].map { CGPoint(x: $0.x, y: $0.y) } ?? .zero
    }

    private func z(of item: CanvasItem) -> Int { item.entries.compactMap { layouts[$0.id]?.z }.max() ?? 0 }

    /// Gives every entry without a layout row a free spot; turns of one recording session join one stack.
    private func placeNewCards() async throws {
        let missing = entries.filter { layouts[$0.id] == nil }
        guard !missing.isEmpty else { return }
        let kinds = Dictionary(entries.map { ($0.id, $0.kind) }, uniquingKeysWith: { a, _ in a })
        var occupied = layouts.values.map { CGRect(center: CGPoint(x: $0.x, y: $0.y), size: CanvasMath.size(kinds[$0.entryId] ?? .moment)) }
        var top = layouts.values.map(\.z).max() ?? 0
        var added: [CardLayout] = []
        for e in missing {
            top += 1
            if let sid = e.sessionId, let mate = (Array(layouts.values) + added).first(where: { $0.stackId == sid }) {
                added.append(CardLayout(entryId: e.id, x: mate.x, y: mate.y, z: top, stackId: sid))
                continue
            }
            let c = CanvasMath.place(e.kind, id: e.id, avoiding: occupied)
            occupied.append(CGRect(center: c, size: CanvasMath.size(e.kind)))
            added.append(CardLayout(entryId: e.id, x: c.x, y: c.y, z: top, stackId: e.sessionId))
        }
        try await ledger.setLayouts(added)
        for l in added { layouts[l.entryId] = l }
    }

    /// Moves cards by a world-space delta and brings them to the front.
    func move(_ ids: Set<String>, by delta: CGSize) {
        var top = layouts.values.map(\.z).max() ?? 0
        var changed: [CardLayout] = []
        for id in ids {
            guard var l = layouts[id] else { continue }
            top += 1
            l.x += delta.width
            l.y += delta.height
            l.z = top
            l.userPlaced = true
            layouts[id] = l
            changed.append(l)
        }
        persist(changed)
    }

    /// Selected cards fly to the first one and settle as a pile (FR-CAN-03).
    func stack(_ ids: Set<String>) {
        let members = entries.filter { ids.contains($0.id) }
        guard members.count > 1, let anchor = members.first.flatMap({ layouts[$0.id] }) else { return }
        let sid = UUID().uuidString
        var top = layouts.values.map(\.z).max() ?? 0
        var changed: [CardLayout] = []
        for e in members {
            top += 1
            let l = CardLayout(entryId: e.id, x: anchor.x, y: anchor.y, z: top, stackId: sid, userPlaced: true)
            layouts[e.id] = l
            changed.append(l)
        }
        persist(changed)
        selection = Set(members.map(\.id))
        show(Toast("Created a Stack"))
    }

    func unstack(_ stackID: String) {
        let members = entries.filter { layouts[$0.id]?.stackId == stackID }
        let points = CanvasMath.fan(count: members.count, size: CanvasMath.size(.moment),
                                    around: members.first.map { position(of: $0.id) } ?? .zero)
        var changed: [CardLayout] = []
        for (e, p) in zip(members, points) {
            guard var l = layouts[e.id] else { continue }
            l.stackId = nil
            l.x = p.x
            l.y = p.y
            l.userPlaced = true
            layouts[e.id] = l
            changed.append(l)
        }
        openStackID = nil
        persist(changed)
    }

    /// A packed, bottom-aligned row (Grid, ⌘G). Stacked cards leave their stack.
    func grid(_ ids: Set<String>) {
        let members = entries.filter { ids.contains($0.id) }
        let placed = CanvasMath.grid(members.map { (id: $0.id, center: position(of: $0.id), size: CanvasMath.size($0.kind)) })
        var changed: [CardLayout] = []
        for (id, p) in placed {
            guard var l = layouts[id] else { continue }
            l.x = p.x
            l.y = p.y
            l.stackId = nil
            l.userPlaced = true
            layouts[id] = l
            changed.append(l)
        }
        persist(changed)
    }

    private func persist(_ layouts: [CardLayout]) {
        guard !layouts.isEmpty else { return }
        Task {
            do { try await ledger.setLayouts(layouts) } catch { show(Toast("Couldn't save the layout: \(error.localizedDescription)", style: .error)) }
        }
    }

    // MARK: Trash

    func trash(_ ids: Set<String>, undoManager: UndoManager? = nil) async {
        guard !ids.isEmpty else { return }
        do {
            let batch = try await ledger.trash(Array(ids))
            selection = []
            if ids.contains(openEntryID ?? "") { openEntryID = nil }
            await reload()
            rereadDay()
            let restore: @MainActor () -> Void = { [weak self] in Task { await self?.restore(batch: batch) } }
            undoManager?.registerUndo(withTarget: self) { _ in MainActor.assumeIsolated { restore() } }
            undoManager?.setActionName("Move to Trash")
            show(Toast(ids.count == 1 ? "Moved to Trash" : "Moved \(ids.count) to Trash", undo: restore))
        } catch {
            show(Toast("Couldn't move to Trash: \(error.localizedDescription)", style: .error))
        }
    }

    func restore(batch: String) async {
        try? await ledger.restore(batch: batch)
        await reload()
        rereadDay()
        show(Toast("Restored"))
    }

    // MARK: Stills

    /// Saves a dropped or pasted image as HEIC with no metadata but its orientation (DR-11: stills lose GPS).
    func importStill(_ data: Data, origin: String, at world: CGPoint?) async {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            show(Toast("That file isn't an image Saro can read", style: .error))
            return
        }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let orientation = props?[kCGImagePropertyOrientation] ?? 1
        var entry = Entry(kind: .still, localDay: day, processingStatus: ProcessingStatus.done)
        let asset = MediaAsset(fileName: "\(entry.localDay)/stills/\(entry.id).heic", kind: .image, origin: origin, state: "ready")
        entry.mediaId = asset.id
        let url = ledger.url(for: asset)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.heic" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85, kCGImagePropertyOrientation: orientation] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
            try await ledger.insertMedia(asset)
            try await ledger.insertEntry(entry)
            if let world {
                try await ledger.setLayouts([CardLayout(entryId: entry.id, x: world.x, y: world.y, z: (layouts.values.map(\.z).max() ?? 0) + 1, userPlaced: true)])
            }
            await reload()
            show(Toast("Still saved to \(DayFormat.sidebar(day))"))
        } catch {
            show(Toast("Couldn't save the still: \(error.localizedDescription)", style: .error))
        }
    }

    // MARK: Toasts

    func show(_ toast: Toast) {
        self.toast = toast
        let id = toast.id
        Task {
            try? await Task.sleep(for: .seconds(toast.undo == nil ? 2.4 : 5))
            if self.toast?.id == id { self.toast = nil }
        }
    }
}

struct CanvasItem: Identifiable {
    let id: String
    let entries: [Entry]
    var isStack: Bool { entries.count > 1 }
    var stackID: String? { isStack ? String(id.dropFirst("stack:".count)) : nil }
    var top: Entry { entries[entries.count - 1] }
}

struct Toast: Identifiable, Equatable {
    enum Style { case info, error }
    let id = UUID()
    let text: String
    let style: Style
    let undo: (@MainActor () -> Void)?

    init(_ text: String, style: Style = .info, undo: (@MainActor () -> Void)? = nil) {
        self.text = text
        self.style = style
        self.undo = undo
    }

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

/// Writes synthetic speech to a file for the demo journal.
enum DemoSpeech {
    private final class Sink: @unchecked Sendable {
        var file: AVAudioFile?
        let url: URL
        init(url: URL) { self.url = url }
    }

    /// Nonisolated: the synthesizer's buffer callback arrives off the main thread.
    nonisolated static func write(_ text: String, to url: URL) async -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let synth = AVSpeechSynthesizer()
        let sink = Sink(url: url)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            var done = false
            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    if !done { done = true; c.resume() }
                    return
                }
                if sink.file == nil { sink.file = try? AVAudioFile(forWriting: sink.url, settings: pcm.format.settings) }
                try? sink.file?.write(from: pcm)
            }
        }
        sink.file = nil
        return FileManager.default.fileExists(atPath: url.path)
    }
}
