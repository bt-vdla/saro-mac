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
                ReplayGround().ignoresSafeArea()
                DayStage(day: model.day, cards: model.stageCards, size: geo.size)
                    .id(model.day)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(x: pitch * model.slideDirection),
                                                                       removal: .offset(x: -pitch * model.slideDirection)))
                    .offset(x: -model.lean)
                    // The world steps back while the moment frame is up (ease.drawer, 400 ms).
                    .scaleEffect(model.recorderKind == .moment && !reduceMotion ? 0.98 : 1)
                    .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.4), value: model.recorderKind)
                if model.openEntryID.flatMap(model.entry) == nil { chrome(geo.size) }
            }
            .overlayPreferenceValue(CaptureOriginKey.self) { [kind = model.recorderKind, grows = model.recorderGrows] origins in
                if let kind {
                    // The voice pill sits 8 pt above the bar; the moment frame fills the canvas.
                    RecorderView(kind: kind, origin: grows ? origins[kind] : nil) { model.recorderKind = nil }
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
        .onDeleteCommand {
            let flies = !Motion.byKey && !reduceMotion
            Task { await model.trash(model.selection, undoManager: undoManager, flies: flies) }
        }
        .onExitCommand {
            if model.openEntryID != nil { model.openEntryID = nil }
            else if model.openStackID != nil { model.openStackID = nil }
            else if model.replay.active { model.replay.exit(animated: false) }
            else if model.openVoiceID != nil { model.openVoiceID = nil }
            else if model.insight != .spine { model.insight = model.insight == .letter ? .panel : .spine }
            else { model.selection = [] }
        }
        .onKeyPress(.return) {
            guard model.openEntryID == nil, model.selection.count == 1, let id = model.selection.first else { return .ignored }
            if model.entry(id)?.kind == .voice { model.openVoiceID = id } else { model.openEntryID = id }
            return .handled
        }
        // While the day replays (DayReplay.tsx): ← → step entry to entry, Home and End go to the ends of the day, Space plays.
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end, .space]) { press in
            let replay = model.replay
            guard replay.active, model.openEntryID == nil, press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
            switch press.key {
            case .rightArrow, .upArrow: replay.step(1)
            case .leftArrow, .downArrow: replay.step(-1)
            case .home, .end: replay.jump(toEnd: press.key == .end)
            default: if press.phase == .down { replay.toggle() }
            }
            return .handled
        }
        .onPasteCommand(of: [.image, .png, .tiff, .heic, .jpeg]) { providers in model.loadStills(providers, at: nil, origin: "pasted") }
        .onChange(of: screenID, initial: true) { _, s in model.screen = s }
        .onChange(of: model.replayItems) { _, items in model.replay.update(items) }
        .onChange(of: model.replay.active) { _, on in if on { focused = true } }
        .onAppear { focused = true }
        // Leaving the journal ends the replay where it is.
        .onDisappear { model.replay.exit(animated: false) }
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

/// The ground at the replay's playhead while one runs, else at the clock's hour. Its own view, so the playhead's every
/// frame redraws only the ground.
private struct ReplayGround: View {
    @Environment(AppModel.self) private var model

    var body: some View { LitGround(hour: model.replay.active ? model.replay.hour : nil) }
}

/// One card or stack as the stage draws it: a value snapshot, so a day sliding out keeps its own cards.
struct StageCard: Identifiable {
    let item: CanvasItem
    let center: CGPoint
    let size: CGSize
    let radius: CGFloat
    var id: String { item.id }
    var ids: Set<String> { Set(item.entries.map(\.id)) }

    /// The card drawn as it is now, at `scale` pixels per point.
    @MainActor func face(_ model: AppModel, scheme: ColorScheme, scale: CGFloat) -> Image? {
        let r = ImageRenderer(content: Group {
            if item.isStack { StackFace(entries: item.entries) } else { CardFace(entry: item.top) }
        }
        .environment(model).environment(\.colorScheme, scheme))
        r.scale = scale
        return r.cgImage.map { Image(decorative: $0, scale: scale) }
    }
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    let day: String
    let cards: [StageCard]
    let size: CGSize

    @State private var camera: Camera
    @State private var marquee: CGRect?
    @State private var marqueeBase: Set<String> = []
    @State private var drag: (ids: Set<String>, offset: CGSize, tilt: Double)?
    @State private var grid: DragGrid?
    @State private var dropTargeted = false
    @State private var shownID: String?
    @State private var flightFrom: (rect: CGRect, radius: CGFloat) = (.zero, 28)
    @State private var flight: Double = 0
    @State private var scrim = false
    @State private var fanned = false
    @State private var userMoved = false
    /// Cards let go and still gliding, which keep their motion blur until they land.
    @State private var thrown: Set<String> = []
    /// The faces of cards flying to or from the Undo toast, taken while the day still has them.
    @State private var faces: [String: Image] = [:]

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
            if let grid { DragGridLayer(grid: grid, camera: camera) }
            ForEach(cards) { card($0) }
            if let sid = model.openStackID, isCurrent { fan(sid) }
            if let m = marquee {
                RoundedRectangle(cornerRadius: 4).fill(Tok.ink.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Tok.ink3.opacity(0.45), lineWidth: 1))
                    .frame(width: m.width, height: m.height).position(x: m.midX, y: m.midY).allowsHitTesting(false)
            }
            if let id = shownID, let entry = model.entry(id) { detail(entry) }
            ForEach(flying) { c in
                if let face = faces[c.id] {
                    let r = screenRect(c)
                    Color.clear.frame(width: r.width, height: r.height)
                        .anchorPreference(key: TrashFlightKey.self, value: .bounds) { [c.id: FlyingCard(place: $0, face: face)] }
                        .position(x: r.midX, y: r.midY)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: flying.map(\.id)) { _, ids in
            faces = faces.filter { ids.contains($0.key) }
            for c in flying where faces[c.id] == nil { faces[c.id] = c.face(model, scheme: colorScheme, scale: displayScale * camera.zoom) }
        }
        .onDrop(of: [.image], isTargeted: $dropTargeted) { providers, location in
            model.loadStills(providers, at: world(location), origin: "dropped")
            return true
        }
        .onChange(of: model.openEntryID) { _, id in if isCurrent { morph(to: id) } }
        #if DOGFOOD
        .onReceive(NotificationCenter.default.publisher(for: Snapshots.hold)) { _ in
            if isCurrent, let c = cards.first { hold(c, translation: CGSize(width: 37, height: 23), velocity: .zero) }
        }
        #endif
        // Until the user pans, zooms or drags, the day stays framed as its cards arrive and settle; one flying into the
        // Undo toast leaves the rest where they are, so Undo brings it back to the same spot.
        .onChange(of: cards.map { "\($0.id)\($0.center)" }) { _, _ in
            if !userMoved && model.trashFlight?.into != true { camera = Camera.fit(cards, in: size) }
        }
        .onChange(of: model.camera) { _, cmd in
            guard isCurrent, let cmd else { return }
            switch cmd {
            case .fit: withAnimation(Motion.pick(Motion.surface, reduce: reduceMotion)) { camera = Camera.fit(cards, in: size) }
            case .zoom(let f, _):
                userMoved = true
                withAnimation(Motion.pick(Motion.small, reduce: reduceMotion)) { zoom(by: f, at: CGPoint(x: size.width / 2, y: size.height / 2)) }
            case .focus(let id, _):
                guard let c = cards.first(where: { $0.id == id }) else { return }
                userMoved = true
                model.selection = c.ids
                withAnimation(Motion.pick(Motion.surface, reduce: reduceMotion)) {
                    camera.pan = CGSize(width: size.width / 2 - c.center.x * camera.zoom, height: size.height / 2 - c.center.y * camera.zoom)
                }
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
        let at = CGPoint(x: p.x + off.width, y: p.y + off.height)
        return Group {
            if c.item.isStack { StackFace(entries: c.item.entries, selected: selected) } else { CardFace(entry: c.item.top, selected: selected, open: open) }
        }
        // An open voice note grows right and down from the card's top-left corner.
        .frame(width: c.size.width, height: c.size.height, alignment: .topLeading)
        .scaleEffect(moving && !reduceMotion ? 1.02 : 1)
        .rotationEffect(.degrees(moving && !reduceMotion ? drag!.tilt : 0))
        .animation(Motion.lift, value: moving)
        .animation(Motion.small, value: drag?.tilt)
        .modifier(ReplayLanding(shown: model.replay.shows(c.id), cue: model.replay.cues[c.id], reduceMotion: reduceMotion))
        .scaleEffect(camera.zoom)
        // Held or thrown only (useCardGesture.ts); an open voice note holds a scroller the shader can't draw.
        .modifier(MotionBlurred(position: at, coverage: c.size.width * c.size.height * camera.zoom * camera.zoom / (size.width * size.height),
                                enabled: !open && (moving || !thrown.isDisjoint(with: c.ids))))
        .position(at)
        .opacity(c.ids.contains(shownID ?? "") || (c.item.stackID != nil && c.item.stackID == model.openStackID) || inFlight(c) ? 0 : 1)
        .zIndex(moving ? 10 : open ? 5 : 0)
        .gesture(dragGesture(c))
        .onTapGesture { tap(c) }
        .pointerStyle(moving ? .grabActive : .grabIdle)
        .allowsHitTesting(model.replay.shows(c.id))
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

    /// 4 pt of slop, then 1:1 tracking with a lift and a velocity tilt; a throw glides on (velocity × 0.12), lands on a
    /// guide when one is close to where it would stop, and settles on the release spring (useCardGesture.ts).
    private func dragGesture(_ c: StageCard) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in hold(c, translation: v.translation, velocity: v.velocity) }
            .onEnded { v in
                guard let d = drag, var g = grid else { return }
                let speed = hypot(v.velocity.width, v.velocity.height)
                var total = d.offset
                if speed > 20 && !reduceMotion {
                    let glide = CGSize(width: (v.velocity.width * 0.12).clamped(to: -360...360), height: (v.velocity.height * 0.12).clamped(to: -360...360))
                    let s = snaps(g.rect.offsetBy(dx: glide.width / camera.zoom, dy: glide.height / camera.zoom), g)
                    total.width += glide.width + (s.x?.delta ?? 0) * camera.zoom
                    total.height += glide.height + (s.y?.delta ?? 0) * camera.zoom
                }
                // ponytail: the grid retracts where the card was let go; the web's follows the glide until it lands.
                let ended = Date.now
                g.ended = ended
                grid = g
                Task {
                    try? await Task.sleep(for: .seconds(DragGridLayer.retract))
                    if grid?.ended == ended { grid = nil }
                }
                thrown.formUnion(d.ids)
                withAnimation(reduceMotion ? nil : speed > 1000 ? Motion.release : Motion.lift) {
                    model.move(d.ids, by: CGSize(width: total.width / camera.zoom, height: total.height / camera.zoom))
                    drag = nil
                } completion: {
                    thrown.subtract(d.ids)
                }
            }
    }

    /// The first move lifts the card(s) and draws the grid out from them; every move snaps.
    private func hold(_ c: StageCard, translation t: CGSize, velocity: CGSize) {
        userMoved = true
        let ids = drag?.ids ?? memberIDs(model.selection.isDisjoint(with: c.ids) ? c.ids : model.selection.union(c.ids))
        guard let box = CanvasMath.bounds(cards.filter { !$0.ids.isDisjoint(with: ids) }.map { CGRect(center: $0.center, size: $0.size) }) else { return }
        if drag == nil {
            grid = DragGrid(rect: box, others: cards.filter { $0.ids.isDisjoint(with: ids) }.map { CGRect(center: $0.center, size: $0.size) },
                            zoom: camera.zoom)
        }
        guard var g = grid else { return }
        let m = box.offsetBy(dx: t.width / camera.zoom, dy: t.height / camera.zoom)
        let s = snaps(m, g)
        g.move(to: m.offsetBy(dx: s.x?.delta ?? 0, dy: s.y?.delta ?? 0), x: s.x, y: s.y)
        grid = g
        drag = (ids, CGSize(width: t.width + (s.x?.delta ?? 0) * camera.zoom, height: t.height + (s.y?.delta ?? 0) * camera.zoom),
                (velocity.width * 0.0012).clamped(to: -3...3))
    }

    /// Where a moving box snaps (cardGeometry.ts): its left/centre/right and top/middle/bottom to the other cards' within
    /// 6 screen points, else an edge to the rhythm within 3. ⌥ turns snapping off.
    private func snaps(_ m: CGRect, _ g: DragGrid) -> (x: CanvasMath.Snap?, y: CanvasMath.Snap?) {
        guard !NSEvent.modifierFlags.contains(.option) else { return (nil, nil) }
        let reach = 6 / camera.zoom, rhythm = 3 / camera.zoom
        return (CanvasMath.snap([m.minX, m.midX, m.maxX], cards: g.cardX, reach: reach, axis: 0, level: g.level, rhythmReach: rhythm),
                CanvasMath.snap([m.minY, m.midY, m.maxY], cards: g.cardY, reach: reach, axis: 1, level: g.level, rhythmReach: rhythm))
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

    // MARK: Into the Undo toast and back out (Canvas.tsx)

    /// The cards of a trash flight this stage draws: on the way in, the trashed cards where they were; on the way out,
    /// the restored ones once the day has them again.
    private var flying: [StageCard] {
        guard isCurrent, let f = model.trashFlight else { return [] }
        return f.into ? f.cards : cards.filter { c in f.cards.contains { $0.id == c.id } }
    }

    /// A card on its way in hides once its face flies in its place; one coming back waits hidden until it lands.
    private func inFlight(_ c: StageCard) -> Bool {
        guard let f = model.trashFlight, f.cards.contains(where: { $0.id == c.id }) else { return false }
        return !f.into || faces[c.id] != nil
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
        let tile = members.first.map { CanvasMath.size($0.kind) } ?? .zero
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
                .modifier(MotionBlurred(position: p, coverage: tile.width * tile.height / (size.width * size.height)))
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
                        toRadius: Radius.sheet, viewport: size, v: flight, crossfadeOnly: reduceMotion)
        }
    }
}

/// The flight between a card and its detail: size interpolates in log space, the centre in a straight line, the card
/// fades out by v 0.55 and the detail in by v 0.35, blurred along its path while it travels fast (morph.ts, MorphLayer.tsx).
struct MorphFlight: View, @MainActor Animatable {
    let entry: Entry
    let from: CGRect
    let fromRadius: CGFloat
    let to: CGRect
    let toRadius: CGFloat
    let viewport: CGSize
    var v: Double
    var crossfadeOnly = false
    @State private var blur = MotionBlurTracker()

    var animatableData: Double {
        get { v }
        set { v = newValue }
    }

    var body: some View {
        let t = CGFloat(v)
        let safeFrom = from.width > 1 && from.height > 1 ? from : CGRect(center: CGPoint(x: to.midX, y: to.midY), size: CGSize(width: to.width * 0.92, height: to.height * 0.92))
        let box = crossfadeOnly ? to : CanvasMath.flightBox(from: safeFrom, to: to, v: t)
        let (w, h, cx, cy) = (box.width, box.height, box.midX, box.midY)
        let r = fromRadius + (toRadius - fromRadius) * t
        let cardSize = CanvasMath.size(entry.kind)
        let fades = CanvasMath.flightFades(v)
        let source = fades.leaving
        let dest = crossfadeOnly ? v : fades.arriving
        let sigma = crossfadeOnly || v == 0 || v == 1 ? blur.reset()
            : blur.track(CGPoint(x: cx, y: cy), coverage: w * h / (viewport.width * viewport.height))
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
        // The detail holds AppKit views (player, editors, scrollers) the shader can't sample, so the flight takes
        // SwiftUI's round blur at the web's strength along its path.
        .blur(radius: max(sigma.width, sigma.height))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            Text("\(model.selection.count) selected").monoCaps(10).foregroundStyle(Tok.ink3).padding(.horizontal, 12)
            tool("Stack", "square.stack.3d.up", "⌘S") { withAnimation(Motion.small) { model.stack(model.selection) } }
                .keyboardShortcut("s", modifiers: .command).disabled(model.selection.count < 2)
            tool("Grid", "rectangle.grid.1x2", "⌘G") { withAnimation(Motion.small) { model.grid(model.selection) } }
                .keyboardShortcut("g", modifiers: .command)
            tool("Delete", "trash", "⌫") {
                let flies = !Motion.byKey && !reduceMotion
                Task { await model.trash(model.selection, undoManager: undoManager, flies: flies) }
            }
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
