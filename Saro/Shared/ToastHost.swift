import SwiftUI

/// Toasts confirm structural changes in a short pill from the top (FR-CAN-11), with Undo when there is one.
struct ToastHost: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if let toast = model.toast {
                HStack(spacing: 12) {
                    Image(systemName: toast.style == .error ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(toast.style == .error ? Tok.danger : Tok.sageTeal)
                    Text(toast.text).font(Typo.ui(13, .medium)).foregroundStyle(Tok.ink)
                    if let undo = toast.undo {
                        Button("Undo") {
                            undo()
                            model.toast = nil
                        }
                        .buttonStyle(.plain).font(Typo.ui(13, .semibold)).foregroundStyle(Tok.sageTeal)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
                .saroSurface(radius: 20, lifted: true)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
            }
            Spacer()
        }
        .padding(.top, 14)
        .animation(Motion.pick(Motion.open, reduce: reduceMotion), value: model.toast)
    }
}
