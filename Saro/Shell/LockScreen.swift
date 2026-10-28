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
    @ObservationIgnored private var leftAt: Date?
    @ObservationIgnored private var unlockedAt = Date.now
    /// Touch ID asks by itself when you come back to Saro: at launch, and after you left it or the Mac slept. A lock made
    /// in front of you waits for Unlock, and a prompt you cancelled doesn't ask again until you've been away.
    @ObservationIgnored private var asksWhenBack = true
    /// Where typing was when Saro locked, so it goes on there after Unlock.
    @ObservationIgnored private var responders: [(window: NSWindow, responder: NSResponder)] = []
    @ObservationIgnored private var installed = false

    var enabled: Bool { PrefsStore.shared.lockEnabled }
    /// Posted as Saro locks, so a moment or voice note playing stops rather than going on behind the lock.
    static let didLock = Notification.Name("SaroDidLock")

    func lock() {
        guard enabled, !locked else { return }
        locked = true
        failed = nil
        asksWhenBack = !NSApp.isActive
        // Nothing goes on under the lock: typing in the covered windows ends, and what was open over them closes. The
        // capture panel (⌃⌘J) keeps working.
        responders = NSApp.windows.filter { !($0 is NSPanel) }.compactMap { w in w.firstResponder.map { (w, $0) } }
        for w in NSApp.windows where !(w is NSPanel) { w.makeFirstResponder(nil) }
        ShellPanels.shared.sheet = nil
        ShellPanels.shared.panel = nil
        NotificationCenter.default.post(name: Self.didLock, object: nil)
        AccessibilityNotification.Announcement("Saro is locked").post()
    }

    func unlock() async {
        guard locked, !asking else { return }
        #if DOGFOOD
        // Snapshots run unattended: no system prompt.
        if UserDefaults.standard.string(forKey: "SaroSnapshot") != nil { return }
        #endif
        asking = true
        asksWhenBack = false
        defer { asking = false }
        let context = LAContext()
        context.localizedCancelTitle = "Not now"
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "open your journal") else { return }
            locked = false
            failed = nil
            unlockedAt = .now
            // Once the content under the lock can take focus again.
            try? await Task.sleep(for: .milliseconds(50))
            for (w, r) in responders where w.isVisible { w.makeFirstResponder(r) }
            responders = []
        } catch let e as LAError where [.userCancel, .appCancel, .systemCancel].contains(e.code) {
            failed = nil
        } catch {
            failed = "Saro couldn't check it's you. Try again, or use your Mac's password."
        }
    }

    /// Back with Saro in front after being away: Touch ID asks once.
    func askIfBack() {
        guard locked, asksWhenBack, NSApp.isActive else { return }
        Task { await unlock() }
    }

    /// Watches for leaving, sleep and the screen locking. Call once, from the main window.
    func install() {
        guard !installed else { return }
        installed = true
        let app = NotificationCenter.default
        app.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let l = Locker.shared
                // The Touch ID prompt itself takes Saro out of front; that isn't leaving.
                guard !l.asking else { return }
                l.leftAt = .now
                l.asksWhenBack = true
                if PrefsStore.shared.lockAfter == .immediately { l.lock() }
            }
        }
        app.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                Locker.shared.check()
                Locker.shared.askIfBack()
            }
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { Locker.shared.away() } }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Locker.shared.away() }
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { Locker.shared.askIfBack() } }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Locker.shared.askIfBack() }
        }
        Task {
            while true {
                try? await Task.sleep(for: .seconds(15))
                check()
            }
        }
    }

    /// The Mac slept or its screen locked: Saro locks, and asks once you're back.
    private func away() {
        lock()
        if locked { asksWhenBack = true }
    }

    /// Turning the lock off in Settings lets go of it; turning it on waits for the next time away.
    func settingChanged() {
        if !enabled {
            locked = false
            responders = []
        }
        unlockedAt = .now
    }

    /// Away (Saro not frontmost) or idle (no input to the Mac while it is) for as long as Settings says.
    private func check() {
        guard enabled, !locked, let after = PrefsStore.shared.lockAfter.seconds, after > 0 else { return }
        if let leftAt, Date.now.timeIntervalSince(max(leftAt, unlockedAt)) >= after {
            lock()
            asksWhenBack = true
        } else if NSApp.isActive {
            leftAt = nil
            // The system's idle time, capped at the last unlock so an idle Mac doesn't lock again at once.
            let idle = min(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInput),
                           Date.now.timeIntervalSince(unlockedAt))
            if idle >= after { lock() }
        }
    }

    /// kCGAnyInputEventType: any key, click, scroll or movement.
    private static let anyInput = CGEventType(rawValue: ~0)!
}

extension View {
    /// The lock over a window's content: under it nothing can be focused, typed into or read by VoiceOver.
    func lockable() -> some View {
        let locked = Locker.shared.locked && Locker.shared.enabled
        return disabled(locked).accessibilityHidden(locked).overlay { LockScreen() }
    }
}

/// The lock screen over the whole window: the lit ground, the greeting and Unlock with Touch ID. Everything under it is
/// covered and hidden from VoiceOver.
struct LockScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
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
                        .focused($focused)
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
                .onAppear { focused = true }
                // At launch Touch ID asks at once with Saro in front; a lock you just made waits for Unlock.
                .task { locker.askIfBack() }
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

    /// New windows (Settings, the capture panel, sheets, popovers) take it as they come on screen.
    static func install() {
        apply()
        guard !observing else { return }
        observing = true
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.didChangeOcclusionStateNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { apply() } }
        }
    }
}
