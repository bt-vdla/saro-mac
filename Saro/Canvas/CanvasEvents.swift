import AppKit
import SwiftUI

/// Two-finger scroll pans, pinch and ⌘-scroll zoom. SwiftUI has no scroll-wheel gesture on macOS, so a transparent
/// NSView sized to the canvas installs a local event monitor and consumes only events over its own bounds.
struct CanvasEvents: NSViewRepresentable {
    var enabled: Bool
    var onPan: (CGSize) -> Void
    var onZoom: (_ factor: CGFloat, _ at: CGPoint) -> Void

    func makeNSView(context: Context) -> EventView { EventView() }

    func updateNSView(_ view: EventView, context: Context) {
        view.enabled = enabled
        view.onPan = onPan
        view.onZoom = onZoom
    }

    final class EventView: NSView {
        var enabled = true
        var onPan: ((CGSize) -> Void)?
        var onZoom: ((CGFloat, CGPoint) -> Void)?
        private var monitor: Any?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return consumed ? nil : event
            }
        }

        private func handle(_ e: NSEvent) -> Bool {
            guard enabled, e.window === window else { return false }
            let p = convert(e.locationInWindow, from: nil)
            guard bounds.contains(p) else { return false }
            // A scroller on the canvas with more to show (an open voice note's transcript) scrolls itself.
            if e.type == .scrollWheel, !e.modifierFlags.contains(.command), let s = window?.contentView?.hitTest(e.locationInWindow)?.enclosingScrollView,
               (s.documentView?.frame.height ?? 0) > s.contentView.bounds.height + 1 { return false }
            switch e.type {
            case .magnify:
                onZoom?(1 + e.magnification, p)
            case .scrollWheel where e.modifierFlags.contains(.command):
                let d = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 8
                onZoom?(exp(d * 0.006), p)
            case .scrollWheel:
                // ponytail: a fixed 12× for notched mouse wheels; trackpads report precise deltas and momentum phases.
                let k: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 12
                onPan?(CGSize(width: e.scrollingDeltaX * k, height: e.scrollingDeltaY * k))
            default:
                return false
            }
            return true
        }
    }
}
