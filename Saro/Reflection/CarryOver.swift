import SaroKit
import SwiftUI

/// D9 (CarryOverPrompt.tsx): yesterday's still-open commitments, one at a time. 'Carry over' adds the same words to
/// today; 'Let it go' leaves yesterday's unfinished there, and Saro stops asking. Yesterday's row is never edited. A
/// 500 ms guard keeps a double-click from answering the next one unseen; answered from the keyboard, focus moves on.
struct CarryOverPrompt: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where focus goes when none is left.
    var home: FocusState<Bool>.Binding
    @State private var answeredAt = Date.distantPast
    @FocusState private var focused: String?

    private static let bulkFrom = 3

    var body: some View {
        let items = model.reflection.carryOvers
        VStack(alignment: .leading, spacing: 0) {
            if let first = items.first {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("From yesterday").font(Typo.ui(10.5, .semibold)).tracking(1.2).textCase(.uppercase).foregroundStyle(Tok.ink3)
                        Spacer()
                        if items.count > 1 { Text("1 OF \(items.count)").font(Typo.mono(11)).tracking(0.4).foregroundStyle(Tok.ink3) }
                    }
                    Text("Yesterday you said you’d \(Text(said(first.text)).font(Typo.serif(15, italic: true)).foregroundStyle(Tok.voice)). Still on?")
                        .font(Typo.serif(15)).lineSpacing(2).foregroundStyle(Tok.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Button("Carry over") { answer { await $0.carry([first.id]) } }
                            .buttonStyle(Pill(primary: true)).focused($focused, equals: first.id)
                        Button("Let it go") { answer { await $0.letGo([first.id]) } }
                            .buttonStyle(Pill(primary: false, ghost: true))
                    }
                    if items.count >= Self.bulkFrom {
                        HStack(spacing: 4) {
                            Text("All \(items.count):").font(Typo.ui(12)).foregroundStyle(Tok.ink3)
                            Button("Carry all") { answer { await $0.carry(items.map(\.id)) } }.buttonStyle(Quiet())
                            Button("Let all go") { answer { await $0.letGo(items.map(\.id)) } }.buttonStyle(Quiet())
                        }
                    }
                }
                .id(first.id)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(y: 6).combined(with: .opacity),
                                                                   removal: .offset(y: -4).combined(with: .opacity)))
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) { Rectangle().fill(Tok.reflection.opacity(0.15)).frame(height: 1) }
                .padding(.bottom, 12)
            }
        }
        .animation(Motion.pick(Motion.small, reduce: reduceMotion), value: items.first?.id)
    }

    /// Their words, without the trailing full stop, cut at 140 characters.
    private func said(_ text: String) -> String {
        let s = text.replacingOccurrences(of: #"[.!]+$"#, with: "", options: .regularExpression)
        return s.count > 140 ? s.prefix(139).trimmingCharacters(in: .whitespaces) + "…" : s
    }

    private func answer(_ act: @escaping (ReflectionModel) async -> Void) {
        guard Date.now.timeIntervalSince(answeredAt) >= 0.5 else { return }
        answeredAt = .now
        let fromKeys = NSApp.currentEvent?.type == .keyDown
        Task {
            await act(model.reflection)
            guard fromKeys else { return }
            if let next = model.reflection.carryOvers.first { focused = next.id } else { home.wrappedValue = true }
        }
    }
}

/// A text-weight button in the panel's quiet ink.
private struct Quiet: ButtonStyle {
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.ui(12, .medium)).foregroundStyle(hover ? Tok.ink : Tok.ink2)
            .padding(.horizontal, 8).frame(minHeight: 30)
            .background(Tok.ink.opacity(hover ? 0.05 : 0), in: .capsule)
            .contentShape(.capsule)
            .onHover { hover = $0 }
    }
}
