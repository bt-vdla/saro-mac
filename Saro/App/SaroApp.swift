import SaroKit
import SwiftUI

@main
struct SaroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var boot = AppModel.boot()

    init() {
        Daylight.shared.start()
    }

    var body: some Scene {
        Window("Saro", id: "main") {
            switch boot {
            case .success(let model):
                RootView()
                    .environment(model)
                    .task { await model.sweep() }
                    .task { CapturePanelController.shared.install(model) }
                    #if DOGFOOD
                    .task { Snapshots.runIfRequested(model) }
                    .task { Scenarios.runIfRequested(model) }
                    #endif
            case .failure(let error):
                ContentUnavailableView("Saro couldn't open its journal", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(error.localizedDescription))
            }
        }
        .defaultSize(width: 1320, height: 860)
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
            if case .success(let model) = boot { SettingsView().environment(model) }
        }

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
}

struct SaroCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Go") {
            Button("Search…") { model.searchOpen.toggle() }.keyboardShortcut("k", modifiers: .command)
            Divider()
            Button("Today") { model.goToday() }.keyboardShortcut("t", modifiers: .command)
            Button("Previous Day") { model.goPrevious() }.keyboardShortcut("[", modifiers: .command)
            Button("Next Day") { model.goNext() }.keyboardShortcut("]", modifiers: .command)
        }
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { model.camera = .zoom(1.25, UUID()) }.keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { model.camera = .zoom(0.8, UUID()) }.keyboardShortcut("-", modifiers: .command)
            Button("Show Days") { model.sidebarVisible.toggle() }.keyboardShortcut("s", modifiers: [.command, .control])
        }
        CommandGroup(before: .help) {
            Button("If You're Struggling…") {
                // The main window may be closed (Saro runs from the menu bar); the card shows once it opens.
                openWindow(id: "main")
                model.safetyCardRequested = true
            }
        }
        CommandGroup(after: .importExport) {
            Button("Export Everything…") { Task { await model.exportEverything() } }
        }
    }
}
