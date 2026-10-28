import AppKit
import SaroKit
import SwiftUI

/// The time lens's controller (lensEngine.ts): zoom, pan, flights and keys on one physics loop that runs only while
/// something moves, plus the day summaries and key frames it draws. One per opening; `AppModel.lens` holds it.
@Observable @MainActor
final class LensState {
    enum Opener { case pinch, key }
    enum Status { case loading, ready, failed }
    enum How { case animated, instant }

    /// The live day under the lens, driven along the inverse of the lens's flight, so it is the surface that becomes the
    /// tile (and comes back out of it). Scale about the top-left corner, then offset.
    struct DayPose: Equatable {
        var scale: CGFloat, offset: CGSize, opacity: CGFloat
    }

    /// A picked day's tile flying into the canvas while the lens gets out of the way.
    struct Handoff: Equatable {
        let index: Int
        let from: CGRect
    }

    @ObservationIgnored unowned let model: AppModel
    let opener: Opener
    let cal: LensCalendar
    let initialIndex: Int
    /// The canvas's own day, when the lens reaches it.
    let selectedIndex: Int?
    /// "November 2016" when the lens opened on a day older than it reaches.
    let reachFrom: String?
    /// "today", "yesterday", "Tue 22 Sep", for the close button.
    let back: String
    let reduced = PrefsStore.shared.reduceMotionEffective
    var todayIndex: Int { cal.days.count - 1 }

    private(set) var level: LensMath.Level
    private(set) var focus: Int
    /// The continuous zoom: 0 week, 1 month, 2 year.
    private(set) var z: CGFloat
    /// A key moved the focus, so its ring shows; the pointer hides it.
    private(set) var focusVisible: Bool
    private(set) var hover: Int?
    private(set) var blocks: [LensMath.Transform] = []
    private(set) var rowBand: CGFloat = 1
    /// The tiles' smear along their velocity while they move fast, in points.
    private(set) var smear: CGSize = .zero
    private(set) var dayPose: DayPose?
    private(set) var opacity: CGFloat = 1
    private(set) var dip: CGFloat = 1
    /// How far the entry or exit flight is (0 at rest), so the band mask gives way to a tile covering the window.
    private(set) var flightShown: CGFloat = 0
    private(set) var busy = true
    private(set) var exiting = false
    private(set) var handoff: Handoff?
    private(set) var handoffProgress: CGFloat = 0
    /// A tile handed off to the canvas isn't drawn in the grid any more.
    private(set) var hidden: Int?
    private(set) var geo: LensMath.Geometry
    private(set) var viewport = LensState.firstViewport
    private static let firstViewport = LensMath.Viewport(width: 1320, height: 860, top: 120, bottom: 61)

    private(set) var summaries: [Int: DaySummary] = [:]
    private(set) var frames: [Int: CGImage] = [:]
    /// When a tile's mood and picture arrived, so they fade in over 0.24 s.
    private(set) var arrived: [Int: Date] = [:]
    private(set) var status = Status.loading
    private(set) var slow = false
    private(set) var weekEntries: [LensEntry] = []

    private struct Sample { let t: Double; let v: CGFloat }
    private struct Gesture {
        enum Kind { case zoom, pan }
        let kind: Kind
        var raw: CGFloat
        var origin: CGFloat
        let startLevel: Int
        let level: LensMath.Level
        var samples: [Sample] = []
        var stepped = false
        var lastStep = 0.0
    }

    @ObservationIgnored private var zs: LensMath.Spring
    @ObservationIgnored private var zTarget: CGFloat
    @ObservationIgnored private var zRunning = false
    @ObservationIgnored private var zDamping: CGFloat = 1
    @ObservationIgnored private var pan = LensMath.Spring(0)
    @ObservationIgnored private var panRunning = false
    @ObservationIgnored private var panDamping: CGFloat = 1
    @ObservationIgnored private var flight: LensMath.Spring
    @ObservationIgnored private var flightTarget: CGFloat = 0
    @ObservationIgnored private var flightRunning: Bool
    @ObservationIgnored private var flightIndex: Int
    @ObservationIgnored private var fade: LensMath.Spring
    @ObservationIgnored private var fadeTarget: CGFloat = 1
    @ObservationIgnored private var fadeRunning: Bool
    @ObservationIgnored private var afterFade: (() -> Void)?
    @ObservationIgnored private var dipS = LensMath.Spring(1)
    @ObservationIgnored private var dipTarget: CGFloat = 1
    @ObservationIgnored private var dipRunning = false
    @ObservationIgnored private var afterDip: (() -> Void)?
    @ObservationIgnored private var handoffS = LensMath.Spring(0)
    @ObservationIgnored private var gesture: Gesture?
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var finished = false
    @ObservationIgnored private var picked = false
    @ObservationIgnored private var last: Double?
    @ObservationIgnored private var lastFocusCentre: CGPoint?
    @ObservationIgnored private var wheelRelease: Task<Void, Never>?

    // Apple-style response and damping from the shared tokens: a token's settle time is about 9.23/(2π) of its response.
    private static let surface: CGFloat = 2 * .pi * 0.4 / 9.23
    private static let small: CGFloat = 2 * .pi * 0.25 / 9.23
    private static let flickDamping: CGFloat = 0.85

    init(model: AppModel, level: LensMath.Level, opener: Opener) {
        self.model = model
        self.opener = opener
        let today = LocalDay.today()
        let opened = model.day
        let first = model.days.last?.day ?? today
        // The last twelve months, back to the first entry ever and the day it opened on; ten years at most.
        let yearAgo = LocalDay.adding(-334, to: today)
        let floor = LocalDay.adding(-3652, to: today)
        let wanted = min(yearAgo, first, opened)
        let start = String(max(wanted, floor).prefix(7)) + "-01"
        let cal = LensCalendar(from: start, through: today, weekStart: Calendar.current.firstWeekday - 1)
        self.cal = cal
        let found = cal.index(of: opened)
        let tooOld = found == nil && opened < (cal.days.first?.key ?? "")
        initialIndex = found ?? (tooOld ? 0 : max(0, cal.days.count - 1))
        selectedIndex = found
        reachFrom = tooOld ? cal.days.first.map { $0.date.formatted(.dateTime.month(.wide).year()) } : nil
        let relative = DayFormat.relative(opened)
        back = ["Today", "Yesterday"].contains(relative) ? relative.lowercased() : relative
        self.level = level
        focus = initialIndex
        flightIndex = initialIndex
        z = CGFloat(level.rawValue)
        zs = LensMath.Spring(CGFloat(level.rawValue))
        zTarget = CGFloat(level.rawValue)
        focusVisible = opener == .key
        let flies = opener == .pinch && !PrefsStore.shared.reduceMotionEffective
        flight = LensMath.Spring(flies ? 1 : 0)
        flightRunning = flies
        let fadesIn = opener == .pinch && PrefsStore.shared.reduceMotionEffective
        fade = LensMath.Spring(fadesIn ? 0 : 1)
        fadeRunning = fadesIn
        geo = LensMath.measure(cal, Self.firstViewport)
        Task { await load() }
    }

    var focusDay: String { cal.days[focus].key }
    var unit: ClosedRange<Int> { cal.unit(focus, level) }

    // MARK: Data

    func load() async {
        status = .loading
        let slowTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled { slow = true }
        }
        defer { slowTask.cancel() }
        do {
            guard let from = cal.days.first?.key, let to = cal.days.last?.key else { return }
            let rows = try await model.ledger.daySummaries(from: from, to: to)
            var byIndex: [Int: DaySummary] = [:]
            let index = Dictionary(uniqueKeysWithValues: cal.days.enumerated().map { ($1.key, $0) })
            for s in rows { if let i = index[s.day] { byIndex[i] = s } }
            summaries = byIndex
            status = .ready
            slow = false
            kick()
            await loadWeek()
            // Moods fill in afterwards, most recent days first, a few at a time and batched every 250 ms. A held day has none.
            let order = byIndex.keys.sorted { abs($0 - initialIndex) < abs($1 - initialIndex) }
            Task { await loadFrames(order) }
            var batch: [Int: Mood] = [:], flushed = ContinuousClock.now
            for i in order {
                guard model.lens === self else { return }
                if let mood = await model.pipeline.dayMood(cal.days[i].key) { batch[i] = mood }
                if ContinuousClock.now - flushed > .milliseconds(250) || i == order.last {
                    let now = Date.now
                    for (j, m) in batch { summaries[j]?.mood = m; arrived[j] = now }
                    batch = [:]
                    flushed = .now
                    kick()
                }
            }
        } catch {
            status = .failed
            slow = false
        }
    }

    /// Key frames, nearest the opening day first.
    private func loadFrames(_ order: [Int]) async {
        var media: [(Int, MediaAsset)] = []
        for i in order {
            if let id = summaries[i]?.keyMediaId, let m = try? await model.ledger.media(id) { media.append((i, m)) }
        }
        await Posters.backfill(media.map(\.1), in: model.ledger) { [weak self] id in
            guard let self, let i = media.first(where: { $0.1.id == id })?.0, let img = Posters.image(id: id) else { return }
            frames[i] = img
            arrived[i] = arrived[i].map { max($0, .now) } ?? .now
            kick()
        }
    }

    /// The week on screen's entries, for its replay.
    func loadWeek() async {
        let r = cal.unit(focus, .week)
        weekEntries = (try? await model.ledger.lensEntries(from: cal.days[r.lowerBound].key, to: cal.days[r.upperBound].key)) ?? []
    }

    // MARK: Frames

    func setViewport(_ vp: LensMath.Viewport) {
        guard vp.width > 0, vp != viewport || !ready else { return }
        viewport = vp
        geo = LensMath.measure(cal, vp)
        ready = true
        draw()
        kick()
    }

    func kick() {
        guard !finished else { return }
        if !busy { last = nil }
        busy = true
    }

    /// One frame of the physics loop, called by the lens's timeline while `busy`.
    func tick(_ date: Date) {
        guard !finished else { return }
        let t = date.timeIntervalSinceReferenceDate
        let dt = CGFloat(last.map { min(max(t - $0, 0), 1.0 / 30) } ?? 1.0 / 60)
        last = t
        var moving = gesture != nil
        if zRunning { if zs.step(to: zTarget, dt: dt, response: Self.surface, damping: zDamping) { zRunning = false } else { moving = true } }
        if panRunning { if pan.step(to: 0, dt: dt, response: Self.surface, damping: panDamping, epsilon: 0.0002) { panRunning = false } else { moving = true } }
        if flightRunning && (ready || exiting) {
            let done = flight.step(to: flightTarget, dt: dt, response: Self.surface, epsilon: 0.0008)
            // An exit is over once the tile covers the window; the last few percent aren't visible.
            if done || (exiting && flight.x > 0.97) {
                flightRunning = false
                if exiting { return finish() }
            } else { moving = true }
        } else if flightRunning { moving = true }
        if fadeRunning && (ready || exiting) {
            if fade.step(to: fadeTarget, dt: dt, response: Self.small, epsilon: 0.002) || (fadeTarget == 0 && fade.x < 0.02) {
                fadeRunning = false
                let next = afterFade
                afterFade = nil
                next?()
                if finished { return }
            } else { moving = true }
        } else if fadeRunning { moving = true }
        if dipRunning {
            if dipS.step(to: dipTarget, dt: dt, response: Self.small * 0.5, epsilon: 0.004) {
                dipRunning = false
                let next = afterDip
                afterDip = nil
                next?()
            }
            moving = true
        }
        if handoff != nil {
            if handoffS.step(to: 1, dt: dt, response: Self.surface, epsilon: 0.002) { handoffProgress = 1; return finish() }
            handoffProgress = handoffS.x
            moving = true
        }
        draw(dt: dt)
        let fading = arrived.values.contains { date.timeIntervalSince($0) < 0.26 }
        if !moving && !fading { busy = false }
    }

    private static func smooth01(_ t: CGFloat) -> CGFloat {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    private func draw(dt: CGFloat = 1.0 / 60) {
        guard !cal.days.isEmpty else { return }
        var (t, band) = LensMath.transforms(cal, geo, focus: focus, z: zs.x, pan: pan.x)
        let f = flight.x
        if let fl = LensMath.applyFlight(cal, &t, f: f, index: flightIndex, width: viewport.width, height: viewport.height), !reduced,
           opener == .pinch || exiting, handoff == nil {
            let k = pow(fl.cover, f - 1), cx = viewport.width / 2, cy = viewport.height / 2
            let pose = DayPose(scale: k, offset: CGSize(width: fl.x + (cx - fl.x) * f - k * cx, height: fl.y + (cy - fl.y) * f - k * cy),
                               opacity: Self.smooth01((f - 0.45) / 0.55))
            dayPose = f <= 0.0005 ? DayPose(scale: pose.scale, offset: pose.offset, opacity: 0) : pose
        } else {
            dayPose = nil
        }
        blocks = t
        rowBand = band
        z = zs.x
        opacity = min(max(fade.x, 0), 1) * (1 - Self.smooth01((f - 0.45) / 0.55))
        flightShown = min(max(f, 0), 1)
        dip = min(max(dipS.x, 0), 1)
        // The smear follows the focus tile's velocity: none at rest, up to 6 pt from 0.6 pt/ms.
        let centre = LensMath.tileRect(cal, t, focus).map { CGPoint(x: $0.midX, y: $0.midY) }
        if let centre, let before = lastFocusCentre, !reduced, dt > 0 {
            let v = CGSize(width: (centre.x - before.x) / (dt * 1000), height: (centre.y - before.y) / (dt * 1000))
            let speed = hypot(v.width, v.height)
            let length = speed > 0.6 ? min(6, (speed - 0.6) * 4) : 0
            smear = length > 0.3 ? CGSize(width: v.width / speed * length, height: v.height / speed * length) : .zero
        } else {
            smear = .zero
        }
        lastFocusCentre = centre
    }

    // MARK: Focus, levels, exits

    private func setFocus(_ i: Int) {
        guard i != focus else { return }
        let week = cal.unit(focus, .week)
        focus = i
        if !week.contains(i) { Task { await loadWeek() } }
    }

    private func springZ(_ target: Int, v: CGFloat) {
        zTarget = CGFloat(target)
        zs.v = v
        // A zoom never overshoots a level: a bouncing grid reads as indecision.
        zDamping = 1
        zRunning = true
        level = LensMath.Level(rawValue: target) ?? .week
        kick()
    }

    /// Reduce Motion: a quick dip of the content instead of travelling.
    private func dipThen(_ apply: @escaping () -> Void) {
        dipTarget = 0
        dipRunning = true
        afterDip = { [weak self] in
            apply()
            self?.dipTarget = 1
            self?.dipRunning = true
        }
        kick()
    }

    private func jump(to target: Int) {
        (zs.x, zs.v, zTarget, zRunning) = (CGFloat(target), 0, CGFloat(target), false)
        (pan.x, panRunning) = (0, false)
        level = LensMath.Level(rawValue: target) ?? .week
        draw()
        kick()
    }

    func go(to l: LensMath.Level, how: How) {
        guard !exiting else { return }
        gesture = nil
        if how == .instant { jump(to: l.rawValue) }
        else if reduced { dipThen { [weak self] in self?.jump(to: l.rawValue) } }
        else { springZ(l.rawValue, v: zRunning ? zs.v : 0) }
    }

    /// One level in (−1) or out (+1); in from the week opens the focused day.
    func step(_ dir: Int, how: How) {
        let current = Int((zRunning ? zTarget : zs.x).rounded()).clamped(to: 0...2)
        if dir < 0 && current == 0 { return pick(focus, how: how) }
        guard let l = LensMath.Level(rawValue: (current + dir).clamped(to: 0...2)) else { return }
        go(to: l, how: how)
    }

    func move(_ key: LensMath.Move) {
        guard !exiting, !cal.days.isEmpty else { return }
        gesture = nil
        (panRunning, pan.x) = (false, 0)
        focusVisible = true
        setFocus(LensMath.move(cal, focus, key))
        draw()
        kick()
    }

    /// The accessibility grid moved the focus.
    func focusFromAccessibility(_ i: Int) {
        guard i != focus, !exiting else { return }
        (pan.x, panRunning) = (0, false)
        focusVisible = true
        setFocus(i)
        draw()
        kick()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        busy = false
        dayPose = nil
        if !picked { model.camera = .fit(UUID()) }
        model.lens = nil
    }

    /// From the moment it starts, the lens stops taking pointer input, so the canvas is live again; a watchdog makes sure an
    /// exit whose frames stall never leaves an invisible lens over it.
    private func startExit() {
        exiting = true
        gesture = nil
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            finish()
        }
    }

    private func fadeOut() {
        fadeTarget = 0
        fadeRunning = true
        afterFade = { [weak self] in if self?.handoff == nil { self?.finish() } }
        kick()
    }

    private func onScreen(_ r: CGRect) -> Bool { r.maxX > 0 && r.maxY > 0 && r.minX < viewport.width && r.minY < viewport.height }

    /// Flies into the tile until it covers the window (the entry reversed); a tile off screen, or Reduce Motion, fades.
    private func leave(_ i: Int, how: How) {
        gesture = nil
        if how == .instant { return finish() }
        guard let r = LensMath.tileRect(cal, blocks, i), !reduced, onScreen(r), !(flight.x > 0.05 && flightIndex != i) else { return fadeOut() }
        (zRunning, panRunning) = (false, false)
        flightIndex = i
        flightTarget = 1
        flightRunning = true
        kick()
    }

    /// Opens a day. Another day picked with the pointer flies its tile into that day while the lens fades out of the way;
    /// the day the lens opened on, or a key's pick, is left in place by the lens itself.
    func pick(_ i: Int, how: How) {
        guard !exiting, cal.days.indices.contains(i) else { return }
        startExit()
        picked = true
        let r = LensMath.tileRect(cal, blocks, i)
        let hands = how == .animated && i != initialIndex && !reduced && r.map(onScreen) == true
        model.go(to: cal.days[i].key)
        if hands, let r {
            hidden = i
            handoff = Handoff(index: i, from: r)
            handoffS = LensMath.Spring(0)
            fadeOut()
        } else {
            leave(i, how: how)
        }
    }

    func close(how: How) {
        guard !exiting else { return }
        startExit()
        leave(initialIndex, how: how)
    }

    // MARK: Gestures

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    private func record(_ v: CGFloat) {
        gesture?.samples.append(Sample(t: Self.now, v: v))
        if (gesture?.samples.count ?? 0) > 32 { gesture?.samples.removeFirst() }
    }

    /// Units a second over the last 100 ms; zero if the gesture paused before letting go.
    private func velocity(releasedAt: Double? = nil) -> CGFloat {
        guard let s = gesture?.samples, let last = s.last else { return 0 }
        if let releasedAt, releasedAt - last.t > 0.06 { return 0 }
        let first = s.first { last.t - $0.t <= 0.1 } ?? last
        let dt = last.t - first.t
        return dt > 0.008 ? (last.v - first.v) / CGFloat(dt) : 0
    }

    private var focusScale: CGFloat { blocks.indices.contains(cal.days[focus].block) ? blocks[cal.days[focus].block].scale : geo.weekScale }

    /// At rest on a level, a zoom starts from the tile under the pointer; a dimmed neighbour becomes the focus and the pan
    /// carries it to the centre.
    private func retarget(_ p: CGPoint) {
        let l = Int(zs.x.rounded())
        guard !zRunning, abs(zs.x - CGFloat(l)) <= 0.02, let i = LensMath.tileAt(cal, blocks, p, slack: 6), i != focus else { return }
        if l < 2 {
            let unit: LensMath.Level = l == 0 ? .week : .month
            let (a, f) = (cal.days[i], cal.days[focus])
            if !(a.block == f.block && (l == 1 || a.row == f.row)) {
                pan.x += LensMath.framingY(cal, focus, unit) - LensMath.framingY(cal, i, unit)
                (pan.v, panRunning) = (0, true)
            }
        }
        setFocus(i)
    }

    private func beginZoom(at p: CGPoint) {
        guard !exiting, gesture?.kind != .zoom else { return }
        if gesture != nil { releasePan() }
        retarget(p)
        zRunning = false
        focusVisible = false
        // The gesture drives the log of the focus tile's size, so the tiles scale 1:1 with the fingers.
        let raw = LensMath.logOfZ(geo, LensMath.zRaw(zs.x))
        gesture = Gesture(kind: .zoom, raw: raw, origin: raw, startLevel: Int(zs.x.rounded()).clamped(to: 0...2), level: .week)
        record(zs.x)
    }

    private func updateZoom(by delta: CGFloat) {
        guard var g = gesture, g.kind == .zoom else { return }
        g.raw += delta
        gesture = g
        if reduced {
            if !g.stepped, abs(g.raw - g.origin) > 0.3 {
                gesture?.stepped = true
                step(g.raw > g.origin ? -1 : 1, how: .animated)
            }
            return
        }
        zs.x = LensMath.zShown(LensMath.zOfLog(geo, g.raw))
        zs.v = 0
        record(zs.x)
        kick()
    }

    private func releaseZoom() {
        guard let g = gesture, g.kind == .zoom else { return }
        let v = velocity()
        gesture = nil
        guard !reduced else { return }
        if let target = LensMath.settle(z: zs.x, velocity: v, from: g.startLevel) { springZ(target, v: v) } else { pick(focus, how: .animated) }
    }

    private func panBounds(_ l: LensMath.Level) -> ClosedRange<CGFloat> {
        let fy = LensMath.framingY(cal, focus, l)
        return (LensMath.framingY(cal, 0, l) - fy)...(LensMath.framingY(cal, todayIndex, l) - fy)
    }

    @discardableResult
    private func beginPan() -> Bool {
        guard !exiting, zs.x <= 1.3 else { return false }
        if gesture?.kind == .pan { return true }
        if gesture != nil { releaseZoom() }
        panRunning = false
        focusVisible = false
        gesture = Gesture(kind: .pan, raw: pan.x, origin: 0, startLevel: 0, level: zs.x < 0.5 ? .week : .month)
        record(pan.x)
        return true
    }

    private func updatePan(world: CGFloat, points: CGFloat) {
        guard var g = gesture, g.kind == .pan else { return }
        if reduced {
            // A step per decent push, faded rather than slid.
            g.origin += points
            if abs(g.origin) > 90, Self.now - g.lastStep > 0.3 {
                let key: LensMath.Move = g.level == .week ? (g.origin > 0 ? .down : .up) : (g.origin > 0 ? .pageDown : .pageUp)
                let next = LensMath.move(cal, focus, key)
                (g.origin, g.lastStep) = (0, Self.now)
                if next != focus { dipThen { [weak self] in self?.setFocus(next); self?.draw() } }
            }
            gesture = g
            return
        }
        g.raw += world
        gesture = g
        let b = panBounds(g.level), dim = viewport.height / focusScale * 0.5
        pan.x = g.raw < b.lowerBound ? b.lowerBound + LensMath.rubberband(g.raw - b.lowerBound, dim)
            : g.raw > b.upperBound ? b.upperBound + LensMath.rubberband(g.raw - b.upperBound, dim) : g.raw
        pan.v = 0
        record(pan.x)
        kick()
    }

    /// A pan rests on the week row or month nearest where its momentum would carry it; a trackpad scroll that carried
    /// the system's own momentum settles where that stopped.
    private func releasePan(at released: Double? = nil, momentum: Bool = true) {
        guard let g = gesture, g.kind == .pan else { return }
        let v = velocity(releasedAt: released)
        gesture = nil
        guard !reduced else { return }
        let b = panBounds(g.level), fy = LensMath.framingY(cal, focus, g.level)
        let next = LensMath.snapFocus(cal, focus, g.level, worldY: fy + (pan.x + (momentum ? LensMath.project(v) : 0)).clamped(to: b))
        if next != focus {
            pan.x += fy - LensMath.framingY(cal, next, g.level)
            setFocus(next)
        }
        pan.v = v
        panDamping = abs(v * focusScale) > 1500 ? Self.flickDamping : 1
        panRunning = true
        kick()
    }

    /// Pinch, ⌘-scroll and two-finger scroll from the lens's event monitor: 100 pt of wheel scales the tiles by e (each
    /// step clamped to ±40), exact gesture phases end them, and a plain mouse wheel ends 80 ms after its last notch.
    func handle(_ e: NSEvent, at p: CGPoint) {
        guard !exiting else { return }
        if hover != nil { hover = nil }
        switch e.type {
        case .magnify:
            if e.phase == .began || gesture?.kind != .zoom { beginZoom(at: p) }
            if e.magnification != 0 { updateZoom(by: log(max(0.05, 1 + e.magnification))) }
            if e.phase == .ended || e.phase == .cancelled { releaseZoom() }
        case .scrollWheel where e.modifierFlags.contains(.command):
            let dy = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 16
            if gesture?.kind != .zoom { beginZoom(at: p) }
            updateZoom(by: dy.clamped(to: -40...40) / 100)
            endWheel(e, zoom: true)
        case .scrollWheel:
            let k: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 12
            let dy = -e.scrollingDeltaY * k
            guard dy != 0 || e.phase == .ended || e.momentumPhase == .ended else { return }
            if e.momentumPhase == .ended { return releasePan(momentum: false) }
            guard beginPan() else { return }
            updatePan(world: dy / focusScale, points: dy)
            endWheel(e, zoom: false)
        default: break
        }
    }

    private func endWheel(_ e: NSEvent, zoom: Bool) {
        wheelRelease?.cancel()
        // A trackpad says when the fingers lift and when its momentum stops; a mouse wheel says neither.
        let fingersUp = e.phase == .ended
        guard !e.hasPreciseScrollingDeltas || fingersUp else { return }
        wheelRelease = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, let self else { return }
            if zoom { releaseZoom() } else { releasePan(momentum: !fingersUp) }
        }
    }

    /// A drag that moved past 8 pt pans; one that didn't is a tap.
    func drag(by delta: CGFloat) {
        guard beginPan() else { return }
        updatePan(world: -delta / focusScale, points: -delta)
    }

    func dragEnded() { releasePan(at: Self.now) }

    func tap(at p: CGPoint) {
        focusVisible = false
        if let i = LensMath.tileAt(cal, blocks, p, slack: 4) { pick(i, how: .animated) }
    }

    func hover(at p: CGPoint?) {
        let i = p.flatMap { gesture == nil ? LensMath.tileAt(cal, blocks, $0) : nil }
        guard i != hover else { return }
        hover = i
        kick()
    }
}

/// The lens over the window: the grid, the header, the week replay and the key hint (LensView.tsx). A modal dialog
/// named by the period it frames.
struct TimeLens: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let lens: LensState
    @FocusState private var focused: Bool
    @State private var headerBottom: CGFloat = 96

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                ZStack {
                    Tok.bg
                    RadialGradient(colors: [Tok.surface, Tok.surface.opacity(0)], center: UnitPoint(x: 0.5, y: -0.1), startRadius: 0,
                                   endRadius: geo.size.height * 0.85)
                    LensGrid(lens: lens).opacity(lens.dip)
                    CanvasEvents(enabled: !lens.exiting, onEvent: { e, p in lens.handle(e, at: p) })
                }
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 8)
                    .onChanged { v in
                        lens.drag(by: v.translation.height - (lastDrag ?? 0))
                        lastDrag = v.translation.height
                    }
                    .onEnded { _ in
                        lastDrag = nil
                        lens.dragEnded()
                    })
                .onTapGesture { p in lens.tap(at: p) }
                .onContinuousHover { phase in
                    if case .active(let p) = phase { lens.hover(at: p) } else { lens.hover(at: nil) }
                }
                .pointerStyle(lens.hover != nil ? .link : nil)
                LensHeader(lens: lens)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("lens")).maxY } action: { headerBottom = $0 }
                if lens.level == .week, lens.status == .ready, lens.z < 0.5 {
                    WeekReplayPanel(lens: lens)
                }
                Text("← → ↑ ↓ days · + − zoom · ↵ open · esc back")
                    .monoCaps(10.5, tracking: 0.06).foregroundStyle(Tok.ink3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .opacity(lens.opacity)
            .coordinateSpace(.named("lens"))
            .overlay { if let h = lens.handoff { TileHandoff(lens: lens, handoff: h, size: geo.size) } }
            .onChange(of: geo.size, initial: true) { _, s in measure(s) }
            .onChange(of: headerBottom) { _, _ in measure(geo.size) }
        }
        .allowsHitTesting(!lens.exiting)
        .background { TimelineView(.animation(paused: !lens.busy)) { t in Color.clear.onChange(of: t.date, initial: true) { _, d in lens.tick(d) } } }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onExitCommand { lens.close(how: .instant) }
        // Keys stop here, so the canvas's own (Delete, Return, Space) can't fire behind the lens; none animates.
        .onDeleteCommand {}
        .onKeyPress { press in key(press) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(LensHeader.title(lens))
        .accessibilityHint("Arrow keys move between days, Page Up and Page Down between months. Plus and minus zoom between week, month and year. Enter opens a day. Escape goes back.")
    }

    @State private var lastDrag: CGFloat?

    /// The free band between the header and the key hint, each with 24 pt of air.
    private func measure(_ s: CGSize) {
        lens.setViewport(LensMath.Viewport(width: s.width, height: s.height, top: max(72, headerBottom) + 24, bottom: 24 + 13 + 24))
    }

    private func key(_ press: KeyPress) -> KeyPress.Result {
        guard press.phase != .up else { return .handled }
        let mods = press.modifiers.intersection([.command, .option, .control])
        if mods == .command, let l = ["1": LensMath.Level.week, "2": .month, "3": .year][press.characters] {
            lens.go(to: l, how: .instant)
            return .handled
        }
        guard mods.isEmpty else { return .ignored }
        switch press.key {
        case .leftArrow: lens.move(.left)
        case .rightArrow: lens.move(.right)
        case .upArrow: lens.move(.up)
        case .downArrow: lens.move(.down)
        case .pageUp: lens.move(.pageUp)
        case .pageDown: lens.move(.pageDown)
        case .home: lens.move(.home)
        case .end: lens.move(.end)
        case .return: lens.pick(lens.focus, how: .instant)
        case .tab: return .ignored
        default:
            switch press.characters {
            case "+", "=": lens.step(-1, how: .instant)
            case "-", "_": lens.step(1, how: .instant)
            default: break
            }
        }
        return .handled
    }
}

/// A picked day's tile (its key frame under the mood wash) flying from its place into the whole canvas, size in log
/// space as a card's flight, and crossfading into the real day from 60%.
private struct TileHandoff: View {
    @Environment(\.colorScheme) private var scheme
    let lens: LensState
    let handoff: LensState.Handoff
    let size: CGSize

    var body: some View {
        let v = lens.handoffProgress
        let box = CanvasMath.flightBox(from: handoff.from, to: CGRect(origin: .zero, size: size), v: v)
        let r = min(14, max(1.5, handoff.from.width * 0.085)) * (1 - v)
        LensTile(summary: lens.summaries[handoff.index], frame: lens.frames[handoff.index], night: scheme == .dark)
            .frame(width: box.width, height: box.height)
            .clipShape(.rect(cornerRadius: r))
            .position(x: box.midX, y: box.midY)
            .opacity(1 - min(1, max(0, (v - 0.6) / 0.4)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension DayFormat {
    /// "Today", "Yesterday", or "Tue 22 Sep" with the year when it's another year (dates.ts's formatDay).
    static func relative(_ day: String) -> String {
        let today = LocalDay.today()
        if day == today { return "Today" }
        if day == LocalDay.adding(-1, to: today) { return "Yesterday" }
        if day == LocalDay.adding(1, to: today) { return "Tomorrow" }
        guard let d = LocalDay.date(day) else { return day }
        // Spelled out piece by piece, so it reads "Tue 22 Sep" as the web's does, with no comma.
        let label = [d.formatted(.dateTime.weekday(.abbreviated)), d.formatted(.dateTime.day()), d.formatted(.dateTime.month(.abbreviated))]
        return (label + (day.prefix(4) == today.prefix(4) ? [] : [String(day.prefix(4))])).joined(separator: " ")
    }
}
