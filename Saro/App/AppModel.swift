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
    case knows
}

/// The app's root state. One per process; every surface reads it from the environment.
@Observable @MainActor
final class AppModel {
    let ledger: Ledger
    let ai = SaroAI()
    let pipeline: Pipeline
    /// What Saro knows (Saro/Memory).
    let memory: MemoryModel
    /// Leaving the day closes what sits over it: the lens and the date picker are the day's own.
    var pane: Pane = .day { didSet { if pane != .day { (lens, datePickerOpen) = (nil, false) } } }
    /// Another day ends a replay where it is.
    var day: String = LocalDay.today() { didSet { if replay.day.map({ $0 != day }) ?? false { replay.exit(animated: false) } } }
    let replay = DayReplay()
    var days: [(day: String, count: Int)] = []
    var entries: [Entry] = []
    var media: [String: MediaAsset] = [:]
    var layouts: [String: CardLayout] = [:]
    var annotations: [String: EntryAnnotation] = [:]
    var verdicts: [String: SafetyVerdictRow] = [:]
    var selection: Set<String> = []
    /// Opening a detail folds the voice note open in place, which would otherwise draw and play over it.
    var openEntryID: String? { didSet { if openEntryID == nil { rollOver() } else { openVoiceID = nil } } }
    /// The stack fanned out in place, if any.
    var openStackID: String?
    /// The voice note open in place on its card (VoiceEchoCard.tsx), if any.
    var openVoiceID: String?
    var toasts: [Toast] = []
    /// Toasts the pointer or VoiceOver is on, whose time doesn't run.
    var heldToasts: Set<UUID> = []
    /// Every user-content write, so the avatar's dot is honest (Saro/Shell/SaveStatus.swift).
    let saves = SaveStatus()
    /// Cards flying into the Undo toast, or out of it back to their places.
    var trashFlight: TrashFlight?
    enum Insight { case spine, panel, letter }
    var insight: Insight = .spine { didSet { reflection.moved(to: insight) } }
    let reflection = ReflectionModel()
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
    /// `focus` centres and selects a card (jumpToEntry.ts).
    enum CameraCommand: Equatable { case fit(UUID), zoom(CGFloat, UUID), focus(String, UUID) }
    var camera: CameraCommand?
    var devNotesVisible = false
    /// The time lens, while it is open (Saro/TimeLens).
    var lens: LensState?
    /// The date picker above the bar, which an open entry or set hides: opening it closes them.
    var datePickerOpen = false { didSet { if datePickerOpen, openEntryID != nil || openStackID != nil { (openEntryID, openStackID) = (nil, nil) } } }
    /// The world rect the day's camera shows inside the chrome, published by the stage; new cards land in it.
    var visibleWorld: CGRect?
    var stageSize = CGSize(width: 1320, height: 860)
    /// Where the day view sits in the window, published by it, so ⌘K over the whole window can fly a row into it.
    var dayOrigin: CGPoint = .zero
    /// How far the bottom bar reaches up from the window's bottom (one row or two), published by the day view; the
    /// voice pill, toasts and the spine keep clear of it.
    var barClear: CGFloat = 84
    /// Days loaded ahead of a click (a hovered chevron, a picker day, the days either side), newest last.
    private var neighbours: [(day: String, data: DayData)] = []
    /// The day a change is heading for while its rows load, so quick presses count on from it instead of repeating it.
    private var heading: String?
    /// Bumped by every reload, so a day read ahead before a write can't land in the cache after it.
    private var neighboursVersion = 0
    var screen: ScreenID = .canvas
    /// Non-nil while the in-window recorder is up.
    var recorderKind: EntryKind? {
        didSet {
            // Only the bar button (or the background menu) that opens it sets these, just after.
            if recorderKind != oldValue {
                recorderGrows = false
                recorderLandsAt = nil
            }
            guard recorderKind != nil else { handoffPrompt = nil; return }
            openVoiceID = nil
            replay.exit(animated: false)
        }
    }
    /// A click on the recorder's bar button opened it: it grows out of that button and closes back into it (morph.ts).
    var recorderGrows = false
    /// The first reflection's question, from before onboarding closes until its recorder does (AppModel+Onboarding).
    var handoffPrompt: String?
    /// The background menu's New ▸ Moment or Voice Note: where, in the day's world space, the recording's card lands.
    var recorderLandsAt: CGPoint?
    /// Help and the menu bar's 'If you're struggling…' ask for the SafetyCard. State, not an event, so the window that
    /// same click opens still presents it.
    var safetyCardRequested = false
    /// Nil until `loadProfile` has read it at launch.
    var profile: Profile?
    var starter: StarterContext?
    /// `saro://knows?q=`: what What Saro knows opens filtered by.
    var knowsQuery: String?

    /// The day whose data is on screen; it lags `day` until that day's first load lands (Canvas.tsx's loadedDay).
    private(set) var loadedDay: String?
    /// The day on screen couldn't be read, so the canvas says so instead of looking empty (DayState.tsx).
    var loadFailed = false
    var dayStatus: DayStatus = .empty
    var dayReading: (payload: DayPayload, generator: String, runId: String?)?
    private var queue: [String] = []
    /// Cleared entries the memory extractor hasn't read: learned one at a time, only while nothing else waits.
    private var backlog: [String] = []
    private var draining = false
    /// Refreshes and gate checks waiting their turn behind the entries (§11.7: one model call at a time).
    private var jobs: [@MainActor () async -> Void] = []
    /// Days to read once the queued entries are done (a trash, a restore, the inspector opening).
    private var unreadDays: Set<String> = []
    /// True while the queue is being worked, so a day that can be read but has no reading is still coming.
    private(set) var working = false
    private var current: String?
    private var navigation = 0
    /// Bumped by every drag, stack and grid, so a load that read the layouts before one doesn't put the cards back.
    private var layoutEdits = 0
    /// The calendar day as of the last midnight, wake or activation. Internal so a scenario can stand on the far side of midnight.
    var today = LocalDay.today()
    private static var swept = false

    init(ledger: Ledger) {
        self.ledger = ledger
        pipeline = Pipeline(ledger: ledger, ai: ai)
        memory = MemoryModel(ledger: ledger, pipeline: pipeline)
        memory.showError = { [weak self] in self?.show(Toast($0, style: .error)) }
        memory.gate = { [weak self, pipeline] text in await self?.exclusive { await pipeline.check(text) } }
        memory.saves = saves
        let center = NotificationCenter.default
        // The menu bar and ⌘K post this, sometimes before the window they open has a RootView to receive it.
        center.addObserver(forName: .showSafetyCard, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.safetyCardRequested = true }
        }
        for (c, name) in [(center, Notification.Name.NSCalendarDayChanged), (center, NSApplication.didBecomeActiveNotification),
                          (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)] {
            let gently = name == .NSCalendarDayChanged
            c.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.catchUp(gently: gently) }
            }
        }
    }

    /// Midnight, wake or activation: the day on screen follows today, and entries that waited for the model re-gate.
    private func catchUp(gently: Bool = false) {
        // The day changed under a running Saro: Trash's 30 days and the daily snapshot follow it.
        if LocalDay.today() != today {
            Task {
                _ = try? await ledger.purgeTrash(now: .now)
                _ = try? await ledger.dailySnapshot(now: .now)
            }
        }
        if gently { followMidnight() } else { rollOver() }
        Task { await regateWaiting() }
    }

    /// When the day on screen was today, it moves on to the new today, so a morning capture isn't filed (as backdated)
    /// under yesterday. An open entry stays open; the day moves on when it closes.
    private func rollOver(animated: Bool = false) {
        let now = LocalDay.today()
        guard now != today, openEntryID == nil else { return }
        if day == today {
            if pane == .day { go(to: now, animation: animated ? Motion.pick(Motion.surface, reduce: PrefsStore.shared.reduceMotionEffective) : nil) }
            else { day = now; Task { await reload() } }
        }
        today = now
    }

    /// At midnight today follows the clock with a gentle slide, once the person has left the pointer and keys alone for
    /// 2 s with the window on screen (DateContext.tsx); coming back to the window switches at once.
    private func followMidnight() {
        Task {
            while LocalDay.today() != today {
                let idle = [CGEventType.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]
                    .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
                let visible = NSApp.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) && $0.canBecomeMain }
                if idle >= 2, visible { return rollOver(animated: true) }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Opens the time lens on the day (FR: the lens), from any pane. A key or the menu opens it in place; a pinch flies.
    func openLens(level: LensMath.Level = .week, opener: LensState.Opener = .key) {
        guard lens == nil else { return }
        pane = .day
        lens = LensState(model: self, level: level, opener: opener)
    }

    /// Entries an older gate checked go back through this one (SR-18), entries gated while Apple Intelligence was off
    /// go back once it can run (SR-17), and work a rate limit deferred is tried again (§11.7). The person's other words go
    /// first, so no day is read past one they'd hold.
    private func regateWaiting() async {
        await regateOwnWords()
        for id in (try? await ledger.entryIDs(withLatestVerdictNotAt: SafetyGate.version)) ?? [] { process(id) }
        // The page open in the editor goes when it closes.
        for e in (try? await ledger.unfinishedEntries()) ?? []
        where e.processingStatus == ProcessingStatus.pending && !isQueued(e.id) && e.id != openEntryID {
            process(e.id)
        }
        guard ai.status == .available else { return }
        let waiting = ["unavailable_clear", "unavailable_caution"]
        for id in (try? await ledger.entryIDs(withLatestVerdictIn: waiting, except: "unsupported_language")) ?? [] { process(id) }
    }

    static func boot() -> Result<AppModel, Error> {
        Typo.registerFonts()
        do {
            // `-SaroDemo YES` opens a throwaway ledger with synthetic entries, so testing never touches the real journal.
            guard UserDefaults.standard.bool(forKey: "SaroDemo") else { return .success(AppModel(ledger: try Ledger())) }
            let root = URL.temporaryDirectory.appending(path: "SaroDemo-\(UUID().uuidString)")
            let model = AppModel(ledger: try Ledger(rootURL: root))
            #if DOGFOOD
            Task { await DemoJournal.seed(model) }
            #endif
            return .success(model)
        } catch {
            return .failure(error)
        }
    }

    var isDemo: Bool { ledger.rootURL.lastPathComponent.hasPrefix("SaroDemo") }

    var isToday: Bool { day == LocalDay.today() }

    /// SR-13's whole-day rule. The loaded holds count too: the pipeline says `.working` while any other entry is in progress.
    var isDayHeld: Bool {
        dayStatus == .held || entries.contains { verdicts[$0.id].map { EntryState(verdict: $0.verdict) == .safetyHold } ?? false }
    }

    func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }

    func mediaURL(for entry: Entry) -> URL? {
        guard let id = entry.mediaId, let m = media[id] else { return nil }
        return ledger.url(for: m)
    }

    // MARK: Loading

    /// Everything one day's canvas shows, loaded together so a day change swaps it in one step.
    struct DayData {
        var day: String?
        var entries: [Entry] = []
        var layouts: [String: CardLayout] = [:]
        var annotations: [String: EntryAnnotation] = [:]
        var verdicts: [String: SafetyVerdictRow] = [:]
        var media: [String: MediaAsset] = [:]
        var status: DayStatus = .empty
        var reading: (payload: DayPayload, generator: String, runId: String?)?
    }

    private func load(_ day: String) async throws -> DayData {
        var d = DayData(day: day)
        d.entries = try await ledger.entries(day: day)
        d.layouts = try await ledger.layouts(day: day)
        d.annotations = try await ledger.annotations(day: day)
        d.verdicts = try await ledger.verdicts(day: day)
        // Only what was checked and read from the entry's current text shows (§13.2): an edit is unchecked until gated.
        for e in d.entries {
            guard let v = d.verdicts[e.id] else { d.annotations[e.id] = nil; continue }
            // The words and any typed title, as the gate read them; nil while a still's hold stands as it is.
            if let text = await pipeline.gatedText(of: e), sha256(text) != v.textSha256 {
                // A stale all-clear allows nothing; a stale hold still hides the AI text and keeps the hold shown, until
                // the text is emptied: then nothing is left to hold, as the pipeline's day status already counts it.
                let emptied = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if emptied || v.verdict == "clear" || v.verdict == "unavailable_clear" { d.verdicts[e.id] = nil }
                d.annotations[e.id] = nil
            } else if d.annotations[e.id] != nil {
                // A reading is of the words alone: a title is gated, never read.
                let words = await pipeline.wordsHash(of: e) ?? ""
                if (try? await ledger.hasAnnotation(entryId: e.id, inputHash: words)) != true { d.annotations[e.id] = nil }
            }
        }
        for e in d.entries { if let id = e.mediaId, let a = try await ledger.media(id) { d.media[id] = a } }
        d.status = await pipeline.dayStatus(day)
        d.reading = d.status == .ready ? await pipeline.latestDayReading(day) : nil
        let live = Set(d.entries.map(\.id))
        d.reading?.payload.quotes.removeAll { !live.contains($0.entryId) }
        return d
    }

    private func apply(_ d: DayData) {
        loadedDay = d.day
        loadFailed = false
        entries = d.entries
        layouts = d.layouts
        annotations = d.annotations
        verdicts = d.verdicts
        media = d.media
        dayStatus = d.status
        dayReading = d.reading
        selection = selection.filter { id in entries.contains { $0.id == id } }
        reflection.load(day: day, model: self)
    }

    func reload() async {
        let target = day
        let edits = layoutEdits
        // Something was written: a day read ahead may no longer be what the ledger says (a new hold hides its readings).
        neighbours = []
        neighboursVersion += 1
        // A recorder on a day the window isn't showing (the panel's today) reads its hold again too (SR-13).
        Task { await CaptureController.shared.refreshHeld() }
        do {
            days = try await ledger.days()
            var data = try await load(target)
            // The day changed while this load was in flight: its data belongs to the old day.
            guard target == day else { return }
            // A card moved while it read the layouts, and the move may not be saved yet: what's on screen is newer.
            if edits != layoutEdits { data.layouts.merge(layouts) { _, onScreen in onScreen } }
            apply(data)
            try await placeNewCards()
            week = await loadWeek()
        } catch {
            // An empty canvas would look like lost entries, so a day that never loaded says what happened on the canvas;
            // one already on screen keeps its cards.
            if target == day && loadedDay != target {
                apply(DayData())
                loadFailed = true
            } else {
                show(.failed("Couldn't refresh this day", error, retry: { [weak self] in Task { await self?.reload() } }))
            }
        }
    }

    /// The 7 days ending on the day on screen, each with its reading's mood unless the day is held (§13.2).
    private func loadWeek() async -> [(day: String, mood: Mood?)] {
        var out: [(day: String, mood: Mood?)] = []
        for i in (0..<7).reversed() {
            let d = LocalDay.adding(-i, to: day)
            out.append((d, await pipeline.dayMood(d)))
        }
        return out
    }

    /// Switches day. Pointer-driven changes slide (the caller animates); keys switch instantly (the frequency rule). A
    /// day loaded ahead (armed) lands at once; the others land when their rows are read.
    func go(to day: String, animation: Animation? = nil) {
        // Counted even when it stays put: ⌘[ then ⌘T must cancel the ⌘[ still loading.
        navigation += 1
        heading = nil
        guard day != self.day || pane != .day else { return }
        let target = day
        let ticket = navigation
        heading = target
        if let armed = neighbours.last(where: { $0.day == target })?.data { return land(target, armed, animation: animation) }
        Task {
            let data = try? await load(target)
            // A later day change won: drop this one so quick ⌘[ ⌘T can't land on the wrong day.
            guard ticket == navigation else { return }
            // A day that couldn't be read mustn't show the day before's cards; the reload below says why.
            land(target, data ?? DayData(), animation: animation)
        }
    }

    private func land(_ target: String, _ data: DayData, animation: Animation?) {
        heading = nil
        withAnimation(animation) {
            slideDirection = target > self.day ? 1 : -1
            self.day = target
            pane = .day
            // The letter belongs to the day it was opened on.
            if insight == .letter { insight = .spine }
            openEntryID = nil
            openStackID = nil
            openVoiceID = nil
            selection = []
            apply(data)
        }
        let landed = target
        Task {
            await reload()
            // Once a day lands and the app is idle, the days either side (and two back) are read and their pictures decoded.
            try? await Task.sleep(for: .milliseconds(600))
            guard self.day == landed else { return }
            for d in [-1, 1, -2] { arm(LocalDay.adding(d, to: landed)) }
        }
    }

    /// Reads a day ahead of a click and decodes its pictures, so the slide only has to move: a hovered chevron, a day in
    /// the picker, the days either side of one that landed (daySlide.ts's armDay).
    // ponytail: a small LRU instead of the web's 800 ms disarm; local rows are cheap to keep, and a reload drops them all.
    func arm(_ target: String) {
        guard target <= LocalDay.today(), target != day, !neighbours.contains(where: { $0.day == target }) else { return }
        let version = neighboursVersion
        Task {
            guard let data = try? await load(target), version == neighboursVersion, !neighbours.contains(where: { $0.day == target }) else { return }
            neighbours.append((target, data))
            if neighbours.count > 6 { neighbours.removeFirst() }
            for e in data.entries where e.kind == .moment || e.kind == .still {
                guard let id = e.mediaId, let m = data.media[id], m.state == "ready" else { continue }
                _ = await ThumbCache.image(for: ledger.url(for: m), kind: e.kind)
            }
        }
    }

    func slide(_ by: Int) { slide(to: LocalDay.adding(by, to: heading ?? day)) }

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
        go(to: day, animation: PrefsStore.shared.reduceMotionEffective ? Motion.fade : Motion.surface)
    }

    func goToday() { go(to: LocalDay.today()) }
    func goPrevious() { go(to: LocalDay.adding(-1, to: heading ?? day)) }
    func goNext() {
        let next = LocalDay.adding(1, to: heading ?? day)
        if next <= LocalDay.today() { go(to: next) }
    }

    // MARK: Capture

    /// Creates the media and entry rows (state `recording`) and returns where the turn's file goes:
    /// `Media/<local_day>/<session>/part-<n>.mov` for moments, `Media/<local_day>/voice/<entry>.mov` for voice notes.
    /// `day` defaults to the day on screen (a past day backdates); the floating panel passes today. The question the part
    /// answers is kept with it as its prompt row.
    func beginTurn(kind: EntryKind, sessionId: String, turn: Int, day: String? = nil, prompt: String = "", generator: String = "curated",
                   aiRunId: String? = nil) async throws -> TurnTicket {
        Task { await Self.askForSpeechOnce() }
        let entry = Entry(kind: kind, sessionId: sessionId, turnNumber: turn, localDay: day ?? self.day, processingStatus: ProcessingStatus.recording)
        let rel = kind == .moment ? "\(entry.localDay)/\(sessionId)/part-\(turn).mov" : "\(entry.localDay)/voice/\(entry.id).mov"
        let asset = MediaAsset(fileName: rel, kind: kind == .moment ? .video : .audio, origin: "recorded")
        var e = entry
        e.mediaId = asset.id
        let url = ledger.url(for: asset)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await ledger.insertMedia(asset)
        try await ledger.insertEntry(e)
        if !prompt.isEmpty {
            try? await ledger.insertTurn(ReflectionTurn(kind: .prompt, question: prompt, generator: generator, localDay: e.localDay, entryId: e.id,
                                                        sessionId: sessionId, turnNumber: turn, aiRunId: aiRunId))
        }
        // The first turn's card goes where the background menu opened; later turns join its stack.
        if turn == 1, kind == recorderKind, let p = recorderLandsAt {
            recorderLandsAt = nil
            let l = CardLayout(entryId: e.id, x: p.x, y: p.y, z: (layouts.values.map(\.z).max() ?? 0) + 1, stackId: sessionId, userPlaced: true)
            try await ledger.setLayouts([l])
            if e.localDay == loadedDay { layouts[e.id] = l }
        }
        return TurnTicket(entryId: e.id, mediaId: asset.id, url: url)
    }

    /// Marks the turn's file ready (or failed) and, once kept, starts processing it.
    func finishTurn(_ ticket: TurnTicket, durationMs: Int, error: Error?, process kept: Bool = true) async {
        let bytes = (try? ticket.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        let exists = FileManager.default.fileExists(atPath: ticket.url.path)
        try? await saves.track(ticket.entryId) { [ledger] in
            try await ledger.updateMedia(id: ticket.mediaId, state: exists ? "ready" : "failed", durationMs: durationMs, bytes: bytes)
            try await ledger.setProcessingStatus(id: ticket.entryId, exists ? ProcessingStatus.pending : ProcessingStatus.failed)
        }
        if let error, !exists { show(.failed("That recording couldn't be saved", error)) }
        await reload()
        guard exists else { return }
        Task { if let m = try? await ledger.media(ticket.mediaId) { await Posters.ensure(m, in: ledger) } }
        if kept { process(ticket.entryId) }
    }

    /// A new, empty piece of writing on the current day.
    func newWriting(body: String = "", day: String? = nil) async -> Entry? {
        let e = Entry(kind: .reflection, body: body, localDay: day ?? self.day)
        do {
            try await saves.track(e.id) { [weak self] in
                try await self?.ledger.insertEntry(e)
                await self?.reload()
            }
            return e
        } catch {
            show(.failed("Couldn't save your reflection", error, retry: { [weak self] in Task { await self?.saves.retry(e.id) } }))
            return nil
        }
    }

    /// Queues an entry for transcription → SafetyGate → reading, one job at a time (§11.7), then re-reads the
    /// days those entries belong to.
    func process(_ entryId: String) {
        // The entry under way queues again too: its pass read the text before this request, and a rerun skips cached work.
        if !queue.contains(entryId) { queue.append(entryId) }
        drain()
    }

    /// Whether a pass for this entry is waiting or under way.
    func isQueued(_ entryId: String) -> Bool { current == entryId || queue.contains(entryId) }

    /// An autosave changed an entry's text, which is unchecked until gated. Pending lets the launch sweep gate it if Saro
    /// quits before the editor closes; a pass already reading the old text runs again.
    func edited(_ entryId: String) async {
        try? await ledger.setProcessingStatus(id: entryId, ProcessingStatus.pending)
        if entryId == current { process(entryId) }
    }

    /// Works the queue until it is empty, re-reading each touched day; work that arrives meanwhile is picked up.
    private func drain() {
        guard !draining else { return }
        draining = true
        Task {
            repeat {
                // The memory backfill waits behind everything else, and no day waits on it.
                let busy = !queue.isEmpty || !unreadDays.isEmpty || !jobs.isEmpty
                if working != busy { working = busy }
                if !busy, !backlog.isEmpty {
                    await memory.learn(entryId: backlog.removeFirst())
                    continue
                }
                var days = unreadDays
                unreadDays = []
                while !queue.isEmpty {
                    // The jobs waiting now (a refresh, a gate check, Settings' model calls) go before the next entry, so
                    // a backlog of entries doesn't hold them; ones that arrive meanwhile wait one entry, so neither starves.
                    let waiting = jobs
                    jobs = []
                    for job in waiting { await job() }
                    let id = queue.removeFirst()
                    current = id
                    if let d = try? await ledger.entry(id)?.localDay { days.insert(d) }
                    await pipeline.process(entryId: id) { [weak self] in await self?.reload() }
                    await memory.learn(entryId: id)
                }
                current = nil
                // The same before each day's reading; a capture made meanwhile goes before the days left.
                var left = Array(days)
                while let d = left.popLast() {
                    let waiting = jobs
                    jobs = []
                    for job in waiting { await job() }
                    await pipeline.readDay(d)
                    if !queue.isEmpty { unreadDays.formUnion(left); break }
                }
                while !jobs.isEmpty { await jobs.removeFirst()() }
                // Read back while still working, so a reading never shows as missing between landing and the reload.
                if queue.isEmpty, unreadDays.isEmpty, jobs.isEmpty { await reload() }
            } while !queue.isEmpty || !unreadDays.isEmpty || !jobs.isEmpty || !backlog.isEmpty
            draining = false
            working = false
            // A hold on a day hides its lines at once (SR-16), wherever What Saro knows is showing.
            await memory.load()
        }
    }

    /// On-device transcription may need the Speech permission; ask once, when there is first something to transcribe.
    /// A refusal doesn't stop anything: the recording is kept and shows "Transcript not ready" if Speech says no.
    /// Nonisolated so the handler, which Speech may call off the main queue, isn't main-actor-isolated (Swift 6 would trap).
    private nonisolated static func askForSpeechOnce() async {
        #if DOGFOOD
        // Scenarios run unattended, often at night: no system prompt.
        if UserDefaults.standard.string(forKey: "SaroScenario") != nil { return }
        #endif
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

    /// After a trash or restore the day's reading may quote what's gone (or miss what's back): read it again, after
    /// whatever is under way (§11.7: one model call at a time).
    func rereadDay() {
        unreadDays.insert(day)
        drain()
    }

    /// Reads the day when the inspector opens and nothing is stored yet (or the inputs changed). `force` writes a new
    /// reading (Refresh), sampled and past the `avoid` title, and returns it.
    @discardableResult
    func refreshDayReading(force: Bool = false, avoid: String? = nil) async -> DayPayload? {
        guard dayStatus == .ready else { return nil }
        guard force else {
            rereadDay()
            return nil
        }
        let day = self.day
        let payload = await exclusive { await self.pipeline.readDay(day, force: true, avoid: avoid, seed: .random(in: 1 ... .max)) }
        await reload()
        return payload
    }

    /// Runs `work` in the queue, after whatever is under way (§11.7: one model call at a time).
    func exclusive<T: Sendable>(_ work: @escaping @MainActor () async -> T) async -> T {
        await withCheckedContinuation { c in
            jobs.append { c.resume(returning: await work()) }
            drain()
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
                // Numeric only, as turnFinished checks: an indefinite or invalid duration's NaN seconds would trap Int(_:)
                // here on every launch, since the row stays `recording` until this sweep updates it.
                let duration = try? await AVURLAsset(url: url).load(.duration)
                let ms = duration.flatMap { $0.isNumeric ? Int($0.seconds * 1000) : nil } ?? 0
                try? await ledger.updateMedia(id: m.id, state: "ready", durationMs: ms, bytes: nil)
            } else {
                try? await ledger.updateMedia(id: m.id, state: "missing", durationMs: nil, bytes: nil)
            }
        }
        for e in (try? await ledger.unfinishedEntries()) ?? [] {
            if e.processingStatus == ProcessingStatus.recording { try? await ledger.setProcessingStatus(id: e.id, ProcessingStatus.pending) }
            process(e.id)
        }
        backlog = await memory.unlearned()
        drain()
        for id in await pipeline.ungatedTitles() { process(id) }
        await regateWaiting()
        _ = try? await ledger.purgeTrash(now: .now)
        _ = try? await ledger.dailySnapshot(now: .now)
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

    func size(of e: Entry) -> CGSize { CanvasMath.size(e.kind, w: layouts[e.id]?.w, h: layouts[e.id]?.h) }

    private func z(of item: CanvasItem) -> Int { item.entries.compactMap { layouts[$0.id]?.z }.max() ?? 0 }

    /// Gives every entry without a layout row a place; turns of one recording session join one stack. A day with none
    /// yet is laid out as if by hand (dayLayout.ts); new cards on a laid-out day land in the visible area, a burst as one
    /// block, else card by card at the free spot nearest the middle, else the first free spot in reading order.
    private func placeNewCards() async throws {
        let missing = entries.filter { layouts[$0.id] == nil }
        guard !missing.isEmpty else { return }
        let kinds = Dictionary(entries.map { ($0.id, $0.kind) }, uniquingKeysWith: { a, _ in a })
        var occupied = layouts.values.map {
            CGRect(center: CGPoint(x: $0.x, y: $0.y), size: CanvasMath.size(kinds[$0.entryId] ?? .moment, w: $0.w, h: $0.h))
        }
        var top = layouts.values.map(\.z).max() ?? 0
        var added: [CardLayout] = []
        var loose: [Entry] = []
        for e in missing {
            top += 1
            if let sid = e.sessionId, let mate = (Array(layouts.values) + added).first(where: { $0.stackId == sid }) {
                added.append(CardLayout(entryId: e.id, x: mate.x, y: mate.y, z: top, stackId: sid, userPlaced: mate.userPlaced))
            } else {
                added.append(CardLayout(entryId: e.id, x: 0, y: 0, z: top, stackId: e.sessionId))
                loose.append(e)
            }
        }
        // A day with no cards yet opens at 100%: its visible area is the canvas inside the chrome (Camera.fit's frame).
        let frame = Camera.frame(stageSize)
        let visible = layouts.isEmpty ? frame : visibleWorld ?? frame
        let sizes = loose.map { CanvasMath.size($0.kind) }
        let centre = { (corner: CGPoint, size: CGSize) in CGPoint(x: corner.x + size.width / 2, y: corner.y + size.height / 2) }
        var spots: [CGPoint]?
        if layouts.isEmpty {
            let items = zip(loose, sizes).map { DayLayout.Item(id: $0.id, kind: $0.kind, size: $1) }
            let at = DayLayout.layoutDay(items, center: CGPoint(x: visible.midX, y: visible.midY), visible: visible.size)
            spots = loose.map { at[$0.id] ?? .zero }
        } else if loose.count > 1, let block = DayLayout.packBurst(sizes, in: visible, avoiding: occupied) {
            spots = zip(block, sizes).map(centre)
        }
        for (i, e) in loose.enumerated() {
            let size = sizes[i]
            let free = DayLayout.freeSpot(size, in: visible, avoiding: occupied).map { centre($0, size) }
            let c = spots?[i] ?? free ?? CanvasMath.place(e.kind, id: e.id, avoiding: occupied)
            occupied.append(CGRect(center: c, size: size))
            if let j = added.firstIndex(where: { $0.entryId == e.id }) { (added[j].x, added[j].y) = (c.x, c.y) }
        }
        // A recording's later turns sit on their first's place.
        let placed = Set(loose.map(\.id))
        for (j, l) in added.enumerated() where !placed.contains(l.entryId) {
            if let first = added.first(where: { $0.stackId == l.stackId && placed.contains($0.entryId) }) { (added[j].x, added[j].y) = (first.x, first.y) }
        }
        try await ledger.setLayouts(added)
        for l in added { layouts[l.entryId] = l }
    }

    /// The window's width changed: the cards nobody moved follow the day's layout for the new visible area (B-002); the
    /// ones moved by hand stay where they were put. Height alone changes nothing. A stack moves as one card.
    func relayout(for visible: CGRect) {
        let key = { (e: Entry) in self.layouts[e.id]?.stackId ?? e.id }
        // A stack is hand-placed if any of its turns is: it is drawn where its top turn sits.
        let moved = Set(entries.filter { layouts[$0.id]?.userPlaced ?? true }.map(key))
        let auto = entries.filter { !moved.contains(key($0)) }
        var cards: [String: [Entry]] = [:], order: [String] = []
        for e in auto {
            if cards[key(e)] == nil { order.append(key(e)) }
            cards[key(e), default: []].append(e)
        }
        guard order.count > 1 else { return }
        let items = order.compactMap { k in
            cards[k].map { m in DayLayout.Item(id: k, kind: m[0].kind, size: m.count > 1 ? CanvasMath.stackSize : size(of: m[0])) }
        }
        // The hand-placed cards stay where they were put, so the others' new places keep off them.
        let taken = self.items.filter { moved.contains(key($0.top)) && layouts[$0.top.id] != nil }
            .map { CGRect(center: position(of: $0.top.id), size: $0.isStack ? CanvasMath.stackSize : size(of: $0.top)) }
        let at = DayLayout.relayout(items, in: visible, avoiding: taken)
        var changed: [CardLayout] = []
        for e in auto {
            guard var l = layouts[e.id], let p = at[key(e)] else { continue }
            (l.x, l.y) = (p.x, p.y)
            layouts[e.id] = l
            changed.append(l)
        }
        persist(changed)
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

    /// A card let go by its resize handle: its centre and width, and its height unless that follows its content.
    func resize(_ id: String, to r: CGRect, height: CGFloat?) {
        guard var l = layouts[id] else { return }
        l.x = r.midX
        l.y = r.midY
        l.w = r.width
        l.h = height.map(Double.init)
        l.userPlaced = true
        layouts[id] = l
        persist([l])
    }

    /// Selected cards fly to the first one and settle as a pile (FR-CAN-03).
    func stack(_ ids: Set<String>) {
        let members = entries.filter { ids.contains($0.id) }
        guard members.count > 1, let anchor = members.first.flatMap({ layouts[$0.id] }) else { return }
        if ids.contains(openVoiceID ?? "") { openVoiceID = nil }
        let sid = UUID().uuidString
        var top = layouts.values.map(\.z).max() ?? 0
        var changed: [CardLayout] = []
        for e in members {
            top += 1
            // A card keeps the size it was given, so Unstack brings it back as it was.
            let l = CardLayout(entryId: e.id, x: anchor.x, y: anchor.y, z: top, stackId: sid, userPlaced: true,
                               w: layouts[e.id]?.w, h: layouts[e.id]?.h)
            layouts[e.id] = l
            changed.append(l)
        }
        persist(changed)
        selection = Set(members.map(\.id))
        show(Toast("Created a Stack"))
    }

    func unstack(_ stackID: String) {
        let members = entries.filter { layouts[$0.id]?.stackId == stackID }
        let sizes = members.map(size(of:))
        let room = CGSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).max() ?? 0)
        let points = CanvasMath.fan(count: members.count, size: room, around: members.first.map { position(of: $0.id) } ?? .zero)
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
        let placed = CanvasMath.grid(members.map { (id: $0.id, center: position(of: $0.id), size: size(of: $0)) })
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
        layoutEdits += 1
        let ids = layouts.map(\.entryId)
        let key = "layout:" + ids.sorted().joined(separator: ",")
        Task {
            do {
                // A retry saves where the cards are by then.
                try await saves.track(key) { [self] in try await ledger.setLayouts(ids.compactMap { self.layouts[$0] }) }
            } catch {
                show(.failed("Couldn't save the layout", error, retry: { [saves] in Task { await saves.retry(key) } }))
            }
        }
    }

    // MARK: Trash

    /// `flies`: the cards fly into the Undo toast (Canvas.tsx). Set before the day reloads without them, so the stage
    /// takes their faces while it still has them.
    func trash(_ ids: Set<String>, undoManager: UndoManager? = nil, flies: Bool = false) async {
        guard !ids.isEmpty else { return }
        let cards = stageCards.filter { !$0.ids.isDisjoint(with: ids) }
        let flight = flies && !cards.isEmpty ? TrashFlight(cards: cards) : nil
        if let flight { trashFlight = flight }
        do {
            let batch = try await ledger.trash(Array(ids))
            // A deleted card's unsaved change no longer counts (save-status.ts forgetSave).
            saves.forget(ids)
            let trashedKinds = entries.filter { ids.contains($0.id) }.map(\.kind)
            selection = []
            if ids.contains(openEntryID ?? "") { openEntryID = nil }
            if ids.contains(openVoiceID ?? "") { openVoiceID = nil }
            await reload()
            // Each trashed entry's own day: ⌘K trashes from any day.
            for id in ids { if let d = try? await ledger.entry(id)?.localDay { unreadDays.insert(d) } }
            drain()
            let restore: @MainActor () -> Void = { [weak self] in Task { await self?.restore(batch: batch) } }
            // Its own target, held by its own step, so the toast's Undo takes just this step off the Edit menu.
            let token = TrashUndo()
            undoManager?.registerUndo(withTarget: token) { _ in MainActor.assumeIsolated { withExtendedLifetime(token) { restore() } } }
            undoManager?.setActionName("Move to Trash")
            show(Toast(title: EntryKind.trashTitle(trashedKinds, count: ids.count), detail: "You can undo this",
                       action: Toast.Action(label: "Undo", run: { [weak undoManager] in
                           undoManager?.removeAllActions(withTarget: token)
                           restore()
                       }), trashed: cards))
        } catch {
            if let flight, trashFlight?.id == flight.id { trashFlight = nil }
            show(.failed("Couldn't move that to Trash", error, context: "It's still on your canvas.", retry: { [weak self] in
                Task { await self?.trash(ids, undoManager: undoManager) }
            }))
        }
    }

    /// A batch already back (from the Trash pane, say) restores nothing and says nothing.
    func restore(batch: String) async {
        do {
            var ids: [String] = []
            try await saves.track("restore:\(batch)") { [weak self] in
                guard let self else { return }
                ids = try await ledger.restore(batch: batch)
                await restored(ids)
            }
            // A batch already restored (the toast's Undo, then ⌘Z) says nothing.
            if !ids.isEmpty { show(Toast("Restored")) }
        } catch {
            show(.failed("Couldn't restore that item", error, retry: { [weak self] in Task { await self?.restore(batch: batch) } }))
        }
    }

    /// The Trash panel's Restore. Returns whether it landed.
    @discardableResult
    func restore(ids: [String]) async -> Bool {
        do {
            try await saves.track("restore:" + ids.joined(separator: ",")) { [weak self] in
                guard let self else { return }
                try await ledger.restore(ids: ids)
                await restored(ids)
            }
            return true
        } catch {
            show(.failed(ids.count == 1 ? "Couldn't restore that item" : "Couldn't restore \(ids.count) items", error,
                         context: ids.count == 1 ? nil : "They're still in the trash."))
            return false
        }
    }

    /// Restored entries go back on the queue: one trashed before its pass ran was never read, and its day's reading
    /// misses it until read again (the drain reads each entry's day; a rerun skips cached work).
    private func restored(_ ids: [String]) async {
        await reload()
        for id in ids { process(id) }
    }

}

private final class TrashUndo: Sendable {}

struct CanvasItem: Identifiable {
    let id: String
    let entries: [Entry]
    var isStack: Bool { entries.count > 1 }
    var stackID: String? { isStack ? String(id.dropFirst("stack:".count)) : nil }
    var top: Entry { entries[entries.count - 1] }
}

/// Trashed cards on their way into the Undo toast, or with `back`, out of it to their places again (Canvas.tsx).
struct TrashFlight: Equatable {
    let id = UUID()
    let cards: [StageCard]
    /// Undo: the toast they fly out of, and where it sat.
    var back: (toast: Toast, frame: CGRect)?

    var into: Bool { back == nil }

    static func == (a: TrashFlight, b: TrashFlight) -> Bool { a.id == b.id }
}

/// Writes synthetic speech to a file for the demo journal.
enum DemoSpeech {
    private final class Sink: @unchecked Sendable {
        var synth: AVSpeechSynthesizer?
        var file: AVAudioFile?
        let url: URL
        init(url: URL) { self.url = url }
    }

    /// Nonisolated: the synthesizer's buffer callback arrives off the main thread.
    nonisolated static func write(_ text: String, to url: URL) async -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sink = Sink(url: url)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            // The synthesizer blocks synchronously while it sets up (AXCommon's "unsafeForcedSync called from Swift
            // Concurrent context"), so it starts on a plain queue, not a cooperative thread.
            DispatchQueue.global().async {
                let synth = AVSpeechSynthesizer()
                sink.synth = synth
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
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
        }
        sink.file = nil
        sink.synth = nil
        return FileManager.default.fileExists(atPath: url.path)
    }
}
