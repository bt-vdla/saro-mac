import SwiftUI

/// Regions the guided tour can spotlight. Views mark themselves with `.tourAnchor(_:)`; the tour overlay reads the bounds.
enum TourTarget: String, CaseIterable {
    case sidebar, dayNav, canvas, captureBar, recordButton, toolbar, noticedButton, inspector, devNotes, helpMenu
}

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func tourAnchor(_ target: TourTarget) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [target: $0] }
    }
}
