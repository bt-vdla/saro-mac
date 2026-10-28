import OSLog
import SaroKit
import SwiftUI

/// A toast (toast.tsx): a title, an optional line under it, one action (Undo, Retry), info or destructive, and how long
/// it stays.
struct Toast: Identifiable, Equatable {
    enum Style {
        case info, destructive
        /// The name other packages use for a failure.
        static var error: Style { .destructive }
    }

    struct Action {
        let label: String
        let run: @MainActor () -> Void
    }

    let id = UUID()
    /// The title as given; a fold shows it with a count.
    let base: String
    var count = 1
    let detail: String?
    var action: Action?
    let style: Style
    let duration: Duration
    /// The cards a trash took off the canvas, which Undo flies back out of the toast.
    var trashed: [StageCard]
    let at = Date.now

    var title: String { ToastRules.title(base, count: count) }
    var text: String { title }
    /// The Undo of a trash, which the flight back out of the toast follows.
    var undo: (@MainActor () -> Void)? { action?.label == "Undo" ? action?.run : nil }

    init(title: String, detail: String? = nil, action: Action? = nil, style: Style = .info, duration: Duration? = nil,
         trashed: [StageCard] = []) {
        base = title
        self.detail = detail
        self.action = action
        self.style = style
        // use-toast.ts: 5 s by default; a failure with something to retry waits 10 s.
        self.duration = duration ?? (style == .destructive && action != nil ? .seconds(10) : .seconds(5))
        self.trashed = trashed
    }

    init(_ text: String, style: Style = .info, undo: (@MainActor () -> Void)? = nil, trashed: [StageCard] = []) {
        self.init(title: text, action: undo.map { Action(label: "Undo", run: $0) }, style: style, trashed: trashed)
    }

    /// A write that didn't land: what happened in plain words and what to do about it on this Mac, with Retry when
    /// running it again is safe. The error itself is only logged, as its domain and code.
    static func failed(_ title: String, _ error: Error, context: String? = nil, retry: (@MainActor () -> Void)? = nil) -> Toast {
        Log.shell.error("\(title, privacy: .public): \(FailureCopy.code(error), privacy: .public)")
        return Toast(title: title, detail: [context, FailureCopy.remedy(for: error)].compactMap { $0 }.joined(separator: " "),
                     action: retry.map { Action(label: "Retry", run: $0) }, style: .destructive)
    }

    var shown: ToastRules.Shown { ToastRules.Shown(title: base, destructive: style == .destructive, at: at, hasAction: action != nil, count: count) }

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id && a.count == b.count }
}

enum Log {
    static let shell = Logger(subsystem: "com.saro.mac", category: "shell")
}

extension AppModel {
    /// The newest toast, or nil; setting nil dismisses it.
    var toast: Toast? {
        get { toasts.first }
        set { if newValue == nil, let id = toasts.first?.id { dismiss(id) } }
    }

    /// Shows a toast over the stack (use-toast.ts): a same-title twin within a second folds into it, and its action runs
    /// for every twin; past three the oldest without an action close. It stays its own duration, paused while the
    /// pointer or VoiceOver is on it, and VoiceOver hears it as it arrives.
    func show(_ toast: Toast) {
        var toast = toast
        let r = ToastRules.arrive(toast.shown, over: toasts.map(\.shown))
        let twins = r.twins.map { toasts[$0] }
        toast.count = r.count
        toast.trashed += twins.flatMap(\.trashed)
        if let action = toast.action {
            let older = twins.compactMap { t in t.action.map { (run: $0.run, until: t.at.addingTimeInterval(t.duration.seconds)) } }
            toast.action = Toast.Action(label: action.label) {
                // An older twin's Undo only while its own toast would still be up, so a fold never stretches it.
                for o in older where Date.now < o.until { o.run() }
                action.run()
            }
        }
        let gone = Set((r.twins + r.closing).map { toasts[$0].id })
        toasts.removeAll { gone.contains($0.id) }
        toasts.insert(toast, at: 0)
        AccessibilityNotification.Announcement([toast.title, toast.detail].compactMap { $0 }.joined(separator: ". ")).post()
        let id = toast.id
        Task { await expire(id, after: toast.duration) }
    }

    func dismiss(_ id: UUID) {
        toasts.removeAll { $0.id == id }
        heldToasts.remove(id)
    }

    /// ponytail: polls a quarter second at a time, which is all a pause needs to be felt.
    private func expire(_ id: UUID, after duration: Duration) async {
        var left = duration
        while left > .zero, toasts.contains(where: { $0.id == id }) {
            try? await Task.sleep(for: .milliseconds(250))
            if !heldToasts.contains(id) { left -= .milliseconds(250) }
        }
        dismiss(id)
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
