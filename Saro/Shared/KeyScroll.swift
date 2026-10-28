import SwiftUI

extension View {
    /// A scroller that takes the focus, where ↑ ↓ scroll by a line, Page Up and Page Down by a page, and Home and End go
    /// to its ends, at once (a key's move never animates). SwiftUI's scroller takes the focus but not these keys; a field
    /// inside it keeps its own.
    func keyScrolls() -> some View { modifier(KeyScroll()) }
}

/// Whether the nearest focusable view around it has the focus itself, rather than a field or scroller inside it. SwiftUI
/// hands a key up from whatever has the focus, so a container's keys check this.
struct OwnFocus: View {
    @Environment(\.isFocused) private var isFocused
    @Binding var focused: Bool

    var body: some View { Color.clear.onChange(of: isFocused, initial: true) { _, f in focused = f } }
}

private struct KeyScroll: ViewModifier {
    @State private var position = ScrollPosition()
    @State private var geometry: ScrollGeometry?
    @State private var focused = false

    func body(content: Content) -> some View {
        content
            .background(OwnFocus(focused: $focused))
            .focusable()
            .focusEffectDisabled()
            .scrollPosition($position)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, g in geometry = g }
            .onKeyPress(keys: [.upArrow, .downArrow, .pageUp, .pageDown, .home, .end]) { press in
                guard focused, let g = geometry, press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
                let line: CGFloat = 40, page = max(line, g.containerSize.height - line), y = g.contentOffset.y
                let to: CGFloat = switch press.key {
                case .upArrow: y - line
                case .downArrow: y + line
                case .pageUp: y - page
                case .pageDown: y + page
                case .home: 0
                default: .infinity
                }
                position.scrollTo(y: to.clamped(to: 0...max(0, g.contentSize.height - g.containerSize.height)))
                return .handled
            }
    }
}
