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
                // Three weeks of synthetic history, seeded here so the steps before see only the demo day.
                ("knows", {
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
                // ⌘K's Recent list on today, then Trash with today's first page in it.
                ("search", {
                    model.goToday()
                    model.searchOpen = true
                }),
                ("trash-pane", {
                    model.searchOpen = false
                    Task {
                        if let e = model.entries.first(where: { $0.kind == .reflection }) { await model.trash([e.id]) }
                        model.pane = .trash
                    }
                }),
                // ⌘K's actions menu, then a day not yet loaded as it loads and as it couldn't be read, on its own ground
                // (the canvas's own load is too quick to catch). These leave the live UI, so they come after its states.
                ("actions", {
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
                ("grow", { p.contentView = NSHostingView(rootView: GrowGallery()) }),
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
            for (name, apply) in steps + SettingsSnapshots.steps(p, model, dir) where only.map(name.hasPrefix) ?? true {
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
            VoicePill(notice: nil, inSession: false, grows: true, toggle: {}, done: {}, close: {}).frame(width: 380)
        } else {
            Text("Getting your camera ready…").font(Typo.ui(13)).foregroundStyle(.white.opacity(0.8))
                .frame(width: 400, height: 250)
                .background(.black, in: .rect(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.1)))
        }
    }
}

/// The recorder's surfaces under the first reflection's question (no camera or microphone is asked for): the moment
/// frame's top, and the voice pill with its card.
private struct HandoffGallery: View {
    private let prompt = "Bharat, the launch has been taking up a lot of room. How are you holding up?"

    var body: some View {
        HStack(alignment: .bottom, spacing: 40) {
            ZStack {
                LinearGradient(colors: [Color(white: 0.3), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                MomentPrompt(prompt: prompt, dimmed: false)
            }
            .frame(width: 720, height: 460)
            .clipShape(.rect(cornerRadius: 28))
            VoicePill(notice: nil, inSession: false, grows: true, prompt: prompt, toggle: {}, done: {}, close: {}).frame(width: 380)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(Tok.bg)
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
