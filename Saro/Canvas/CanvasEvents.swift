import AppKit
import SwiftUI

/// Two-finger scroll pans, pinch and ⌘-scroll zoom. SwiftUI has no scroll-wheel gesture on macOS, so a transparent
/// NSView sized to the canvas installs a local event monitor and consumes only events over its own bounds. Each event
/// is passed along too, for its phase and momentum phase; `onEvent`, when set, takes every event raw instead.
struct CanvasEvents: NSViewRepresentable {
    var enabled: Bool
    var onPan: (CGSize, CGPoint, NSEvent) -> Void = { _, _, _ in }
    var onZoom: (_ factor: CGFloat, _ at: CGPoint, NSEvent) -> Void = { _, _, _ in }
    var onEvent: ((NSEvent, CGPoint) -> Void)?
    /// Space-drag and middle-drag pan (a mouse down, its drags and its up); Space is taken only while this is set and
    /// `takesSpace` says the canvas has keyboard focus, so a focused button still presses on Space.
    var onDragPan: ((NSEvent.EventType, CGPoint) -> Void)?
    var takesSpace = true

    func makeNSView(context: Context) -> EventView { EventView() }

    func updateNSView(_ view: EventView, context: Context) {
        view.enabled = enabled
        view.onPan = onPan
        view.onZoom = onZoom
        view.onEvent = onEvent
        view.onDragPan = onDragPan
        view.takesSpace = takesSpace
    }

    final class EventView: NSView {
        var enabled = true
        var onPan: ((CGSize, CGPoint, NSEvent) -> Void)?
        var onZoom: ((CGFloat, CGPoint, NSEvent) -> Void)?
        var onEvent: ((NSEvent, CGPoint) -> Void)?
        var onDragPan: ((NSEvent.EventType, CGPoint) -> Void)?
        var takesSpace = true
        private var monitor: Any?
        private var spaceHeld = false
        private var dragging = false

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .keyDown, .keyUp, .leftMouseDown, .leftMouseDragged,
                                                                  .leftMouseUp, .otherMouseDown, .otherMouseDragged, .otherMouseUp]) { [weak self] event in
                let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return consumed ? nil : event
            }
        }

        /// Space held (outside text) turns a left drag into a pan, as a middle drag always is.
        private func dragPan(_ e: NSEvent, _ p: CGPoint) -> Bool? {
            switch e.type {
            case .keyUp:
                // Let go wherever focus went, so a later click is never taken for a pan.
                guard e.keyCode == 49 else { return false }
                defer { spaceHeld = false }
                return spaceHeld && e.window === window
            case .keyDown:
                guard e.keyCode == 49, enabled, takesSpace, onDragPan != nil, e.window === window, !(window?.firstResponder is NSTextView),
                      e.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
                spaceHeld = true
                return true
            case .leftMouseDown, .otherMouseDown:
                // Space may have come up in another app; the key's live state settles it.
                let space = spaceHeld && CGEventSource.keyState(.combinedSessionState, key: 49)
                guard enabled, let onDragPan, e.window === window, e.type == .otherMouseDown ? e.buttonNumber == 2 : space, bounds.contains(p) else { return false }
                dragging = true
                onDragPan(e.type, p)
                return true
            case .leftMouseDragged, .otherMouseDragged, .leftMouseUp, .otherMouseUp:
                guard dragging else { return false }
                if e.type == .leftMouseUp || e.type == .otherMouseUp { dragging = false }
                onDragPan?(e.type, p)
                return true
            default:
                return nil
            }
        }

        private func handle(_ e: NSEvent) -> Bool {
            let p = convert(e.locationInWindow, from: nil)
            if let used = dragPan(e, p) { return used }
            guard enabled, e.window === window else { return false }
            guard bounds.contains(p) else { return false }
            if let onEvent {
                onEvent(e, p)
                return true
            }
            // A scroller on the canvas with more to show (an open voice note's transcript) scrolls itself.
            if e.type == .scrollWheel, !e.modifierFlags.contains(.command), let s = window?.contentView?.hitTest(e.locationInWindow)?.enclosingScrollView,
               (s.documentView?.frame.height ?? 0) > s.contentView.bounds.height + 1 { return false }
            switch e.type {
            case .magnify:
                onZoom?(1 + e.magnification, p, e)
            case .scrollWheel where e.modifierFlags.contains(.command):
                let d = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 8
                onZoom?(exp(d * 0.006), p, e)
            case .scrollWheel:
                // ponytail: a fixed 12× for notched mouse wheels; trackpads report precise deltas and momentum phases.
                let k: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 12
                onPan?(CGSize(width: e.scrollingDeltaX * k, height: e.scrollingDeltaY * k), p, e)
            default:
                return false
            }
            return true
        }
    }
}
