import SaroKit
import SwiftUI

@main
struct SaroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var boot: Result<AppModel, Error>

    init() {
        Daylight.shared.start()
        let boot = AppModel.boot()
        _boot = State(initialValue: boot)
        // At launch, not when the window appears: Saro can start without it (macOS restores a window closed at quit),
        // and ⌃⌘J, the menu bar's capture and the launch sweep mustn't wait until it opens.
        if case .success(let model) = boot {
            CapturePanelController.shared.install(model)
            Task { await model.sweep() }
            #if DOGFOOD
            // Here rather than on the window, which macOS never opens while the screen is locked.
            if UserDefaults.standard.string(forKey: "SaroSnapshot") != nil {
                Task { await model.loadProfile() }
                Snapshots.runIfRequested(model)
            }
            #endif
        }
    }

    var body: some Scene {
        Window("Saro", id: "main") {
            switch boot {
            case .success(let model):
                RootView()
                    .environment(model)
                    .environment(PrefsStore.shared)
                    .comfortEnvironment()
                    .deepLinks(model)
                    .task { await model.loadProfile() }
                    .task { await model.sweep() }
                    #if DOGFOOD
                    .task { Scenarios.runIfRequested(model) }
                    #endif
            case .failure(let error):
                RecoveryView(error: error) {
                    boot = AppModel.boot()
                    if case .success(let model) = boot { CapturePanelController.shared.install(model) }
                }
            }
        }
        .defaultSize(width: 1320, height: 860)
        // Always open the journal at launch: a window closed before quitting must not come back closed.
        .restorationBehavior(.disabled)
        .windowStyle(.hiddenTitleBar)
        .commands {
            if case .success(let model) = boot {
                SaroCommands(model: model)
                #if DOGFOOD
                DevCommands(model: model)
                #endif
            }
        }

        Settings {
            if case .success(let model) = boot {
                SettingsWindow().environment(model).environment(PrefsStore.shared).comfortEnvironment().overlay { LockScreen() }
            }
        }
        .defaultSize(width: 920, height: 720)
        .windowResizability(.contentMinSize)

        Window("About Saro", id: "about") { AboutView().comfortEnvironment() }
            .windowResizability(.contentSize)
            .windowStyle(.hiddenTitleBar)
            .restorationBehavior(.disabled)
        Window("Keyboard Shortcuts", id: "shortcuts") { ShortcutsView().comfortEnvironment() }
            .defaultSize(width: 720, height: 620)
            .restorationBehavior(.disabled)
        Window("Acknowledgements", id: "acknowledgements") { AcknowledgementsView().comfortEnvironment() }
            .defaultSize(width: 600, height: 640)
            .restorationBehavior(.disabled)

        SaroMenuBar()
    }
}

/// Quitting mid-recording (⌘Q, the menu bar, logout) stops the turn first: AVFoundation writes the open movie fragment,
/// up to the last 2 s or all of a short turn, only when recording stops.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let capture = CaptureController.shared
        guard let owner = capture.owner else { return .terminateNow }
        capture.finish(owner)
        Task {
            // ponytail: polls until the turn is saved and the camera is off; capped so a file that never finishes can't block quitting.
            let deadline = ContinuousClock.now + .seconds(10)
            while capture.owner != nil, .now < deadline { try? await Task.sleep(for: .milliseconds(50)) }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillFinishLaunching(_ notification: Notification) { Reminders.shared.install() }
}

struct SaroCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Saro") { openWindow(id: "about") }
        }
        CommandGroup(after: .appSettings) {
            Button("Lock Saro") { Locker.shared.lock() }
                .keyboardShortcut("l", modifiers: [.control, .command])
                .disabled(!PrefsStore.shared.lockEnabled || Locker.shared.locked)
        }
        CommandMenu("Entry") { EntryCommands(model: model).disabled(Locker.shared.locked) }
        CommandMenu("Go") {
            Group {
                Button("Search…") { model.searchOpen.toggle() }.keyboardShortcut("k", modifiers: .command)
                Divider()
                Button("Today") { model.goToday() }.keyboardShortcut("t", modifiers: .command)
                // During onboarding ⌘[ and ⌘] are its own Previous and Next Step, so these give the keys up.
                Button("Previous Day") { model.goPrevious() }.keyboardShortcut(model.showsOnboarding ? nil : KeyboardShortcut("[", modifiers: .command))
                Button("Next Day") { model.goNext() }.keyboardShortcut(model.showsOnboarding ? nil : KeyboardShortcut("]", modifiers: .command))
                Divider()
                Button("What Saro Knows") { model.pane = .knows }.keyboardShortcut("k", modifiers: [.command, .option])
            }
            .disabled(model.showsOnboarding || Locker.shared.locked)
        }
        CommandGroup(after: .toolbar) {
            Group {
                Button("Zoom In") { model.camera = .zoom(1.25, UUID()) }.keyboardShortcut("=", modifiers: .command)
                Button("Zoom Out") { model.camera = .zoom(0.8, UUID()) }.keyboardShortcut("-", modifiers: .command)
                Button("Show Days") { model.sidebarVisible.toggle() }.keyboardShortcut("s", modifiers: [.command, .control])
                Divider()
                Button("What Saro Noticed") {
                    model.pane = .day
                    model.insight = model.insight == .panel ? .spine : .panel
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                Button("Evening Letter") {
                    model.pane = .day
                    model.insight = model.insight == .letter ? .spine : .letter
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                Button("Read the Day Again") { Task { await model.reflection.refreshInsights() } }
                    .disabled(!model.reflection.canRefresh)
            }
            .disabled(model.showsOnboarding || Locker.shared.locked)
        }
        CommandGroup(before: .help) {
            Button("If You're Struggling…") {
                // The main window may be closed (Saro runs from the menu bar); the card shows once it opens.
                openWindow(id: "main")
                model.safetyCardRequested = true
            }
            Button("Keyboard Shortcuts") { openWindow(id: "shortcuts") }.keyboardShortcut("/", modifiers: .command)
            Button("Privacy") { model.open(DeepLink.settings("data").url) }
            Button("Acknowledgements") { openWindow(id: "acknowledgements") }
        }
        CommandGroup(after: .importExport) {
            Group {
                Button("Export Day as Image…") { Task { await model.exportDayImage() } }
                    .disabled(model.pane != .day || model.entries.isEmpty)
                Button("Export Everything…") { Task { await model.exportEverything() } }
                Button("Import…") { Task { await model.importJournal() } }
            }
            .disabled(model.showsOnboarding || Locker.shared.locked)
        }
    }
}
