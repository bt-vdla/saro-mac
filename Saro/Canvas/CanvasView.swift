import SaroKit
import SwiftUI
import UniformTypeIdentifiers

/// The day surface (D-03), built to the web overnight build: a lit ground that doesn't move, a day stage that slides
/// between days, and floating chrome — Monolith and search top-left, the insight spine on the right, the glass bar below.
struct DayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geo in
            let pitch = geo.size.width + 32
            ZStack {
                LitGround().ignoresSafeArea()
                DayStage(day: model.day, cards: model.stageCards, size: geo.size)
                    .id(model.day)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(x: pitch * model.slideDirection),
                                                                       removal: .offset(x: -pitch * model.slideDirection)))
                    .offset(x: -model.lean)
                    // The world steps back while the moment frame is up (ease.drawer, 400 ms).
                    .scaleEffect(model.recorderKind == .moment && !reduceMotion ? 0.98 : 1)
                    .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.4), value: model.recorderKind)
                if model.openEntryID.flatMap(model.entry) == nil { chrome(geo.size) }
                if let kind = model.recorderKind {
                    // The voice pill sits 8 pt above the bar; the moment frame fills the canvas.
                    RecorderView(kind: kind) { model.recorderKind = nil }
                        .padding(.bottom, kind == .voice ? 92 : 0)
                        // A window close or pane switch ends the session too; left set, the camera would come back on its own.
                        .onDisappear { model.recorderKind = nil }
                }
            }
            .animation(Motion.pick(Motion.easeOut(0.3), reduce: reduceMotion), value: model.recorderKind)
        }
        .clipped()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onDeleteCommand { Task { await model.trash(model.selection, undoManager: undoManager) } }
        .onExitCommand {
            if model.openEntryID != nil { model.openEntryID = nil }
            else if model.openStackID != nil { model.openStackID = nil }
            else if model.openVoiceID != nil { model.openVoiceID = nil }
            else if model.insight != .spine { model.insight = model.insight == .letter ? .panel : .spine }
            else { model.selection = [] }
        }
        .onKeyPress(.return) {
            guard model.openEntryID == nil, model.selection.count == 1, let id = model.selection.first else { return .ignored }
            if model.entry(id)?.kind == .voice { model.openVoiceID = id } else { model.openEntryID = id }
            return .handled
        }
        .onPasteCommand(of: [.image, .png, .tiff, .heic, .jpeg]) { providers in model.loadStills(providers, at: nil, origin: "pasted") }
        .onChange(of: screenID, initial: true) { _, s in model.screen = s }
        .onAppear { focused = true }
        .onChange(of: model.searchOpen) { _, open in if !open { focused = true } }
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
        if model.openVoiceID != nil { return .voiceDetail }
        if model.insight == .letter { return .letter }
        if model.insight == .panel { return .noticed }
        return model.openStackID != nil ? .stack : .canvas
    }

    private func chrome(_ size: CGSize) -> some View {
        ZStack {
            OrbitNav()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 24).padding(.top, 40)
            InsightSurface(height: size.height - size.height * 0.075 - 120)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 24).padding(.top, size.height * 0.075)
            VStack(spacing: 10) {
                if !model.selection.isEmpty && model.openStackID == nil {
                    SelectionToolbar().transition(.move(edge: .bottom).combined(with: .opacity))
                }
                BottomBar()
            }
            .animation(Motion.pick(Motion.small, reduce: reduceMotion), value: model.selection.isEmpty)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 20)
        }
    }
}

/// One card or stack as the stage draws it: a value snapshot, so a day sliding out keeps its own cards.
struct StageCard: Identifiable {
    let item: CanvasItem
    let center: CGPoint
    let size: CGSize
    let radius: CGFloat
    var id: String { item.id }
    var ids: Set<String> { Set(item.entries.map(\.id)) }
}

extension AppModel {
    var stageCards: [StageCard] {
        items.map { item in
            let size = item.isStack ? CanvasMath.stackSize : CanvasMath.size(item.top.kind)
            return StageCard(item: item, center: position(of: item.top.id), size: size,
                             radius: item.isStack ? 18 : CanvasMath.radius(item.top.kind))
        }
    }

    func loadStills(_ providers: [NSItemProvider], at point: CGPoint?, origin: String) {
        for (i, provider) in providers.enumerated() {
            let at = point.map { CGPoint(x: $0.x + CGFloat(i) * 30, y: $0.y + CGFloat(i) * 30) }
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                guard let data else { return }
                Task { @MainActor in await self.importStill(data, origin: origin, at: at) }
            }
        }
    }
}

struct Guide: Equatable {
    enum Axis { case x, y }
    let axis: Axis
    let at: CGFloat
    let from: CGFloat
    let to: CGFloat
}

/// The camera: screen = world × zoom + pan.
struct Camera: Equatable {
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    static let range: ClosedRange<CGFloat> = 0.2...3

    /// Frames every card inside the web's insets (top 104, right 120 for the spine, bottom 112 for the bar), never above 100%.
    static func fit(_ cards: [StageCard], in size: CGSize) -> Camera {
        guard let b = CanvasMath.bounds(cards.map { CGRect(center: $0.center, size: $0.size) }), size.width > 0 else { return Camera() }
        let frame = CGRect(x: 40, y: 104, width: max(200, size.width - 160), height: max(200, size.height - 104 - 132))
        let z = min(1, frame.width / b.width, frame.height / b.height).clamped(to: range)
        return Camera(zoom: z, pan: CGSize(width: frame.midX - b.midX * z, height: frame.midY - b.midY * z))
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}

/// One day's canvas: cards on a camera, marquee, stack fan-out and the open/close flight. Keyed by day, so each day
/// arrives with its own fitted camera.
struct DayStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let day: String
    let cards: [StageCard]
    let size: CGSize

    @State private var camera: Camera
    @State private var marquee: CGRect?
    @State private var marqueeBase: Set<String> = []
    @State private var drag: (ids: Set<String>, offset: CGSize, tilt: Double)?
    /// Snap guides while dragging, in world units: vertical lines at x (`axis == .x`) or horizontal at y.
    @State private var guides: [Guide] = []
    @State private var dropTargeted = false
    @State private var shownID: String?
    @State private var flightFrom: (rect: CGRect, radius: CGFloat) = (.zero, 28)
    @State private var flight: Double = 0
    @State private var scrim = false
    @State private var fanned = false
    @State private var userMoved = false

    init(day: String, cards: [StageCard], size: CGSize) {
        self.day = day
        self.cards = cards
        self.size = size
        _camera = State(initialValue: Camera.fit(cards, in: size))
    }

    private var isCurrent: Bool { day == model.day }

    var body: some View {
        ZStack {
            background
            ForEach(cards) { card($0) }
            if !guides.isEmpty { guideLayer }
            if let sid = model.openStackID, isCurrent { fan(sid) }
            if let m = marquee {
                RoundedRectangle(cornerRadius: 4).fill(Tok.ink.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Tok.ink3.opacity(0.45), lineWidth: 1))
                    .frame(width: m.width, height: m.height).position(x: m.midX, y: m.midY).allowsHitTesting(false)
            }
            if let id = shownID, let entry = model.entry(id) { detail(entry) }
        }
        .frame(width: size.width, height: size.height)
        .onDrop(of: [.image], isTargeted: $dropTargeted) { providers, location in
            model.loadStills(providers, at: world(location), origin: "dropped")
            return true
        }
        .onChange(of: model.openEntryID) { _, id in if isCurrent { morph(to: id) } }
        // Until the user pans, zooms or drags, the day stays framed as its cards arrive and settle.
        .onChange(of: cards.map { "\($0.id)\($0.center)" }) { _, _ in if !userMoved { camera = Camera.fit(cards, in: size) } }
        .onChange(of: model.camera) { _, cmd in
            guard isCurrent, let cmd else { return }
            switch cmd {
            case .fit: withAnimation(Motion.pick(Motion.surface, reduce: reduceMotion)) { camera = Camera.fit(cards, in: size) }
            case .zoom(let f, _):
                userMoved = true
                withAnimation(Motion.pick(Motion.small, reduce: reduceMotion)) { zoom(by: f, at: CGPoint(x: size.width / 2, y: size.height / 2)) }
            }
        }
    }

    // MARK: Coordinates

    private func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * camera.zoom + camera.pan.width, y: p.y * camera.zoom + camera.pan.height) }
    private func world(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - camera.pan.width) / camera.zoom, y: (p.y - camera.pan.height) / camera.zoom) }

    private func zoom(by factor: CGFloat, at p: CGPoint) {
        let next = (camera.zoom * factor).clamped(to: Camera.range)
        camera.pan = CGSize(width: p.x - (p.x - camera.pan.width) * next / camera.zoom, height: p.y - (p.y - camera.pan.height) * next / camera.zoom)
        camera.zoom = next
    }

    private func screenRect(_ c: StageCard) -> CGRect {
        CGRect(center: screen(c.center), size: CGSize(width: c.size.width * camera.zoom, height: c.size.height * camera.zoom))
    }

    private func screenRect(entry id: String) -> (CGRect, CGFloat) {
        if let sid = model.openStackID, let p = fanPoints(sid)[id], let e = model.entry(id) {
            return (CGRect(center: p, size: CanvasMath.size(e.kind)), CanvasMath.radius(e.kind))
        }
        guard let c = cards.first(where: { $0.ids.contains(id) }) else { return (CGRect(center: CGPoint(x: size.width / 2, y: size.height / 2), size: .zero), 28) }
        return (screenRect(c), c.radius * camera.zoom)
    }

    // MARK: Ground and empty state

    private var background: some View {
        ZStack {
            Color.clear
            // The letter, the Noticed panel, ⌘K and dev notes scroll themselves; the monitor would take their wheel.
            CanvasEvents(enabled: isCurrent && shownID == nil && model.recorderKind == nil && model.openStackID == nil
                             && model.insight == .spine && !model.searchOpen && !model.devNotesVisible,
                         onPan: { d in
                             userMoved = true
                             camera.pan = CGSize(width: camera.pan.width + d.width, height: camera.pan.height + d.height)
                         },
                         onZoom: { f, p in
                             userMoved = true
                             zoom(by: f, at: p)
                         })
            if dropTargeted {
                RoundedRectangle(cornerRadius: Radius.sheet).strokeBorder(Tok.sage.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(12)
            }
            if cards.isEmpty { EmptyDay(today: day == LocalDay.today()) }
        }
        .contentShape(.rect)
        .gesture(marqueeGesture)
        .onTapGesture {
            model.selection = []
            if model.openVoiceID != nil { model.openVoice(nil, reduceMotion: reduceMotion) }
            if model.insight != .spine { model.insight = .spine }
        }
        .tourAnchor(.canvas)
    }

    // MARK: Cards

    private func card(_ c: StageCard) -> some View {
        let moving = drag.map { !$0.ids.isDisjoint(with: c.ids) } ?? false
        let off = moving ? drag!.offset : .zero
        let p = screen(c.center)
        let selected = !model.selection.isDisjoint(with: c.ids)
        let open = !c.item.isStack && model.openVoiceID == c.item.top.id
        return Group {
            if c.item.isStack { StackFace(entries: c.item.entries, selected: selected) } else { CardFace(entry: c.item.top, selected: selected, open: open) }
        }
        // An open voice note grows right and down from the card's top-left corner.
        .frame(width: c.size.width, height: c.size.height, alignment: .topLeading)
        .scaleEffect(moving && !reduceMotion ? 1.02 : 1)
        .rotationEffect(.degrees(moving && !reduceMotion ? drag!.tilt : 0))
        .animation(Motion.lift, value: moving)
        .animation(Motion.small, value: drag?.tilt)
        .scaleEffect(camera.zoom)
        .position(x: p.x + off.width, y: p.y + off.height)
        .opacity(c.ids.contains(shownID ?? "") || (c.item.stackID != nil && c.item.stackID == model.openStackID) ? 0 : 1)
        .zIndex(moving ? 10 : open ? 5 : 0)
        .gesture(dragGesture(c))
        .onTapGesture { tap(c) }
        .pointerStyle(moving ? .grabActive : .grabIdle)
    }

    private func tap(_ c: StageCard) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) || flags.contains(.shift) {
            model.selection = c.ids.isSubset(of: model.selection) ? model.selection.subtracting(c.ids) : model.selection.union(c.ids)
            return
        }
        model.selection = c.ids
        // A tap opens a voice note in place and plays it (VoiceEchoCard.tsx); a tap anywhere else folds it.
        let voice = !c.item.isStack && c.item.top.kind == .voice ? c.item.top.id : nil
        if model.openVoiceID != voice { model.openVoice(voice, reduceMotion: reduceMotion) }
        if voice != nil { return }
        if let sid = c.item.stackID {
            fanned = false
            withAnimation(Motion.pick(Motion.surface, reduce: reduceMotion)) { model.openStackID = sid }
        } else {
            model.openEntryID = c.item.top.id
        }
    }

    /// 4 pt of slop, then 1:1 tracking with a lift and a velocity tilt; a throw glides on (velocity × 0.12) and settles
    /// on the release spring (useCardGesture.ts).
    private func dragGesture(_ c: StageCard) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                userMoved = true
                let ids = drag?.ids ?? memberIDs(model.selection.isDisjoint(with: c.ids) ? c.ids : model.selection.union(c.ids))
                let tilt = (v.velocity.width * 0.0012).clamped(to: -3...3)
                let (offset, found) = snap(ids, translation: v.translation)
                if found.isEmpty != guides.isEmpty || found != guides { withAnimation(.easeOut(duration: 0.08)) { guides = found } }
                drag = (ids, offset, tilt)
            }
            .onEnded { v in
                guard let d = drag else { return }
                let snapped = !guides.isEmpty
                withAnimation(.easeOut(duration: 0.15)) { guides = [] }
                let speed = hypot(v.velocity.width, v.velocity.height)
                let glide = speed > 20 && !reduceMotion && !snapped
                    ? CGSize(width: (v.velocity.width * 0.12).clamped(to: -360...360), height: (v.velocity.height * 0.12).clamped(to: -360...360))
                    : .zero
                let total = CGSize(width: d.offset.width + glide.width, height: d.offset.height + glide.height)
                withAnimation(reduceMotion ? nil : speed > 1000 ? Motion.release : Motion.lift) {
                    model.move(d.ids, by: CGSize(width: total.width / camera.zoom, height: total.height / camera.zoom))
                    drag = nil
                }
            }
    }

    /// Snaps the moving cards' left/centre/right (and top/middle/bottom) to the other cards' within 6 screen points
    /// (cardGeometry.ts). ⌥ turns snapping off. Returns the snapped screen offset and the guides to draw.
    private func snap(_ ids: Set<String>, translation t: CGSize) -> (CGSize, [Guide]) {
        let moving = cards.filter { !$0.ids.isDisjoint(with: ids) }.map { CGRect(center: $0.center, size: $0.size) }
        guard !NSEvent.modifierFlags.contains(.option), var m = CanvasMath.bounds(moving) else { return (t, []) }
        m = m.offsetBy(dx: t.width / camera.zoom, dy: t.height / camera.zoom)
        let others = cards.filter { $0.ids.isDisjoint(with: ids) }.map { CGRect(center: $0.center, size: $0.size) }
        let reach = 6 / camera.zoom
        let best = { (mine: [CGFloat], theirs: [(CGFloat, CGRect)]) in CanvasMath.snap(mine, to: theirs, reach: reach) }
        var out = t
        var found: [Guide] = []
        if let x = best([m.minX, m.midX, m.maxX], others.flatMap { r in [(r.minX, r), (r.midX, r), (r.maxX, r)] }) {
            out.width += x.delta * camera.zoom
            let span = x.rects.reduce(m.offsetBy(dx: x.delta, dy: 0)) { $0.union($1) }
            found.append(Guide(axis: .x, at: x.at, from: span.minY - 12, to: span.maxY + 12))
        }
        if let y = best([m.minY, m.midY, m.maxY], others.flatMap { r in [(r.minY, r), (r.midY, r), (r.maxY, r)] }) {
            out.height += y.delta * camera.zoom
            let span = y.rects.reduce(m.offsetBy(dx: 0, dy: y.delta)) { $0.union($1) }
            found.append(Guide(axis: .y, at: y.at, from: span.minX - 12, to: span.maxX + 12))
        }
        return (out, found)
    }

    /// Hairline guides with 2 pt dots at their ends, in the accent (moment green by day, echo violet at night).
    private var guideLayer: some View {
        Canvas { ctx, _ in
            for g in guides {
                var path = Path()
                let a = g.axis == .x ? screen(CGPoint(x: g.at, y: g.from)) : screen(CGPoint(x: g.from, y: g.at))
                let b = g.axis == .x ? screen(CGPoint(x: g.at, y: g.to)) : screen(CGPoint(x: g.to, y: g.at))
                path.move(to: a)
                path.addLine(to: b)
                ctx.stroke(path, with: .color(Tok.guide.opacity(0.42)), lineWidth: 1)
                for p in [a, b] { ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(Tok.guide.opacity(0.55))) }
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
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
                for c in cards where screenRect(c).intersects(r) { hit.formUnion(c.ids) }
                model.selection = hit
            }
            .onEnded { _ in marquee = nil }
    }

    // MARK: The set, fanned out (VideoStackOverlay.tsx)

    private func fanPoints(_ sid: String) -> [String: CGPoint] {
        let members = model.entries.filter { model.layouts[$0.id]?.stackId == sid }
        guard !members.isEmpty else { return [:] }
        let tile = CanvasMath.size(members[0].kind)
        let pts = CanvasMath.fan(count: members.count, size: tile, around: CGPoint(x: size.width / 2, y: size.height / 2 - 30))
        return Dictionary(uniqueKeysWithValues: zip(members.map(\.id), pts))
    }

    private func fan(_ sid: String) -> some View {
        let points = fanPoints(sid)
        let members = model.entries.filter { points[$0.id] != nil }
        let origin = cards.first { $0.item.stackID == sid }.map { screen($0.center) } ?? CGPoint(x: size.width / 2, y: size.height / 2)
        return ZStack {
            Rectangle().fill(.ultraThinMaterial).overlay(Tok.bg.opacity(0.85)).ignoresSafeArea()
                .onTapGesture { close(sid) }
            ForEach(Array(members.enumerated()), id: \.element.id) { i, e in
                let p = fanned || reduceMotion ? points[e.id] ?? origin : origin
                VStack(spacing: 8) {
                    CardFace(entry: e, selected: model.selection.contains(e.id))
                    Text("Turn \(e.turnNumber ?? i + 1)").monoCaps(10).foregroundStyle(Tok.ink3)
                }
                .scaleEffect(fanned || reduceMotion ? 1 : 0.6)
                .position(p)
                .opacity(e.id == shownID ? 0 : 1)
                .animation(fanned ? Motion.easeOut(0.42).delay(Double(i) * 0.04) : Motion.easeOut(0.22).delay(Double(members.count - 1 - i) * 0.03), value: fanned)
                .onTapGesture { model.openEntryID = e.id }
            }
            HStack(spacing: 12) {
                Text("\(members.count) turns").monoCaps(10).foregroundStyle(Tok.ink3)
                Button("Unstack") { withAnimation(Motion.pick(Motion.small, reduce: reduceMotion)) { model.unstack(sid) } }
                Button("Done") { close(sid) }
            }
            .font(Typo.ui(12.5, .medium))
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .glassPanel(radius: 20)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 28)
        }
        .onAppear { fanned = true }
        .transition(.opacity)
    }

    private func close(_ sid: String) {
        fanned = false
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 260))
            withAnimation(Motion.fade) { model.openStackID = nil }
        }
    }

    // MARK: Open and close (morph.ts)

    private func detailTarget(_ e: Entry) -> CGRect {
        let w: CGFloat, h: CGFloat
        switch e.kind {
        case .moment:
            // The video is a flush 16:9 column beside a min(420, 40%) side column, so size the sheet to the video.
            let side = min(420, (size.width - 96) * 0.4)
            w = min(1200, size.width - 96, (size.height - 96) * 16 / 9 + side)
            h = min(size.height - 96, (w - side) * 9 / 16)
        case .voice: (w, h) = (min(720, size.width - 96), min(600, size.height - 96))
        case .still: (w, h) = (min(1000, size.width - 96), min(760, size.height - 96))
        case .reflection, .music: (w, h) = (min(820, size.width - 96), min(820, size.height - 96))
        }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func morph(to id: String?) {
        if let id {
            flightFrom = screenRect(entry: id)
            shownID = id
            guard !reduceMotion else {
                withAnimation(Motion.fade) { flight = 1; scrim = true }
                return
            }
            flight = 0
            DispatchQueue.main.async {
                withAnimation(Motion.surface) { flight = 1 }
                withAnimation(Motion.easeOut(0.2)) { scrim = true }
            }
        } else if let shown = shownID {
            flightFrom = screenRect(entry: shown)
            withAnimation(Motion.easeOut(0.2)) { scrim = false }
            withAnimation(reduceMotion ? Motion.fade : Motion.surface) { flight = 0 } completion: {
                if model.openEntryID == nil { shownID = nil }
            }
        }
    }

    private func detail(_ entry: Entry) -> some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).overlay(Tok.bg.opacity(0.85)).ignoresSafeArea()
                .opacity(scrim ? 1 : 0)
                .onTapGesture { model.openEntryID = nil }
            MorphFlight(entry: entry, from: flightFrom.rect, fromRadius: flightFrom.radius, to: detailTarget(entry),
                        toRadius: Radius.sheet, v: flight, crossfadeOnly: reduceMotion)
        }
    }
}

/// The flight between a card and its detail: size interpolates in log space, the centre in a straight line, the card
/// fades out by v 0.55 and the detail in by v 0.35 (morph.ts).
struct MorphFlight: View, @MainActor Animatable {
    let entry: Entry
    let from: CGRect
    let fromRadius: CGFloat
    let to: CGRect
    let toRadius: CGFloat
    var v: Double
    var crossfadeOnly = false

    var animatableData: Double {
        get { v }
        set { v = newValue }
    }

    var body: some View {
        let t = CGFloat(v)
        let safeFrom = from.width > 1 && from.height > 1 ? from : CGRect(center: CGPoint(x: to.midX, y: to.midY), size: CGSize(width: to.width * 0.92, height: to.height * 0.92))
        let w = crossfadeOnly ? to.width : safeFrom.width * pow(to.width / safeFrom.width, t)
        let h = crossfadeOnly ? to.height : safeFrom.height * pow(to.height / safeFrom.height, t)
        let cx = crossfadeOnly ? to.midX : safeFrom.midX + (to.midX - safeFrom.midX) * t
        let cy = crossfadeOnly ? to.midY : safeFrom.midY + (to.midY - safeFrom.midY) * t
        let r = fromRadius + (toRadius - fromRadius) * t
        let cardSize = CanvasMath.size(entry.kind)
        let source = 1 - ((v - 0.05) / 0.5).clamped(to: 0...1)
        let dest = crossfadeOnly ? v : (v / 0.35).clamped(to: 0...1)
        ZStack {
            DetailView(entry: entry)
                .id(entry.id)
                .frame(width: to.width, height: to.height)
                .scaleEffect(min(w / to.width, h / to.height))
                .opacity(dest)
            if source > 0 && !crossfadeOnly {
                CardFace(entry: entry)
                    .scaleEffect(min(w / cardSize.width, h / cardSize.height))
                    .opacity(source)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: w, height: h)
        .background(Tok.surface)
        .clipShape(.rect(cornerRadius: r))
        .elevation(v > 0.5 ? .overlay : .panel)
        .position(x: cx, y: cy)
        .opacity(crossfadeOnly ? v : 1)
    }
}

/// "Nothing here yet." in Newsreader, rising 6 pt over 500 ms (DayState.tsx).
private struct EmptyDay: View {
    let today: Bool
    @State private var shown = false

    var body: some View {
        VStack(spacing: 10) {
            Text(today ? "Nothing here yet." : "Nothing was saved on this day.").font(Typo.serif(28)).foregroundStyle(Tok.ink)
            Text("Record a moment, leave a voice note or write. Drop or paste a photo to keep a still.")
                .font(Typo.ui(14)).foregroundStyle(Tok.ink2)
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 6)
        .onAppear { withAnimation(Motion.easeOut(0.5)) { shown = true } }
        .allowsHitTesting(false)
    }
}

private struct SelectionToolbar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(spacing: 2) {
            Text("\(model.selection.count) selected").monoCaps(10).foregroundStyle(Tok.ink3).padding(.horizontal, 12)
            tool("Stack", "square.stack.3d.up", "⌘S") { withAnimation(Motion.small) { model.stack(model.selection) } }
                .keyboardShortcut("s", modifiers: .command).disabled(model.selection.count < 2)
            tool("Grid", "rectangle.grid.1x2", "⌘G") { withAnimation(Motion.small) { model.grid(model.selection) } }
                .keyboardShortcut("g", modifiers: .command)
            tool("Delete", "trash", "⌫") { Task { await model.trash(model.selection, undoManager: undoManager) } }
        }
        .font(Typo.ui(12.5, .medium))
        .foregroundStyle(Tok.ink)
        .padding(5)
        .glassPanel(radius: 22)
        .tourAnchor(.toolbar)
    }

    private func tool(_ title: String, _ symbol: String, _ shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).padding(.horizontal, 10).padding(.vertical, 7).contentShape(.rect)
        }
        .buttonStyle(PressStyle(hoverFill: true))
        .help("\(title.uppercased())  \(shortcut)")
    }
}
