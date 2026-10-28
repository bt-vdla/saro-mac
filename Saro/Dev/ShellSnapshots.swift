#if DOGFOOD
import AppKit
import SaroKit
import SwiftUI

/// The shell's snapshot states: live ones on the demo day (toasts, the account menu with a failed save, Trash, the
/// Light Lab, the lock, the day image), then galleries of what sits in sheets or other windows.
@MainActor
enum ShellSnapshots {
    /// Edit Details' fields where they show: the voice note's own summary open in place, and a page's caption.
    static func details(_ model: AppModel) {
        model.pane = .day
        model.openEntryID = nil
        guard let voice = model.entries.first(where: { $0.kind == .voice }) else { return }
        Task {
            try? await model.ledger.updateSummary(id: voice.id, "The walk home through the park, and feeling lighter.")
            if let page = model.entries.first(where: { $0.kind == .reflection }) {
                try? await model.ledger.updateEntryText(id: page.id, body: page.body ?? "", titleUser: page.titleUser,
                                                       captionUser: "Written on the bus home")
                model.process(page.id)
            }
            await model.reload()
            model.openVoiceID = voice.id
        }
    }

    static func toasts(_ model: AppModel) {
        model.openVoiceID = nil
        model.pane = .day
        model.show(Toast(title: "Couldn't save your changes", detail: "Your Mac may be out of space.",
                         action: Toast.Action(label: "Retry", run: {}), style: .destructive, duration: .seconds(60)))
        model.show(Toast(title: "Voice note moved to Trash", detail: "You can undo this", action: Toast.Action(label: "Undo", run: {}),
                         duration: .seconds(60)))
        model.show(Toast(title: "Voice note moved to Trash", detail: "You can undo this", action: Toast.Action(label: "Undo", run: {}),
                         duration: .seconds(60)))
        model.show(Toast(title: "Duplicated to Yesterday", duration: .seconds(60)))
    }

    /// A write that failed: the red dot, Not saved, and Retry at the top of the account menu.
    static func accountMenu(_ model: AppModel) {
        for t in model.toasts { model.dismiss(t.id) }
        DevFlags.shared.simulateWriteFailures = true
        Task {
            try? await model.saves.track("snapshot") {}
            DevFlags.shared.simulateWriteFailures = false
            ShellPanels.shared.open(.account)
        }
    }

    static func trash(_ model: AppModel) {
        ShellPanels.shared.panel = nil
        let ids = Set([EntryKind.voice, .reflection].compactMap { k in model.entries.first { $0.kind == k }?.id })
        Task {
            await model.trash(ids)
            for t in model.toasts { model.dismiss(t.id) }
            ShellPanels.shared.open(.trash)
        }
    }

    static func lightLab() {
        ShellPanels.shared.panel = nil
        DevFlags.shared.lightLab = true
        Daylight.shared.pinnedHour = 19.5
    }

    static func lock() {
        DevFlags.shared.lightLab = false
        Daylight.shared.pinnedHour = nil
        PrefsStore.shared.lockEnabled = true
        Locker.shared.lock()
    }

    /// The day as Export Day as Image draws it, written beside the snapshots.
    static func dayImage(_ model: AppModel, dir: String) {
        PrefsStore.shared.lockEnabled = false
        model.pane = .day
        Task {
            if let image = await DayImage.render(model, dark: false) {
                try? DayImage.writePNG(image, to: URL(fileURLWithPath: "\(dir)/shell-dayimage-export.png"))
            }
        }
    }

    static func galleries(_ p: NSPanel, _ model: AppModel) -> [(String, @MainActor () -> Void)] {
        let host = { @MainActor @Sendable (v: AnyView) in
            p.contentView = NSHostingView(rootView: v.environment(model).environment(PrefsStore.shared))
        }
        let voice = model.entries.first { $0.kind == .voice } ?? Entry(kind: .voice)
        return [
            ("shell-sheets", {
                host(AnyView(HStack(alignment: .top, spacing: 40) {
                    EditDetailsSheet(entry: voice).elevation(.overlay)
                    ChooseDaySheet(id: voice.id).elevation(.overlay)
                }
                .padding(40).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Tok.bg)))
            }),
            ("shell-recovery", { host(AnyView(RecoveryView(error: CocoaError(.fileReadCorruptFile), retry: {}))) }),
            ("shell-launch", {
                LaunchProgress.shared.demo = 0.6
                host(AnyView(LaunchView()))
            }),
            ("shell-help", {
                LaunchProgress.shared.demo = nil
                host(AnyView(HStack(alignment: .top, spacing: 32) {
                    AboutView().elevation(.panel)
                    ShortcutsView().frame(width: 720, height: 760).clipShape(.rect(cornerRadius: Radius.panel))
                }
                .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Tok.bg)))
            }),
            ("shell-acknowledgements", { host(AnyView(AcknowledgementsView())) }),
            // A song's artist under its title, and a page's caption under its words, as Edit Details saves them.
            ("shell-cards", {
                let song = Entry(kind: .music, titleUser: "Weightless", captionUser: "Marconi Union",
                                 body: "https://open.spotify.com/search/weightless%20marconi%20union")
                let page = Entry(kind: .reflection, titleUser: "Morning run", captionUser: "Before work, by the river",
                                 body: "Ran 8k along the river. My legs are sore but my head is quiet.")
                host(AnyView(HStack(alignment: .top, spacing: 40) {
                    CardFace(entry: song)
                    CardFace(entry: page)
                }
                .padding(48).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Tok.bg)))
            }),
        ]
    }
}
#endif
