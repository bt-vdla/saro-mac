import SaroKit
import SwiftUI

/// "For you to wonder" (QuestionSection.tsx): the day's question, held to three lines until the section opens, and the
/// person's answer: 'Add a passing thought…', an editor (⌘↵ saves, Esc cancels), then 'Today’s answer' with Edit. The
/// answer is gated before it is stored, and locks the question against re-reads.
struct QuestionSection: View {
    @Environment(AppModel.self) private var model
    let question: String?
    let open: Bool
    @Binding var editing: Bool
    let toggle: () -> Void
    @State private var draft = ""
    @State private var saving = false
    @State private var saved = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let r = model.reflection
        VStack(alignment: .leading, spacing: 3) {
            Button { if !editing { toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "book").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tok.still).frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                    Text("For you to wonder").font(Typo.ui(16.5, .semibold)).foregroundStyle(Tok.stillInk)
                    Spacer(minLength: 0)
                    Chevron(open: open, tint: Tok.stillInk).opacity(editing ? 0.5 : 1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            Text(Letter.typeset(question ?? "A question for today...")).font(Typo.serif(16)).lineSpacing(2).foregroundStyle(Tok.stillInk)
                .lineLimit(open ? nil : 3).fixedSize(horizontal: false, vertical: true)
            if let answer = r.answer, !open {
                Text("You wrote: \(answer)").font(Typo.ui(12)).foregroundStyle(Tok.ink2).lineLimit(1).padding(.top, 2)
            }
            if open, question != nil {
                VStack(alignment: .trailing, spacing: 4) {
                    if editing { editor } else if let answer = r.answer { answered(answer) } else {
                        Button("Add a passing thought…") { startEditing() }
                            .buttonStyle(.plain)
                            .font(Typo.ui(13).italic()).foregroundStyle(Tok.ink3)
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .contentShape(.rect)
                    }
                    if saved {
                        Text("Saved").font(Typo.ui(11)).foregroundStyle(Tok.ink3).transition(.opacity.combined(with: .offset(y: 4)))
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                // Room under Save, so the editor scrolled into view clears the panel's corner.
                .padding(.top, 6).padding(.bottom, editing ? 12 : 0)
                .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: saved)
        .contentShape(.rect)
        .contextMenu {
            Button("Refresh question", systemImage: "arrow.clockwise") { Task { await r.refreshQuestion() } }
                .disabled(r.busy.contains(.question) || editing)
            Button("Copy question", systemImage: "doc.on.doc") { r.copy(CopyText.question(question ?? ""), toast: "Question copied") }
                .disabled(question == nil)
        }
        .onChange(of: r.answerRequested, initial: true) { _, asked in
            guard asked, question != nil else { return }
            r.answerRequested = false
            startEditing()
        }
    }

    private var editor: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("Add a passing thought…").font(Typo.ui(13)).foregroundStyle(Tok.ink3).padding(.horizontal, 5).padding(.top, 1)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .font(Typo.ui(13)).foregroundStyle(Tok.ink)
                    .scrollContentBackground(.hidden)
                    .focused($fieldFocused)
                    .writingToolsFollowPref()
                    .disabled(saving)
                    .accessibilityLabel("Your answer")
            }
            .frame(height: 66)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Tok.surface.opacity(0.4), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Tok.still, lineWidth: 2))
            HStack(spacing: 8) {
                Button { editing = false } label: { round("xmark", Tok.ink2) }
                    .buttonStyle(PressStyle(hoverFill: true, radius: 16))
                    .keyboardShortcut(.cancelAction)
                    .disabled(saving)
                    .accessibilityLabel("Cancel")
                Button(action: save) {
                    Group { if saving { ProgressView().controlSize(.small) } else { round("checkmark", Tok.stillInk) } }.frame(width: 32, height: 32)
                }
                .buttonStyle(PressStyle(hoverFill: true, radius: 16))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                .help("Save  ⌘↵")
                .accessibilityLabel(saving ? "Saving answer" : "Save answer")
            }
        }
    }

    private func answered(_ answer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today’s answer").font(Typo.ui(10, .medium)).tracking(1.4).textCase(.uppercase).foregroundStyle(Tok.stillInk)
            Text(answer).font(Typo.ui(13.5)).lineSpacing(3).foregroundStyle(Tok.ink).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button { startEditing() } label: { Label("Edit", systemImage: "pencil").font(Typo.ui(11)).foregroundStyle(Tok.stillInk) }
                    .buttonStyle(.plain)
                    .frame(minHeight: 28)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Tok.still.opacity(0.3)))
    }

    private func round(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint).frame(width: 32, height: 32).contentShape(.circle)
    }

    private func startEditing() {
        draft = model.reflection.answer ?? ""
        if !open { toggle() }
        editing = true
        fieldFocused = true
    }

    private func save() {
        guard !saving else { return }
        saving = true
        Task {
            if await model.reflection.saveAnswer(draft) {
                editing = false
                saved = true
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    saved = false
                }
            }
            saving = false
        }
    }
}
