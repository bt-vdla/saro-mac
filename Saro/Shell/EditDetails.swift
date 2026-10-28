import SaroKit
import SwiftUI

extension View {
    /// The shell's layer over the main window: Edit Details and Duplicate To ▸ Choose a Day, and "Preparing your day…".
    /// It also tells the Entry menu which window is the journal's.
    func shellSheets() -> some View { modifier(ShellSheets()) }
}

private struct ShellSheets: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var panels = ShellPanels.shared
        content
            .sheet(item: $panels.sheet) { sheet in
                Group {
                    switch sheet {
                    case .edit(let id): if let e = model.entry(id) { EditDetailsSheet(entry: e) }
                    case .duplicate(let id): ChooseDaySheet(id: id)
                    }
                }
                .environment(model)
                .environment(PrefsStore.shared)
            }
            .overlay {
                if DayImageProgress.shared.preparing {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Preparing your day…").font(Typo.ui(13, .medium)).foregroundStyle(Tok.ink)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .glassPanel()
                    .transition(.opacity)
                    .onAppear { AccessibilityNotification.Announcement("Preparing your day…").post() }
                }
            }
            .animation(Motion.fade, value: DayImageProgress.shared.preparing)
            .background(WindowReader(window: Binding(get: { JournalWindow.shared.window },
                                                     set: { if let w = $0 { JournalWindow.shared.window = w } })))
    }
}

/// Edit details (EditMetadataModal.tsx), by type: a moment's title, a voice note's title and summary, a still's caption,
/// a reflection's title and caption, a song's title and artist. ⌘↵ saves; the edit is gated again; a save that
/// doesn't land keeps the sheet open with what was typed, so Save is the retry.
struct EditDetailsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entry: Entry
    @State private var title = ""
    @State private var second = ""
    @State private var saving = false
    @State private var failed: String?
    @FocusState private var focus: Int?

    private var hasTitle: Bool { entry.kind != .still }
    private var secondLabel: (label: String, placeholder: String)? {
        switch entry.kind {
        case .moment: nil
        case .voice: ("Summary", "Add a summary")
        case .still, .reflection: ("Caption", "Add a caption")
        case .music: ("Artist", "Add the artist")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Edit details").font(Typo.ui(20, .semibold)).foregroundStyle(Tok.ink)
                Text("\(entry.kind.noun) · \(MusicDetail.when(entry))").monoCaps(10.5, tracking: 0.12).foregroundStyle(Tok.ink3)
            }
            if hasTitle {
                field("Title") {
                    // A song's title field shows the title its card reads until one is typed.
                    TextField("Title", text: $title, prompt: Text(entry.kind == .music ? model.title(for: entry) : "Add a title").foregroundStyle(Tok.ink3))
                        .textFieldStyle(.plain).font(Typo.ui(14, .medium))
                        .padding(.horizontal, 14).frame(height: 44)
                        .focused($focus, equals: 0)
                        .naturalAlignment(for: title)
                }
            }
            if let s = secondLabel {
                field(s.label) {
                    ZStack(alignment: .topLeading) {
                        if second.isEmpty {
                            Text(s.placeholder).font(Typo.ui(14)).foregroundStyle(Tok.ink3).padding(.horizontal, 14).padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $second)
                            .font(Typo.ui(14)).scrollContentBackground(.hidden)
                            .padding(.horizontal, 9).padding(.vertical, 12)
                            .focused($focus, equals: 1)
                            .naturalAlignment(for: second)
                    }
                    .frame(height: entry.kind == .music ? 56 : 104)
                }
            }
            if let failed {
                Text(failed).font(Typo.ui(12)).foregroundStyle(Tok.danger).transition(.opacity)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SheetButton(primary: false))
                    .keyboardShortcut(.cancelAction)
                    .disabled(saving)
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    .buttonStyle(SheetButton(primary: true))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(saving)
                    .help("Save  ⌘↵")
            }
        }
        .saroWritingTools()
        .padding(28)
        .frame(width: 440)
        .background(Tok.paper)
        .task {
            title = entry.titleUser ?? ""
            second = switch entry.kind {
            case .voice: (try? await model.ledger.summaryUser(id: entry.id)) ?? ""
            case .moment: ""
            default: entry.captionUser ?? ""
            }
            focus = hasTitle ? 0 : 1
        }
    }

    private func field(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(Typo.ui(13, .medium)).foregroundStyle(Tok.ink2)
            content()
                .background(Tok.surfaceAlt, in: .rect(cornerRadius: Radius.field))
                .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(Tok.line))
        }
    }

    private func save() async {
        saving = true
        failed = nil
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = second.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = entry
        do {
            try await model.saves.track(e.id) { [model] in
                let now = try await model.ledger.entry(e.id) ?? e
                let caption = e.kind == .moment || e.kind == .voice ? now.captionUser : s.isEmpty ? nil : s
                try await model.ledger.updateEntryText(id: e.id, body: now.body, titleUser: e.kind == .still ? now.titleUser : t.isEmpty ? nil : t,
                                                       captionUser: caption)
                if e.kind == .voice { try await model.ledger.updateSummary(id: e.id, s.isEmpty ? nil : s) }
                await model.reload()
                // Edited words are checked again before anything reads them.
                model.process(e.id)
            }
            dismiss()
        } catch {
            saving = false
            withAnimation(Motion.fade) { failed = "Couldn't save your changes. \(FailureCopy.remedy(for: error))" }
            model.show(.failed("Couldn't save your changes", error))
        }
    }
}

/// Duplicate To ▸ Choose a Day: the calendar, with days that haven't happened yet out of reach.
struct ChooseDaySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var date = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Duplicate to a day").font(Typo.ui(20, .semibold)).foregroundStyle(Tok.ink)
            Text("The copy keeps the same recording or photo, and stays out of what Saro counts.")
                .font(Typo.ui(12)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
            DatePicker("Day", selection: $date, in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SheetButton(primary: false)).keyboardShortcut(.cancelAction)
                Button("Duplicate") {
                    let day = LocalDay.string(for: date)
                    dismiss()
                    Task { await model.duplicate(id, to: day) }
                }
                .buttonStyle(SheetButton(primary: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 360)
        .background(Tok.paper)
    }
}

/// The dialogs' buttons (EditMetadataModal.tsx): 44 pt, a quiet Cancel and a sage Save.
struct SheetButton: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.ui(13, primary ? .semibold : .medium))
            .foregroundStyle(primary ? Tok.onPrimary : hover ? Tok.ink : Tok.ink2)
            .padding(.horizontal, primary ? 20 : 16).frame(minHeight: 44)
            .background(primary ? (hover ? Tok.sageDark : Tok.sage) : Tok.ink.opacity(hover ? 0.05 : 0), in: .rect(cornerRadius: Radius.control))
            .shadow(color: primary && hover ? Tok.sage.opacity(0.22) : .clear, radius: 10, y: 4)
            .contentShape(.rect(cornerRadius: Radius.control))
            .opacity(enabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .focusRing(radius: Radius.control)
            .onHover { hover = $0 }
    }
}
