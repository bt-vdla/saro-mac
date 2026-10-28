import SaroKit
import SwiftUI

/// One node's side panel: where it comes up over time in the person's own words (each opens its entry on its day),
/// first and last seen, mentions per week, what it comes up with, and Forget or Rename.
struct NodePanel: View {
    let node: KnowledgeGraph.Node
    let graph: KnowledgeGraph
    let onSelect: (String) -> Void
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renaming = false
    @State private var name = ""
    @State private var confirming = false
    @State private var held = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(20)
            Rectangle().fill(Tok.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    weeks
                    related
                    mentions
                }
                .padding(20)
            }
            .scrollIndicators(.never)
            Rectangle().fill(Tok.line).frame(height: 1)
            forget.padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .glassPanel()
        .onExitCommand {
            if renaming { renaming = false } else if confirming { confirming = false } else { onClose() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(node.label)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(node.kind.tint).frame(width: 8, height: 8)
                Text([node.detail ?? node.kind.noun, "\(node.mentions.count) \(node.mentions.count == 1 ? "mention" : "mentions")"].joined(separator: " · "))
                    .monoCaps(10.5, tracking: 0.12).foregroundStyle(Tok.ink3)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Tok.ink2)
                        .frame(width: 28, height: 28).background(Tok.ink.opacity(0.05), in: .circle)
                }
                .buttonStyle(.plain).help("Close  esc").accessibilityLabel("Close")
            }
            if renaming {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain).font(Typo.serif(24, .medium)).focused($nameFocused)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Tok.surfaceAlt, in: .rect(cornerRadius: Radius.control))
                    .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Tok.sage, lineWidth: 1.5))
                    .onSubmit(saveName)
                    .onExitCommand { renaming = false }
                    .onAppear { nameFocused = true }
                Text("↵ save · esc cancel").monoCaps(10.5, tracking: 0.12).foregroundStyle(Tok.ink3)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(node.label).font(Typo.serif(26, .medium)).foregroundStyle(Tok.ink).fixedSize(horizontal: false, vertical: true)
                    IconButton(symbol: "pencil", label: "Correct the name") {
                        name = node.label
                        renaming = true
                    }
                }
            }
            if held {
                Text("Saro won’t keep that name.").font(Typo.ui(12)).foregroundStyle(Tok.ink3)
            }
            Text("First seen \(MemoryList.day(node.first)) · Last seen \(MemoryList.day(node.last))")
                .font(Typo.mono(11, .regular)).foregroundStyle(Tok.ink3)
        }
    }

    private var weeks: some View {
        let counts = KnowledgeGraph.weekly(node.mentions)
        let top = max(counts.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Last 12 weeks").monoCaps(10.5, tracking: 0.12).foregroundStyle(Tok.ink3)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(counts.enumerated()), id: \.offset) { _, n in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(n == 0 ? Tok.ink.opacity(0.08) : node.kind.tint.opacity(0.8))
                        .frame(height: n == 0 ? 2 : 4 + 26 * CGFloat(n) / CGFloat(top))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 30, alignment: .bottom)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mentions per week")
        .accessibilityValue(counts.map(String.init).joined(separator: ", "))
    }

    @ViewBuilder private var related: some View {
        let near = graph.neighbours(of: node.id).prefix(8)
        if !near.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Comes up with").monoCaps(10.5, tracking: 0.12).foregroundStyle(Tok.ink3)
                FlowRow(near.map(\.node)) { n in
                    Button { onSelect(n.id) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(n.kind.tint).frame(width: 7, height: 7)
                            Text(n.label).font(Typo.ui(12.5, .medium)).foregroundStyle(Tok.ink).lineLimit(1)
                        }
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Tok.surface.opacity(0.8), in: .capsule)
                        .overlay(Capsule().strokeBorder(Tok.border))
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(n.label), \(n.kind.noun.lowercased())")
                }
            }
        }
    }

    private var mentions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where it comes up").monoCaps(10.5, tracking: 0.12).foregroundStyle(Tok.ink3)
            ForEach(node.mentions) { s in
                Button { Task { await model.memory.open(s, in: model) } } label: {
                    Quote(text: s.quote, caption: "\(MemoryList.day(s.at)) · \(s.at.formatted(date: .omitted, time: .shortened))")
                }
                .buttonStyle(.plain)
                .help(s.field == "transcript" ? "Play from here" : "Open this entry")
                .accessibilityHint(s.field == "transcript" ? "Plays the recording from here" : "Opens this entry on its day")
            }
        }
    }

    @ViewBuilder private var forget: some View {
        if confirming {
            VStack(alignment: .leading, spacing: 10) {
                Text("Forget “\(node.label)”? Saro won’t learn it again. Your entries stay.")
                    .font(Typo.ui(13)).foregroundStyle(Tok.ink).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Forget") {
                        let (key, label) = (node.id, node.label)
                        Task {
                            await model.memory.forget(key, label: label)
                            onClose()
                        }
                    }
                    .buttonStyle(FilledButton(fill: Tok.danger))
                    Button("Keep") { confirming = false }
                        .buttonStyle(QuietButton(tint: Tok.ink, bordered: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
        } else {
            Button("Forget") { withAnimation(Motion.pick(Motion.small, reduce: reduceMotion)) { confirming = true } }
                .buttonStyle(QuietButton(tint: Tok.danger))
                .help("Saro forgets this and won’t learn it again")
        }
    }

    private func saveName() {
        let key = node.id
        let text = name
        renaming = false
        Task { held = await model.memory.rename(key, to: text) == .held }
    }
}

/// Chips that wrap onto as many lines as they need.
private struct FlowRow<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let cell: (Item) -> Cell

    init(_ items: [Item], @ViewBuilder cell: @escaping (Item) -> Cell) {
        self.items = items
        self.cell = cell
    }

    var body: some View {
        Flow(spacing: 6, lineSpacing: 6) { ForEach(items) { cell($0) } }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
