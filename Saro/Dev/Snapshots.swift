#if DOGFOOD
import AppKit
import SaroKit
import SwiftUI

/// `-SaroSnapshot <dir>` (with -SaroDemo, in an unsandboxed build) hosts the real UI in an off-screen window, steps through
/// a few states and writes each as `<dir>/<state>.png`, so the UI can be checked without taking the user's focus.
@MainActor
enum Snapshots {
    private static var panel: NSPanel?
    /// Holds the day's first card a little off its place, so the drag grid can be seen.
    static let hold = Notification.Name("SaroSnapshotHold")
    /// Holds a trash flight this far along, so both its ends can be seen.
    static var trashFreeze: Double?
    /// Starts (true) or ends (false) a resize of the day's first moment from its bottom-right handle.
    static let resize = Notification.Name("SaroSnapshotResize")
    /// Opens ⌘K with its actions menu up on the first row.
    static var paletteActions = false
    /// Opens the busiest node of What Saro knows' graph.
    static let pickNode = Notification.Name("SaroSnapshotPickNode")
    /// Shows Why on the first person in What Saro knows' list.
    static let showWhy = Notification.Name("SaroSnapshotShowWhy")

    static func runIfRequested(_ model: AppModel) {
        guard panel == nil, let dir = UserDefaults.standard.string(forKey: "SaroSnapshot") else { return }
        let p = NSPanel(contentRect: NSRect(x: -6000, y: 0, width: 1320, height: 860), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentView = NSHostingView(rootView: RootView().environment(model))
        panel = p
        let dark = UserDefaults.standard.bool(forKey: "SaroSnapshotDark")
        p.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        Task {
            await seedReflection(model)
            await seedHistory(model)
            try? await Task.sleep(for: .seconds(UserDefaults.standard.double(forKey: "SaroSnapshotDelay").clamped(to: 5...120)))
            let steps: [(String, @MainActor () -> Void)] = [
                ("canvas", { model.selection = [] }),
                ("selected", { model.selection = Set(model.entries.prefix(2).map(\.id)) }),
                // A moment part way through a resize from its corner, then let go, still selected.
                ("resize", {
                    model.selection = []
                    NotificationCenter.default.post(name: resize, object: true)
                }),
                ("resized", { NotificationCenter.default.post(name: resize, object: false) }),
                ("noticed", { model.selection = []; model.showNoticed = true }),
                ("detail", { model.showNoticed = false; model.openEntryID = model.entries.first(where: { $0.kind == .reflection })?.id }),
                ("still", { model.openEntryID = model.entries.first(where: { $0.kind == .still })?.id }),
                ("letter", { model.openEntryID = nil; model.showLetter = true }),
                ("voice", { model.insight = .spine; model.openVoiceID = model.entries.first(where: { $0.kind == .voice })?.id }),
                // A writing and the still part way into the Undo toast, then part way back out of it (as a click on Undo
                // flies them), then home.
                ("trash", {
                    model.openVoiceID = nil
                    trashFreeze = 0.3
                    let ids = [EntryKind.reflection, .still].compactMap { k in model.entries.first { $0.kind == k }?.id }
                    Task { await model.trash(Set(ids), flies: true) }
                }),
                ("untrash", {
                    guard let t = model.toast else { return }
                    model.trashFlight = TrashFlight(cards: t.trashed, back: (t, CGRect(x: 24, y: 860 - 92 - 56, width: 360, height: 56)))
                    t.undo?()
                    model.toast = nil
                }),
                ("untrashed", {
                    trashFreeze = nil
                    model.trashFlight = nil
                }),
                ("replay", {
                    model.startReplay(animated: false)
                    let items = model.replay.items
                    model.replay.scrub(to: items.isEmpty ? 12 : items[items.count / 2].hour)
                    model.replay.tip = .key
                }),
                ("held", {
                    model.replay.exit(animated: false)
                    model.openVoiceID = nil
                    NotificationCenter.default.post(name: hold, object: nil)
                }),
                // Deep links, without bringing the app forward.
                ("link-day", {
                    WindowActions.openMain = {}
                    model.openVoiceID = nil
                    model.open(DeepLink.day(LocalDay.adding(-1, to: LocalDay.today())).url)
                }),
                ("link-missing", {
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        model.open(DeepLink.entry("gone").url)
                    }
                }),
                // Reflection: the spine's commitment marks and carry ring, the question's editor, then its pieces.
                ("reflection-spine", { model.goToday() }),
                ("reflection-panel", {
                    model.insight = .panel
                    model.reflection.answerRequested = true
                }),
                // Kept, the letter stays open as 'Kept letter' with the check in its footer.
                ("reflection-kept", {
                    model.reflection.answerRequested = false
                    model.insight = .letter
                    guard let p = model.dayReading?.payload,
                          let letter = Letter(reading: p.reading, candidates: p.quotes, narrative: p.narrative, mood: nil) else { return }
                    Task { await model.reflection.keep(letter) }
                }),
                // A day that can be read but whose reading didn't come: the panel says so and offers Try again.
                ("reflection-unavailable", {
                    model.insight = .panel
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        model.dayReading = nil
                    }
                }),
                // A held day: the SafetyCard alone, no commitments under it.
                ("reflection-held", { model.go(to: LocalDay.adding(-2, to: LocalDay.today())) }),
                // Stills (demo journal only): the user's caption over Saro's description, then that still held.
                ("still-yours", {
                    guard model.isDemo else { return }
                    model.goToday()
                    Task {
                        try? await Task.sleep(for: .seconds(0.8))
                        guard let s = model.entries.first(where: { $0.kind == .still }) else { return }
                        try? await model.ledger.updateEntryText(id: s.id, body: nil, titleUser: nil,
                                                               captionUser: "Dusk over the park, the colours I walked home through.")
                        await model.reload()
                        model.openEntryID = s.id
                        model.process(s.id)
                    }
                }),
                ("still-held", {
                    guard model.isDemo, let id = model.openEntryID else { return }
                    Task {
                        try? await model.ledger.insertVerdict(SafetyVerdictRow(entryId: id, textSha256: "snapshot", safetyVersion: SafetyGate.version,
                                                                              layer: 2, verdict: "safety_hold", reasonCode: "snapshot"))
                        await model.reload()
                    }
                }),
                // Capture (demo journal only, synthetic text, SR-28): a song from a link on the canvas and its view, then a page
                // started from a prompt with a question Saro asked under it, then that page edited on its card.
                ("capture-song", {
                    guard model.isDemo else { return }
                    model.openEntryID = nil
                    // The panel left open above would cover the song and the page edited on its card.
                    model.insight = .spine
                    model.goToday()
                    Task {
                        try? await Task.sleep(for: .seconds(0.8))
                        // The still held above is read again, which restates its clear verdict, so today isn't held.
                        if let s = model.entries.first(where: { $0.kind == .still }) { model.process(s.id) }
                        if let url = Music.link("https://music.apple.com/gb/album/a-night-at-the-opera/1440650428") { await model.newMusic(url: url, at: nil) }
                    }
                }),
                ("capture-songview", { model.openEntryID = model.entries.last(where: { $0.kind == .music })?.id }),
                ("capture-page", {
                    guard model.isDemo else { return }
                    model.openEntryID = nil
                    Task {
                        guard let e = await model.newWriting(body: "Walked home the long way. The river was loud after the rain and I kept thinking about the move.")
                        else { return }
                        try? await model.ledger.insertTurn(ReflectionTurn(kind: .prompt, question: "Which moment from today stands out?", generator: "curated",
                                                                          localDay: e.localDay, entryId: e.id))
                        try? await model.ledger.insertTurn(ReflectionTurn(kind: .reflectFurther, question: "You wrote “The river was loud after the rain”. What did that place give you?",
                                                                          generator: "heuristic", localDay: e.localDay, entryId: e.id))
                        await model.reload()
                        await CaptureUI.shared.loadPrompts(model)
                        model.openEntryID = e.id
                    }
                }),
                // A moment's two parts fanned out, each under the question it answered, with its words.
                ("capture-fan", {
                    guard model.isDemo else { return }
                    model.openEntryID = nil
                    Task {
                        let sid = UUID().uuidString
                        let parts = [("Which moment from today stands out?", "Walking home over the bridge after the rain. The river was loud and I stopped for a while."),
                                     ("What did the bridge give you?", "The quiet. Nobody needed anything from me for ten minutes.")]
                        for (i, (question, said)) in parts.enumerated() {
                            var e = Entry(kind: .moment, sessionId: sid, turnNumber: i + 1, capturedAt: .now.addingTimeInterval(Double(i * 60 - 900)),
                                          localDay: model.day, processingStatus: ProcessingStatus.done)
                            let a = MediaAsset(fileName: "\(e.localDay)/\(sid)/part-\(i + 1).mov", kind: .video, origin: "recorded", state: "ready",
                                               durationMs: [42_000, 28_000][i])
                            e.mediaId = a.id
                            try? await model.ledger.insertMedia(a)
                            try? await model.ledger.insertEntry(e)
                            try? await model.ledger.setTranscript(mediaId: a.id, words: said.split(separator: " ").enumerated().map {
                                TranscriptWord(text: String($0.element), startMs: $0.offset * 400, durMs: 380, confidence: 0.95)
                            }, extractorVersion: "snapshot")
                            try? await model.ledger.insertTurn(ReflectionTurn(kind: .prompt, question: question, generator: i == 0 ? "curated" : "heuristic",
                                                                              localDay: e.localDay, entryId: e.id, sessionId: sid, turnNumber: i + 1))
                        }
                        await model.reload()
                        await CaptureUI.shared.loadPrompts(model)
                        model.openStackID = sid
                    }
                }),
                ("capture-cardedit", {
                    guard let e = model.entries.last(where: { $0.kind == .reflection }) else { return }
                    model.openStackID = nil
                    model.openEntryID = nil
                    model.selection = [e.id]
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        CaptureUI.shared.editing = (e.id, .body)
                    }
                }),
                // The music field, grown out of its button over the bar.
                ("capture-music", {
                    CaptureUI.shared.editing = nil
                    model.selection = []
                    CaptureUI.shared.musicGrows = true
                    CaptureUI.shared.musicOpen = true
                }),
                // A page whose title alone trips the phrase gate: the title is gated with its words, so its day is held (SR-01).
                ("capture-titleheld", {
                    guard model.isDemo else { return }
                    CaptureUI.shared.musicOpen = false
                    Task {
                        let day = LocalDay.adding(-4, to: LocalDay.today())
                        let e = Entry(kind: .reflection, titleUser: "No point anymore", body: "Walked home the long way by the river after work.", localDay: day)
                        try? await model.ledger.insertEntry(e)
                        model.go(to: day)
                        model.process(e.id)
                        model.insight = .panel
                    }
                }),
                // Three weeks of synthetic history, seeded here so the steps before see only the demo day.
                ("knows", {
                    CaptureUI.shared.musicOpen = false
                    CaptureUI.shared.editing = nil
                    UserDefaults.standard.set("graph", forKey: "saro.knows.mode")
                    Task {
                        await MemoryDemo.seed(model)
                        model.pane = .knows
                    }
                }),
                ("knows-node", { NotificationCenter.default.post(name: pickNode, object: nil) }),
                ("knows-list", { UserDefaults.standard.set("list", forKey: "saro.knows.mode") }),
                ("knows-why", { NotificationCenter.default.post(name: showWhy, object: nil) }),
                ("knows-search", { model.memory.query = "anxious" }),
                ("knows-deleted", {
                    model.memory.query = ""
                    if let m = model.memory.memories.first(where: { $0.group == .people }) { model.memory.delete(m, undoManager: nil) }
                }),
                // Navigation: the time lens at each level, the date picker, the palette's start and an empty past day.
                ("nav-lens-week", {
                    model.pane = .day
                    (model.openEntryID, model.insight) = (nil, .spine)
                    model.openLens(level: .week, opener: .key)
                }),
                ("nav-lens-month", { model.lens?.go(to: .month, how: .instant) }),
                ("nav-lens-year", { model.lens?.go(to: .year, how: .instant) }),
                ("nav-lens-focus", {
                    model.lens?.go(to: .month, how: .instant)
                    model.lens?.move(.pageUp)
                }),
                ("nav-datepicker", {
                    model.lens?.close(how: .instant)
                    model.datePickerOpen = true
                }),
                ("nav-palette", {
                    model.datePickerOpen = false
                    model.searchOpen = true
                }),
                ("nav-empty-past", {
                    model.searchOpen = false
                    model.go(to: LocalDay.adding(-200, to: LocalDay.today()))
                }),
                ("nav-today", { model.goToday() }),
                // Opened by a pinch: the day has flown into its tile; then the X flies back out and the day is refitted.
                ("nav-lens-pinch", { model.openLens(level: .week, opener: .pinch) }),
                ("nav-lens-back", { model.lens?.close(how: .animated) }),
                // The day as narrow as the smallest window leaves it beside the sidebar: the bar takes two rows, and a toast
                // still sits 8 pt above it.
                ("nav-bar-narrow", {
                    p.setContentSize(NSSize(width: 570, height: 860))
                    // Set, not shown: a shown toast can time out before a loaded machine captures it.
                    model.toasts = [Toast("Saved Yesterday as an image")]
                }),
                ("nav-bar-wide", {
                    p.setContentSize(NSSize(width: 1320, height: 860))
                    model.toasts = []
                }),
                // ⌘K's Recent list on today.
                ("search", {
                    model.goToday()
                    model.searchOpen = true
                }),
                // The shell on the demo day: what Edit Details saved, on its cards; the toast stack, the account menu with a save
                // that failed, Trash over the bar
                // and as the pane, the Light Lab at dusk, the lock, and the day as Export Day as Image draws it.
                ("shell-details", { ShellSnapshots.details(model) }),
                ("shell-toasts", { ShellSnapshots.toasts(model) }),
                ("shell-account", { ShellSnapshots.accountMenu(model) }),
                ("shell-trash", { ShellSnapshots.trash(model) }),
                ("shell-trash-pane", {
                    ShellPanels.shared.panel = nil
                    model.pane = .trash
                }),
                ("shell-lightlab", {
                    model.pane = .day
                    ShellSnapshots.lightLab()
                }),
                ("shell-lock", { ShellSnapshots.lock() }),
                ("shell-dayimage", { ShellSnapshots.dayImage(model, dir: dir) }),
                // ⌘K's actions menu, then a day not yet loaded as it loads and as it couldn't be read, on its own ground
                // (the canvas's own load is too quick to catch). These leave the live UI, so they come after its states.
                ("actions", {
                    model.goToday()
                    model.pane = .day
                    paletteActions = true
                    model.searchOpen = true
                }),
                ("loading", {
                    model.searchOpen = false
                    model.day = LocalDay.adding(-2, to: LocalDay.today())
                    p.contentView = NSHostingView(rootView: DayStateView(day: model.day, empty: true, width: 1320)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Tok.bg).environment(model))
                }),
                ("loaderror", { model.loadFailed = true }),
                ("reflection-pieces", { p.contentView = NSHostingView(rootView: ReflectionGallery().environment(model)) }),
                // A commitment that trips the phrase gate: nothing kept, the note and Talk to someone instead.
                ("reflection-pieces-held", { Task { await model.reflection.addCommitment("Kill myself tomorrow") } }),
                ("grow", { p.contentView = NSHostingView(rootView: GrowGallery().environment(model)) }),
                ("capture-pieces", { p.contentView = NSHostingView(rootView: CaptureGallery().environment(model)) }),
                ("capture-failed", {
                    p.contentView = NSHostingView(rootView: FinishDialog(day: LocalDay.today(), paused: false, interrupted: false, keptParts: false,
                                                                         step: .constant(.failed), finish: {}, keepRecording: {}, discard: {}, reveal: {})
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(DevelopedFrame.gallery))
                }),
                ("foundation", { p.contentView = NSHostingView(rootView: FoundationGallery(profile: model.profile)) }),
                // Onboarding, each step hosted on its own flow (the demo journal itself skips onboarding).
                ("onboarding-welcome", { p.contentView = onboarding(.preview(step: .welcome), model) }),
                ("onboarding-q2", {
                    p.contentView = onboarding(.preview(step: .about, about: .question(2), answers: [1: "Bharat"],
                                                        text: "The launch. My sister Maya. Sleep, honestly."), model)
                }),
                ("onboarding-q5", { p.contentView = onboarding(.preview(step: .about, about: .question(5), answers: Self.answers, text: ""), model) }),
                ("onboarding-prompt", { p.contentView = onboarding(.preview(step: .about, about: .prompt, answers: Self.answers), model) }),
                ("onboarding-held", { p.contentView = onboarding(.preview(step: .about, about: .prompt, answers: Self.answers, held: [2]), model) }),
                ("onboarding-week", { p.contentView = onboarding(.preview(step: .firstWeek, answers: Self.answers), model) }),
                ("onboarding-light", { p.contentView = onboarding(.preview(step: .findLight, answers: Self.answers), model) }),
                ("onboarding-caution", { p.contentView = onboarding(.preview(step: .about, about: .prompt, answers: Self.answers, caution: [4]), model) }),
                ("onboarding-week-narrow", {
                    p.setContentSize(NSSize(width: 960, height: 860))
                    p.contentView = onboarding(.preview(step: .firstWeek, answers: Self.answers), model)
                }),
                // Text size 150%: the answer and the ritual time grow with the question, and the graph's labels keep apart.
                ("onboarding-text150-q2", {
                    PrefsStore.shared.textScale = 1.5
                    p.setContentSize(NSSize(width: 1320, height: 860))
                    p.contentView = onboarding(.preview(step: .about, about: .question(2), answers: [1: "Bharat"],
                                                        text: "The launch. My sister Maya. Sleep, honestly."), model)
                }),
                ("onboarding-text150-week", {
                    PrefsStore.shared.textScale = 1.5
                    p.contentView = onboarding(.preview(step: .firstWeek, answers: Self.answers), model)
                }),
                ("knows-text150", {
                    PrefsStore.shared.textScale = 1.5
                    UserDefaults.standard.set("graph", forKey: "saro.knows.mode")
                    model.memory.query = ""
                    model.pane = .knows
                    p.contentView = NSHostingView(rootView: RootView().environment(model))
                }),
                // The first reflection's hand-off: the page under its question, then the recorder's two surfaces.
                ("handoff-write", {
                    PrefsStore.shared.textScale = 1
                    p.setContentSize(NSSize(width: 1320, height: 860))
                    p.contentView = NSHostingView(rootView: RootView().environment(model))
                    Task { await model.startFirstReflection(.write) }
                }),
                ("handoff-recorder", {
                    model.openEntryID = nil
                    p.contentView = NSHostingView(rootView: HandoffGallery())
                }),
            ]
            // `-SaroSnapshotOnly <prefix>` runs only the states whose names start with it.
            let only = UserDefaults.standard.string(forKey: "SaroSnapshotOnly")
            for (name, apply) in steps + ShellSnapshots.galleries(p, model) + SettingsSnapshots.steps(p, model, dir) where only.map(name.hasPrefix) ?? true {
                apply()
                try? await Task.sleep(for: .seconds(2.5))
                if let v = p.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
                }
            }
            NSApp.terminate(nil)
        }
    }
}

/// Synthetic writings on a scatter of earlier days (none in the last four, which other states show), so the time lens has a
/// history to draw (SR-28: synthetic text only). The on-device model can't gate this many inside the snapshot delay, so
/// each carries a clear verdict for its own text and its day the person's own locked mood, which makes the day ready and
/// lets the tiles show their mood fills.
@MainActor private func seedHistory(_ model: AppModel) async {
    let lines = ["Walked by the river after work.", "Slow morning, good coffee.", "Long call with an old friend.",
                 "The team shipped the release.", "Rain all day; read on the sofa.", "Cooked dinner for everyone."]
    let moods: [Mood] = [.calm, .grateful, .reflective, .energised, .tender, .anxious, .inspired]
    for (i, back) in [5, 6, 8, 9, 12, 15, 16, 20, 23, 27, 31, 34, 40, 47, 55, 62, 70, 88, 120, 160].enumerated() {
        let day = LocalDay.adding(-back, to: LocalDay.today())
        let at = (LocalDay.date(day) ?? .now).addingTimeInterval(Double(i % 5) * 3600 + 9 * 3600)
        let writing = { (line: String, at: Date) in Entry(kind: .reflection, body: line, capturedAt: at, localDay: day, processingStatus: ProcessingStatus.done) }
        var entries = [writing(lines[i % lines.count], at)]
        if i % 3 == 0 { entries.append(writing(lines[(i + 2) % lines.count], at.addingTimeInterval(5400))) }
        for e in entries {
            try? await model.ledger.insertEntry(e)
            try? await model.ledger.insertVerdict(SafetyVerdictRow(entryId: e.id, textSha256: sha256(e.body ?? ""), safetyVersion: SafetyGate.version,
                                                                  layer: 1, verdict: "clear", reasonCode: "snapshot"))
        }
        try? await model.ledger.setUserMood(day: day, label: moods[i % moods.count], note: nil, verdict: nil)
    }
    await model.reload()
}

/// The letter is due at once and the first week started two days ago; yesterday left two commitments open, and the day
/// before is held (synthetic text, SR-28) with a commitment of its own.
@MainActor private func seedReflection(_ model: AppModel) async {
    PrefsStore.shared.letterMinutes = 0
    let twoAgo = LocalDay.adding(-2, to: LocalDay.today())
    PrefsStore.shared.weekStartedOn = twoAgo
    let held = Entry(kind: .reflection, body: "Some nights I just want to die.", capturedAt: .now.addingTimeInterval(-2 * 86_400), localDay: twoAgo)
    try? await model.ledger.insertEntry(held)
    model.process(held.id)
    _ = try? await model.ledger.addCommitment("Run the 5k", day: twoAgo)
    let yesterday = LocalDay.adding(-1, to: LocalDay.today())
    for text in ["Call Ravi about Pune.", "Book the dentist", "Walk home the long way"] {
        _ = try? await model.ledger.addCommitment(text, day: yesterday)
    }
    for text in ["Send the onboarding notes to the team", "Water the plants", "Stretch before bed", "Read one chapter"] {
        let c = try? await model.ledger.addCommitment(text, day: LocalDay.today())
        if text == "Water the plants", let c { try? await model.ledger.setDone(c.id, true) }
    }
}

/// Reflection's pieces that sit in popovers or below the panel's fold: Adjust emotion, the commitments card with its
/// carry-over, and the first week's notes.
private struct ReflectionGallery: View {
    private static let week = [
        WeekEntry(at: .now.addingTimeInterval(-2 * 86_400), words: "The launch slipped again and the team is tired.", quote: "the team is tired"),
        WeekEntry(at: .now.addingTimeInterval(-86_400), words: "Slept badly, then the launch meeting ran over.", quote: "the launch meeting ran over"),
        WeekEntry(at: .now, words: "Walked by the river after work. Felt lighter.", quote: "Walked by the river after work"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            AdjustMoodView(current: .reflective)
                .background(Tok.paper, in: .rect(cornerRadius: Radius.sheet))
                .elevation(.overlay)
            VStack(spacing: 16) {
                CommitmentsCard()
                FirstWeekNoteView(note: WeekMilestones.checkIn(goal: "sleep more"))
            }
            .frame(width: 330)
            VStack(spacing: 16) {
                if let pattern = WeekMilestones.firstPattern(Self.week) { FirstWeekNoteView(note: pattern) }
                FirstWeekNoteView(note: WeekMilestones.firstLetter(name: "Bharat", week: Self.week, carriesPattern: true))
            }
            .frame(width: 340)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tok.bg)
    }
}

/// Foundation's shared pieces, which no screen of their own shows yet: the reminder banner, the greeting, readiness and
/// the privacy copy.
private struct FoundationGallery: View {
    let profile: Profile?

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 16) {
                NotificationPreview(time: "9:30 PM")
                NotificationPreview(time: "7:15 AM").environment(\._accessibilityReduceTransparency, true)
                ForEach([0.0, 5, 8, 11, 13, 16, 18, 21, 23], id: \.self) { h in
                    Text("\(Greeting.eyebrow(hour: h).uppercased()) · \(Greeting.line(hour: h))").font(Typo.ui(12)).foregroundStyle(Tok.ink2)
                }
                Text(Readiness.model().line).font(Typo.ui(12)).foregroundStyle(Tok.ink2)
                Text("Prompt: \(profile.map { $0.tone.previewLine(name: $0.address) } ?? "no profile")").font(Typo.serif(15)).foregroundStyle(Tok.voice)
                Text("Onboarding done: \(profile?.onboardingDoneAt?.formatted() ?? "no")").font(Typo.mono(10)).foregroundStyle(Tok.ink3)
            }
            .frame(width: 380, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(PrivacyCopy.nfr02, id: \.self) { Text($0).font(Typo.serif(15)).foregroundStyle(Tok.ink) }
                ForEach(PrivacyCopy.promises) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.title).font(Typo.serif(18, .medium))
                        ForEach(p.body, id: \.self) { Text($0).font(Typo.ui(12)).foregroundStyle(Tok.ink2) }
                        Text(p.proofs.joined(separator: "  ·  ")).font(Typo.mono(10)).foregroundStyle(Tok.ink3)
                        Text(p.where).font(Typo.ui(11, .medium)).foregroundStyle(Tok.sageTeal)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tok.bg)
    }
}

/// The recorder's flight out of its bar button and back, frozen at a few points of the way (the real one never sits
/// still long enough to snapshot): the voice pill out, then back, then the moment frame out.
private struct GrowGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(.voice, out: true)
            row(.voice, out: false)
            row(.moment, out: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tok.bg)
    }

    private func row(_ kind: EntryKind, out: Bool) -> some View {
        let rest = kind == .voice ? CGRect(x: 30, y: 100, width: 380, height: 98) : CGRect(x: 20, y: 16, width: 400, height: 250)
        return HStack(spacing: 0) {
            ForEach([0.12, 0.3, 0.6], id: \.self) { v in
                surface(kind)
                    .modifier(GrowFlight(v: v, from: CGRect(x: 56, y: 214, width: 68, height: 52), to: rest, outbound: out, face: .of(kind)))
                    .offset(x: rest.minX, y: rest.minY)
                    .frame(width: 440, height: 286, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder private func surface(_ kind: EntryKind) -> some View {
        if kind == .voice {
            VoicePill(notice: nil, grows: true, kept: { _ in true }, close: {}, shut: {}).frame(width: 380)
        } else {
            Text("Getting your camera ready…").font(Typo.ui(13)).foregroundStyle(.white.opacity(0.8))
                .frame(width: 400, height: 250)
                .background(.black, in: .rect(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.1)))
        }
    }
}

/// The moment frame's top under the first reflection's question, as the recorder shows it (no camera or microphone is
/// asked for); the voice pill's line is the same question, in the capture gallery.
private struct HandoffGallery: View {
    private let prompt = "Bharat, the launch has been taking up a lot of room. How are you holding up?"

    var body: some View {
        HStack(alignment: .bottom, spacing: 40) {
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(white: 0.3), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                SaroVoice(question: prompt).padding(.top, 80).padding(.horizontal, 24).environment(\.colorScheme, .dark)
            }
            .frame(width: 720, height: 460)
            .clipShape(.rect(cornerRadius: 28))
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(Tok.bg)
    }
}

/// Capture's pieces that only a camera, a microphone or a drag would bring up, side by side: the moment frame at a
/// checkpoint, the finish dialog's steps, the held checkpoint, the developed frame, the drop overlay, the music field and
/// card, the voice pill's steps and Edit details (synthetic text, SR-28).
private struct CaptureGallery: View {
    @Environment(AppModel.self) private var model
    private static let words = "I walked home the long way and the river was loud after the rain so I stopped on the bridge for a while"
        .split(separator: " ").map { LiveWord(text: String($0), final: true) }
    private static let song = Entry(kind: .music, body: "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC")

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 20) {
                frame {
                    VStack(spacing: 0) {
                        SaroVoice(question: "What did the bridge give you?", observation: "You came back to the river twice there.",
                                  followUp: true, orb: .talking, instant: true)
                            .padding(.top, 40)
                        Spacer()
                        GlassNotice(text: "Click Pause & reflect (or press R) when you want Saro to respond.")
                        CaptionStatus(text: nil)
                        LiveCaptions(words: Self.words, placeholder: nil, size: 19).frame(width: 520)
                        Button("Keep going") {}.buttonStyle(CaptureButtonStyle.mint).padding(.vertical, 18)
                    }
                }
                frame {
                    VStack {
                        SaroVoice(question: "Bharat, which moment from today stands out?")
                            .padding(.top, 40)
                        Spacer()
                        CaptionStatus(text: CaptureController.Live.connecting.line(paused: false, voice: false), connecting: true)
                        LiveCaptions(words: [], placeholder: "Your words will appear here as you speak.").frame(width: 520).padding(.bottom, 30)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 20) {
                ForEach([FinishDialog.Step.confirm, .discard], id: \.self) { step in
                    FinishDialog(day: LocalDay.today(), paused: true, interrupted: false, keptParts: step == .discard, step: .constant(step),
                                 finish: {}, keepRecording: {}, discard: {})
                        .frame(width: 520, height: 250)
                        .background(Color(0x223029, 0x223029), in: .rect(cornerRadius: 20))
                }
                NightSafetyCard {}.frame(width: 520, height: 360).background(.black, in: .rect(cornerRadius: 20))
            }
            VStack(alignment: .leading, spacing: 20) {
                DropOverlay(kind: .moment, day: LocalDay.today()).frame(width: 440, height: 250)
                    .background(Tok.bg, in: .rect(cornerRadius: 20))
                MusicField().frame(width: 440, height: 200).background(Tok.bg, in: .rect(cornerRadius: 20))
                MusicFace(entry: Self.song, box: CanvasMath.size(.music)).padding(8)
                VoicePill(notice: nil, kept: { _ in true }, close: {}, shut: {}).frame(width: 380)
                VoiceReview(again: {}, discard: {}, keep: {}).frame(width: 380)
                    .background(Night.surface, in: .rect(cornerRadius: 28)).environment(\.colorScheme, .dark)
                EditDetailsSheet(entry: Self.song).clipShape(.rect(cornerRadius: 20)).elevation(.overlay)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tok.bg)
    }

    private func frame(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack {
            DevelopedFrame.gallery
            LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
            Color.black.opacity(0.4)
            content().environment(\.colorScheme, .dark)
        }
        .frame(width: 600, height: 390)
        .clipShape(.rect(cornerRadius: 28))
    }
}

extension DevelopedFrame {
    /// A stand-in for a camera frame: warm dusk light.
    static var gallery: some View {
        LinearGradient(colors: [Color(0x6B4B3A, 0x6B4B3A), Color(0x2D3B36, 0x2D3B36)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Snapshots {
    static let answers = [1: "Bharat", 2: "The launch. My sister.", 3: "Late, usually. Around 10:40", 4: "More sleep, less rehearsing conversations",
                          5: "Straight to it"]

    static func onboarding(_ flow: OnboardingFlow, _ model: AppModel) -> NSView {
        NSHostingView(rootView: OnboardingView(flow: flow).environment(model).environment(PrefsStore.shared))
    }
}

private extension Double {
    func clamped(to r: ClosedRange<Double>) -> Double { self == 0 ? 20 : Swift.min(Swift.max(self, r.lowerBound), r.upperBound) }
}
#endif
