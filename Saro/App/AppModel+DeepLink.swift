import AppKit
import SaroKit
import SwiftUI

extension AppModel {
    /// Follows a `saro://` link from a notification, a Shortcut or a letter quote: capture on today, a day, an entry,
    /// a letter, a Settings section, or What Saro knows. A link Saro doesn't know is ignored.
    func open(_ url: URL) {
        guard let link = DeepLink(url) else { return }
        if case .settings(let section) = link {
            PrefsStore.shared.settingsSection = section.flatMap(SettingsSection.init)
            WindowActions.openSettings()
            return
        }
        WindowActions.openMain()
        // Onboarding's own test reminder carries Voice and Write: nothing lands in the journal until it ends.
        guard !showsOnboarding else { return }
        Task { await follow(link) }
    }

    private func follow(_ link: DeepLink) async {
        let today = LocalDay.today()
        // The lens is modal: a link lands on the day it names, not under the lens or into its tile.
        lens?.close(how: .instant)
        switch link {
        case .capture(let kind):
            // A recording under way keeps going: the window only comes forward.
            guard recorderKind == nil, CaptureController.shared.owner == nil else { return }
            await land(on: today)
            if kind == .reflection {
                if let e = await newWriting(day: today) { openEntryID = e.id }
            } else {
                recorderKind = kind
            }
        case .day(let d):
            await land(on: min(d, today))
        case .entry(let id):
            guard let e = try? await ledger.entry(id), e.trashedAt == nil else {
                return show(Toast("This entry wandered off. It may be in Trash."))
            }
            await land(on: e.localDay)
            openEntryID = id
        case .letter(let d):
            await land(on: min(d, today))
            openEntryID = nil
            insight = .letter
        case .knows(let q):
            knowsQuery = q
            pane = .knows
        case .settings:
            break
        }
    }

    /// The day canvas showing `target`, awaited, so what the link opens next isn't cleared by the day change.
    func land(on target: String) async {
        guard target != day || pane != .day else { return }
        go(to: target)
        // ponytail: go(to:) loads in its own Task; wait for it to land, capped so a superseded change can't hang the link.
        let deadline = ContinuousClock.now + .seconds(2)
        while day != target || pane != .day, .now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
    }
}

/// SwiftUI hands out openWindow and openSettings only inside views; the main window's root passes them here, so a
/// link or a notification click can bring up the window, or Settings, even after the window was closed.
@MainActor
enum WindowActions {
    static var openMain: () -> Void = {}
    static var openSettings: () -> Void = {}
    static var openWindow: (String) -> Void = { _ in }
}

extension View {
    /// `saro://` links and notification clicks, for the main window's root.
    func deepLinks(_ model: AppModel) -> some View { modifier(DeepLinks(model: model)) }
}

private struct DeepLinks: ViewModifier {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content
            .onOpenURL { model.open($0) }
            .onAppear {
                WindowActions.openMain = { [openWindow] in
                    NSApp.activate()
                    openWindow(id: "main")
                }
                WindowActions.openSettings = { [openSettings] in
                    NSApp.activate()
                    openSettings()
                }
                WindowActions.openWindow = { [openWindow] id in
                    NSApp.activate()
                    openWindow(id: id)
                }
                Reminders.shared.route = { model.open($0) }
            }
    }
}
