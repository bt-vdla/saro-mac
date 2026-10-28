import AppKit
import SaroKit
import SwiftUI

/// What Saro knows about you (MemorySection.tsx), as a sidebar pane (⌥⌘K) with the knowledge graph on top, or embedded
/// in Settings as the list alone. Every line is the person's to change or delete; the graph shows who and what comes up
/// together.
struct WhatSaroKnowsView: View {
    var embedded = false

    enum Mode: String { case graph, list }

    @Environment(AppModel.self) private var model
    @AppStorage("saro.knows.mode") private var mode: Mode = .graph
    @FocusState private var focus: KnowsFocus?

    var body: some View {
        let memory = model.memory
        Group {
            if embedded {
                // Settings scrolls the page, so here the list sits unscrolled in a card like every other section.
                SettingsCard(label: "Memory", title: "What Saro knows about you") {
                    header(memory)
                    MemoryListView(focus: $focus).padding(.top, 12)
                }
            } else {
                ZStack {
                    LitGround().ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 0) {
                        header(memory)
                            .padding(.horizontal, 32)
                            .padding(.top, 40)
                        if mode == .graph {
                            KnowledgeGraphView(focus: $focus)
                                .padding(.top, 12)
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    MemoryListView(focus: $focus)
                                        .frame(maxWidth: 680, alignment: .leading)
                                        .padding(.horizontal, 22)
                                        .padding(.top, 12).padding(.bottom, 40)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .scrollIndicators(.automatic)
                                // A line picked in ⌘K: shown and focused, with the search cleared so it can't be filtered out.
                                .task(id: memory.reveal) {
                                    guard let key = memory.reveal else { return }
                                    if memory.status != .ready { await memory.load() }
                                    memory.query = ""
                                    try? await Task.sleep(for: .milliseconds(80))
                                    proxy.scrollTo(key, anchor: .center)
                                    focus = .row(key)
                                    memory.reveal = nil
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Tok.bg)
            }
        }
        .background {
            // ⌘F finds; the field owns Esc while it holds a query.
            Button("Find") { focus = .search }.keyboardShortcut("f").opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
        .task { await memory.load() }
        .onAppear {
            if !embedded { model.screen = .knows }
            if let q = model.knowsQuery {
                memory.query = q
                model.knowsQuery = nil
            }
        }
        .onChange(of: model.knowsQuery) { _, q in
            guard let q else { return }
            memory.query = q
            model.knowsQuery = nil
        }
        .onChange(of: memory.reveal, initial: true) { _, key in if key != nil, !embedded { mode = .list } }
        // Closing the pane writes any delete still waiting on its Undo.
        .onDisappear { Task { await memory.commitPending() } }
    }

    private func header(_ memory: MemoryModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !embedded {
                Text("Memory").monoCaps(11, tracking: 0.12).foregroundStyle(Tok.ink3)
                Text("What Saro knows about you").font(Typo.serif(28, .medium)).foregroundStyle(Tok.ink).padding(.top, 6)
                    .accessibilityAddTraits(.isHeader)
            }
            Text("Short things Saro has picked up from your entries. Change or delete any of them.")
                .font(Typo.ui(14)).foregroundStyle(Tok.ink2).padding(.top, embedded ? 0 : 6)
            HStack(spacing: 16) {
                SearchField(text: Bindable(memory).query, focus: $focus)
                    .frame(minWidth: 180, maxWidth: 320)
                let n = memory.live.count
                Text("\(n) \(n == 1 ? "memory" : "memories")")
                    .monoCaps(11, tracking: 0.12).foregroundStyle(Tok.ink3)
                    .contentTransition(.numericText(value: Double(n)))
                    .animation(Motion.small, value: n)
                Spacer(minLength: 0)
                if !embedded {
                    Picker("View", selection: $mode) {
                        Label("Graph", systemImage: "point.3.connected.trianglepath.dotted").tag(Mode.graph)
                        Label("List", systemImage: "list.bullet").tag(Mode.list)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                    .help("Show what Saro knows as a graph or a list")
                }
                MemorySwitch()
            }
            .padding(.top, 18)
            if model.profile?.memoryPaused == true {
                Text("Paused. Saro won’t learn anything new. What’s here stays.")
                    .font(Typo.serif(17)).foregroundStyle(Tok.ink2).padding(.top, 14)
                    .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: model.profile?.memoryPaused)
    }
}

/// The Memory switch: off pauses learning (foundation's pause window), on resumes it.
private struct MemorySwitch: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Text("Memory").font(Typo.ui(13, .medium)).foregroundStyle(Tok.ink2)
            Toggle("Memory", isOn: Binding(get: { !(model.profile?.memoryPaused ?? false) },
                                           set: { on in Task { await model.setMemoryPaused(!on) } }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden().tint(Tok.sage)
                .accessibilityLabel("Memory")
                .accessibilityHint("When off, Saro won’t learn anything new. What’s here stays.")
        }
    }
}

/// "Search", with a magnifier; Esc clears it only when there's a query.
struct SearchField: View {
    @Binding var text: String
    var focus: FocusState<KnowsFocus?>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Tok.ink3).accessibilityHidden(true)
            TextField("Search", text: $text)
                .textFieldStyle(.plain).font(Typo.ui(14)).foregroundStyle(Tok.ink)
                .focused(focus, equals: .search)
                // Esc clears a query; with none it passes on, so Settings can close.
                .onKeyPress(.escape) {
                    guard !text.isEmpty else { return .ignored }
                    text = ""
                    return .handled
                }
                .accessibilityLabel("Search memories")
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tok.ink4) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(Tok.surfaceAlt.opacity(0.9), in: .rect(cornerRadius: Radius.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.field)
            .strokeBorder(focus.wrappedValue == .search ? Tok.sage : Tok.line, lineWidth: focus.wrappedValue == .search ? 1.5 : 1))
    }
}

// MARK: The list

/// The lines in their groups, then Add and Forget everything (MemorySection.tsx MemoryList).
struct MemoryListView: View {
    var focus: FocusState<KnowsFocus?>.Binding

    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing: String?
    @State private var why: String?
    @State private var confirming = false
    @State private var held = false
    @State private var skeleton = false

    private var memory: MemoryModel { model.memory }
    private var visible: [Memory] {
        memory.memories.filter { memory.pending.contains($0.key) || MemoryList.matches($0, memory.query) }
    }
    private var order: [String] { MemoryList.group(visible).flatMap { $0.items.map(\.key) } }
    /// The frequency rule: what a key started doesn't animate.
    private var animation: Animation? {
        NSApp.currentEvent?.type == .keyDown ? nil : Motion.pick(Motion.small, reduce: reduceMotion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch memory.status {
            case .loading:
                if skeleton { RowsSkeleton() }
            case .failed:
                HStack(spacing: 6) {
                    Text("Couldn’t read what Saro knows right now.").font(Typo.ui(14)).foregroundStyle(Tok.ink2)
                    Button("Retry") { Task { await memory.load() } }.buttonStyle(.plain).font(Typo.ui(14, .medium)).underline()
                }
                .padding(.vertical, 16)
            case .ready:
                content
                footer
            }
        }
        .task {
            // A local read is near-instant: the skeleton shows only if it isn't (no flash).
            try? await Task.sleep(for: .milliseconds(150))
            skeleton = true
        }
        #if DOGFOOD
        .onReceive(NotificationCenter.default.publisher(for: Snapshots.showWhy)) { _ in
            why = visible.first { $0.group == .people }?.key
        }
        #endif
        .onChange(of: memory.pending) { old, new in
            // A line whose window closed fades out; focus on its Undo moves to search.
            for key in old.subtracting(new) where focus.wrappedValue == .undo(key) && !memory.memories.contains(where: { $0.key == key }) {
                focus.wrappedValue = .search
            }
        }
    }

    @ViewBuilder private var content: some View {
        let q = memory.query.trimmingCharacters(in: .whitespaces)
        if memory.memories.isEmpty {
            EmptyMemory(cleared: memory.clearedEntries).padding(.vertical, 16)
        } else if visible.isEmpty {
            Text("Nothing mentions “\(q)”.").font(Typo.ui(14)).foregroundStyle(Tok.ink2).padding(.vertical, 16)
        } else {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(MemoryList.group(visible), id: \.group) { g in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(g.group.label).monoCaps(11, tracking: 0.12).foregroundStyle(Tok.ink3).padding(.horizontal, 10)
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            ForEach(Array(g.items.enumerated()), id: \.element.key) { i, m in
                                if i > 0 { Rectangle().fill(Tok.line).frame(height: 1).padding(.horizontal, 10) }
                                row(m)
                                    .id(m.key)
                                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 6)),
                                                                                       removal: .opacity.animation(Motion.easeOut(0.12))))
                            }
                        }
                    }
                    .transition(.opacity.animation(Motion.easeOut(0.12)))
                }
            }
        }
    }

    private func row(_ m: Memory) -> some View {
        MemoryRow(
            memory: m, deleted: memory.pending.contains(m.key), editing: editing == m.key, whyOpen: why == m.key, focus: focus,
            onWhy: { withAnimation(animation) { why = why == m.key ? nil : m.key } },
            onEdit: { editing = m.key },
            onSave: { text in
                Task {
                    let saved = await memory.edit(m, to: text)
                    // A failed write keeps the editor and what was typed; the toast says what happened.
                    guard saved != .failed else { return }
                    held = saved == .held
                    editing = nil
                    move(to: .pencil(m.key))
                }
            },
            onCancel: {
                editing = nil
                move(to: .pencil(m.key))
            },
            onDelete: {
                if why == m.key { why = nil }
                memory.delete(m, undoManager: undoManager)
                move(to: .undo(m.key))
            },
            onUndo: {
                memory.undo(m)
                move(to: .pencil(m.key))
            },
            onOpen: { s in Task { await memory.open(s, in: model) } },
            onMove: { by in
                guard let i = order.firstIndex(of: m.key) else { return }
                let j = i + by
                if order.indices.contains(j) { focus.wrappedValue = .row(order[j]) } else if j < 0 { focus.wrappedValue = .search }
            })
    }

    /// Focus lands once the view it names is on screen: a row turning into "Deleted · Undo" draws its Undo first.
    private func move(to target: KnowsFocus) {
        Task { focus.wrappedValue = target }
    }

    @ViewBuilder private var footer: some View {
        let n = memory.live.count
        Rectangle().fill(Tok.line).frame(height: 1).padding(.top, 16).padding(.horizontal, 10)
        VStack(alignment: .leading, spacing: 8) {
            if editing == "new" {
                MemoryEditor(initial: "", label: "Something Saro should know", saveLabel: "Add",
                             onSave: { text in
                                 Task {
                                     let saved = await memory.add(text)
                                     guard saved != .failed else { return }
                                     held = saved == .held
                                     editing = nil
                                     move(to: .add)
                                 }
                             },
                             onCancel: {
                                 editing = nil
                                 focus.wrappedValue = .add
                             })
            } else {
                KeyButton(focus: focus, id: .add, action: { editing = "new" }) { hover in
                    Label("Add something Saro should know", systemImage: "plus")
                        .font(Typo.ui(13, .medium)).foregroundStyle(hover ? Tok.ink : Tok.ink2)
                        .frame(minHeight: 44)
                }
            }
            if held { HeldNote() }
        }
        .padding(.top, 8).padding(.horizontal, 10)
        if n > 0 {
            Group {
                if confirming {
                    ForgetConfirm(count: n, focus: focus,
                                  onForget: {
                                      Task {
                                          if await memory.forgetAll() != nil {
                                              confirming = false
                                              focus.wrappedValue = .add
                                          }
                                      }
                                  },
                                  onKeep: {
                                      withAnimation(animation) { confirming = false }
                                      focus.wrappedValue = .forget
                                  })
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                } else {
                    KeyButton(focus: focus, id: .forget, action: {
                        withAnimation(animation) { confirming = true }
                        focus.wrappedValue = .keep
                    }) { hover in
                        Text("Forget everything").font(Typo.ui(13, .medium)).foregroundStyle(Tok.danger).opacity(hover ? 0.8 : 1)
                            .frame(minHeight: 44)
                    }
                    .transition(.opacity.animation(Motion.easeOut(0.12)))
                    .padding(.horizontal, 10)
                }
            }
            .padding(.top, 4)
        }
    }
}

/// "Forget all 12? Your entries stay." with the counted button and Keep them, where focus lands; Esc keeps.
private struct ForgetConfirm: View {
    let count: Int
    var focus: FocusState<KnowsFocus?>.Binding
    let onForget: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Forget all \(count)? Your entries stay.").font(Typo.ui(14)).foregroundStyle(Tok.ink)
            HStack(spacing: 10) {
                KeyButton(focus: focus, id: .forgetConfirm, action: onForget) { hover in
                    Text("Forget \(count) \(count == 1 ? "memory" : "memories")")
                        .font(Typo.ui(13, .medium)).foregroundStyle(Tok.onPrimary)
                        .padding(.horizontal, 14).frame(minHeight: 32)
                        .background(Tok.danger.opacity(hover ? 0.9 : 1), in: .rect(cornerRadius: Radius.control))
                }
                KeyButton(focus: focus, id: .keep, action: onKeep) { hover in
                    Text("Keep them").font(Typo.ui(13, .medium)).foregroundStyle(Tok.ink)
                        .padding(.horizontal, 14).frame(minHeight: 32)
                        .background(Tok.ink.opacity(hover ? 0.05 : 0), in: .rect(cornerRadius: Radius.control))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Tok.borderStrong))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tok.dangerBg, in: .rect(cornerRadius: Radius.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(Tok.dangerBorder))
        .onExitCommand(perform: onKeep)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Forget all \(count)? Your entries stay.")
    }
}

/// A line or name the SafetyGate held: nothing was kept, and the resources are right here, in whichever window it was
/// typed (SR-20), as a held entry shows them.
struct HeldNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saro won’t keep that one. If any of it is weighing on you, these people will listen.")
                .font(Typo.ui(13)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
            SafetyCardView(compact: true)
        }
    }
}

/// Nothing yet, and how many entries until Saro starts noticing (R-14).
struct EmptyMemory: View {
    let cleared: Int
    var graph = false

    var body: some View {
        VStack(alignment: graph ? .center : .leading, spacing: 8) {
            Text(graph ? "Saro learns who and what matters as you journal." : "Nothing yet. What matters to you will show up as you write.")
                .font(Typo.serif(18)).foregroundStyle(Tok.ink2).multilineTextAlignment(graph ? .center : .leading)
            if cleared < 2 {
                Text(cleared == 0 ? "Two more entries and Saro starts noticing what comes up." : "One more entry and Saro starts noticing what comes up.")
                    .font(Typo.ui(13)).foregroundStyle(Tok.ink3)
            }
        }
    }
}

/// Three pulsing bars over shorter meta bars; still with Reduce Motion. VoiceOver hears "Reading what Saro knows…".
private struct RowsSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                ForEach([0.72, 0.56, 0.64], id: \.self) { w in
                    VStack(alignment: .leading, spacing: 10) {
                        Capsule().fill(Tok.ink.opacity(0.07)).frame(width: geo.size.width * w, height: 14)
                        Capsule().fill(Tok.ink.opacity(0.05)).frame(width: 160, height: 10)
                    }
                    .padding(.vertical, 16)
                }
            }
            .opacity(dim ? 0.5 : 1)
        }
        .frame(height: 3 * 56)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Reading what Saro knows…")
    }
}
