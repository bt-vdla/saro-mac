import SaroKit
import SwiftUI

@main
struct SaroApp: App {
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

struct SaroCommands: Commands {
    let model: AppModel

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
            Button("If You're Struggling…") { NotificationCenter.default.post(name: .showSafetyCard, object: nil) }
        }
        CommandGroup(after: .importExport) {
            Button("Export Everything…") { Task { await model.exportEverything() } }
        }
    }
}
