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
                    .task { await model.reload() }
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
    }
}

struct SettingsView: View {
    @AppStorage("videoQuality") private var videoQuality = "720p"

    var body: some View {
        Form {
            Picker("Video quality", selection: $videoQuality) {
                Text("720p HEVC (default)").tag("720p")
                Text("1080p HEVC").tag("1080p")
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
