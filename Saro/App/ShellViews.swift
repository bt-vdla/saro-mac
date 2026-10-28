import AppKit
import SaroKit
import SwiftUI

/// Trash (DR-15): soft-deleted entries, restorable one by one. ponytail: no purge yet; the 30-day purge comes with backups.
struct TrashView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [Entry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Trash").font(Typo.serif(26, .medium)).padding(.horizontal, 28).padding(.top, 24)
            Text("Entries you deleted stay here and can be restored. Their recordings are kept.")
                .font(Typo.ui(13)).foregroundStyle(Tok.ink3).padding(.horizontal, 28).padding(.bottom, 12)
            if items.isEmpty {
                ContentUnavailableView("Trash is empty", systemImage: "trash")
            } else {
                List(items) { e in
                    HStack(spacing: 12) {
                        Image(systemName: e.kind.symbol).foregroundStyle(e.kind.tint).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.titleUser ?? e.body?.split(separator: "\n").first.map(String.init) ?? e.kind.noun)
                                .font(Typo.ui(13, .medium)).lineLimit(1)
                            Text("\(DayFormat.sidebar(e.localDay).uppercased()) · DELETED \(e.trashedAt?.formatted(date: .abbreviated, time: .shortened).uppercased() ?? "")")
                                .font(Typo.mono(9.5)).foregroundStyle(Tok.ink3)
                        }
                        Spacer()
                        Button("Restore") {
                            Task {
                                try? await model.ledger.restore(ids: [e.id])
                                await load()
                                await model.reload()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tok.bg)
        .task { await load() }
        .onAppear { model.screen = .trash }
    }

    private func load() async { items = (try? await model.ledger.trashed()) ?? [] }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("videoQuality") private var videoQuality = "720p"
    @AppStorage("tourSeen") private var tourSeen = false
    @State private var previousScreen: ScreenID = .canvas

    var body: some View {
        TabView {
            Form {
                Picker("Video quality", selection: $videoQuality) {
                    Text("720p HEVC (default)").tag("720p")
                    Text("1080p HEVC").tag("1080p")
                }
                LabeledContent("Quick capture", value: "⌃⌘J from anywhere, or the menu bar")
                LabeledContent("Writing Tools", value: "Off in Saro's editors")
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            Form { DaylightPicker() }
                .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }

            Form {
                LabeledContent("Model", value: model.ai.variant)
                LabeledContent("Status", value: model.ai.status == .available ? "Available on this Mac" : "Unavailable")
                LabeledContent("Context", value: "\(model.ai.contextSize) tokens")
                LabeledContent("macOS build", value: SaroAI.osBuild)
                LabeledContent("Routes", value: "On-device only. Nothing leaves this Mac.")
            }
            .tabItem { Label("Intelligence", systemImage: "sparkles") }

            Form {
                LabeledContent("Journal", value: model.isDemo ? "Demo (temporary)" : "Application Support/Saro")
                Button("Export Everything…") { Task { await model.exportEverything() } }
                Button("Show Journal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.ledger.rootURL]) }
                Button("Take the Tour Again") { tourSeen = false }
            }
            .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 320)
        .onAppear {
            previousScreen = model.screen
            model.screen = .settings
        }
        // Unless the main window moved on meanwhile, its screen is current again once Settings closes.
        .onDisappear { if model.screen == .settings { model.screen = previousScreen } }
    }
}

extension AppModel {
    /// Export everything (DR-20): a `.saroexport` folder with every ledger row as JSON plus the media files.
    func exportEverything() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose where to put the Saro export. It contains your words and recordings."
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let name = "Saro-\(LocalDay.today()).saroexport"
        let dest = dir.appending(path: name, directoryHint: .isDirectory)
        do {
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            try await ledger.exportJSON(to: dest.appending(path: "saro.json"))
            try FileManager.default.copyItem(at: ledger.mediaURL, to: dest.appending(path: "Media"))
            show(Toast("Exported to \(dir.lastPathComponent)/\(name)"))
        } catch {
            show(Toast("Export failed: \(error.localizedDescription)", style: .error))
        }
    }
}
