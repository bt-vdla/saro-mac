import SwiftUI

/// Toasts confirm structural changes in a short pill from the top (FR-CAN-11), with Undo when there is one.
struct ToastHost: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            if let toast = model.toast {
                let error = toast.style == .error
                HStack(spacing: 12) {
                    Text(toast.text).font(Typo.ui(13.5, .semibold)).foregroundStyle(error ? Tok.danger : Tok.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let undo = toast.undo {
                        Button {
                            undo()
                            model.toast = nil
                        } label: {
                            Text("Undo").font(Typo.ui(13, .semibold)).padding(.horizontal, 12).frame(minHeight: 32)
                        }
                        .buttonStyle(ToastControl(chip: true))
                    }
                }
                .padding(.vertical, 12).padding(.leading, 16).padding(.trailing, 44)
                .frame(width: 360)
                .background((error ? Tok.dangerBg : Tok.paper).opacity(0.95), in: .rect(cornerRadius: Radius.panel))
                .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(error ? Tok.dangerBorder : Tok.rim.opacity(0.7)))
                .overlay(alignment: .trailing) {
                    Button { model.toast = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .medium)).frame(width: 32, height: 32)
                    }
                    .buttonStyle(ToastControl(chip: false))
                    .accessibilityLabel("Dismiss")
                    .padding(.trailing, 8)
                }
                .elevation(.float)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(y: 8).combined(with: .opacity),
                                                                   removal: .offset(x: -24).combined(with: .opacity)))
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 8 pt above the bar (20 pt off the bottom, 64 tall).
        .padding(.leading, 24).padding(.bottom, 92)
        .animation(Motion.pick(Motion.easeOut(0.24), reduce: reduceMotion), value: model.toast)
    }
}

/// toast.tsx's controls: the Undo chip (ink/5, ink/10 on hover) and the round dismiss (ink-3, ink/5 and ink on hover).
private struct ToastControl: ButtonStyle {
    let chip: Bool
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(chip ? Tok.sageDark : hover ? Tok.ink : Tok.ink3)
            .background(Tok.ink.opacity((chip ? 0.05 : 0) + (hover ? 0.05 : 0)), in: .rect(cornerRadius: chip ? Radius.control : 16))
            .contentShape(.rect)
            .onHover { hover = $0 }
    }
}
