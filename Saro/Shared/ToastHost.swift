import SwiftUI

/// Toasts confirm structural changes in a short pill from the top (FR-CAN-11), with Undo when there is one.
struct ToastHost: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
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
                .padding(.horizontal, 16).padding(.vertical, 11)
                .frame(maxWidth: 360, alignment: .leading)
                .background(Tok.paper.opacity(0.95), in: .rect(cornerRadius: Radius.panel))
                .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Tok.rim.opacity(0.6)))
                .elevation(.float)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(y: 8).combined(with: .opacity),
                                                                   removal: .offset(x: -24).combined(with: .opacity)))
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 24).padding(.bottom, 100)
        .animation(Motion.pick(Motion.easeOut(0.24), reduce: reduceMotion), value: model.toast)
    }
}
