import AppKit
import SaroKit
import SwiftUI

/// MemorySection.tsx MemoryEditor: inline and autosizing. Return saves, Shift-Return is a space at the caret (a memory is
/// one line), Esc cancels. "↵ save · esc cancel", and a counter in the last 20 of 90 characters.
struct MemoryEditor: View {
    let initial: String
    let label: String
    let saveLabel: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(initial: String, label: String, saveLabel: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.label = label
        self.saveLabel = saveLabel
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: initial)
    }

    private var clean: String { MemoryList.oneLine(text) }
    private var canSave: Bool { !clean.isEmpty && clean != MemoryList.oneLine(initial) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(label, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.ui(15))
                .foregroundStyle(Tok.ink)
                .lineLimit(1...4)
                .writingToolsBehavior(.disabled)
                .focused($focused)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Tok.surfaceAlt, in: .rect(cornerRadius: Radius.field))
                .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(focused ? Tok.sage : Tok.borderStrong, lineWidth: focused ? 1.5 : 1))
                .onKeyPress(.return, phases: .down) { press in
                    // A Return that confirms an input method's composition is the field's (IME composition is respected).
                    let field = NSApp.keyWindow?.firstResponder as? NSTextView
                    if field?.hasMarkedText() == true { return .ignored }
                    if !press.modifiers.contains(.shift) {
                        submit()
                    } else if let field {
                        field.insertText(" ", replacementRange: field.selectedRange())
                    } else {
                        text += " "
                    }
                    return .handled
                }
                .onExitCommand(perform: onCancel)
                .onChange(of: text) { _, t in if t.count > MemoryList.maxChars { text = String(t.prefix(MemoryList.maxChars)) } }
                .accessibilityLabel(label)
            HStack(spacing: 12) {
                Text("↵ save · esc cancel").monoCaps(11, tracking: 0.12).foregroundStyle(Tok.ink3).accessibilityHidden(true)
                if text.count > MemoryList.maxChars - 20 {
                    Text("\(text.count)/\(MemoryList.maxChars)").font(Typo.mono(11, .regular)).monospacedDigit().foregroundStyle(Tok.ink3)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(QuietButton())
                Button(saveLabel, action: submit)
                    .buttonStyle(FilledButton(fill: Tok.sage))
                    .disabled(!canSave)
            }
        }
        .onAppear { focused = true }
    }

    private func submit() {
        if canSave { onSave(clean) } else if !clean.isEmpty { onCancel() }
    }
}

/// A text button that brightens on hover: Cancel, Retry, Keep them.
struct QuietButton: ButtonStyle {
    var tint: Color = Tok.ink2
    var bordered = false
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.ui(13, .medium))
            .foregroundStyle(hover ? Tok.ink : tint)
            .padding(.horizontal, 12).frame(minHeight: 30)
            .background(Tok.ink.opacity(hover || configuration.isPressed ? 0.05 : 0), in: .rect(cornerRadius: Radius.control))
            .overlay { if bordered { RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Tok.borderStrong) } }
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .onHover { hover = $0 }
    }
}

/// Save, Add, Forget: a filled control-radius button.
struct FilledButton: ButtonStyle {
    let fill: Color
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.ui(13, .medium))
            .foregroundStyle(Tok.onPrimary)
            .padding(.horizontal, 14).frame(minHeight: 30)
            .background(fill, in: .rect(cornerRadius: Radius.control))
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .contentShape(.rect)
    }
}
