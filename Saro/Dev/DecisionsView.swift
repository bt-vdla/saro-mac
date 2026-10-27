#if DOGFOOD
import SaroKit
import SwiftUI

/// The decision register pane: every decision as a card, Open then Decided. Recording appends a `DecisionEvent`.
struct DecisionsView: View {
    @Environment(AppModel.self) private var model
    private let dev = DevMode.shared

    var body: some View {
        let open = Decision.all.filter { $0.currentStatus(in: dev.events) == .open }
        let decided = Decision.all.filter { $0.currentStatus(in: dev.events) == .decided }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Decisions").font(Typo.serif(28, .medium)).foregroundStyle(Tok.ink)
                        Text("D-01…D-22 from the BRD and the build decisions taken overnight (B-xx, option (a) is what the build did). Pick an option, add a note, Record. Then File → Export Decisions for Claude.")
                            .font(Typo.ui(13)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 6)
                    DevHeading("Open · \(open.count)").padding(.top, 4)
                    ForEach(open) { DecisionCard(decision: $0).id($0.id) }
                    DevHeading("Decided · \(decided.count)").padding(.top, 12)
                    ForEach(decided) { DecisionCard(decision: $0).id($0.id) }
                }
                .padding(28)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: dev.focus, initial: true) { _, id in
                guard let id else { return }
                Task { proxy.scrollTo(id, anchor: .top) }
            }
        }
        .background(Tok.bg)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Copy for Claude", systemImage: "doc.on.doc") { Task { await dev.copy(model) } }
                    .help("Copy the decisions as Markdown")
                Button("Export Decisions for Claude…", systemImage: "square.and.arrow.up") { Task { await dev.export(model) } }
                    .help("Write saro-decisions.json and saro-decisions.md into a folder (⇧⌘E)")
            }
        }
        .onAppear { model.screen = .decisions }
        .onDisappear {
            dev.cameFrom = nil
            dev.focus = nil
        }
        .task { await dev.load(model) }
    }
}

private struct DecisionCard: View {
    let decision: Decision
    @Environment(AppModel.self) private var model
    @State private var picked: String?
    @State private var note = ""
    @State private var saving = false
    private let dev = DevMode.shared

    var body: some View {
        let current = decision.currentChoice(in: dev.events)
        let history = dev.events.filter { $0.decisionId == decision.id }
        let choice = picked ?? current
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(decision.id).font(Typo.mono(11)).foregroundStyle(Tok.sage)
                Text(decision.title).font(Typo.ui(15, .semibold)).foregroundStyle(Tok.ink)
                Spacer()
                Text(decision.due).font(Typo.mono(9.5, .regular)).foregroundStyle(Tok.ink3)
                status(decision.currentStatus(in: dev.events))
            }
            Text(decision.context).font(Typo.ui(13)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(decision.options) { o in chip(o, selected: o.id == choice, current: o.id == current) }
            }
            HStack(spacing: 6) {
                DevHeading("Bharat's choice")
                Text(decision.option(current).map { "(\($0.id)) \($0.label)" } ?? "None recorded")
                    .font(Typo.ui(12.5, .medium)).foregroundStyle(current == nil ? Tok.ink3 : Tok.ink).lineLimit(2)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Note for Claude (optional)", text: $note, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .font(Typo.ui(12.5))
                Button("Record") {
                    saving = true
                    let c = choice, n = note
                    Task {
                        if await dev.record(decision.id, choice: c, note: n, model: model) {
                            note = ""
                            picked = nil
                        }
                        saving = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Tok.sage)
                .disabled(saving || (choice == current && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            if !decision.screens.isEmpty || !decision.brdRefs.isEmpty {
                Text((decision.screens.map(\.rawValue) + decision.brdRefs).joined(separator: "  "))
                    .font(Typo.mono(9.5, .regular)).foregroundStyle(Tok.ink3)
            }
            if !history.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    DevHeading("History")
                    ForEach(history.reversed(), id: \.id) { e in
                        Text(line(e)).font(Typo.ui(11.5)).foregroundStyle(Tok.ink2).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .saroSurface(radius: 14)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tok.sage, lineWidth: dev.focus == decision.id ? 2 : 0))
    }

    private func chip(_ o: Decision.Option, selected: Bool, current: Bool) -> some View {
        Button { picked = o.id } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("(\(o.id))").font(Typo.mono(10.5)).foregroundStyle(selected ? Tok.sage : Tok.ink3)
                Text(o.label).font(Typo.ui(12.5, selected ? .medium : .regular)).foregroundStyle(Tok.ink)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                if o.id == decision.recommendation { tag("Recommended", Tok.voice) }
                if current { tag("Current", Tok.sage) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selected ? Tok.sage.opacity(0.12) : Tok.surfaceAlt, in: .capsule)
            .overlay(Capsule().strokeBorder(selected ? Tok.sage : Tok.border, lineWidth: selected ? 1.5 : 1))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private func tag(_ text: String, _ tint: Color) -> some View {
        Text(text.uppercased()).font(Typo.mono(8.5)).tracking(0.6).foregroundStyle(tint)
    }

    private func status(_ s: Decision.Status) -> some View {
        Text(s.rawValue.uppercased())
            .font(Typo.mono(9))
            .tracking(0.6)
            .foregroundStyle(s == .open ? Tok.warning : Tok.sage)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(s == .open ? Tok.warning : Tok.sage, lineWidth: 1))
    }

    private func line(_ e: DecisionEvent) -> String {
        var parts = [e.createdAt.formatted(date: .abbreviated, time: .shortened)]
        if let c = e.choice { parts.append("chose (\(c)) \(decision.option(c)?.label ?? "")") }
        if let s = e.screenId { parts.append("on \(s)") }
        if let n = e.note { parts.append("“\(n)”") }
        return parts.joined(separator: " · ")
    }
}
#endif
