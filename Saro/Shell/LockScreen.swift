import AppKit
import LocalAuthentication
import Observation
import SaroKit
import SwiftUI

/// The Touch ID lock (FR-SET-08): with Settings → Your data → Lock with Touch ID on, Saro locks at launch, after you've
/// been away as long as you chose, when the Mac sleeps or its screen locks, and from Lock Saro (⌃⌘L). It is a lock on the
/// window, not encryption. ⌃⌘J still captures, and the panel shows nothing already written.
@Observable @MainActor
final class Locker {
    static let shared = Locker()
    private(set) var locked = PrefsStore.shared.lockEnabled
    private(set) var asking = false
    private(set) var failed: String?
    @ObservationIgnored private var lastInput = Date.now
    @ObservationIgnored private var leftAt: Date?
    @ObservationIgnored private var installed = false

    var enabled: Bool { PrefsStore.shared.lockEnabled }

    func lock() {
        guard enabled, !locked else { return }
        locked = true
        failed = nil
        AccessibilityNotification.Announcement("Saro is locked").post()
    }

    func unlock() async {
        guard locked, !asking else { return }
        #if DOGFOOD
        // Snapshots run unattended: no system prompt.
        if UserDefaults.standard.string(forKey: "SaroSnapshot") != nil { return }
        #endif
        asking = true
        defer { asking = false }
        let context = LAContext()
        context.localizedCancelTitle = "Not now"
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "open your journal") else { return }
            locked = false
            failed = nil
            lastInput = .now
        } catch let e as LAError where [.userCancel, .appCancel, .systemCancel].contains(e.code) {
            failed = nil
        } catch {
            failed = "Saro couldn't check it's you. Try again, or use your Mac's password."
        }
    }

    /// Watches for input, leaving, sleep and the screen locking. Call once, from the main window.
    func install() {
        guard !installed else { return }
        installed = true
        _ = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .mouseMoved]) { e in
            MainActor.assumeIsolated { Locker.shared.lastInput = .now }
            return e
        }
        let app = NotificationCenter.default
        app.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                Locker.shared.leftAt = .now
                if PrefsStore.shared.lockAfter == .immediately { Locker.shared.lock() }
            }
        }
        app.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Locker.shared.check() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { Locker.shared.lock() } }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Locker.shared.lock() }
        }
        Task {
            while true {
                try? await Task.sleep(for: .seconds(15))
                check()
            }
        }
    }

    /// Turning the lock off in Settings lets go of it; turning it on waits for the next time away.
    func settingChanged() {
        if !enabled { locked = false }
        lastInput = .now
    }

    /// Away (Saro not frontmost) or idle (no input while it is) for as long as Settings says.
    private func check() {
        guard enabled, !locked, let after = PrefsStore.shared.lockAfter.seconds else { return }
        let since = NSApp.isActive ? lastInput : leftAt ?? lastInput
        if after > 0, Date.now.timeIntervalSince(since) >= after { lock() }
        if NSApp.isActive { leftAt = nil }
    }
}

/// The lock screen over the whole window: the lit ground, the greeting and Unlock with Touch ID. Everything under it is
/// covered and hidden from VoiceOver.
struct LockScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var locker: Locker { .shared }

    var body: some View {
        Group {
            if locker.locked && locker.enabled {
                ZStack {
                    Tok.bg.ignoresSafeArea()
                    LitGround().ignoresSafeArea()
                    VStack(spacing: 0) {
                        Image("Logo").resizable().scaledToFit().frame(width: 64, height: 64).accessibilityHidden(true)
                        TimelineView(.everyMinute) { context in
                            let hour = Sky.localHour(context.date)
                            VStack(spacing: 8) {
                                Text(Greeting.eyebrow(hour: hour)).monoCaps(11, tracking: 0.12).foregroundStyle(Tok.ink3)
                                Text(Greeting.line(hour: hour)).font(Typo.serif(30)).foregroundStyle(Tok.ink)
                            }
                        }
                        .padding(.top, 24)
                        Button { Task { await locker.unlock() } } label: {
                            Label("Unlock with Touch ID", systemImage: "touchid")
                        }
                        .buttonStyle(SheetButton(primary: true))
                        .keyboardShortcut(.defaultAction)
                        .disabled(locker.asking)
                        .padding(.top, 28)
                        Text(locker.failed ?? "Saro is locked. It's a lock on this window, not encryption.")
                            .font(Typo.ui(12)).foregroundStyle(locker.failed == nil ? Tok.ink3 : Tok.danger)
                            .multilineTextAlignment(.center)
                            .padding(.top, 14)
                    }
                    .padding(40)
                }
                .transition(.opacity)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
                // Touch ID asks as soon as you're back with Saro in front, not while the Mac goes to sleep.
                .task { if NSApp.isActive { await locker.unlock() } }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await locker.unlock() }
                }
            }
        }
        .animation(reduceMotion ? nil : Motion.easeOut(0.24), value: locker.locked)
        .onAppear { locker.install() }
        .onChange(of: PrefsStore.shared.lockEnabled) { locker.settingChanged() }
    }
}

/// Hide from screen sharing (FR-SET-08): every Saro window and panel asks to be left out of captures while the setting
/// is on. "Hides Saro from most screen sharing. Test it with your app."
struct ScreenShare: View {
    var body: some View {
        Color.clear
            .onChange(of: PrefsStore.shared.hideFromScreenShare, initial: true) { _, _ in Self.install() }
            .accessibilityHidden(true)
    }

    private static var observing = false

    static func apply() {
        let type: NSWindow.SharingType = PrefsStore.shared.hideFromScreenShare ? .none : .readOnly
        for w in NSApp.windows where w.sharingType != type { w.sharingType = type }
    }

    /// New windows (Settings, the capture panel, sheets) take it as they appear.
    static func install() {
        apply()
        guard !observing else { return }
        observing = true
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSApplication.didUpdateNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { apply() } }
        }
    }
}
