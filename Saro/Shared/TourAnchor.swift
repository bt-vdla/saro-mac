import SwiftUI

/// Regions the guided tour can spotlight. Views mark themselves with `.tourAnchor(_:)`; the tour overlay reads the bounds.
enum TourTarget: String, CaseIterable {
    case history, dayNav, canvas, captureBar, recordButton, toolbar, noticedButton, inspector, devNotes, helpMenu
}

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Merges into what the views inside reported, so an anchor on a container doesn't hide the anchors within it.
    func tourAnchor(_ target: TourTarget) -> some View {
        transformAnchorPreference(key: TourAnchorKey.self, value: .bounds) { $0[target] = $1 }
    }
}
