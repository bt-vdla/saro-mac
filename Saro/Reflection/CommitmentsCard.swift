import SaroKit
import SwiftUI

/// 'My commitments' (CommitmentsCard.tsx), the panel's footer card: round checkboxes, inline edit (Return saves,
/// Shift-Return adds a line, Esc cancels, leaving saves), 'Add new…' up to 280 characters and 20 a day, a context menu,
/// and ⌘Z for an edit or a delete. On today, yesterday's still open come first.
struct CommitmentsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing: String?
    @State private var adding = false
    @State private var draft = ""
    @FocusState private var newFocused: Bool
    @FocusState private var addFocused: Bool

    var body: some View {
        let r = model.reflection
        VStack(alignment: .leading, spacing: 0) {
            if r.isToday { CarryOverPrompt(home: $addFocused) }
            Text("My commitments").font(Typo.ui(14, .semibold)).foregroundStyle(Tok.reflectionInk)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 6)
            // About four rows tall; more scroll.
            if r.commitments.count > 4 {
                ScrollView { list }.frame(height: 128).scrollIndicators(.automatic)
            } else {
                list
            }
            if r.commitmentHeld { HeldNote().padding(.top, 8) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tok.paper, in: .rect(cornerRadius: Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Tok.rim.opacity(0.8)))
        .shadow(color: .black.opacity(0.14), radius: 20, y: 14)
        .animation(Motion.pick(Motion.small, reduce: reduceMotion), value: r.commitments)
    }

    private var list: some View {
        let r = model.reflection
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(r.commitments.enumerated()), id: \.element.id) { i, c in
                CommitmentRow(commitment: c, last: i == r.commitments.count - 1, editing: $editing)
            }
            if adding {
                HStack(spacing: 10) {
                    addMark
                    TextField("Type your commitment…", text: $draft)
                        .textFieldStyle(.plain)
                        .font(Typo.ui(13)).foregroundStyle(Tok.reflectionInk)
                        .focused($newFocused)
                        .writingToolsFollowPref()
                        .onChange(of: draft) { _, d in if d.count > Commitment.maxChars { draft = Commitment.clipped(d) } }
                        .onSubmit { saveNew() }
                        .onExitCommand { closeNew() }
                        .onChange(of: newFocused) { _, f in if !f && adding { saveNew() } }
                        .accessibilityLabel("New commitment")
                }
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Tok.reflection.opacity(0.4)).frame(height: 1).padding(.leading, 24) }
                .padding(.top, 6)
            } else if r.commitments.count >= Commitment.maxCount {
                Text("Maximum \(Commitment.maxCount) commitments reached").font(Typo.ui(11).italic()).foregroundStyle(Tok.ink3)
                    .frame(maxWidth: .infinity).padding(.top, 8)
            } else {
                Button {
                    adding = true
                    newFocused = true
                } label: {
                    HStack(spacing: 10) {
                        addMark
                        Text("Add new…").font(Typo.ui(13).italic()).foregroundStyle(Tok.reflectionInk.opacity(0.9))
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 34)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .focused($addFocused)
                .padding(.top, 2)
            }
        }
    }

    private var addMark: some View {
        Image(systemName: "plus").font(.system(size: 7, weight: .bold)).foregroundStyle(Tok.reflectionInk)
            .frame(width: 14, height: 14).overlay(Circle().strokeBorder(Tok.reflectionInk.opacity(0.6)))
            .accessibilityHidden(true)
    }

    private func saveNew() {
        let text = draft
        closeNew()
        Task { await model.reflection.addCommitment(text) }
    }

    private func closeNew() {
        adding = false
        draft = ""
        addFocused = true
    }
}

private struct CommitmentRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    let commitment: Commitment
    let last: Bool
    @Binding var editing: String?
    @State private var hover = false
    @State private var text = ""
    @FocusState private var fieldFocused: Bool
    @FocusState private var rowFocused: Bool

    private var r: ReflectionModel { model.reflection }
    private var isEditing: Bool { editing == commitment.id }

    var body: some View {
        let c = commitment
        HStack(alignment: .top, spacing: 10) {
            Button { Task { await r.toggle(c) } } label: {
                Circle().strokeBorder(Tok.reflectionInk, lineWidth: 1)
                    .overlay { if c.done { Circle().fill(Tok.reflectionInk) } }
                    .frame(width: 14, height: 14)
                    .frame(width: 24, height: 20)
                    .contentShape(.rect)
            }
            .buttonStyle(PressStyle(scale: 0.9))
            .accessibilityHidden(true)
            if isEditing {
                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typo.ui(13)).foregroundStyle(Tok.reflectionInk)
                    .lineLimit(1...3)
                    .focused($fieldFocused)
                    .writingToolsFollowPref()
                    .onKeyPress(.return, phases: .down) { press in
                        // ponytail: Shift-Return adds the line at the end, not at the caret.
                        guard press.modifiers.contains(.shift) else { return .ignored }
                        text += "\n"
                        return .handled
                    }
                    .onSubmit { save() }
                    .onExitCommand { editing = nil }
                    .onChange(of: fieldFocused) { _, f in if !f && isEditing { save() } }
                    .overlay(alignment: .bottom) { Rectangle().fill(Tok.reflection.opacity(0.4)).frame(height: 1).offset(y: 3) }
                    .accessibilityLabel("Edit commitment")
                    .onAppear {
                        text = c.text
                        fieldFocused = true
                    }
            } else {
                Text(c.text).font(Typo.ui(13)).strikethrough(c.done).foregroundStyle(c.done ? Tok.momentInk : Tok.reflectionInk)
                    .opacity(c.done ? 0.7 : 1)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture { Task { await r.toggle(c) } }
                    .help(c.text)
                if hover || rowFocused {
                    HStack(spacing: 2) {
                        action("pencil", "Edit “\(short(c.text))”") { editing = c.id }
                        action("trash", "Delete “\(short(c.text))”") { Task { await r.delete(c, undo: undo) } }
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Tok.reflection.opacity(0.15)).frame(height: 1) } }
        .onHover { hover = $0 }
        .animation(Motion.fade, value: hover)
        .contextMenu {
            Button(c.done ? "Mark as not done" : "Mark as done", systemImage: c.done ? "circle" : "checkmark.circle") { Task { await r.toggle(c) } }
            Button("Copy commitment", systemImage: "doc.on.clipboard") { r.copy(c) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { Task { await r.delete(c, undo: undo) } }
        }
        .modifier(RowAccessibility(enabled: !isEditing, commitment: c, edit: { editing = c.id },
                                   delete: { Task { await r.delete(c, undo: undo) } }, toggle: { Task { await r.toggle(c) } }))
    }

    private func action(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Tok.reflectionInk.opacity(0.8))
                .frame(width: 24, height: 24).contentShape(.rect)
        }
        .buttonStyle(PressStyle(hoverFill: true, radius: 6))
        .focused($rowFocused)
        .accessibilityLabel(label)
    }

    private func save() {
        let new = text
        editing = nil
        Task { await r.edit(commitment, to: new, undo: undo) }
    }

    private func short(_ s: String) -> String { s.count > 40 ? String(s.prefix(40)) + "…" : s }
}

/// A row is one toggle for VoiceOver, with Edit and Delete as its actions.
private struct RowAccessibility: ViewModifier {
    let enabled: Bool
    let commitment: Commitment
    let edit: () -> Void
    let delete: () -> Void
    let toggle: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(commitment.text)
                .accessibilityValue(commitment.done ? "Done" : "Not done")
                .accessibilityAddTraits(.isToggle)
                .accessibilityAction { toggle() }
                .accessibilityAction(named: "Edit", edit)
                .accessibilityAction(named: "Delete", delete)
        } else {
            content
        }
    }
}
