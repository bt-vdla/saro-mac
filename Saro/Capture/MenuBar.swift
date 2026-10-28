import AppKit
import SwiftUI

/// Saro in the menu bar: capture into today from anywhere, open the app, or find support.
struct SaroMenuBar: Scene {
    var body: some Scene {
        MenuBarExtra("Saro", systemImage: "leaf") { SaroMenu() }
    }
}

private struct SaroMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("New Moment") { CapturePanelController.shared.show(tab: .video) }
            .keyboardShortcut(KeyboardShortcut(.captureAnywhere))
        Button("New Voice Note") { CapturePanelController.shared.show(tab: .voice) }
        Button("Write") { CapturePanelController.shared.show(tab: .write) }
        Divider()
        Button("Open Saro", action: openSaro)
        Button("Settings…") { showSettings(nil) }.keyboardShortcut(KeyboardShortcut(.settings))
        Button("Profile…") { showSettings(.you) }
        if PrefsStore.shared.lockEnabled { Button("Lock Saro") { Locker.shared.lock() }.disabled(Locker.shared.locked) }
        Divider()
        Button("If you're struggling…") {
            openSaro()
            NotificationCenter.default.post(name: Notification.Name("saro.showSafetyCard"), object: nil)
        }
        Divider()
        Button("Quit Saro") { NSApp.terminate(nil) }
    }

    private func showSettings(_ section: SettingsSection?) {
        if let section { PrefsStore.shared.settingsSection = section }
        NSApp.activate()
        openSettings()
    }

    private func openSaro() {
        NSApp.activate()
        openWindow(id: "main")
    }
}
