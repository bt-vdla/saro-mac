import SaroKit
import SwiftUI

@main
struct SaroApp: App {
    @State private var boot = AppModel.boot()

    var body: some Scene {
        Window("Saro", id: "main") {
            switch boot {
            case .success(let model):
                RootView()
                    .environment(model)
                    .task { await model.sweep() }
            case .failure(let error):
                ContentUnavailableView("Saro couldn't open its journal", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(error.localizedDescription))
            }
        }
        .defaultSize(width: 1320, height: 860)
        .windowToolbarStyle(.unifiedCompact)
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
    }
}

struct SaroCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Go") {
            Button("Today") { model.goToday() }.keyboardShortcut("t", modifiers: .command)
            Button("Previous Day") { model.goPrevious() }.keyboardShortcut("[", modifiers: .command)
            Button("Next Day") { model.goNext() }.keyboardShortcut("]", modifiers: .command)
        }
        CommandGroup(before: .help) {
            Button("If You're Struggling…") { NotificationCenter.default.post(name: .showSafetyCard, object: nil) }
        }
        CommandGroup(after: .importExport) {
            Button("Export Everything…") { Task { await model.exportEverything() } }
        }
    }
}
