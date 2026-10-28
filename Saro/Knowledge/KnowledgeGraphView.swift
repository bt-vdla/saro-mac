import AppKit
import SaroKit
import SwiftUI

/// The knowledge graph: people, places, themes, feelings and intentions as nodes sized by mentions, joined by what comes
/// up in the same entry or day. Pans and zooms like the day canvas; hover lights a node's neighbours; it settles on the
/// surface spring, and Reduce Motion places it without moving. ←→ step through nodes, Return or a click opens one.
struct KnowledgeGraphView: View {
    var focus: FocusState<KnowsFocus?>.Binding

    enum Range: String, CaseIterable {
        case week = "Week", month = "Month", all = "All"

        var since: Date? {
            switch self {
            case .week: Date.now.addingTimeInterval(-7 * 86_400)
            case .month: Date.now.addingTimeInterval(-30 * 86_400)
            case .all: nil
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var kinds = Set(KnowledgeGraph.Node.Kind.allCases)
    @State private var range: Range = .all
    @State private var graph = KnowledgeGraph.build([])
    @State private var layout: [String: SIMD2<Double>] = [:]
    @State private var camera = Camera()
    @State private var userMoved = false
    /// The last rebuild moves its nodes on the spring.
    @State private var settling = false
    @State private var hovered: String?
    @State private var selected: String?
    @State private var panStart: CGSize?
    @State private var size: CGSize = .zero

    private var memory: MemoryModel { model.memory }
    nonisolated private static let unit: CGFloat = 120
    private static let panelWidth: CGFloat = 360

    /// Text size too: the labels' boxes grow with it.
    private var buildKey: String {
        "\(memory.rows.count)|\(memory.rows.last?.id ?? "")|\(range)|\(kinds.map(\.rawValue).sorted())|\(PrefsStore.shared.textScale)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            filters.padding(.horizontal, 32)
            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    stage(geo.size)
                    if let id = selected, let node = graph.nodes.first(where: { $0.id == id }) {
                        NodePanel(node: node, graph: graph, onSelect: { select($0) }, onClose: { select(nil) })
                            .frame(width: Self.panelWidth)
                            .padding(.trailing, 20).padding(.vertical, 16)
                            .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                            .id(id)
                    }
                }
                .animation(Motion.pick(Motion.surface, reduce: reduceMotion), value: selected)
                .onAppear { size = geo.size }
                .onChange(of: geo.size) { _, s in
                    size = s
                    if !userMoved { fit() }
                }
            }
        }
        .task(id: buildKey) { await rebuild() }
        #if DOGFOOD
        .onReceive(NotificationCenter.default.publisher(for: Snapshots.pickNode)) { _ in select(graph.nodes.first?.id) }
        #endif
    }

    // MARK: Filters

    private var filters: some View {
        HStack(spacing: 8) {
            ForEach(KnowledgeGraph.Node.Kind.allCases, id: \.self) { k in
                let on = kinds.contains(k)
                Button {
                    if on, kinds.count > 1 { kinds.remove(k) } else { kinds.insert(k) }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(k.tint).frame(width: 8, height: 8).opacity(on ? 1 : 0.35)
                        Text(k.plural).font(Typo.ui(12.5, .medium)).foregroundStyle(on ? Tok.ink : Tok.ink3)
                    }
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(on ? Tok.surface.opacity(0.9) : Color.clear, in: .capsule)
                    .overlay(Capsule().strokeBorder(on ? Tok.border : Tok.line))
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(k.plural)
                .accessibilityValue(on ? "Shown" : "Hidden")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 12)
            Picker("Time", selection: $range) {
                ForEach(Range.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 190)
            .help("Mentions from the last week, the last month, or all time")
        }
        .animation(Motion.pick(Motion.small, reduce: reduceMotion), value: kinds)
    }

    // MARK: Stage

    @ViewBuilder private func stage(_ size: CGSize) -> some View {
        let lit = litIDs
        let shown = labelled(lit)
        ZStack {
            CanvasEvents(enabled: model.pane == .knows && !model.searchOpen,
                         onPan: { d, _, _ in
                             userMoved = true
                             camera.pan = CGSize(width: camera.pan.width + d.width, height: camera.pan.height + d.height)
                         },
                         onZoom: { f, p, _ in
                             userMoved = true
                             zoom(by: f, at: p)
                         })
            // Each edge is its own shape so its ends move in the nodes' transaction and settle with them.
            ZStack {
                ForEach(graph.edges, id: \.key) { e in
                    if let a = layout[e.a], let b = layout[e.b] {
                        let on = lit.map { $0.contains(e.a) && $0.contains(e.b) } ?? true
                        EdgeLine(a: screen(a), b: screen(b))
                            .stroke(Tok.ink.opacity(on ? (lit == nil ? 0.13 : 0.34) : 0.04), lineWidth: 0.75 + 1.1 * log2(1 + e.weight))
                            // A new edge has no earlier ends to move from, so it waits out the spring (it settles by 0.4 s).
                            .transition(.asymmetric(insertion: settling ? .opacity.animation(Motion.easeOut(0.2).delay(0.35)) : .identity,
                                                    removal: .opacity))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            ForEach(graph.nodes) { node in
                if let p = layout[node.id] {
                    NodeDot(node: node, selected: selected == node.id, dimmed: !(lit?.contains(node.id) ?? true) || !matches(node),
                            labelScale: max(1, NodeDot.labelFloor / camera.zoom), labelled: shown.contains(node.id),
                            onHover: { hovered = $0 ? node.id : (hovered == node.id ? nil : hovered) },
                            onTap: { select(selected == node.id ? nil : node.id) })
                        .scaleEffect(camera.zoom)
                        .position(screen(p))
                }
            }
            if graph.nodes.isEmpty, memory.status == .ready {
                EmptyMemory(cleared: memory.clearedEntries, graph: true).frame(maxWidth: 420)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(.rect)
        .gesture(DragGesture(minimumDistance: 3)
            .onChanged { v in
                if panStart == nil { panStart = camera.pan }
                userMoved = true
                camera.pan = CGSize(width: (panStart?.width ?? 0) + v.translation.width, height: (panStart?.height ?? 0) + v.translation.height)
            }
            .onEnded { _ in panStart = nil })
        .onTapGesture(count: 2) {
            userMoved = false
            withAnimation(Motion.pick(Motion.surface, reduce: reduceMotion)) { fit() }
        }
        .onTapGesture { select(nil) }
        .focusable()
        .focused(focus, equals: .graph)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            step(press.key == .rightArrow || press.key == .downArrow ? 1 : -1)
            return .handled
        }
        .onExitCommand { if selected != nil { select(nil) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What Saro knows, as a graph")
    }

    /// The hovered (else selected) node and its neighbours; nil when nothing is lit.
    private var litIDs: Set<String>? {
        guard let id = hovered ?? selected else { return nil }
        return Set(graph.neighbours(of: id).map(\.node.id) + [id])
    }

    /// The labels drawn, each at its readable size: the hovered or selected node first, then its neighbours, then the
    /// busiest, leaving out one that would overlap a label already placed. Hovering a node brings its label back.
    // ponytail: pairwise rectangle test, O(n²) a render; fine at 80 nodes.
    private func labelled(_ lit: Set<String>?) -> Set<String> {
        let scale = max(camera.zoom, NodeDot.labelFloor), text = PrefsStore.shared.textScale
        let rank = { (n: KnowledgeGraph.Node) in n.id == (hovered ?? selected) ? 0 : lit?.contains(n.id) == true ? 1 : 2 }
        var placed: [CGRect] = []
        var out = Set<String>()
        for n in (0...2).flatMap({ r in graph.nodes.filter { rank($0) == r } }) {
            guard let p = layout[n.id] else { continue }
            let c = screen(p), w = NodeDot.labelWidth(n, scale: text) * scale
            let r = CGRect(x: c.x - w / 2, y: c.y + (NodeDot.diameter(n) / 2 + 5) * camera.zoom, width: w, height: NodeDot.labelHeight * text * scale)
            guard !placed.contains(where: { $0.intersects(r) }) else { continue }
            placed.append(r)
            out.insert(n.id)
        }
        return out
    }

    private func matches(_ node: KnowledgeGraph.Node) -> Bool {
        let q = memory.query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || node.label.localizedStandardContains(q) || node.mentions.contains { $0.quote.localizedStandardContains(q) }
    }

    // MARK: Camera

    private func screen(_ p: SIMD2<Double>) -> CGPoint {
        CGPoint(x: p.x * Self.unit * camera.zoom + camera.pan.width, y: p.y * Self.unit * camera.zoom + camera.pan.height)
    }

    private func zoom(by factor: CGFloat, at p: CGPoint) {
        let next = (camera.zoom * factor).clamped(to: Camera.range)
        camera.pan = CGSize(width: p.x - (p.x - camera.pan.width) * next / camera.zoom, height: p.y - (p.y - camera.pan.height) * next / camera.zoom)
        camera.zoom = next
    }

    /// Frames every node, leaving room for the panel when one is open; never above 100%.
    private func fit() {
        guard !layout.isEmpty, size.width > 0 else { return }
        let xs = layout.values.map { $0.x * Self.unit }, ys = layout.values.map { $0.y * Self.unit }
        let (minX, maxX, minY, maxY) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
        let room = CGSize(width: size.width - (selected == nil ? 0 : Self.panelWidth + 20) - 160, height: size.height - 140)
        let z = min(1, room.width / max(maxX - minX, 1), room.height / max(maxY - minY, 1)).clamped(to: 0.5...1)
        let center = CGPoint(x: (size.width - (selected == nil ? 0 : Self.panelWidth + 20)) / 2, y: size.height / 2)
        camera = Camera(zoom: z, pan: CGSize(width: center.x - (minX + maxX) / 2 * z, height: center.y - (minY + maxY) / 2 * z))
    }

    // MARK: Building

    private func rebuild() async {
        let rows = memory.rows
        let (range, kinds, start, scale) = (range.since, kinds, layout, PrefsStore.shared.textScale)
        let (g, l) = await Task.detached(priority: .userInitiated) {
            var g = KnowledgeGraph.build(rows, since: range)
            g.nodes.removeAll { !kinds.contains($0.kind) }
            let ids = Set(g.nodes.map(\.id))
            g.edges.removeAll { !ids.contains($0.a) || !ids.contains($0.b) }
            let boxes = Dictionary(uniqueKeysWithValues: g.nodes.map { n in
                (n.id, SIMD2(Double(max(NodeDot.diameter(n), NodeDot.labelWidth(n, scale: scale))) / 2 + 8,
                             Double(NodeDot.diameter(n) + 10 + 2 * NodeDot.labelHeight * scale) / 2 + 4) / Double(Self.unit))
            })
            return (g, g.layout(from: start, extents: boxes))
        }.value
        let first = layout.isEmpty
        // The graph settles into its new shape on the surface spring; Reduce Motion places it without moving.
        let settle = first || reduceMotion || Motion.byKey ? nil : Motion.surface
        withAnimation(settle) {
            settling = settle != nil
            graph = g
            layout = l
            if let s = selected, !g.nodes.contains(where: { $0.id == s }) { selected = nil }
            if !userMoved { fit() }
        }
    }

    /// After a key the panel and camera are just there. A nil animation alone isn't enough: the stage's
    /// `.animation(value: selected)` replaces it, and only disabling animations stops that.
    private func select(_ id: String?) {
        let keyboard = Motion.byKey
        var t = Transaction(animation: keyboard ? nil : Motion.pick(Motion.surface, reduce: reduceMotion))
        t.disablesAnimations = keyboard
        withTransaction(t) {
            selected = id
            if !userMoved { fit() }
        }
        if let id, let node = graph.nodes.first(where: { $0.id == id }) {
            AccessibilityNotification.Announcement("\(node.label), \(node.mentions.count) \(node.mentions.count == 1 ? "mention" : "mentions")").post()
        }
    }

    /// ←→ walk the nodes, busiest first.
    private func step(_ by: Int) {
        let ids = graph.nodes.map(\.id)
        guard !ids.isEmpty else { return }
        let i = selected.flatMap { ids.firstIndex(of: $0) }.map { ($0 + by + ids.count) % ids.count } ?? 0
        select(ids[i])
    }
}

extension KnowledgeGraph.Node.Kind {
    /// Evergreen kind colours: people echo violet, places music blue, themes moment green, feelings still clay,
    /// intentions reflection gold.
    var tint: Color {
        switch self {
        case .person: Tok.echo
        case .place: Tok.music
        case .theme: Tok.moment
        case .feeling: Tok.still
        case .intention: Tok.reflection
        }
    }
}

/// One node: a disc sized by mentions with its label under it. The disc is the view's centre, where its edges meet.
struct NodeDot: View {
    let node: KnowledgeGraph.Node
    let selected: Bool
    let dimmed: Bool
    /// Over the camera's zoom, so a label far out stays readable.
    let labelScale: CGFloat
    let labelled: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false

    private var diameter: CGFloat { Self.diameter(node) }
    private var label: String { MemoryList.clip(node.label, 24) }

    /// The smallest zoom a label is drawn at: Geist 11.5 there is the type scale's 10.5.
    static let labelFloor: CGFloat = 0.92
    nonisolated static let labelHeight: CGFloat = 20
    nonisolated static func diameter(_ n: KnowledgeGraph.Node) -> CGFloat { min(64, 14 + 9 * CGFloat(n.mentions.count).squareRoot()) }
    /// Near enough for layout: Geist at 12.5 pt (times Text size) averages under 7 pt a character, plus the capsule's padding.
    nonisolated static func labelWidth(_ n: KnowledgeGraph.Node, scale: CGFloat) -> CGFloat {
        CGFloat(MemoryList.clip(n.label, 24).count) * 7 * scale + 12
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                Circle()
                    .fill(node.kind.tint.opacity(0.85))
                    .overlay(Circle().strokeBorder(Tok.rim.opacity(0.7), lineWidth: 1))
                    .frame(width: diameter, height: diameter)
                    .overlay(Circle().strokeBorder(Tok.sage.opacity(selected ? 0.7 : 0), lineWidth: 2).padding(-4))
                    .scaleEffect(hover && !reduceMotion ? 1.08 : 1)
                    .elevation(selected || hover ? .raise : .lift)
                Text(label)
                    .font(Typo.ui(node.mentions.count > 2 ? 12.5 : 11.5, selected ? .semibold : .medium))
                    .foregroundStyle(Tok.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Tok.paper.opacity(0.75), in: .capsule)
                    .scaleEffect(labelScale, anchor: .top)
                    .opacity(labelled ? 1 : 0)
                    .allowsHitTesting(labelled)
            }
        }
        .buttonStyle(.plain)
        .opacity(dimmed ? 0.22 : 1)
        .animation(Motion.small, value: hover)
        .animation(Motion.easeOut(0.16), value: dimmed)
        .animation(Motion.easeOut(0.16), value: labelled)
        .onHover { h in
            hover = h
            onHover(h)
        }
        .help("\(node.label) · \(node.mentions.count) \(node.mentions.count == 1 ? "mention" : "mentions")")
        .accessibilityLabel("\(node.label), \(node.kind.noun.lowercased()), \(node.mentions.count) \(node.mentions.count == 1 ? "mention" : "mentions")")
        .accessibilityHint("Shows where it comes up")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .frame(height: diameter, alignment: .top)
    }
}

/// One edge, its ends animatable, so it settles on the same spring as the nodes it joins.
private struct EdgeLine: Shape {
    var a: CGPoint
    var b: CGPoint

    var animatableData: AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData> {
        get { AnimatablePair(a.animatableData, b.animatableData) }
        set { (a.animatableData, b.animatableData) = (newValue.first, newValue.second) }
    }

    func path(in _: CGRect) -> Path {
        Path { p in
            p.move(to: a)
            p.addLine(to: b)
        }
    }
}

private extension KnowledgeGraph.Edge {
    var key: String { "\(a)|\(b)" }
}
