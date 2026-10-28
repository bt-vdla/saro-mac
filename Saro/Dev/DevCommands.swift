#if DOGFOOD
import AppKit
import Observation
import SaroKit
import SwiftUI

/// Dev mode state: the decision events and screen notes read from the ledger, and the tour's position.
@Observable @MainActor
final class DevMode {
    // ponytail: one per process like AppModel, so the menu commands and the root view share it without wiring.
    static let shared = DevMode()

    var events: [DecisionEvent] = []
    var notes: [ScreenNote] = []
    /// The decision the Decisions pane scrolls to and highlights.
    var focus: String?
    /// The screen a decision was opened from, recorded on its events instead of `dev.decisions`.
    var cameFrom: ScreenID?
    /// Index into the tour's available steps; nil when the tour isn't running.
    var tourStep: Int?

    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    static var gitCommit: String { Bundle.main.object(forInfoDictionaryKey: "SaroGitCommit") as? String ?? "unknown" }

    func load(_ model: AppModel) async {
        do {
            events = try await model.ledger.decisionEvents()
            notes = try await model.ledger.screenNotes()
        } catch {
            model.show(.failed("Couldn't read decisions", error))
        }
    }

    func record(_ decisionId: String, choice: String?, note: String, model: AppModel) async -> Bool {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = DecisionEvent(decisionId: decisionId, choice: choice, note: note.isEmpty ? nil : note,
                              screenId: (cameFrom ?? model.screen).rawValue, appVersion: Self.appVersion)
        do {
            try await model.ledger.appendDecisionEvent(e)
            events.append(e)
            model.show(Toast("Recorded \(decisionId)"))
            return true
        } catch {
            model.show(.failed("Couldn't record \(decisionId)", error))
            return false
        }
    }

    func addNote(_ text: String, screen: ScreenID, model: AppModel) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let n = ScreenNote(screenId: screen.rawValue, note: text, appVersion: Self.appVersion)
        do {
            try await model.ledger.appendScreenNote(n)
            notes.append(n)
            return true
        } catch {
            model.show(.failed("Couldn't save the note", error))
            return false
        }
    }

    func open(_ decisionId: String, model: AppModel) {
        cameFrom = model.screen
        focus = decisionId
        model.pane = .decisions
    }

    private var stamp: DevExport.Stamp { DevExport.Stamp(appVersion: Self.appVersion, gitCommit: Self.gitCommit) }
    private var markdown: String { DevExport.markdown(decisions: Decision.all, events: events, notes: notes, stamp: stamp) }
    private var json: String { DevExport.json(decisions: Decision.all, events: events, notes: notes, stamp: stamp) }

    func copy(_ model: AppModel) async {
        await load(model)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        model.show(Toast("Copied"))
    }

    /// Writes both files into a folder the user picks (the sandbox grants it through the open panel).
    func export(_ model: AppModel) async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export Here"
        panel.message = "Saro writes \(DevExport.jsonName) and \(DevExport.markdownName) into this folder."
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        await load(model)
        do {
            try json.write(to: dir.appending(path: DevExport.jsonName), atomically: true, encoding: .utf8)
            try markdown.write(to: dir.appending(path: DevExport.markdownName), atomically: true, encoding: .utf8)
            model.show(Toast("Exported decisions to \(dir.lastPathComponent)"))
        } catch {
            model.show(.failed("Couldn't export the decisions", error))
        }
    }

    func startTour(_ model: AppModel) {
        model.pane = .day
        model.devNotesVisible = false
        tourStep = 0
    }

    func endTour() {
        tourStep = nil
        OnboardingFlow.defaults.set(true, forKey: "tourSeen")
    }
}

struct DevCommands: Commands {
    let model: AppModel

    var body: some Commands {
        @Bindable var model = model
        CommandGroup(after: .importExport) {
            Button("Export Decisions for Claude…") { Task { await DevMode.shared.export(model) } }
                .keyboardShortcut("e", modifiers: [.shift, .command])
            Button("Copy Decisions for Claude") { Task { await DevMode.shared.copy(model) } }
        }
        CommandGroup(after: .sidebar) {
            Toggle("Dev Notes", isOn: $model.devNotesVisible)
                .keyboardShortcut("d", modifiers: [.shift, .command])
        }
        CommandGroup(after: .help) {
            Button("Take the Tour") { DevMode.shared.startTour(model) }.disabled(model.showsOnboarding)
        }
        CommandMenu("Developer") {
            @Bindable var flags = DevFlags.shared
            Toggle("Simulate Apple Intelligence Unavailable", isOn: $flags.simulateAIUnavailable)
            Toggle("Simulate Write Failures", isOn: $flags.simulateWriteFailures)
            Divider()
            // ⌃⌥L: ⌥L alone types ¬ (or @) in a text field.
            Toggle("Light Lab", isOn: $flags.lightLab).keyboardShortcut("l", modifiers: [.control, .option])
            Divider()
            Button("Replay Onboarding") { Task { await model.replayOnboarding() } }.disabled(model.showsOnboarding)
            Divider()
            if model.isDemo {
                Button("Reset Demo Journal…") { DevFlags.confirmReset(model) }
                Button("Leave Demo Journal") { DevFlags.relaunch(demo: false) }
            } else {
                Button("Open Demo Journal") { DevFlags.relaunch(demo: true) }
            }
        }
    }
}

/// The Developer menu's switches (ProfileMenuPanel.tsx's Demo section). They last for this launch only.
@Observable @MainActor
final class DevFlags {
    static let shared = DevFlags()

    /// Every tracked write fails, so the save status and the failure toasts can be seen.
    var simulateWriteFailures = false
    var simulateAIUnavailable = false { didSet { SaroAI.simulatedUnavailable.withLock { $0 = simulateAIUnavailable } } }
    var lightLab = UserDefaults.standard.string(forKey: "SaroHour") != nil

    static var simulateWriteFailures: Bool { shared.simulateWriteFailures }

    /// Open Demo Journal starts a new Saro on a throwaway journal (-SaroDemo YES); Leave starts one on the real journal.
    static func relaunch(demo: Bool) {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = demo ? ["-SaroDemo", "YES"] : []
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    static func confirmReset(_ model: AppModel) {
        let alert = NSAlert()
        alert.messageText = "Erase the demo journal and seed it again?"
        alert.informativeText = "Only this launch's throwaway journal is erased. Your own journal isn't touched."
        alert.addButton(withTitle: "Erase and Seed")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await DemoJournal.reset(model) }
    }
}

/// The Developer items at the foot of the account menu.
struct DeveloperItems: View {
    @Environment(AppModel.self) private var model
    var focus: FocusState<Int?>.Binding
    static let rows = [10, 11, 13, 14, 15]

    var body: some View {
        let flags = DevFlags.shared
        MenuDivider()
        Text("DEVELOPER").font(Typo.mono(10)).tracking(1.1).foregroundStyle(Tok.ink3).padding(.horizontal, 12).padding(.vertical, 4)
        MenuRow(check(flags.simulateWriteFailures, "Simulate write failures"), symbol: "externaldrive.badge.xmark", index: 10, focus: focus,
                closes: false) { flags.simulateWriteFailures.toggle() }
        MenuRow(check(flags.simulateAIUnavailable, "Simulate Apple Intelligence unavailable"), symbol: "bolt.slash", index: 11, focus: focus,
                closes: false) { flags.simulateAIUnavailable.toggle() }
        MenuRow("Light Lab", symbol: "sun.horizon", keys: "⌃⌥L", index: 13, focus: focus) { flags.lightLab.toggle() }
        MenuRow("Replay onboarding", symbol: "arrow.counterclockwise", index: 14, focus: focus) { Task { await model.replayOnboarding() } }
        if model.isDemo {
            MenuRow("Reset demo journal…", symbol: "eraser", index: 15, focus: focus) { DevFlags.confirmReset(model) }
        } else {
            MenuRow("Open demo journal", symbol: "flask", index: 15, focus: focus) { DevFlags.relaunch(demo: true) }
        }
    }

    private func check(_ on: Bool, _ title: String) -> String { on ? "\(title) ✓" : title }
}

extension View {
    /// The dev notes panel, the DEV pill and the tour overlay, over everything at the root.
    func devMode() -> some View { modifier(DevModeLayer()) }
}

private struct DevModeLayer: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if model.devNotesVisible {
                    DevNotesPanel().transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !model.devNotesVisible {
                    Button { model.devNotesVisible = true } label: {
                        Text("DEV NOTES ⇧⌘D")
                            .font(Typo.mono(9.5))
                            .tracking(0.6)
                            .foregroundStyle(Tok.ink2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .saroSurface(radius: 999)
                    }
                    .buttonStyle(.plain)
                    .help("Dev notes for this screen")
                    .tourAnchor(.devNotes)
                    .padding(14)
                }
            }
            .overlay(alignment: .top) { if DevFlags.shared.lightLab { LightLab() } }
            .overlayPreferenceValue(TourAnchorKey.self) { TourOverlay(anchors: $0) }
            .animation(Motion.pick(Motion.open, reduce: reduceMotion), value: model.devNotesVisible)
            .task { await DevMode.shared.load(model) }
            // The first tour waits for onboarding to hand off and for the first recording or page to close. A demo run's
            // tour is seen in the demo's own defaults, so it never hides the real journal's.
            .task(id: model.showsOnboarding || model.handoffPrompt != nil || model.recorderKind != nil || model.openEntryID != nil) {
                guard !model.showsOnboarding, model.handoffPrompt == nil, model.recorderKind == nil, model.openEntryID == nil,
                      DevMode.shared.tourStep == nil, !OnboardingFlow.defaults.bool(forKey: "tourSeen") else { return }
                try? await Task.sleep(for: .milliseconds(600))
                if !Task.isCancelled { DevMode.shared.startTour(model) }
            }
    }
}
#endif
