#if DOGFOOD
import SaroKit
import SwiftUI

/// ⇧⌘D: the current screen's dev notes on the trailing edge, with its open decisions and a note box for Claude.
struct DevNotesPanel: View {
    @Environment(AppModel.self) private var model
    @State private var picked: ScreenID?
    @State private var draft = ""
    private let dev = DevMode.shared

    private var screen: ScreenID { picked ?? model.screen }

    var body: some View {
        let notes = DevNotes.of(screen)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                DevHeading("Dev notes")
                Spacer()
                Picker("Screen", selection: Binding(get: { screen }, set: { picked = $0 == model.screen ? nil : $0 })) {
                    ForEach(ScreenID.allCases) { Text(DevNotes.of($0).name).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button { model.devNotesVisible = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Hide dev notes (⇧⌘D)")
            }
            .padding(14)
            Divider().overlay(Tok.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(screen.rawValue).font(Typo.mono(10)).foregroundStyle(Tok.ink3).textSelection(.enabled)
                        Text(notes.does).font(Typo.ui(13)).foregroundStyle(Tok.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    list("Built", notes.built, mark: "checkmark", tint: Tok.sage)
                    list("Stubbed", notes.stubbed, mark: "circle.dashed", tint: Tok.ink3)
                    list("Known issues", notes.issues, mark: "exclamationmark.triangle", tint: Tok.warning)
                    if !notes.brd.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            DevHeading("BRD")
                            Text(notes.brd.joined(separator: "  ")).font(Typo.mono(10.5, .regular)).foregroundStyle(Tok.ink2)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    decisions
                    noteBox
                }
                .padding(14)
            }
        }
        .frame(width: 340)
        .frame(maxHeight: .infinity, alignment: .top)
        .saroSurface(radius: 16, lifted: true)
        .padding(12)
        .onChange(of: model.screen) { picked = nil }
    }

    @ViewBuilder
    private func list(_ title: String, _ items: [String], mark: String, tint: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                DevHeading(title)
                ForEach(items, id: \.self) { item in
                    Label {
                        Text(item).font(Typo.ui(12.5)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: mark).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var decisions: some View {
        let open = DevNotes.decisions(for: screen).filter { $0.currentStatus(in: dev.events) == .open }
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                DevHeading("Open decisions")
                ForEach(open) { d in
                    Button { dev.open(d.id, model: model) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(d.id).font(Typo.mono(10)).foregroundStyle(Tok.sage)
                                Text(d.title).font(Typo.ui(12.5, .medium)).foregroundStyle(Tok.ink)
                            }
                            Text("Recommended: \(d.option(d.recommendation)?.label ?? d.recommendation)")
                                .font(Typo.ui(11.5)).foregroundStyle(Tok.ink3).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Tok.surfaceAlt, in: .rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tok.border))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Open \(d.id) in Decisions")
                }
            }
        }
    }

    private var noteBox: some View {
        let history = dev.notes.filter { $0.screenId == screen.rawValue }.reversed()
        return VStack(alignment: .leading, spacing: 8) {
            DevHeading("Notes for Claude")
            TextField("Add a note for Claude", text: $draft, axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
                .font(Typo.ui(12.5))
            HStack {
                Text("Saved with \(screen.rawValue)").font(Typo.mono(9.5, .regular)).foregroundStyle(Tok.ink3)
                Spacer()
                Button("Add Note") {
                    let text = draft, target = screen
                    Task { if await dev.addNote(text, screen: target, model: model) { draft = "" } }
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(Array(history), id: \.id) { n in
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.createdAt.formatted(date: .abbreviated, time: .shortened)).font(Typo.mono(9.5, .regular)).foregroundStyle(Tok.ink3)
                    Text(n.note).font(Typo.ui(12.5)).foregroundStyle(Tok.ink2).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Mono-caps section heading used across dev mode.
struct DevHeading: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased()).font(Typo.mono(10)).tracking(0.8).foregroundStyle(Tok.ink3)
    }
}
#endif
