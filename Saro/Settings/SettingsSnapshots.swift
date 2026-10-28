#if DOGFOOD
import AppKit
import SaroKit
import SwiftUI

/// Settings' states for `-SaroSnapshot`: every section, Say it with a proposal, the narrow layout, and the main
/// screens at 150% text. Also checks two things a PNG can't show: that Comfort's switches reach a child view
/// (comfort-probe.txt), and that the Book binds to HTML and PDF (book-of-<year>.html, .pdf).
@MainActor
enum SettingsSnapshots {
    static func steps(_ p: NSPanel, _ model: AppModel, _ dir: String) -> [(String, @MainActor () -> Void)] {
        let prefs = PrefsStore.shared
        // The section is set once the new window is up, so the one it replaces can't take the link first.
        func host(_ section: SettingsSection?, width: CGFloat = 920) {
            p.setContentSize(NSSize(width: width, height: 760))
            p.contentView = NSHostingView(rootView: SettingsWindow().environment(model).environment(prefs).comfortEnvironment())
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                prefs.settingsSection = section
            }
        }
        return [
            ("comfort-probe", {
                (prefs.reduceMotion, prefs.reduceTransparency) = (true, true)
                p.contentView = NSHostingView(rootView: ComfortProbe(dir: dir).comfortEnvironment())
            }),
            ("settings-top", {
                (prefs.reduceMotion, prefs.reduceTransparency) = (false, false)
                host(nil)
            }),
            ("settings-sayit", {
                SayItBar.propose = "remind me at half past nine and bigger text, be more direct"
                host(nil)
            }),
            // Words that match no setting: the example chips, once the on-device model, where ready, finds nothing either.
            ("settings-sayit-none", {
                SayItBar.propose = "zqxv"
                host(nil)
            }),
            // Words the phrase gate holds: the SafetyCard, never a setting or the example chips (synthetic text).
            ("settings-sayit-held", {
                SayItBar.propose = "turn off reminders, there is no point anymore"
                host(nil)
            }),
            ("settings-talk", { host(.talk) }),
            ("settings-rhythm", {
                RhythmSection.sampleFirst = true
                host(.rhythm)
            }),
            ("settings-appearance", { host(.appearance) }),
            ("settings-comfort", { host(.comfort) }),
            ("settings-knows", { host(.knows) }),
            ("settings-intelligence", { host(.intelligence) }),
            ("settings-data", {
                bindBook(model, dir)
                host(.data)
            }),
            ("settings-narrow", { host(.rhythm, width: 680) }),
            // Your data whole, so the export, book, What Saro read and erase rows can be seen.
            ("settings-data-full", {
                p.setContentSize(NSSize(width: 760, height: 2400))
                p.contentView = NSHostingView(rootView: DataSection().padding(32).frame(width: 760, height: 2400, alignment: .top).background(Tok.bg)
                    .environment(model).environment(prefs).comfortEnvironment())
            }),
            ("text150-settings", {
                prefs.textScale = 1.5
                host(.you)
            }),
            ("text150-canvas", {
                p.setContentSize(NSSize(width: 1320, height: 860))
                p.contentView = NSHostingView(rootView: RootView().environment(model).environment(prefs).comfortEnvironment())
                // The knows-* steps leave What Saro knows up.
                model.pane = .day
                model.openEntryID = nil
                model.insight = .spine
            }),
            ("text150-detail", { model.openEntryID = model.entries.first { $0.kind == .reflection }?.id }),
            ("text150-noticed", {
                model.openEntryID = nil
                model.showNoticed = true
            }),
            ("text150-letter", { model.showLetter = true }),
            // Saro's own Reduce transparency: the search pill, the spine and the scrims go solid.
            ("solid-canvas", {
                model.showLetter = false
                prefs.textScale = 1
                prefs.reduceTransparency = true
            }),
        ]
    }

    private static func bindBook(_ model: AppModel, _ dir: String) {
        Task {
            let year = Calendar.current.component(.year, from: .now)
            let html = Book.build(year: year, name: model.profile?.address, days: (try? await model.ledger.bookDays(year: year)) ?? [])
            try? Data(html.utf8).write(to: URL(fileURLWithPath: "\(dir)/\(Book.fileName(year))"))
            do { try await BookPDF.write(html, to: URL(fileURLWithPath: "\(dir)/saro-book-of-\(year).pdf")) } catch {
                try? "PDF failed: \(error.localizedDescription)\n".write(toFile: "\(dir)/book-pdf-error.txt", atomically: true, encoding: .utf8)
            }
        }
    }
}

/// Reads what a child sees once `comfortEnvironment` is applied with both of Saro's switches on.
private struct ComfortProbe: View {
    let dir: String
    @Environment(\.accessibilityReduceMotion) private var motion
    @Environment(\.accessibilityReduceTransparency) private var transparency

    var body: some View {
        // Every reading is appended: on while the switches are on, then off once the next step turns them off.
        let _ = append("reduceMotion=\(motion) reduceTransparency=\(transparency)\n")
        Text("Comfort probe: reduce motion \(motion ? "on" : "off"), reduce transparency \(transparency ? "on" : "off")")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func append(_ line: String) {
        let path = "\(dir)/comfort-probe.txt"
        guard let h = FileHandle(forWritingAtPath: path) else { FileManager.default.createFile(atPath: path, contents: Data(line.utf8)); return }
        h.seekToEndOfFile()
        h.write(Data(line.utf8))
        h.closeFile()
    }
}
#endif
