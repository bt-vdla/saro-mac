import AppKit
import SaroKit
import SwiftUI

/// Where keyboard focus sits in What Saro knows.
enum KnowsFocus: Hashable {
    case search, row(String), pencil(String), trash(String), undo(String), add, forget, forgetConfirm, keep, graph
}

/// One line of What Saro knows (MemorySection.tsx MemoryRow), keyboard-first: the row takes focus; Return edits, Space
/// opens Why, Delete deletes, ↑↓ move, and Tab reaches its pencil and trash, which show on hover or focus. A deleted
/// row is just its Undo.
struct MemoryRow: View {
    let memory: Memory
    let deleted: Bool
    let editing: Bool
    let whyOpen: Bool
    var focus: FocusState<KnowsFocus?>.Binding
    let onWhy: () -> Void
    let onEdit: () -> Void
    let onSave: (String) -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    let onUndo: () -> Void
    let onOpen: (Sighting) -> Void
    let onMove: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    @State private var showAll = false

    private var focused: Bool { focus.wrappedValue == .row(memory.key) }
    /// Focus anywhere on the row: the row itself, or its pencil or trash.
    private var within: Bool { focused || [.pencil(memory.key), .trash(memory.key)].contains(focus.wrappedValue) }
    private var fill: Color { focused ? Tok.sage.opacity(0.08) : hover ? Tok.ink.opacity(0.025) : .clear }

    var body: some View {
        content
            .padding(.vertical, 14).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(fill, in: .rect(cornerRadius: Radius.field))
            .contentShape(.rect)
            .onHover { hover = $0 }
            .focusable(!editing && !deleted)
            .focused(focus, equals: .row(memory.key))
            .focusEffectDisabled()
            // The editor's keys are its own: none of these reach past it while it is open.
            .onKeyPress(.return) {
                guard !deleted, !editing else { return .ignored }
                onEdit()
                return .handled
            }
            .onKeyPress(.space) {
                guard !deleted, !editing, memory.evidence != nil else { return .ignored }
                onWhy()
                return .handled
            }
            .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                guard !deleted, !editing else { return .ignored }
                onDelete()
                return .handled
            }
            .onKeyPress(.upArrow) { guard !editing else { return .ignored }; onMove(-1); return .handled }
            .onKeyPress(.downArrow) { guard !editing else { return .ignored }; onMove(1); return .handled }
    }

    @ViewBuilder private var content: some View {
        Group {
            if deleted {
                HStack(spacing: 4) {
                    Text("Deleted ·").font(Typo.ui(14)).foregroundStyle(Tok.ink3).accessibilityHidden(true)
                    KeyButton(focus: focus, id: .undo(memory.key), action: onUndo) { hover in
                        Text("Undo").font(Typo.ui(14, .medium)).foregroundStyle(hover ? Tok.sageDark : Tok.ink)
                            .underline(color: Tok.borderStrong)
                    }
                    .accessibilityLabel("Undo delete: \(memory.text)")
                }
            } else if editing {
                MemoryEditor(initial: memory.text, label: "Edit this memory", saveLabel: "Save", onSave: onSave, onCancel: onCancel)
            } else {
                line
            }
        }
    }

    private var line: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(memory.text).font(Typo.ui(15)).foregroundStyle(Tok.ink).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 0) {
                    Text(MemoryList.meta(memory)).font(Typo.mono(11.5, .regular)).foregroundStyle(Tok.ink3)
                    if memory.evidence != nil {
                        Text(" · ").font(Typo.mono(11.5, .regular)).foregroundStyle(Tok.ink3)
                        Button("Why", action: onWhy)
                            .buttonStyle(.plain).font(Typo.mono(11.5, .regular)).foregroundStyle(whyOpen ? Tok.ink : Tok.ink3)
                            .underline(color: Tok.borderStrong)
                            .accessibilityValue(whyOpen ? "Open" : "Closed")
                    }
                }
                if whyOpen {
                    why.transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -4)))
                }
            }
            .accessibilityElement(children: whyOpen ? .contain : .ignore)
            .accessibilityLabel(memory.text)
            .accessibilityValue(MemoryList.meta(memory))
            .accessibilityAction(named: "Edit", onEdit)
            .accessibilityAction(named: "Delete", onDelete)
            .accessibilityAction(named: whyOpen ? "Hide why" : "Why") { if memory.evidence != nil { onWhy() } }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                KeyButton(focus: focus, id: .pencil(memory.key), action: onEdit) { IconLabel(symbol: "pencil", hover: $0) }
                    .help("Edit").accessibilityLabel("Edit: \(memory.text)")
                KeyButton(focus: focus, id: .trash(memory.key), action: onDelete) { IconLabel(symbol: "trash", hover: $0, hoverTint: Tok.danger) }
                    .help("Delete").accessibilityLabel("Delete: \(memory.text)")
            }
            .opacity(hover || within ? 1 : 0)
            .animation(Motion.easeOut(0.16), value: hover || within)
        }
    }

    /// Every dated sighting in the person's own words, newest first; each opens its entry (a recording plays from it).
    private var why: some View {
        let shown = showAll ? memory.sightings : Array(memory.sightings.prefix(5))
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(shown) { s in
                Button { onOpen(s) } label: { Quote(text: s.quote, caption: "\(MemoryList.day(s.at)) · \(s.at.formatted(date: .omitted, time: .shortened))") }
                    .buttonStyle(.plain)
                    .help(s.field == "transcript" ? "Play from here" : "Open this entry")
                    .accessibilityHint(s.field == "transcript" ? "Plays the recording from here" : "Opens this entry")
            }
            if memory.sightings.count > shown.count {
                Button("Show all \(memory.sightings.count)") { showAll = true }
                    .buttonStyle(.plain).font(Typo.mono(11, .regular)).foregroundStyle(Tok.ink3).underline(color: Tok.borderStrong)
            }
            if memory.sightings.isEmpty, let told = memory.told { Quote(text: told, caption: "You told Saro") }
        }
        .padding(.top, 8)
    }
}

/// The person's own words, as Saro quotes them: serif italic in curly quotes, with a left rule.
struct Quote: View {
    let text: String
    var caption: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle().fill(Tok.borderStrong).frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("“\(MemoryList.clip(text, 140))”").font(Typo.serif(16, italic: true)).lineSpacing(3).foregroundStyle(Tok.ink2)
                    .multilineTextAlignment(.leading)
                if let caption { Text(caption).monoCaps(10.5).foregroundStyle(Tok.ink3) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(.rect)
    }
}

/// A 32 pt icon (ink-3, ink/5 and ink on hover; danger red for delete).
struct IconLabel: View {
    let symbol: String
    let hover: Bool
    var hoverTint: Color = Tok.ink

    var body: some View {
        Image(systemName: symbol).font(.system(size: 13, weight: .regular))
            .foregroundStyle(hover ? hoverTint : Tok.ink3)
            .frame(width: 32, height: 32)
            .background(Tok.ink.opacity(hover ? 0.05 : 0), in: .rect(cornerRadius: Radius.control))
            .contentShape(.rect)
    }
}

/// A plain icon button, for panels that aren't keyboard-first lists.
struct IconButton: View {
    let symbol: String
    let label: String
    var hoverTint: Color = Tok.ink
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) { IconLabel(symbol: symbol, hover: hover, hoverTint: hoverTint) }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .help(label)
            .accessibilityLabel(label)
    }
}

/// A control that keyboard users reach with Tab whatever Full Keyboard Access says: Return or Space runs it.
struct KeyButton<Label: View>: View {
    var focus: FocusState<KnowsFocus?>.Binding
    let id: KnowsFocus
    let action: () -> Void
    @ViewBuilder let label: (_ hover: Bool) -> Label
    @State private var hover = false

    var body: some View {
        label(hover)
            .contentShape(.rect)
            .onHover { hover = $0 }
            .onTapGesture(perform: action)
            .focusable()
            .focused(focus, equals: id)
            .focusEffectDisabled()
            .overlay {
                if focus.wrappedValue == id {
                    RoundedRectangle(cornerRadius: Radius.control + 3).strokeBorder(Tok.sage.opacity(0.55), lineWidth: 2).padding(-3)
                }
            }
            .onKeyPress(.return) { action(); return .handled }
            .onKeyPress(.space) { action(); return .handled }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
    }
}
