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

    var body: some View {
        Button("New Moment") { CapturePanelController.shared.show(tab: .video) }
            .keyboardShortcut("j", modifiers: [.control, .command])
        Button("New Voice Note") { CapturePanelController.shared.show(tab: .voice) }
        Button("Write") { CapturePanelController.shared.show(tab: .write) }
        Divider()
        Button("Open Saro", action: openSaro)
        Divider()
        Button("If you're struggling…") {
            openSaro()
            NotificationCenter.default.post(name: Notification.Name("saro.showSafetyCard"), object: nil)
        }
        Divider()
        Button("Quit Saro") { NSApp.terminate(nil) }
    }

    private func openSaro() {
        NSApp.activate()
        openWindow(id: "main")
    }
}
