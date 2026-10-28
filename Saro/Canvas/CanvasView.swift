import SaroKit
import SwiftUI
import UniformTypeIdentifiers

/// The day surface (D-03), built to the web overnight build: a lit ground that doesn't move, a day stage that slides
/// between days, and floating chrome — Monolith and search top-left, the insight spine on the right, the glass bar below.
struct DayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager
    /// True while focus is anywhere inside the day view, a panel's scroller or a field included.
    @FocusState private var focused: Bool
    /// The canvas itself has focus: SwiftUI hands a key up from whatever inside has it, so the canvas's keys check this.
    @State private var canvasFocused = false
    /// An ⌥-arrow nudge or ⇧⌥-arrow resize moved something not yet saved; the arrow's release saves it, whichever
    /// modifier was let go first.
    @State private var nudged: Nudge?
    private enum Nudge { case moved(Set<String>), resized(String) }
    /// The chrome and the stage share it, so the letter's quotes can fly into their cards.
    nonisolated static let space = "day"

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
                    // The live day is the surface that shrinks into its lens tile and comes back out of it.
                    .modifier(LensPose(pose: model.lens?.dayPose))
                // An open entry or set takes the window, as the web's dialogs do: its controls sit clear of the bar and the panel.
                if model.openEntryID.flatMap(model.entry) == nil && model.openStackID == nil && model.lens == nil { chrome(geo.size) }
                if let lens = model.lens { TimeLens(lens: lens).transition(.identity) }
            }
            .overlayPreferenceValue(CaptureOriginKey.self) { [kind = model.recorderKind, grows = model.recorderGrows] origins in
                if let kind {
                    // The voice pill sits 8 pt above the bar; the moment frame fills the canvas.
                    RecorderView(kind: kind, origin: grows ? origins[kind] : nil) { model.recorderKind = nil }
                        .padding(.bottom, kind == .voice ? model.barClear + 8 : 0)
                        // With Full Keyboard Access a focused button in it hands Esc up the view tree, past its visible Esc
                        // button (Close, Not yet, Keep recording, Keep it, a step's Cancel), to the day: it goes to that button.
                        .onExitCommand {
                            if let e = NSApp.currentEvent, e.type == .keyDown { _ = e.window?.performKeyEquivalent(with: e) }
                        }
                        // A window close or pane switch ends the session too; left set, the camera would come back on its own.
                        .onDisappear { model.recorderKind = nil }
                }
            }
            .animation(Motion.pick(Motion.easeOut(0.3), reduce: reduceMotion), value: model.recorderKind)
            .overlayPreferenceValue(CaptureOriginKey.self) { origins in
                if CaptureUI.shared.musicOpen {
                    MusicField(origin: CaptureUI.shared.musicGrows ? origins[.music] : nil)
                        .transition(.opacity.animation(Motion.easeOut(0.16)))
                }
            }
            .coordinateSpace(.named(Self.space))
            .background(OwnFocus(focused: $canvasFocused))
        }
        .clipped()
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { model.dayOrigin = $0 }
        // While a recorder is up its key equivalents take Esc, Return and Space, so the canvas gives the keys up and can't
        // take them back until it closes.
        .focusable(model.lens == nil && model.recorderKind == nil)
        .focusEffectDisabled()
        .focused($focused)
        // Arrows walk to the nearest card that way, Tab and ⇧Tab through capture order; ⌥ nudges by 8 pt, saved once the
        // key is let go, and ⇧⌥ resizes by as much.
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat, .up]) { canvasKey($0) }
        // ⇧Tab arrives as backtab (U+0019). Past the last card (or before the first) Tab goes on to the bar.
        .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")]) { press in
            guard cardsTakeKeys, !model.replay.active else { return .ignored }
            return walk(press.key == .tab && !press.modifiers.contains(.shift) ? 1 : -1)
        }
        .onCommand(#selector(NSText.selectAll(_:))) {
            if cardsTakeKeys { model.selection = Set(model.entries.map(\.id)) }
        }
        // Whatever held the focus over the canvas closed. A field that goes away leaves focus nowhere, and Space-drag, the
        // arrows and Tab need it back.
        .onChange(of: model.lens == nil) { _, closed in if closed { focused = true } }
        .onChange(of: model.openEntryID == nil) { _, closed in if closed { focused = true } }
        .onChange(of: model.insight == .spine) { _, closed in if closed { focused = true } }
        .onChange(of: model.searchOpen) { _, open in if !open { focused = true } }
        .onChange(of: ShellPanels.shared.panel == nil) { _, closed in if closed { focused = true } }
        // With keyboard navigation on, focus goes back to the date button instead (BottomBar).
        .onChange(of: model.datePickerOpen) { _, open in if !open && !NSApp.isFullKeyboardAccessEnabled { focused = true } }
        .onDeleteCommand {
            guard cardsTakeKeys else { return }
            let flies = !Motion.byKey && !reduceMotion
            Task { await model.trash(model.selection, undoManager: undoManager, flies: flies) }
        }
        .onExitCommand {
            if model.datePickerOpen { model.datePickerOpen = false }
            else if model.openEntryID != nil { model.openEntryID = nil }
            else if model.openStackID != nil { model.openStackID = nil }
            else if model.replay.active { model.replay.exit(animated: false) }
            else if model.openVoiceID != nil { model.openVoiceID = nil }
            else if model.insight != .spine { model.insight = .spine }
            else { model.selection = [] }
        }
        .onKeyPress(.return) {
            guard cardsTakeKeys else { return .ignored }
            // A stack the keys selected opens as its set.
            if let sid = model.stageCards.first(where: { $0.ids == model.selection })?.item.stackID {
                model.openStackID = sid
                return .handled
            }
            guard model.selection.count == 1, let id = model.selection.first else { return .ignored }
            if model.entry(id)?.kind == .voice { model.openVoiceID = id } else { model.openEntryID = id }
            return .handled
        }
        // While the day replays (DayReplay.tsx): ← → step entry to entry, Home and End go to the ends of the day, Space plays.
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end, .space]) { press in
            let replay = model.replay
            guard canvasFocused, replay.active, model.openEntryID == nil, press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
            switch press.key {
            case .rightArrow, .upArrow: replay.step(1)
            case .leftArrow, .downArrow: replay.step(-1)
            case .home, .end: replay.jump(toEnd: press.key == .end)
            default: if press.phase == .down { replay.toggle() }
            }
            return .handled
        }
        .onPasteCommand(of: CaptureInput.pasteTypes) { CaptureInput.paste($0, model: model) }
        .task(id: model.entries.map(\.id)) { await CaptureUI.shared.loadPrompts(model) }
        .onChange(of: screenID, initial: true) { _, s in model.screen = s }
        .onChange(of: model.replayItems) { _, items in model.replay.update(items) }
        .onChange(of: model.replay.active) { _, on in if on { focused = true } }
        .onAppear { focused = true }
        .task {
            try? await Task.sleep(for: .seconds(2.5))
            LensState.warm()
        }
        // A closed recorder or music field leaves no field holding the keys; the bar's button may take them next.
        .onChange(of: model.recorderKind == nil && !CaptureUI.shared.musicOpen) { _, idle in if idle { focused = true } }
        .onChange(of: model.recorderKind != nil) { _, up in if up { focused = false } }
        // So does an edit on a card that Return or Esc ended; a click that ended it leaves the keys where it put them.
        .onChange(of: CaptureUI.shared.editing == nil) { _, ended in if ended, NSApp.currentEvent?.type == .keyDown { focused = true } }
        .onChange(of: focused) { _, on in if !on { saveNudge() } }
        // Leaving the journal (another pane, or the window closed) ends the replay where it is and closes the open entry,
        // which would otherwise hide the chrome of a day view that comes back without its detail.
        .onDisappear {
            model.replay.exit(animated: false)
            model.openEntryID = nil
        }
    }

    /// The canvas has the keys, with nothing over it that takes them: the arrows, Tab, ⌘A, Return and Delete act on its cards.
    private var cardsTakeKeys: Bool {
        canvasFocused && model.lens == nil && model.openEntryID == nil && model.openStackID == nil && model.recorderKind == nil
            && !model.datePickerOpen && model.insight == .spine
    }

    private var screenID: ScreenID {
        if model.lens != nil { return .lens }
        if model.datePickerOpen { return .datePicker }
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

    private func canvasKey(_ press: KeyPress) -> KeyPress.Result {
        if press.phase == .up {
            guard nudged != nil else { return .ignored }
            saveNudge()
            return .handled
        }
        guard cardsTakeKeys, !model.replay.active else { return .ignored }
        let dir: CGVector = switch press.key {
        case .leftArrow: CGVector(dx: -1, dy: 0)
        case .rightArrow: CGVector(dx: 1, dy: 0)
        case .upArrow: CGVector(dx: 0, dy: -1)
        default: CGVector(dx: 0, dy: 1)
        }
        let cards = model.stageCards
        switch press.modifiers.intersection([.command, .option, .shift, .control]) {
        case []:
            saveNudge()
            let current = cards.first { !$0.ids.isDisjoint(with: model.selection) }
            let next = current.map { c in DayLayout.neighbour(of: c.center, toward: dir, among: cards.map { ($0.id, $0.center) }) }
                ?? Self.captureOrder(cards).first?.id
            if let next, let c = cards.first(where: { $0.id == next }) { model.selection = c.ids }
        case .option:
            for id in model.selection { model.layouts[id]?.x += dir.dx * 8; model.layouts[id]?.y += dir.dy * 8 }
            if !model.selection.isEmpty { nudged = .moved(model.selection) }
        case [.option, .shift]:
            guard model.selection.count == 1, let id = model.selection.first, let e = model.entry(id),
                  let spec = CanvasMath.resizeSpec(e.kind), var l = model.layouts[id] else { return .ignored }
            // The top-left corner stays; a picture with no height of its own keeps its proportions.
            let s = model.size(of: e)
            let w = (s.width + dir.dx * 8).clamped(to: spec.minW...spec.maxW)
            if dir.dy != 0 || l.h != nil { l.h = Double((s.height + dir.dy * 8).clamped(to: spec.minH...spec.maxH)) }
            l.w = Double(w)
            model.layouts[id] = l
            let after = model.size(of: e)
            model.layouts[id]?.x += (after.width - s.width) / 2
            model.layouts[id]?.y += (after.height - s.height) / 2
            nudged = .resized(id)
        default:
            return .ignored
        }
        return .handled
    }

    /// Saves what an ⌥-arrow nudge or ⇧⌥-arrow resize moved, once.
    private func saveNudge() {
        switch nudged {
        case .moved(let ids): model.move(ids, by: .zero)
        case .resized(let id):
            if let e = model.entry(id), let l = model.layouts[id] {
                model.resize(id, to: CGRect(center: CGPoint(x: l.x, y: l.y), size: model.size(of: e)), height: l.h.map { CGFloat($0) })
            }
        case nil: break
        }
        nudged = nil
    }

    /// Tab and ⇧Tab walk the cards in the order they were captured; past either end the selection clears and the key
    /// moves focus on, as the web's cards sit in the page's Tab order.
    private func walk(_ by: Int) -> KeyPress.Result {
        let order = Self.captureOrder(model.stageCards)
        let i = order.firstIndex { !$0.ids.isDisjoint(with: model.selection) }.map { $0 + by } ?? (by > 0 ? 0 : -1)
        guard order.indices.contains(i) else {
            model.selection = []
            return .ignored
        }
        model.selection = order[i].ids
        return .handled
    }

    private static func captureOrder(_ cards: [StageCard]) -> [StageCard] {
        cards.sorted { ($0.item.entries.map(\.capturedAt).min() ?? .distantPast) < ($1.item.entries.map(\.capturedAt).min() ?? .distantPast) }
    }

    private func chrome(_ size: CGSize) -> some View {
        ZStack {
            OrbitNav()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 24).padding(.top, 40)
            InsightSurface(height: size.height - size.height * 0.075 - model.barClear - 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 24).padding(.top, size.height * 0.075)
            // A click anywhere else closes the date picker.
            if model.datePickerOpen {
                Color.clear.contentShape(.rect).onTapGesture { model.datePickerOpen = false }
            }
            VStack(spacing: 10) {
                if model.datePickerOpen {
                    DatePickerPanel().transition(reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .bottom).combined(with: .opacity))
                } else if !model.selection.isEmpty && model.openStackID == nil {
                    SelectionToolbar().transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // Never edge to edge: past its one row's width the bar takes two.
                BottomBar()
                    .padding(.horizontal, 16)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height + 20 } action: { if model.barClear != $0 { model.barClear = $0 } }
            }
            .animation(Motion.pick(Motion.small, reduce: reduceMotion), value: model.selection.isEmpty)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 20)
        }
    }
}

/// The day under the lens, scaled about its top-left corner and offset along the lens's flight; identity otherwise, so the
/// stage keeps its state.
private struct LensPose: ViewModifier {
    let pose: LensState.DayPose?

    func body(content: Content) -> some View {
        content.scaleEffect(pose?.scale ?? 1, anchor: .topLeading).offset(pose?.offset ?? .zero).opacity(Double(pose?.opacity ?? 1))
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
            let size = item.isStack ? CanvasMath.stackSize : self.size(of: item.top)
            return StageCard(item: item, center: position(of: item.top.id), size: size,
                             radius: item.isStack ? 18 : CanvasMath.radius(item.top.kind))
        }
    }
}

/// The camera: screen = world × zoom + pan.
struct Camera: Equatable {
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    /// The gestures' floor and ceiling (MIN_SCALE, MAX_SCALE); a busy day's own framing may sit below the floor.
    static let range: ClosedRange<CGFloat> = 0.2...3

    /// The canvas inside the web's insets: top 104, right 120 for the spine, bottom 112 for the bar.
    static func frame(_ size: CGSize) -> CGRect {
        CGRect(x: 40, y: 104, width: max(200, size.width - 160), height: max(200, size.height - 104 - 132))
    }

    /// Frames every card inside the insets, never above 100% and down to 8% for a very busy day (FIT_MIN_SCALE).
    static func fit(_ cards: [StageCard], in size: CGSize) -> Camera {
        guard let b = CanvasMath.bounds(cards.map { CGRect(center: $0.center, size: $0.size) }), size.width > 0 else { return Camera() }
        let frame = frame(size)
        let z = min(1, frame.width / b.width, frame.height / b.height).clamped(to: 0.08...1)
        return Camera(zoom: z, pan: CGSize(width: frame.midX - b.midX * z, height: frame.midY - b.midY * z))
    }

    /// The world rect this camera shows inside the insets.
    func visible(_ size: CGSize) -> CGRect {
        let f = Camera.frame(size)
        return CGRect(x: (f.minX - pan.width) / zoom, y: (f.minY - pan.height) / zoom, width: f.width / zoom, height: f.height / zoom)
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}

extension View {
    /// The modifier, except while `skip` holds (the view is rebuilt as it changes).
    @ViewBuilder func modifier(_ m: some ViewModifier, unless skip: Bool) -> some View {
        if skip { self } else { modifier(m) }
    }
}

/// One day's canvas: cards on a camera, marquee, stack fan-out and the open/close flight. Keyed by day, so each day
/// arrives with its own fitted camera.
struct DayStage: View {
    @Environment(AppModel.self) private var model
    /// The canvas (the day view around the stage) has keyboard focus.
    @Environment(\.isFocused) private var canvasFocused
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
    /// What a file dragged over the canvas would become.
    @State private var dropKind: EntryKind?
    /// The recorder's developed frame on its way into its card, which waits hidden until it lands.
    @State private var landing: (image: Image, from: CGRect, to: CGRect, radius: CGFloat, card: String, v: Double)?
    @State private var shownID: String?
    @State private var flightFrom: (rect: CGRect, radius: CGFloat) = (.zero, 28)
    @State private var flight: Double = 0
    @State private var scrim = false
    @State private var fanned = false
    /// Each fanned turn's words, under its question.
    @State private var answers: [String: String] = [:]
    @State private var userMoved = false
    /// Cards thrown and still gliding, which keep their motion blur until they land.
    @State private var thrown: Set<String> = []
    /// The faces of cards flying to or from the Undo toast, taken while the day still has them.
    @State private var faces: [String: Image] = [:]
    @State private var sizing: Sizing?
    /// The card whose handles show because the pointer is on it, kept 150 ms after the pointer leaves.
    @State private var hoverID: String?
    @State private var unhover: Task<Void, Never>?
    /// Where the pointer last was over the empty canvas, so something new from its menu lands there. A plain box, so
    /// following the pointer doesn't redraw the stage.
    @State private var menuPoint = PointerBox()

    private final class PointerBox { var point: CGPoint? }
    /// Below the day's floor a zoom-out builds a pull (1 is none): the day shrinks slowly and dims, and at 0.7 the time
    /// lens opens.
    @State private var pull: CGFloat = 1
    @State private var pullAt: CGPoint = .zero
    @State private var settle: Task<Void, Never>?
    /// The faint grid while the canvas pans, and when it last moved.
    @State private var panning = false
    @State private var panIdle: Task<Void, Never>?
    /// Space-drag and middle-drag, with their recent pointer samples for the glide.
    @State private var dragPan: [(t: TimeInterval, p: CGPoint)] = []
    /// While a held card is within 60 pt of an edge, the canvas pans that way each frame and the card goes along.
    @State private var edgePush: CGSize = .zero
    @State private var edgePanned: CGSize = .zero
    @State private var edgeTask: Task<Void, Never>?
    @State private var lastHold: (card: StageCard, translation: CGSize, velocity: CGSize)?
    @State private var relayoutTask: Task<Void, Never>?

    /// A card's box while one of its handles is dragged (world units).
    private struct Sizing {
        let id: String
        let handle: CanvasMath.Handle
        let start: CGRect
        /// It had a height of its own when the drag began.
        let sized: Bool
        /// Where the press landed, in the world; and the pointer now, on the stage.
        let from: CGPoint
        var pointer: CGPoint
        var rect: CGRect
        var follows = false
    }

    /// The stage's own space, where a handle reports its pointer.
    static let space = "DayStage"

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
            ForEach(cards) { card(live($0)) }
            if let sid = model.openStackID, isCurrent { fan(sid) }
            if let m = marquee {
                RoundedRectangle(cornerRadius: 4).fill(Tok.ink.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Tok.ink3.opacity(0.45), lineWidth: 1))
                    .frame(width: m.width, height: m.height).position(x: m.midX, y: m.midY).allowsHitTesting(false)
            }
            if let id = shownID, let entry = model.entry(id) { detail(entry) }
            if let l = landing { LandingFlight(image: l.image, from: l.from, to: l.to, toRadius: l.radius, v: l.v).allowsHitTesting(false) }
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
        .coordinateSpace(.named(Self.space))
        .onChange(of: flying.map(\.id)) { _, ids in
            faces = faces.filter { ids.contains($0.key) }
            for c in flying where faces[c.id] == nil { faces[c.id] = c.face(model, scheme: colorScheme, scale: displayScale * camera.zoom) }
        }
        .onDrop(of: CaptureInput.dropTypes, delegate: CaptureDrop(model: model, kind: $dropKind, world: world))
        .overlay { DropOverlay(kind: dropKind, day: day) }
        .onChange(of: model.openEntryID) { _, id in if isCurrent { morph(to: id) } }
        .onChange(of: CaptureUI.shared.landing) { _, l in if isCurrent, let l { land(l) } }
        .onContinuousHover { phase in
            guard case .active(let p) = phase else { return hover(nil) }
            hover(cards.last { underPointer($0, p) }.flatMap { resizable($0) ? $0.id : nil })
        }
        // Shift and ⌥ change a resize without the pointer moving; so does a pan or zoom, which keeps the edge under it.
        .onModifierKeysChanged(mask: [.shift, .option], initial: false) { _, keys in
            resize(shift: keys.contains(.shift), option: keys.contains(.option))
        }
        .onChange(of: camera) { _, _ in
            let keys = NSEvent.modifierFlags
            resize(shift: keys.contains(.shift), option: keys.contains(.option))
        }
        // A card trashed or stacked mid-resize takes the drag with it, unsaved, as the web's does when it unmounts.
        .onChange(of: cards.map(\.id)) { _, ids in
            if let s = sizing, !ids.contains(s.id) {
                sizing = nil
                retractGrid()
            }
        }
        #if DOGFOOD
        .onReceive(NotificationCenter.default.publisher(for: Snapshots.hold)) { _ in
            if isCurrent, let c = cards.first { hold(c, translation: CGSize(width: 37, height: 23), velocity: .zero) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Snapshots.resize)) { n in
            guard isCurrent else { return }
            if n.object as? Bool == false { return endResize() }
            if let c = cards.first(where: { resizable($0) && $0.item.top.kind == .moment }) ?? cards.first(where: resizable) {
                let p = screen(c.center)
                beginResize(c, .se, at: p)
                resize(to: CGPoint(x: p.x + 96, y: p.y + 30), shift: false, option: false)
            }
        }
        #endif
        // Until the user pans, zooms or drags, the day stays framed as its cards arrive and settle; one flying into the
        // Undo toast leaves the rest where they are, so Undo brings it back to the same spot.
        .onChange(of: cards.map { "\($0.id)\($0.center)" }) { _, _ in
            // A key's nudge leaves the camera where it is.
            if !userMoved && model.trashFlight?.into != true && !Motion.byKey { camera = Camera.fit(cards, in: size) }
        }
        .onChange(of: model.camera) { _, cmd in
            guard isCurrent, let cmd else { return }
            // ⌘0, ⌘= and ⌘- (and the refit after Esc closes the lens) move the camera at once: the frequency rule.
            let key = Motion.byKey
            switch cmd {
            case .fit: withAnimation(key ? nil : Motion.pick(Motion.surface, reduce: reduceMotion)) { camera = Camera.fit(cards, in: size) }
            case .zoom(let f, _):
                userMoved = true
                withAnimation(key ? nil : Motion.pick(Motion.small, reduce: reduceMotion)) { zoom(by: f, at: CGPoint(x: size.width / 2, y: size.height / 2)) }
            case .focus(let id, _):
                guard let c = cards.first(where: { $0.id == id }) else { return }
                userMoved = true
                model.selection = c.ids
                withAnimation(Motion.pick(Motion.surface, reduce: reduceMotion)) {
                    camera.pan = CGSize(width: size.width / 2 - c.center.x * camera.zoom, height: size.height / 2 - c.center.y * camera.zoom)
                }
            }
        }
        // The rubber band below the floor dims the day as the pull builds.
        .opacity(pull < 1 && !reduceMotion ? max(0, 1 - (1 - pull) * 1.2) : 1)
        .onChange(of: camera, initial: true) { publishVisible() }
        .onChange(of: isCurrent) { publishVisible() }
        // A new width lays the day's untouched cards out again for its shape (B-002); a new height changes nothing.
        .onChange(of: size.width) { _, _ in
            guard isCurrent else { return }
            relayoutTask?.cancel()
            relayoutTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                userMoved = false
                model.relayout(for: Camera.frame(size))
            }
        }
        // A card the keyboard selected is panned into view, instantly (the frequency rule).
        .onChange(of: model.selection) { _, ids in
            guard isCurrent, Motion.byKey, ids.count == 1, let c = cards.first(where: { !$0.ids.isDisjoint(with: ids) }) else { return }
            let r = screenRect(c), f = Camera.frame(size)
            guard !f.contains(r) else { return }
            userMoved = true
            camera.pan.width += r.minX < f.minX ? f.minX - r.minX : r.maxX > f.maxX ? max(f.minX - r.minX, f.maxX - r.maxX) : 0
            camera.pan.height += r.minY < f.minY ? f.minY - r.minY : r.maxY > f.maxY ? max(f.minY - r.minY, f.maxY - r.maxY) : 0
        }
    }

    // MARK: Coordinates

    private func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * camera.zoom + camera.pan.width, y: p.y * camera.zoom + camera.pan.height) }
    private func world(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - camera.pan.width) / camera.zoom, y: (p.y - camera.pan.height) / camera.zoom) }

    /// The wheel's floor: 20%, or lower when the day only fits further out, so its own framing isn't a pull.
    private var floor: CGFloat { min(Camera.range.lowerBound, Camera.fit(cards, in: size).zoom) }

    private func setZoom(_ next: CGFloat, at p: CGPoint) {
        camera.pan = CGSize(width: p.x - (p.x - camera.pan.width) * next / camera.zoom, height: p.y - (p.y - camera.pan.height) * next / camera.zoom)
        camera.zoom = next
    }

    /// A key or menu zoom stops at the floor.
    private func zoom(by factor: CGFloat, at p: CGPoint) {
        setZoom((camera.zoom * factor).clamped(to: floor...Camera.range.upperBound), at: p)
    }

    /// A pinch or ⌘-scroll: one level through the floor, where the zoom becomes a pull (Canvas.tsx zoomAt). The day keeps
    /// shrinking slowly (floor × pull^0.35) and dims, and once the pull reaches 0.7 the lens opens and the same gesture
    /// carries on into it. Let go before that and it springs back. Reduce Motion: no pull to see, the lens fades in.
    private func pinch(by factor: CGFloat, at p: CGPoint) {
        let lo = floor
        let level = (pull < 1 ? lo * pull : camera.zoom) * factor
        pull = level < lo ? level / lo : 1
        pullAt = p
        if pull < 1 { LensState.warm() }
        if pull < 0.7 {
            pull = 1
            settle?.cancel()
            if PrefsStore.shared.haptics { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
            model.openLens(level: .week, opener: .pinch)
            return
        }
        setZoom(pull < 1 ? (reduceMotion ? lo : lo * pow(pull, 0.35)) : min(Camera.range.upperBound, level), at: p)
    }

    /// The pull springs back to the floor when the fingers lift (or 160 ms after a mouse wheel's last notch).
    private func endPull(after e: NSEvent) {
        settle?.cancel()
        let lifted = e.phase == .ended || e.phase == .cancelled
        guard pull < 1, lifted || e.phase.isEmpty else { return }
        settle = Task {
            if !lifted { try? await Task.sleep(for: .milliseconds(160)) }
            guard !Task.isCancelled, pull < 1, model.lens == nil else { return }
            withAnimation(Motion.pick(Motion.surface, reduce: reduceMotion)) {
                setZoom(floor, at: pullAt)
                pull = 1
            }
        }
    }

    /// Pans the camera, with the faint grid out from the pointer until 160 ms after the last move.
    private func panBy(_ d: CGSize, at p: CGPoint?, animated: Bool = false) {
        userMoved = true
        withAnimation(animated && !reduceMotion ? .spring(duration: 0.25) : nil) {
            camera.pan = CGSize(width: camera.pan.width + d.width, height: camera.pan.height + d.height)
        }
        if let p { pulseGrid(at: p) }
    }

    private func pulseGrid(at p: CGPoint) {
        guard !reduceMotion, drag == nil, sizing == nil else { return }
        let at = CGRect(center: world(p), size: .zero)
        if panning, var g = grid { g.move(to: at, x: nil, y: nil); grid = g } else {
            panning = true
            grid = DragGrid(rect: at, others: cards.map { CGRect(center: $0.center, size: $0.size) }, zoom: camera.zoom)
        }
        panIdle?.cancel()
        panIdle = Task {
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            panning = false
            retractGrid()
        }
    }

    /// Space-drag or middle-drag: the canvas follows 1:1, then glides on (velocity × 0.12 over 250 ms) unless the
    /// pointer rested 60 ms before letting go or moved slower than 20 pt/s.
    private func dragPan(_ phase: NSEvent.EventType, at p: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        switch phase {
        case .leftMouseDown, .otherMouseDown:
            dragPan = [(now, p)]
        case .leftMouseDragged, .otherMouseDragged:
            guard let last = dragPan.last else { return }
            panBy(CGSize(width: p.x - last.p.x, height: p.y - last.p.y), at: p)
            dragPan = (dragPan + [(now, p)]).suffix(8)
        default:
            defer { dragPan = [] }
            guard let last = dragPan.last, now - last.t < 0.06, let first = dragPan.first(where: { last.t - $0.t <= 0.1 }), last.t > first.t else { return }
            let v = CGSize(width: (last.p.x - first.p.x) / (last.t - first.t), height: (last.p.y - first.p.y) / (last.t - first.t))
            guard hypot(v.width, v.height) >= 20, !reduceMotion else { return }
            withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.75)) {
                camera.pan = CGSize(width: camera.pan.width + v.width * 0.12, height: camera.pan.height + v.height * 0.12)
            }
        }
    }

    /// Holding a card within 60 pt of an edge pans the canvas that way, faster the closer it gets; the card goes along.
    private func edge(_ location: CGPoint) {
        let push = { (d: CGFloat) in d < 60 ? (60 - d) / 60 * 12 : 0 }
        edgePush = CGSize(width: push(location.x) - push(size.width - location.x), height: push(location.y) - push(size.height - location.y))
        guard edgePush != .zero, edgeTask == nil else { return }
        edgeTask = Task {
            while !Task.isCancelled, edgePush != .zero, drag != nil {
                camera.pan = CGSize(width: camera.pan.width + edgePush.width, height: camera.pan.height + edgePush.height)
                edgePanned = CGSize(width: edgePanned.width + edgePush.width, height: edgePanned.height + edgePush.height)
                if let h = lastHold { hold(h.card, translation: h.translation, velocity: h.velocity) }
                try? await Task.sleep(for: .milliseconds(16))
            }
            edgeTask = nil
        }
    }

    /// Publishes what the camera shows, so new cards land in it.
    private func publishVisible() {
        guard isCurrent else { return }
        model.visibleWorld = camera.visible(size)
        if model.stageSize != size { model.stageSize = size }
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
                             && model.insight == .spine && !model.searchOpen && !model.devNotesVisible && model.lens?.exiting != false
                             && !model.datePickerOpen,
                         onPan: { d, p, e in
                             // A mouse wheel's notch springs through its step; a trackpad follows the fingers.
                             panBy(d, at: p, animated: !e.hasPreciseScrollingDeltas)
                         },
                         onZoom: { f, p, e in
                             userMoved = true
                             if e.type == .scrollWheel, !e.hasPreciseScrollingDeltas, pull >= 1, camera.zoom * f >= floor {
                                 withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { zoom(by: f, at: p) }
                             } else {
                                 pinch(by: f, at: p)
                             }
                             pulseGrid(at: p)
                             endPull(after: e)
                         },
                         onDragPan: model.replay.active ? nil : { phase, p in dragPan(phase, at: p) },
                         takesSpace: canvasFocused,
                         // A bare Space tap on the canvas opens the voice pill; held while dragging, it pans.
                         onSpaceTap: { CaptureInput.space(model) })
            DayStateView(day: day, empty: cards.isEmpty, width: size.width)
        }
        .contentShape(.rect)
        .onContinuousHover { if case .active(let p) = $0 { menuPoint.point = p } }
        .contextMenu { CanvasMenu { menuPoint.point.map(world) } }
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
        return pose(Group {
            if c.item.isStack {
                StackFace(entries: c.item.entries, selected: selected)
            } else {
                CardFace(entry: c.item.top, selected: selected, open: open, size: c.size)
            }
        }
        // An open voice note grows right and down from the card's top-left corner.
        .frame(width: c.size.width, height: c.size.height, alignment: .topLeading), c, moving: moving)
        // Held or thrown only (useCardGesture.ts); an open voice note holds a scroller the shader can't draw, and a page
        // being typed into on its card holds AppKit editors the shader's layer can't host at all.
        .modifier(MotionBlurred(position: at, coverage: c.size.width * c.size.height * camera.zoom * camera.zoom / (size.width * size.height),
                                enabled: !open && (moving || !thrown.isDisjoint(with: c.ids))), unless: CaptureUI.shared.editing?.id == c.id)
        // Over the blur, so the handles stay crisp on a thrown card, as the web's sit beside the card it blurs.
        .overlay {
            if showsHandles(c) {
                pose(ResizeHandles(size: c.size, zoom: camera.zoom, active: sizing?.id == c.id ? sizing?.handle : nil,
                                   onDrag: { h, from, to in
                                       beginResize(c, h, at: from)
                                       let keys = NSEvent.modifierFlags
                                       resize(to: to, shift: keys.contains(.shift), option: keys.contains(.option))
                                   },
                                   onEnd: endResize), c, moving: moving)
                // ponytail: a gliding card's handles wait for it to land; the web stops the glide where it is, which SwiftUI can't read back.
                .allowsHitTesting(thrown.isDisjoint(with: c.ids))
            }
        }
        .cardMenu(c.item)
        .position(at)
        .opacity(c.ids.contains(shownID ?? "") || (c.item.stackID != nil && c.item.stackID == model.openStackID) || inFlight(c)
            || landing.map { $0.card == c.id && $0.v < 1 } == true ? 0 : 1)
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
        } else if c.item.top.kind != .reflection {
            // A reflection's next click edits it on the card; its corner button (or Return) opens the page.
            model.openEntryID = c.item.top.id
        }
    }

    /// 4 pt of slop, then 1:1 tracking with a lift and a velocity tilt; a throw glides on (velocity × 0.12), lands on a
    /// guide when one is close to where it would stop, and settles on the release spring (useCardGesture.ts).
    private func dragGesture(_ c: StageCard) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                lastHold = (c, v.translation, v.velocity)
                hold(c, translation: v.translation, velocity: v.velocity)
                edge(v.location)
            }
            .onEnded { v in
                edgeTask?.cancel()
                (edgeTask, edgePush, edgePanned, lastHold) = (nil, .zero, .zero, nil)
                guard let d = drag, let g = grid else { return }
                let speed = hypot(v.velocity.width, v.velocity.height)
                var total = d.offset
                if speed > 20 && !reduceMotion {
                    let glide = CGSize(width: (v.velocity.width * 0.12).clamped(to: -360...360), height: (v.velocity.height * 0.12).clamped(to: -360...360))
                    let s = snaps(g.rect.offsetBy(dx: glide.width / camera.zoom, dy: glide.height / camera.zoom), g)
                    total.width += glide.width + (s.x?.delta ?? 0) * camera.zoom
                    total.height += glide.height + (s.y?.delta ?? 0) * camera.zoom
                    thrown.formUnion(d.ids)
                }
                // ponytail: the grid retracts where the card was let go; the web's follows the glide until it lands.
                retractGrid()
                withAnimation(reduceMotion ? nil : speed > 1000 ? Motion.release : Motion.lift) {
                    model.move(d.ids, by: CGSize(width: total.width / camera.zoom, height: total.height / camera.zoom))
                    drag = nil
                } completion: {
                    thrown.subtract(d.ids)
                }
            }
    }

    /// The first move lifts the card(s) and draws the grid out from them; every move snaps.
    private func hold(_ c: StageCard, translation: CGSize, velocity: CGSize) {
        userMoved = true
        // What the edge pan moved the canvas by comes off, so the card stays under the pointer.
        let t = CGSize(width: translation.width - edgePanned.width, height: translation.height - edgePanned.height)
        if panning { (panning, grid) = (false, nil) }
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

    private func retractGrid() {
        guard var g = grid else { return }
        let ended = Date.now
        g.ended = ended
        grid = g
        Task {
            try? await Task.sleep(for: .seconds(DragGridLayer.retract))
            if grid?.ended == ended { grid = nil }
        }
    }

    /// A held card's lift and tilt, its replay landing and the camera's zoom: its handles take them too, so they move as one.
    private func pose(_ v: some View, _ c: StageCard, moving: Bool) -> some View {
        v.scaleEffect(moving && !reduceMotion ? 1.02 : 1)
            .rotationEffect(.degrees(moving && !reduceMotion ? drag!.tilt : 0))
            .animation(Motion.lift, value: moving)
            .animation(Motion.small, value: drag?.tilt)
            .modifier(ReplayLanding(shown: model.replay.shows(c.id), cue: model.replay.cues[c.id], reduceMotion: reduceMotion))
            .scaleEffect(camera.zoom)
    }

    // MARK: Resizing (CanvasCard.tsx, useCardGesture.ts)

    private func resizable(_ c: StageCard) -> Bool { !c.item.isStack && CanvasMath.resizeSpec(c.item.top.kind) != nil }

    /// On a hovered card, or a single selected one.
    private func showsHandles(_ c: StageCard) -> Bool {
        isCurrent && resizable(c) && (sizing?.id == c.id || hoverID == c.id || model.selection == c.ids)
    }

    /// On the card, or within its handles' reach: 8 pt off its edges, 36 off its corners.
    private func underPointer(_ c: StageCard, _ p: CGPoint) -> Bool {
        let r = screenRect(c)
        guard resizable(c) else { return r.contains(p) }
        let near = { (out: CGFloat) in (-8...36).contains(out) }
        return r.insetBy(dx: -8, dy: -8).contains(p)
            || (near(r.minX - p.x) || near(p.x - r.maxX)) && (near(r.minY - p.y) || near(p.y - r.maxY))
    }

    private func hover(_ id: String?) {
        if let id {
            unhover?.cancel()
            unhover = nil
            if hoverID != id { hoverID = id }
        } else if hoverID != nil && unhover == nil {
            unhover = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                hoverID = nil
                unhover = nil
            }
        }
    }

    /// The card being resized, at its live box.
    private func live(_ c: StageCard) -> StageCard {
        guard let s = sizing, s.id == c.id else { return c }
        return StageCard(item: c.item, center: CGPoint(x: s.rect.midX, y: s.rect.midY), size: s.rect.size, radius: c.radius)
    }

    /// A press on a handle selects the card and draws the grid out from it.
    private func beginResize(_ c: StageCard, _ handle: CanvasMath.Handle, at press: CGPoint) {
        guard sizing == nil else { return }
        userMoved = true
        model.selection = c.ids
        let start = CGRect(center: c.center, size: c.size)
        sizing = Sizing(id: c.id, handle: handle, start: start, sized: model.layouts[c.id]?.h != nil, from: world(press), pointer: press,
                        rect: start)
        grid = DragGrid(rect: start, others: cards.filter { $0.id != c.id }.map { CGRect(center: $0.center, size: $0.size) },
                        zoom: camera.zoom)
    }

    /// The opposite edge stays put and the moving one snaps as a dragged card's do (⌥ frees it); Shift frees a picture's
    /// proportions. A card with no height of its own sets only its width when it keeps them or is only widened.
    private func resize(to pointer: CGPoint? = nil, shift: Bool, option: Bool) {
        guard var s = sizing, var g = grid, let c = cards.first(where: { $0.id == s.id }),
              let spec = CanvasMath.resizeSpec(c.item.top.kind) else { return }
        if let pointer { s.pointer = pointer }
        let at = world(s.pointer)
        let d = CGSize(width: at.x - s.from.x, height: at.y - s.from.y)
        var sx: CanvasMath.Snap?, sy: CanvasMath.Snap?
        // Only a move resizes (useCardGesture.ts): with no distance an edge could still snap to a guide and a bare click would save it.
        if d == .zero {
            s.rect = s.start
        } else {
            let reach = 6 / camera.zoom, rhythm = 3 / camera.zoom
            let next = CanvasMath.resize(s.start, s.handle, by: d, spec: spec,
                                         free: shift,
                                         snapX: { x in
                                             sx = option ? nil : CanvasMath.snap([x], cards: g.cardX, reach: reach, axis: 0, level: g.level, rhythmReach: rhythm)
                                             return x + (sx?.delta ?? 0)
                                         },
                                         snapY: { y in
                                             sy = option ? nil : CanvasMath.snap([y], cards: g.cardY, reach: reach, axis: 1, level: g.level, rhythmReach: rhythm)
                                             return y + (sy?.delta ?? 0)
                                         })
            let side = s.handle.sides.y
            s.follows = !s.sized && ((spec.keepsAspect && !shift) || side == 0)
            let h = s.follows ? CanvasMath.size(c.item.top.kind, w: next.width, h: nil).height : next.height
            s.rect = CGRect(x: next.minX, y: side < 0 ? s.start.maxY - h : next.minY, width: next.width, height: h)
        }
        g.move(to: s.rect, x: sx, y: sy)
        sizing = s
        grid = g
    }

    private func endResize() {
        guard let s = sizing else { return }
        if s.rect != s.start { model.resize(s.id, to: s.rect, height: s.follows ? nil : s.rect.height) }
        sizing = nil
        retractGrid()
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

    // MARK: The recorder's last frame into its card (VideoReflectionScreen.tsx captureMorph)

    /// The camera centres the session's card, then the developed frame flies from where the recorder held it into the card.
    private func land(_ l: CaptureUI.Landing) {
        CaptureUI.shared.landing = nil
        guard let c = cards.first(where: { $0.ids.contains(l.entryId) }) else { return }
        userMoved = true
        let pan = CGSize(width: size.width / 2 - c.center.x * camera.zoom, height: size.height / 2 - c.center.y * camera.zoom)
        withAnimation(Motion.surface) { camera.pan = pan }
        let to = CGRect(center: CGPoint(x: size.width / 2, y: size.height / 2),
                        size: CGSize(width: c.size.width * camera.zoom, height: c.size.height * camera.zoom))
        landing = (Image(decorative: l.image, scale: 1), l.from, to, c.radius * camera.zoom, c.id, 0)
        DispatchQueue.main.async {
            withAnimation(Motion.surface) { landing?.v = 1 } completion: { landing = nil }
        }
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
            Rectangle().fill(.frosted(solid: Tok.bg)).overlay(Tok.bg.opacity(0.85)).ignoresSafeArea()
                .onTapGesture { close(sid) }
            ForEach(Array(members.enumerated()), id: \.element.id) { i, e in
                let p = fanned || reduceMotion ? points[e.id] ?? origin : origin
                VStack(spacing: 6) {
                    CardFace(entry: e, selected: model.selection.contains(e.id), size: tile)
                    Text(["Turn \(e.turnNumber ?? i + 1)", model.media[e.mediaId ?? ""]?.durationMs.map { Duration.milliseconds($0).formatted(.time(pattern: .minuteSecond)) }]
                        .compactMap { $0 }.joined(separator: " · ")).monoCaps(10).foregroundStyle(Tok.ink2)
                    if let q = model.prompt(for: e) {
                        Text(q).font(Typo.serif(15, italic: true)).foregroundStyle(Tok.voice).lineLimit(2)
                            .multilineTextAlignment(.center).frame(width: tile.width)
                    }
                    if let a = answers[e.id], model.verdicts[e.id]?.verdict != "safety_hold" {
                        Text(a).font(Typo.ui(14)).foregroundStyle(Tok.ink2).lineLimit(2)
                            .multilineTextAlignment(.center).frame(width: tile.width)
                    }
                }
                .scaleEffect(fanned || reduceMotion ? 1 : 0.6)
                .modifier(MotionBlurred(position: p, coverage: tile.width * tile.height / (size.width * size.height)))
                .position(p)
                .opacity(e.id == shownID ? 0 : 1)
                .animation(fanned ? Motion.easeOut(0.42).delay(Double(i) * 0.04) : Motion.easeOut(0.22).delay(Double(members.count - 1 - i) * 0.03), value: fanned)
                .onTapGesture { model.openEntryID = e.id }
            }
            // The set's header (VideoStackOverlay.tsx), at the top as the web keeps it.
            HStack(spacing: 14) {
                Text("\(members.count) turns").monoCaps(10).foregroundStyle(Tok.ink2)
                Button("Unstack") { withAnimation(Motion.pick(Motion.small, reduce: reduceMotion)) { model.unstack(sid) } }
                    .help("Lay the turns out on the canvas")
                if let first = members.first, first.kind == .moment {
                    Button {
                        CaptureUI.shared.playAll = true
                        model.openEntryID = first.id
                    } label: {
                        Label("Play all", systemImage: "play.fill").labelStyle(.titleAndIcon).font(Typo.ui(12.5, .semibold))
                    }
                    .foregroundStyle(Tok.sage)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Play every turn in order  ⌘↩")
                }
                Button("Done") { close(sid) }.help("Fold back into the stack  Esc")
            }
            .font(Typo.ui(12.5, .medium))
            .buttonStyle(.plain)
            .fixedSize()
            .padding(.horizontal, 16).padding(.vertical, 9)
            .glassPanel(radius: 20)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 28)
        }
        .onAppear { fanned = true }
        .task(id: members.map(\.id)) {
            for e in members {
                guard let id = e.mediaId, let words = try? await model.ledger.transcript(mediaId: id), !words.isEmpty else { continue }
                answers[e.id] = words.map(\.text).joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
        }
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
        case .still:
            return CanvasMath.stillFrame(in: size, aspect: ThumbCache.aspect(model.mediaURL(for: e)),
                                         below: StillBelow.room(held: model.verdicts[e.id]?.verdict == "safety_hold"))
        case .reflection: (w, h) = (min(820, size.width - 96), min(820, size.height - 96))
        case .music: (w, h) = (min(560, size.width - 96), min(460, size.height - 96))
        }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    /// A key opens and closes the detail at once (morph.ts: keyboard-initiated opens and closes don't fly).
    private func morph(to id: String?) {
        let key = Motion.byKey
        if let id {
            flightFrom = model.reflection.flightSource.map { ($0, Radius.card) } ?? screenRect(entry: id)
            model.reflection.flightSource = nil
            shownID = id
            if key {
                flight = 1
                scrim = true
                return
            }
            guard !reduceMotion else {
                withAnimation(Motion.fade) { flight = 1; scrim = true }
                return
            }
            flight = 0
            DispatchQueue.main.async {
                withAnimation(Motion.surface) { flight = 1 }
                withAnimation(Motion.easeOut(0.2)) { scrim = true }
            }
        } else if key {
            scrim = false
            flight = 0
            shownID = nil
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
            Rectangle().fill(.frosted(solid: Tok.bg)).overlay(Tok.bg.opacity(0.85)).ignoresSafeArea()
                .opacity(scrim ? 1 : 0)
                .onTapGesture { model.openEntryID = nil }
            MorphFlight(entry: entry, from: flightFrom.rect, fromRadius: flightFrom.radius, to: detailTarget(entry),
                        toRadius: Radius.sheet, viewport: size, v: flight, crossfadeOnly: reduceMotion)
            // A still's caption sits under the photo, outside the flight, and fades on its own (Lightbox.tsx `below`).
            if entry.kind == .still {
                let to = detailTarget(entry), w = max(to.width, min(420, size.width - 32))
                StillBelow(entry: entry)
                    .frame(width: w)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(x: to.midX - w / 2, y: to.maxY + 18)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .opacity(scrim ? 1 : 0)
                    .animation(scrim ? Motion.easeOut(0.24).delay(0.16) : Motion.easeOut(0.12), value: scrim)
            }
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
    @Environment(AppModel.self) private var model
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
        // A turn opened from the fanned set flies from its tile, which is drawn at the default size.
        let fanned = model.openStackID != nil && model.layouts[entry.id]?.stackId == model.openStackID
        let cardSize = fanned ? CanvasMath.size(entry.kind) : model.size(of: entry)
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
                CardFace(entry: entry, size: cardSize)
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

/// The developed frame on its way into its card: the morph's log-space box and straight-line centre, the recorder's 28 pt
/// corners easing to the card's, handing over to the card in the last 30% of the way.
private struct LandingFlight: View, @MainActor Animatable {
    let image: Image
    let from: CGRect
    let to: CGRect
    let toRadius: CGFloat
    var v: Double

    var animatableData: Double {
        get { v }
        set { v = newValue }
    }

    var body: some View {
        let box = CanvasMath.flightBox(from: from, to: to, v: CGFloat(v))
        image.resizable().scaledToFill()
            .frame(width: box.width, height: box.height)
            .clipShape(.rect(cornerRadius: Radius.sheet + (toRadius - Radius.sheet) * v))
            .elevation(.overlay)
            .opacity(1 - min(max((v - 0.7) / 0.3, 0), 1))
            .position(x: box.midX, y: box.midY)
            .accessibilityHidden(true)
    }
}

/// What the canvas says when it has no cards (DayState.tsx): the day is loading (only once that is slow enough to notice,
/// so a quick load doesn't flash), it couldn't be read, or it is honestly empty.
struct DayStateView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let day: String
    let empty: Bool
    let width: CGFloat
    @State private var slow = false

    private enum Shown { case loading, failed, empty }

    /// A day sliding away keeps what it said.
    private var current: Bool { model.day == day }
    /// Not while it shows it failed, so Try again waits its 150 ms before the skeleton, as the first load did.
    private var loading: Bool { current && model.loadedDay != day && !model.loadFailed }

    private var shown: Shown? {
        if current && model.loadFailed { return .failed }
        if loading { return slow && empty ? .loading : nil }
        return empty ? .empty : nil
    }

    /// "Today" and "Yesterday" read lower-case mid-sentence ("Couldn't load yesterday.").
    private var label: String {
        let s = DayFormat.sidebar(day)
        return ["Today", "Yesterday"].contains(s) ? s.lowercased() : s
    }

    var body: some View {
        ZStack {
            switch shown {
            case .loading:
                DaySkeleton(width: width)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Loading \(label)…")
                    .transition(.opacity.animation(Motion.easeOut(0.2)))
            case .failed:
                failed.transition(.asymmetric(insertion: reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)), removal: .opacity)
                    .animation(Motion.easeOut(0.4)))
            case .empty:
                EmptyDay(day: day).transition(.asymmetric(insertion: .identity, removal: .opacity.animation(Motion.easeOut(0.5))))
            case nil:
                EmptyView()
            }
        }
        .task(id: loading) {
            slow = false
            guard loading else { return }
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled { slow = true }
        }
    }

    private var failed: some View {
        VStack(spacing: 8) {
            Text("Couldn't load \(label).").font(Typo.ui(15, .medium)).foregroundStyle(Tok.ink)
            Text("Saro couldn't read the journal on this Mac.").font(Typo.ui(13)).tracking(0.13).foregroundStyle(Tok.ink2)
            Button("Try again") {
                model.loadFailed = false
                Task { await model.reload() }
            }
            .buttonStyle(RetryStyle())
            .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24).padding(.vertical, 20)
        // ponytail: sized to its two short lines; the web's 384 pt cap only matters to text long enough to wrap.
        .fixedSize()
        .glassPanel()
        .onAppear { AccessibilityNotification.Announcement("Couldn't load \(label).").post() }
    }
}

/// Three shimmer blocks, 24 pt apart, each 120 ms behind the last; the outer two give way on a narrow window.
private struct DaySkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let width: CGFloat
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSince(start)
            HStack(spacing: 24) {
                if width >= 768 { block(CGSize(width: 220, height: 150), t: t) }
                block(CGSize(width: min(280, width * 0.6), height: 190), t: t - 0.12)
                if width >= 640 { block(CGSize(width: 200, height: 150), t: t - 0.24) }
            }
        }
        .allowsHitTesting(false)
    }

    /// The `shimmer` keyframes: surface-alt light sweeping over line/50, 1.6 s ease-in-out, forever; still under Reduce Motion.
    private func block(_ size: CGSize, t: Double) -> some View {
        let p = reduceMotion || t < 0 ? 0 : UnitCurve.easeInOut.value(at: t.truncatingRemainder(dividingBy: 1.6) / 1.6)
        let line = Tok.line.opacity(0.5)
        return LinearGradient(stops: [.init(color: line, location: 0), .init(color: Tok.surfaceAlt, location: 0.25),
                                      .init(color: line, location: 0.5), .init(color: Tok.surfaceAlt, location: 0.75),
                                      .init(color: line, location: 1)], startPoint: .leading, endPoint: .trailing)
            .frame(width: size.width * 4, height: size.height)
            .offset(x: CanvasMath.shimmerOffset(width: size.width, progress: p))
            .frame(width: size.width, height: size.height, alignment: .leading)
            .clipShape(.rect(cornerRadius: Radius.sheet))
    }
}

/// The web's sage call to action: 44 pt tall, radius 8, sage-dark on hover, 0.98 on press, the cta shadow.
private struct RetryStyle: ButtonStyle {
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.ui(13, .medium)).tracking(0.13)
            .foregroundStyle(Tok.onPrimary)
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background(hover ? Tok.sageDark : Tok.sage, in: .rect(cornerRadius: Radius.control))
            .shadow(color: Tok.sage.opacity(0.22), radius: 10, y: 4)
            .contentShape(.rect(cornerRadius: Radius.control))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(Motion.easeOut(0.16), value: hover)
            .onHover { hover = $0 }
    }
}

/// "Nothing here yet." or "Nothing from yesterday." in Newsreader, rising 6 pt over 500 ms (DayState.tsx). A past day says
/// a capture now is saved to it, which is what backdating does here.
private struct EmptyDay: View {
    let day: String
    @State private var shown = false

    var body: some View {
        let today = day == LocalDay.today()
        let label = DayFormat.relative(day)
        VStack(spacing: 10) {
            Text(today ? "Nothing here yet." : "Nothing from \(label == "Yesterday" ? "yesterday" : label).").font(Typo.serif(28)).foregroundStyle(Tok.ink)
            Text(today ? "Start with a moment, a voice note or a few words." : "Anything you add now is saved to this day.")
                .font(Typo.ui(14)).foregroundStyle(Tok.ink2)
        }
        .multilineTextAlignment(.center)
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
            tool("Stack", "square.stack.3d.up", Shortcut.stack.keys) { withAnimation(Motion.byKey ? nil : Motion.small) { model.stack(model.selection) } }
                .keyboardShortcut(KeyboardShortcut(.stack)).disabled(model.selection.count < 2)
            tool("Grid", "rectangle.grid.1x2", Shortcut.grid.keys) { withAnimation(Motion.byKey ? nil : Motion.small) { model.grid(model.selection) } }
                .keyboardShortcut(KeyboardShortcut(.grid)).disabled(model.selection.count < 2)
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
