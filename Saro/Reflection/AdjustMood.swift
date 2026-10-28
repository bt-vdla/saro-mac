import SaroKit
import SwiftUI

/// Adjust emotion (AdjustEmotionDialog.tsx): a 4 × 3 grid the arrows move through, an optional note of up to 200
/// characters (gated before it is stored), Return to save and Esc to cancel. The mood is then the person's own, locked
/// against every re-read, and the panel, the ribbon and the letter read it first.
struct AdjustMoodView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let current: Mood
    @State private var selected: Mood?
    @State private var note = ""
    @State private var saving = false
    @FocusState private var gridFocused: Bool
    static let noteLimit = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Adjust emotion").font(Typo.ui(17, .semibold)).foregroundStyle(Tok.momentInk)
                    Text("Currently: **\(current.rawValue)**").font(Typo.ui(12)).foregroundStyle(Tok.ink2)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tok.momentInk)
                        .frame(width: 28, height: 28).background(Tok.paper.opacity(0.8), in: .circle)
                        .overlay(Circle().strokeBorder(Tok.rim.opacity(0.7)))
                }
                .buttonStyle(PressStyle())
                .disabled(saving)
                .accessibilityLabel("Close")
            }
            .padding(.bottom, 14)

            Text("How does today feel?").font(Typo.ui(11, .medium)).tracking(0.6).textCase(.uppercase).foregroundStyle(Tok.ink2)
                .padding(.bottom, 8)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Mood.allCases, id: \.self) { tile($0) }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($gridFocused)
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                let all = Mood.allCases
                let i = selected.flatMap { all.firstIndex(of: $0) } ?? 0
                let step = switch press.key { case .leftArrow: -1; case .rightArrow: 1; case .upArrow: -4; default: 4 }
                selected = all[(i + step + all.count) % all.count]
                return .handled
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("How does today feel?")

            if let selected {
                Text(selected.summary).font(Typo.ui(12)).lineSpacing(2).foregroundStyle(Tok.momentInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Tok.moment.opacity(0.1), in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tok.moment.opacity(0.15)))
                    .id(selected)
                    .transition(.opacity)
                    .padding(.top, 10)
            }

            HStack(spacing: 4) {
                Text("Add a note").font(Typo.ui(11, .medium)).tracking(0.6).textCase(.uppercase)
                Text("(optional)").font(Typo.ui(10))
            }
            .foregroundStyle(Tok.ink2)
            .padding(.top, 14).padding(.bottom, 6)
            TextField("What’s behind this feeling today?", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.ui(12.5)).lineLimit(2...3)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Tok.surface.opacity(0.7), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tok.border))
                .writingToolsFollowPref()
                .disabled(saving)
                .onChange(of: note) { _, n in if n.count > Self.noteLimit { note = String(n.prefix(Self.noteLimit)) } }
                .onSubmit(save)
                .accessibilityLabel("Add a note, optional")
            Text("\(note.count)/\(Self.noteLimit)").font(Typo.ui(10)).foregroundStyle(Tok.ink3)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 4)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(Pill(primary: false))
                    .disabled(saving)
                Spacer()
                Button(action: save) {
                    HStack(spacing: 6) {
                        if saving { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                        Text(saving ? "Saving…" : "Update emotion")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(Pill(primary: true))
                .disabled(selected == nil || saving)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 344)
        .animation(Motion.fade, value: selected)
        .onAppear {
            selected = current
            note = model.reflection.state.lockedMood == current ? model.reflection.state.moodNote ?? "" : ""
            gridFocused = true
        }
    }

    private func tile(_ m: Mood) -> some View {
        let active = selected == m
        return Button { selected = m } label: {
            VStack(spacing: 5) {
                Text(MoodSymbol.emoji(m)).font(.system(size: 22))
                Text(m.rawValue).font(Typo.ui(10, .medium)).foregroundStyle(active ? Tok.momentInk : Tok.ink2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(active ? Tok.moment.opacity(0.1) : Tok.surface.opacity(0.5), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(active ? Tok.moment.opacity(0.45) : Tok.rim.opacity(0.6), lineWidth: active ? 1.5 : 1))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .accessibilityLabel(m.rawValue)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func save() {
        guard let selected, !saving else { return }
        saving = true
        Task {
            if await model.reflection.adjustMood(selected, note: note) { dismiss() }
            saving = false
        }
    }
}

/// The panel's button weights: sage for the action, a quiet pill beside it, or a ghost (Button.tsx's) that shows its
/// fill and rim only under the pointer.
struct Pill: ButtonStyle {
    let primary: Bool
    var ghost = false
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.ui(13, primary ? .semibold : .medium))
            .foregroundStyle(primary ? Tok.onPrimary : Tok.ink2)
            .padding(.horizontal, primary ? 16 : 14).frame(minHeight: 36)
            .background(primary ? Tok.sage.opacity(enabled ? 1 : 0.35) : ghost ? Tok.ink.opacity(hover ? 0.05 : 0) : Tok.surface.opacity(0.6),
                        in: .capsule)
            .overlay(Capsule().strokeBorder(primary || ghost && !hover ? .clear : Tok.rim.opacity(0.7)))
            .opacity(enabled || primary ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .contentShape(.capsule)
            .onHover { hover = $0 }
    }
}
