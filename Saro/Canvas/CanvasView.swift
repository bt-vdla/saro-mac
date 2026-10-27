import SaroKit
import SwiftUI
import UniformTypeIdentifiers

/// One free canvas per local day (D-03, FR-CAN-01…06): pan, pinch or ⌘-scroll zoom, press-and-hold drag, marquee,
/// a contextual toolbar, stacks that fan out in place, and cards that morph open into their detail view.
struct DayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var size: CGSize = .zero
    @State private var marquee: CGRect?
    @State private var marqueeBase: Set<String> = []
    @State private var dragging: (ids: Set<String>, offset: CGSize)?
    @State private var dropTargeted = false
    // The morph: what's rendered, where it grew from, and whether it has finished growing.
    @State private var shownID: String?
    @State private var morphFrom: CGRect = .zero
    @State private var expanded = false
    @FocusState private var focused: Bool

    /// ponytail: a fixed hold before a card drag (FR-CAN-06); tune on a real trackpad (B-05).
    static let holdBeforeDrag = 0.12

    var body: some View {
        @Bindable var model = model
        GeometryReader { geo in
            ZStack {
                background
                cards
                if let sid = model.openStackID { fan(sid) }
                if let m = marquee {
                    Rectangle().fill(Tok.ink.opacity(0.06)).overlay(Rectangle().strokeBorder(Tok.ink3.opacity(0.5), lineWidth: 1))
                        .frame(width: m.width, height: m.height).position(x: m.midX, y: m.midY).allowsHitTesting(false)
                }
                if shownID == nil { chrome }
                if let id = shownID, let entry = model.entry(id) { detail(entry) }
                if let kind = model.recorderKind {
                    Tok.bg.opacity(0.7).ignoresSafeArea().onTapGesture {}
                    RecorderSlot(kind: kind) { model.recorderKind = nil }
                }
                ToastHost()
            }
            .onAppear { size = geo.size }
            .onChange(of: geo.size) { _, new in size = new }
        }
        .clipped()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onDeleteCommand { Task { await model.trash(model.selection, undoManager: undoManager) } }
        .onExitCommand {
            if model.openEntryID != nil { model.openEntryID = nil } else if model.openStackID != nil { model.openStackID = nil } else { model.selection = [] }
        }
        .onKeyPress(.return) {
            guard model.openEntryID == nil, model.selection.count == 1, let id = model.selection.first else { return .ignored }
            model.openEntryID = id
            return .handled
        }
        .onPasteCommand(of: [.image, .png, .tiff, .heic, .jpeg]) { providers in load(providers, at: nil, origin: "pasted") }
        .onDrop(of: [.image], isTargeted: $dropTargeted) { providers, location in
            load(providers, at: world(location), origin: "dropped")
            return true
        }
        .onChange(of: model.openEntryID) { _, id in morph(to: id) }
        .onChange(of: model.day) { _, _ in
            zoom = 1
            pan = .zero
        }
        .onChange(of: screenID) { _, s in model.screen = s }
        .onAppear { focused = true }
        .inspector(isPresented: $model.showNoticed) {
            NoticedView().inspectorColumnWidth(min: 300, ideal: 340, max: 440)
        }
        .sheet(isPresented: $model.showLetter) { LetterView() }
    }

    private var screenID: ScreenID {
        if model.recorderKind != nil { return .recorder }
        if let id = model.openEntryID, let e = model.entry(id) {
            return switch e.kind {
            case .moment: .momentDetail
            case .voice: .voiceDetail
            case .still: .stillDetail
            case .reflection, .music: .writingDetail
            }
        }
        return model.openStackID != nil ? .stack : .canvas
    }

    // MARK: Coordinates

    private func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * zoom + pan.width, y: p.y * zoom + pan.height) }
    private func world(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - pan.width) / zoom, y: (p.y - pan.height) / zoom) }

    private func zoom(by factor: CGFloat, at p: CGPoint) {
        let next = min(2.5, max(0.25, zoom * factor))
        pan = CGSize(width: p.x - (p.x - pan.width) * next / zoom, height: p.y - (p.y - pan.height) * next / zoom)
        zoom = next
    }

    private func screenRect(_ entry: Entry) -> CGRect {
        if let sid = model.openStackID, let p = fanPoints(sid)[entry.id] {
            return CGRect(center: p, size: CanvasMath.size(entry.kind))
        }
        let s = CanvasMath.size(entry.kind)
        return CGRect(center: screen(model.position(of: entry.id)), size: CGSize(width: s.width * zoom, height: s.height * zoom))
    }

    // MARK: Layers

    private var background: some View {
        ZStack {
            Tok.bg
            // A quiet dot grid that moves with the canvas, so panning and zoom read as space.
            Canvas { ctx, sz in
                let step = 36 * zoom
                guard step > 9 else { return }
                let ox = pan.width.truncatingRemainder(dividingBy: step), oy = pan.height.truncatingRemainder(dividingBy: step)
                var x = ox
                while x < sz.width {
                    var y = oy
                    while y < sz.height {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)), with: .color(Tok.borderStrong))
                        y += step
                    }
                    x += step
                }
            }
            CanvasEvents(enabled: shownID == nil && model.recorderKind == nil && model.openStackID == nil,
                         onPan: { d in pan = CGSize(width: pan.width + d.width, height: pan.height + d.height) },
                         onZoom: { f, p in zoom(by: f, at: p) })
            if dropTargeted { RoundedRectangle(cornerRadius: 18).strokeBorder(Tok.sage, style: StrokeStyle(lineWidth: 2, dash: [8, 6])).padding(12) }
            if model.entries.isEmpty { emptyState }
        }
        .contentShape(.rect)
        .gesture(marqueeGesture)
        .onTapGesture {
            focused = true
            model.selection = []
        }
        .tourAnchor(.canvas)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(model.isToday ? "Today is empty, for now." : "Nothing was saved on this day.")
                .font(Typo.serif(22)).foregroundStyle(Tok.ink2)
            Text("Record a moment, leave a voice note or write. Drop or paste a photo to keep a still.")
                .font(Typo.ui(13)).foregroundStyle(Tok.ink3)
        }
        .allowsHitTesting(false)
    }

    private var cards: some View {
        ForEach(model.items) { item in
            let ids = Set(item.entries.map(\.id))
            let moving = dragging.map { !$0.ids.isDisjoint(with: ids) } ?? false
            let off = moving ? dragging!.offset : .zero
            let p = screen(model.position(of: item.top.id))
            ItemView(item: item, selected: !model.selection.isDisjoint(with: ids), lifted: moving)
                .scaleEffect(zoom)
                .position(x: p.x + off.width, y: p.y + off.height)
                .opacity(item.entries.contains { $0.id == shownID } || item.stackID == model.openStackID && model.openStackID != nil ? 0 : 1)
                .gesture(dragGesture(ids))
                .onTapGesture(count: 2) { open(item) }
                .simultaneousGesture(TapGesture().onEnded { select(ids) })
                .animation(Motion.pick(Motion.arrange, reduce: reduceMotion), value: model.position(of: item.top.id))
        }
    }

    private func dragGesture(_ ids: Set<String>) -> some Gesture {
        LongPressGesture(minimumDuration: Self.holdBeforeDrag)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                let moving = model.selection.isDisjoint(with: ids) ? ids : model.selection.union(ids)
                dragging = (moving, drag?.translation ?? .zero)
            }
            .onEnded { value in
                guard case .second(true, let drag) = value, let drag, let d = dragging else {
                    dragging = nil
                    return
                }
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    model.move(memberIDs(d.ids), by: CGSize(width: drag.translation.width / zoom, height: drag.translation.height / zoom))
                    dragging = nil
                }
            }
    }

    /// Every entry in the stacks the ids belong to, so a stack always moves as one.
    private func memberIDs(_ ids: Set<String>) -> Set<String> {
        let stacks = Set(ids.compactMap { model.layouts[$0]?.stackId })
        return ids.union(model.entries.filter { model.layouts[$0.id]?.stackId.map(stacks.contains) ?? false }.map(\.id))
    }

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                if marquee == nil { marqueeBase = NSEvent.modifierFlags.contains(.shift) ? model.selection : [] }
                let r = CGRect(x: min(v.startLocation.x, v.location.x), y: min(v.startLocation.y, v.location.y),
                               width: abs(v.location.x - v.startLocation.x), height: abs(v.location.y - v.startLocation.y))
                marquee = r
                var hit = marqueeBase
                for e in model.entries where screenRect(e).intersects(r) { hit.insert(e.id) }
                model.selection = memberIDs(hit)
            }
            .onEnded { _ in marquee = nil }
    }

    private func select(_ ids: Set<String>) {
        focused = true
        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
            model.selection = ids.isSubset(of: model.selection) ? model.selection.subtracting(ids) : model.selection.union(ids)
        } else {
            model.selection = ids
        }
    }

    private func open(_ item: CanvasItem) {
        if let sid = item.stackID {
            withAnimation(Motion.pick(Motion.fan, reduce: reduceMotion)) { model.openStackID = sid }
        } else {
            model.openEntryID = item.top.id
        }
    }

    // MARK: Stack fan (FR-CAN-03)

    private func fanPoints(_ sid: String) -> [String: CGPoint] {
        let members = model.entries.filter { model.layouts[$0.id]?.stackId == sid }
        guard let first = members.first else { return [:] }
        var c = screen(model.position(of: first.id))
        let pts0 = CanvasMath.fan(count: members.count, size: CanvasMath.size(.moment), around: .zero)
        let half = CGSize(width: (pts0.map(\.x).max() ?? 0) + CanvasMath.cardWidth / 2 + 24, height: (pts0.map(\.y).max() ?? 0) + 120)
        c.x = min(max(c.x, half.width), max(half.width, size.width - half.width))
        c.y = min(max(c.y, half.height), max(half.height, size.height - half.height))
        let pts = CanvasMath.fan(count: members.count, size: CanvasMath.size(.moment), around: c)
        return Dictionary(uniqueKeysWithValues: zip(members.map(\.id), pts))
    }

    private func fan(_ sid: String) -> some View {
        let points = fanPoints(sid)
        let members = model.entries.filter { points[$0.id] != nil }
        return ZStack {
            Tok.bg.opacity(0.9).contentShape(.rect)
                .onTapGesture { withAnimation(Motion.pick(Motion.close, reduce: reduceMotion)) { model.openStackID = nil } }
            ForEach(Array(members.enumerated()), id: \.element.id) { i, e in
                let p = points[e.id] ?? .zero
                VStack(spacing: 6) {
                    CardFace(entry: e, selected: model.selection.contains(e.id))
                    Text("TURN \(e.turnNumber ?? i + 1)").font(Typo.mono(9.5)).foregroundStyle(Tok.ink3)
                }
                .position(p)
                .opacity(e.id == shownID ? 0 : 1)
                .onTapGesture(count: 2) { model.openEntryID = e.id }
                .simultaneousGesture(TapGesture().onEnded { model.selection = [e.id] })
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            HStack(spacing: 10) {
                Text("\(members.count) TURNS").font(Typo.mono(10)).foregroundStyle(Tok.ink3)
                Button("Unstack") { withAnimation(Motion.pick(Motion.arrange, reduce: reduceMotion)) { model.unstack(sid) } }
                Button("Done") { withAnimation(Motion.pick(Motion.close, reduce: reduceMotion)) { model.openStackID = nil } }
                    .keyboardShortcut(.cancelAction)
            }
            .font(Typo.ui(12, .medium))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .saroSurface(radius: 20)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 92)
        }
        .transition(.opacity)
    }

    // MARK: Detail morph (FR-CAN-01)

    private var detailTarget: CGRect {
        let w = min(1040, size.width - 64), h = min(760, size.height - 56)
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func morph(to id: String?) {
        if let id, let e = model.entry(id) {
            morphFrom = screenRect(e)
            shownID = id
            expanded = reduceMotion
            if reduceMotion { return }
            DispatchQueue.main.async { withAnimation(Motion.open) { expanded = true } }
        } else if let shown = shownID, let e = model.entry(shown) {
            morphFrom = screenRect(e)
            withAnimation(Motion.pick(Motion.close, reduce: reduceMotion)) { expanded = false } completion: {
                if model.openEntryID == nil { shownID = nil }
            }
        } else {
            shownID = nil
        }
    }

    private func detail(_ entry: Entry) -> some View {
        let r = expanded ? detailTarget : morphFrom
        return ZStack {
            Tok.bg.opacity(expanded ? 0.94 : 0).ignoresSafeArea()
                .onTapGesture { model.openEntryID = nil }
            ZStack(alignment: .top) {
                DetailView(entry: entry)
                    .frame(width: detailTarget.width, height: detailTarget.height)
                    .opacity(expanded ? 1 : 0)
                CardFace(entry: entry)
                    .scaleEffect(morphFrom.width / CanvasMath.cardWidth, anchor: .top)
                    .frame(width: morphFrom.width, height: morphFrom.height, alignment: .top)
                    .opacity(expanded ? 0 : 1)
                    .allowsHitTesting(false)
            }
            .frame(width: r.width, height: r.height, alignment: .top)
            .background(Tok.surface)
            .clipShape(.rect(cornerRadius: expanded ? 20 : 14 * zoom))
            .shadow(color: Tok.shadow.opacity(expanded ? 0.18 : 0.08), radius: expanded ? 30 : 8, y: expanded ? 12 : 3)
            .position(x: r.midX, y: r.midY)
        }
        .opacity(reduceMotion && !expanded ? 0 : 1)
    }

    // MARK: Chrome

    private var chrome: some View {
        ZStack {
            DayHeader()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 28).padding(.top, 18)
            NoticedButton()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 22).padding(.top, 20)
            VStack(spacing: 12) {
                if !model.selection.isEmpty && model.openStackID == nil {
                    SelectionToolbar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                CaptureBar()
            }
            .animation(Motion.pick(Motion.arrange, reduce: reduceMotion), value: model.selection.isEmpty)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 22)
            ZoomControls(zoom: zoom, onZoom: { zoom(by: $0, at: CGPoint(x: size.width / 2, y: size.height / 2)) },
                         onReset: { withAnimation(Motion.pick(Motion.arrange, reduce: reduceMotion)) { zoom = 1; pan = .zero } })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 22).padding(.bottom, 26)
        }
    }

    // MARK: Stills

    private func load(_ providers: [NSItemProvider], at point: CGPoint?, origin: String) {
        for (i, provider) in providers.enumerated() {
            let at = point.map { CGPoint(x: $0.x + CGFloat(i) * 30, y: $0.y + CGFloat(i) * 30) }
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                guard let data else { return }
                Task { @MainActor in await model.importStill(data, origin: origin, at: at) }
            }
        }
    }
}

/// One card, or a loose pile of a stack's cards.
private struct ItemView: View {
    let item: CanvasItem
    let selected: Bool
    let lifted: Bool
    @State private var hover = false

    var body: some View {
        ZStack {
            ForEach(Array(item.entries.suffix(4).enumerated()), id: \.element.id) { i, e in
                let depth = min(item.entries.count, 4) - 1 - i
                let o = CanvasMath.pileOffset(e.id, depth: depth)
                CardFace(entry: e, selected: selected && depth == 0)
                    .rotationEffect(.degrees(o.degrees))
                    .offset(x: o.dx, y: o.dy)
            }
            if item.isStack {
                Text("\(item.entries.count)")
                    .font(Typo.mono(10, .medium)).foregroundStyle(Tok.onPrimary)
                    .frame(minWidth: 20, minHeight: 20).background(Tok.sage, in: .capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 8, y: -8)
            }
        }
        .frame(width: CanvasMath.cardWidth, height: CanvasMath.cardHeight(item.top.kind))
        .scaleEffect(lifted ? 1.03 : hover ? 1.01 : 1)
        .shadow(color: Tok.shadow.opacity(lifted ? 0.18 : 0), radius: 18, y: 10)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

private struct DayHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isToday ? "TODAY" : DayFormat.sidebar(model.day).uppercased())
                    .font(Typo.mono(10)).foregroundStyle(Tok.ink3)
                Text(DayFormat.title(model.day)).font(Typo.serif(26, .medium)).foregroundStyle(Tok.ink)
            }
            HStack(spacing: 2) {
                Button { model.goPrevious() } label: { Image(systemName: "chevron.left") }.help("Previous day  ⌘[")
                Button { model.goNext() } label: { Image(systemName: "chevron.right") }.help("Next day  ⌘]")
                if !model.isToday {
                    Button("Today") { model.goToday() }.help("⌘T").font(Typo.ui(12, .medium)).padding(.leading, 6)
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Tok.ink2)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Tok.bg.opacity(0.85), in: .rect(cornerRadius: 14))
        .tourAnchor(.dayNav)
    }
}

private struct NoticedButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.showNoticed.toggle()
        } label: {
            Label("What Saro noticed", systemImage: "sparkles")
                .font(Typo.ui(12.5, .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.showNoticed ? Tok.onPrimary : Tok.ink)
        .background(model.showNoticed ? Tok.sage : Tok.surface, in: .capsule)
        .overlay(Capsule().strokeBorder(Tok.border))
        .keyboardShortcut("i", modifiers: [.command, .option])
        .help("What Saro noticed  ⌥⌘I")
        .tourAnchor(.noticedButton)
    }
}

private struct CaptureBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            Button { model.recorderKind = .moment } label: {
                Label("Moment", systemImage: "video.fill").padding(.horizontal, 16).padding(.vertical, 10)
                    .foregroundStyle(Tok.onPrimary).background(Tok.sage, in: .capsule)
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("Record a moment  ⌘N")
            .tourAnchor(.recordButton)
            Button { model.recorderKind = .voice } label: {
                Label("Voice", systemImage: "waveform").padding(.horizontal, 14).padding(.vertical, 10)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help("Leave a voice note  ⇧⌘N")
            Button {
                Task { if let e = await model.newWriting() { model.openEntryID = e.id } }
            } label: {
                Label("Write", systemImage: "square.and.pencil").padding(.horizontal, 14).padding(.vertical, 10)
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .help("Write  ⌥⌘W")
            Divider().frame(height: 18).padding(.horizontal, 4)
            Text("DROP OR PASTE A PHOTO").font(Typo.mono(9.5)).foregroundStyle(Tok.ink3).padding(.trailing, 10)
        }
        .buttonStyle(.plain)
        .font(Typo.ui(13, .medium))
        .foregroundStyle(Tok.ink)
        .padding(5)
        .saroSurface(radius: 30, lifted: true)
        .tourAnchor(.captureBar)
    }
}

private struct SelectionToolbar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(spacing: 2) {
            Text("\(model.selection.count) SELECTED").font(Typo.mono(10)).foregroundStyle(Tok.ink3).padding(.horizontal, 10)
            tool("Stack", "square.stack.3d.up", "⌘S") { model.stack(model.selection) }
                .keyboardShortcut("s", modifiers: .command).disabled(model.selection.count < 2)
            tool("Grid", "rectangle.grid.1x2", "⌘G") { model.grid(model.selection) }
                .keyboardShortcut("g", modifiers: .command)
            tool("Delete", "trash", "⌫") { Task { await model.trash(model.selection, undoManager: undoManager) } }
        }
        .buttonStyle(.plain)
        .font(Typo.ui(12.5, .medium))
        .padding(5)
        .saroSurface(radius: 22, lifted: true)
        .tourAnchor(.toolbar)
    }

    private func tool(_ title: String, _ symbol: String, _ shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).padding(.horizontal, 10).padding(.vertical, 7).contentShape(.rect)
        }
        .help("\(title.uppercased())  \(shortcut)")
    }
}

private struct ZoomControls: View {
    let zoom: CGFloat
    let onZoom: (CGFloat) -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button { onZoom(1 / 1.25) } label: { Image(systemName: "minus").frame(width: 28, height: 26) }
                .keyboardShortcut("-", modifiers: .command)
            Button(action: onReset) { Text("\(Int((zoom * 100).rounded()))%").font(Typo.mono(10)).frame(width: 46, height: 26) }
                .keyboardShortcut("0", modifiers: .command)
            Button { onZoom(1.25) } label: { Image(systemName: "plus").frame(width: 28, height: 26) }
                .keyboardShortcut("=", modifiers: .command)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Tok.ink2)
        .saroSurface(radius: 13)
    }
}

/// Where the recorder goes; the capture module provides `RecorderView`.
private struct RecorderSlot: View {
    let kind: EntryKind
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Recorder").font(Typo.serif(22))
            Button("Close", action: onClose).keyboardShortcut(.cancelAction)
        }
        .padding(40)
        .saroSurface(radius: 20, lifted: true)
    }
}
