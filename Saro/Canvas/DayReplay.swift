import SaroKit
import SwiftUI

/// A day replay (hooks/useReplay.ts): a playhead runs through the day's time, the ground takes the light of that hour,
/// and each card shows once the playhead passes the moment it was captured. `hour` moves every frame, so only the track
/// and the ground read it; cards read `reached`.
@Observable @MainActor
final class DayReplay {
    struct Item: Equatable {
        let id: String
        let kind: EntryKind
        let hour: Double
        let title: String
        let mood: String?
    }

    /// How a card shows its last change; set with `reached` and read as the card redraws for it.
    enum Cue { case instant, land(delay: Double), leave }
    /// The track's tooltip: the cluster under the pointer, or the entry the playhead is on after a key or a landing.
    enum Tip: Equatable {
        case hover(Int), key, land
        var hovering: Bool { if case .hover = self { true } else { false } }
    }

    /// The day being replayed, or nil when the canvas shows the day as it is.
    private(set) var day: String?
    /// The playhead, 0–24.
    private(set) var hour = 0.0
    private(set) var atEnd = false
    private(set) var playing = false
    /// How many of `items` (oldest first) the playhead has passed.
    private(set) var reached = 0
    private(set) var items: [Item] = []
    /// 1 plays the day in about 20 s, 2 in 10 s, 0.5 in 40 s.
    private(set) var rate = 1.0
    var tip: Tip?
    /// The last open or close came from the pointer: the bar crossfades and the track grows out of the date.
    private(set) var animated = true

    @ObservationIgnored private(set) var cues: [String: Cue] = [:]
    @ObservationIgnored private var rank: [String: Int] = [:]
    @ObservationIgnored private var hours: [Double] = []
    @ObservationIgnored private var lapse: Replay.Lapse?
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var tipTimer: Task<Void, Never>?

    /// A far jump lands the last few with a stagger and puts the rest in place, so it never runs 150 animations at once.
    private static let maxLanding = 8, maxLeaving = 24, stagger = 0.04

    var active: Bool { day != nil }

    func shows(_ id: String) -> Bool {
        guard day != nil, let i = rank[id] else { return true }
        return i < reached
    }

    /// Replays `day` from 00:00: its cards fade away, then land as the playhead passes them.
    func start(_ day: String, items: [Item], animated: Bool) {
        stopClock()
        playing = false
        self.animated = animated
        cues = [:]
        set(items)
        lapse = nil
        self.day = day
        reached = items.count
        tip = nil
        seek(0, instant: false)
        play()
    }

    /// Time-lapses the rest of the day (the whole day from the end), sped up where nothing happens.
    func play() {
        guard day != nil, !playing else { return }
        let from = atEnd ? 0 : curve().time(at: hour)
        playing = true
        if from == 0 { seek(0, instant: false) }
        clock = Task { [weak self] in
            var t = from
            var last = ContinuousClock.now
            // ponytail: a ~60 Hz sleep loop rather than a display link; frames cap at 100 ms, so a stall resumes in place.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, !Task.isCancelled else { return }
                let now = ContinuousClock.now
                // A card deleted mid-play: the new curve carries on from where the playhead is.
                if lapse == nil { t = curve().time(at: hour) }
                t += min(0.1, (now - last) / .seconds(1)) * rate
                last = now
                let path = curve()
                seek(path.hour(at: t), instant: false)
                if t >= path.length {
                    clock = nil
                    pause()
                    return
                }
            }
        }
    }

    func pause() {
        stopClock()
        if playing { playing = false }
        if tip == .land { tip = nil }
    }

    func toggle() { playing ? pause() : play() }

    func cycleRate() { rate = rate == 1 ? 2 : rate == 2 ? 0.5 : 1 }

    /// The pointer on the track: entries it passes land, entries behind it fade away.
    func scrub(to hour: Double) {
        guard day != nil else { return }
        pause()
        seek(hour, instant: false)
    }

    /// Keys: to the next or previous entry, then the ends of the day. No animation.
    func step(_ by: Int) {
        guard day != nil else { return }
        pause()
        seek(by > 0 ? Replay.nextStop(hours, after: hour) : Replay.previousStop(hours, before: hour), instant: true)
        tip = .key
    }

    /// Home and End.
    func jump(toEnd: Bool) {
        guard day != nil else { return }
        pause()
        seek(toEnd ? Replay.dayHours : 0, instant: true)
        tip = nil
    }

    /// Back to the day as it is: every card in place, the light on the real clock. The track keeps its last state while
    /// it goes back into the date.
    func exit(animated: Bool) {
        guard day != nil else { return }
        stopClock()
        self.animated = animated
        for (i, item) in items[reached...].enumerated() {
            cues[item.id] = !animated || i >= Self.maxLanding ? .instant : .land(delay: Double(i) * Self.stagger)
        }
        day = nil
        playing = false
        tip = nil
        lapse = nil
        Daylight.shared.replayHour = nil
    }

    /// The day's cards changed mid-replay. Something new ends the replay, so it's never hidden ahead of the playhead; a
    /// deletion leaves the rest where the playhead has them; a rename or a new mood only redraws the track.
    func update(_ next: [Item]) {
        guard day != nil, next != items else { return }
        if next.contains(where: { rank[$0.id] == nil }) { return exit(animated: true) }
        let moved = next.map(\.id) != items.map(\.id) || next.map(\.hour) != hours
        set(next)
        guard moved else { return }
        lapse = nil
        for item in next { cues[item.id] = .instant }
        let r = Replay.reached(hours, at: hour)
        if r != reached { reached = r }
    }

    private func set(_ next: [Item]) {
        items = next
        hours = next.map(\.hour)
        rank = Dictionary(uniqueKeysWithValues: next.enumerated().map { ($1.id, $0) })
    }

    private func curve() -> Replay.Lapse {
        if let lapse { return lapse }
        let l = Replay.dayLapse(hours)
        lapse = l
        return l
    }

    private func stopClock() {
        clock?.cancel()
        clock = nil
    }

    /// Moves the playhead: cards it passes land (staggered when several land together), cards behind it fade away.
    private func seek(_ to: Double, instant: Bool) {
        let h = min(Replay.dayHours, max(0, to))
        let from = reached, next = Replay.reached(hours, at: h)
        if next > from {
            let staggerFrom = max(from, next - Self.maxLanding)
            for i in from..<next {
                cues[items[i].id] = instant || i < staggerFrom ? .instant : .land(delay: Double(i - staggerFrom) * Self.stagger)
            }
        } else if next < from {
            for i in next..<from { cues[items[i].id] = instant || from - i > Self.maxLeaving ? .instant : .leave }
        }
        hour = h
        if atEnd != (h >= Replay.dayHours) { atEnd = h >= Replay.dayHours }
        Daylight.shared.replayHour = h
        guard next != from else { return }
        reached = next
        // As each entry lands during play, its tooltip shows for a moment.
        tipTimer?.cancel()
        if playing && next > from {
            tip = .land
            tipTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                if !Task.isCancelled, self?.tip == .land { self?.tip = nil }
            }
        } else if tip == .land {
            tip = nil
        }
    }
}

extension AppModel {
    /// The day's cards as replay items, oldest first, each at the time it was captured (a stack at its first turn). A card
    /// captured on another day and filed here isn't replayed; it stays in place. Titles and moods follow §13.2.
    var replayItems: [DayReplay.Item] {
        items.compactMap { item -> DayReplay.Item? in
            guard let first = item.entries.min(by: { $0.capturedAt < $1.capturedAt }),
                  LocalDay.string(for: first.capturedAt) == day else { return nil }
            return DayReplay.Item(id: item.id, kind: item.top.kind, hour: Replay.hour(of: first.capturedAt),
                                  title: title(for: item.top), mood: item.entries.lazy.compactMap { self.mood(for: $0) }.first)
        }
        .enumerated().sorted { ($0.element.hour, $0.offset) < ($1.element.hour, $1.offset) }.map(\.element)
    }

    func startReplay(animated: Bool) {
        let items = replayItems
        guard !items.isEmpty else { return }
        openVoiceID = nil
        replay.start(day, items: items, animated: animated)
    }

    /// ⌘K: the day opens, its cards settle, then it replays.
    func requestReplay(_ target: String) {
        go(to: target)
        Task {
            let deadline = ContinuousClock.now + .seconds(6)
            while day != target || pane != .day, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(50)) }
            try? await Task.sleep(for: .milliseconds(450))
            guard day == target, pane == .day else { return }
            startReplay(animated: false)
        }
    }
}

/// What a card wears during a replay (useReplayCard): hidden until the playhead reaches it, then landing with opacity
/// 0→1, y 8→0 and scale 0.96→1 on the small spring; leaving is a 120 ms fade and the pose resets once it's gone. Reduce
/// Motion only fades, and a key sets it at once.
struct ReplayLanding: ViewModifier {
    let shown: Bool
    let cue: DayReplay.Cue?
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.96)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .animation(pose, value: shown)
            .opacity(shown ? 1 : 0)
            .animation(fade, value: shown)
    }

    private var pose: Animation? {
        switch cue {
        case .land(let delay)?: Motion.small.delay(delay)
        case .leave?: .linear(duration: 0.01).delay(0.12)
        default: nil
        }
    }

    private var fade: Animation? {
        switch cue {
        case .land(let delay)?: (reduceMotion ? Motion.easeOut(0.2) : Motion.small).delay(delay)
        case .leave?: Motion.easeOut(0.12)
        default: nil
        }
    }
}

/// Play, speed and where the replay is ("Today", "4 of 9"), then the track: the bar's replay layer (BottomLeftStatus.tsx).
struct ReplayBar: View {
    @Environment(AppModel.self) private var model
    let namespace: Namespace.ID

    var body: some View {
        let r = model.replay
        HStack(spacing: 2) {
            Button { r.toggle() } label: {
                Image(systemName: r.playing ? "pause.fill" : r.atEnd ? "arrow.counterclockwise" : "play.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Tok.onPrimary)
                    .offset(x: r.playing || r.atEnd ? 0 : 1)
                    .frame(width: 44, height: 44)
                    .background(Tok.sage, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(PressStyle(radius: 22))
            .accessibilityLabel(r.playing ? "Pause replay" : r.atEnd ? "Play the day again" : "Play the day")
            .help(r.playing ? "Pause  Space" : "Play  Space")
            Button { r.cycleRate() } label: {
                Text(r.rate == 2 ? "2×" : r.rate == 0.5 ? "½×" : "1×").font(Typo.mono(12)).monospacedDigit().foregroundStyle(Tok.ink2)
                    .frame(width: 44, height: 44).contentShape(.circle)
            }
            .buttonStyle(PressStyle(hoverFill: true, radius: 22))
            .accessibilityLabel("Replay speed: \(r.rate == 2 ? "double" : r.rate == 0.5 ? "half" : "normal")")
            .help("Change the replay speed")
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isToday ? "Today" : LocalDay.date(model.day)?.formatted(.dateTime.weekday(.abbreviated).day()) ?? "")
                    .monoCaps(11.5, tracking: 0.04).foregroundStyle(Tok.sageDark)
                Text("\(r.reached) of \(r.items.count)").font(Typo.mono(11, .regular)).monospacedDigit().foregroundStyle(Tok.ink3)
            }
            .fixedSize()
            .frame(minWidth: 56, alignment: .leading)
            .accessibilityHidden(true)
            ZStack {
                if r.active { ReplayTrack().matchedGeometryEffect(id: "replayTrack", in: namespace).transition(.opacity) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.leading, 12).padding(.trailing, 10)
        }
    }
}

/// The day's 24 hours as a track (DayReplay.tsx): a marker at each entry, the pin with its time, the mood filling in
/// behind it. Drag to scrub (it snaps to an entry within 6 pt); click a marker to go to its card.
private struct ReplayTrack: View {
    @Environment(AppModel.self) private var model
    /// Where the current press started, while it's down.
    @State private var press: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let r = model.replay
            let w = geo.size.width
            let xs = r.items.map { $0.hour / Replay.dayHours * w }
            let groups = Replay.clusters(xs, gap: 22)
            let x = min(max(r.hour / Replay.dayHours, 0), 1) * w
            ZStack(alignment: .topLeading) {
                playhead(x: x, w: w)
                ReplayMarkers(items: r.items, xs: xs, groups: groups, reached: r.reached).equatable()
            }
            .frame(width: w, height: geo.size.height, alignment: .topLeading)
            .overlay(alignment: .topLeading) { tip(xs, groups) }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if press == nil {
                        press = v.startLocation.x
                        r.tip = nil
                    }
                    let i = nearest(v.location.x, xs, within: 6)
                    r.scrub(to: i.map { r.items[$0].hour } ?? min(max(v.location.x, 0), w) / max(w, 1) * Replay.dayHours)
                }
                .onEnded { v in
                    let start = press ?? v.startLocation.x
                    press = nil
                    // A click on or near a marker, not a drag, goes to that entry and takes the canvas to its card.
                    guard abs(v.location.x - start) < 4, let i = nearest(start, xs, within: 22) else { return }
                    r.scrub(to: r.items[i].hour)
                    model.camera = .focus(r.items[i].id, UUID())
                })
            .onContinuousHover { phase in
                guard press == nil else { return }
                let g: Int? = switch phase {
                case .active(let p): groupAt(p.x, xs, groups)
                case .ended: nil
                }
                if let g { if r.tip != .hover(g) { r.tip = .hover(g) } } else if r.tip?.hovering == true { r.tip = nil }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Time of day")
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { model.replay.step($0 == .increment ? 1 : -1) }
    }

    /// What moves every frame: the played rail with the mood behind it, the hour labels making way, the pin and its time.
    @ViewBuilder private func playhead(x: CGFloat, w: CGFloat) -> some View {
        let r = model.replay
        let marks = r.items.compactMap { item in item.mood.map { (hour: item.hour, label: $0) } }
        Capsule().fill(Tok.ink.opacity(0.1))
            .overlay(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Tok.sage
                    ForEach(Replay.moodSegments(marks), id: \.from) { s in
                        MoodPalette.color(s.label).frame(width: (s.to - s.from) / Replay.dayHours * w).offset(x: s.from / Replay.dayHours * w)
                    }
                }
                .frame(width: w, alignment: .leading)
                .mask(alignment: .leading) { Rectangle().frame(width: x) }
            }
            .clipShape(.capsule)
            .frame(width: w, height: 4)
            .offset(y: 28)
        ForEach(w >= 360 ? [3, 6, 9, 12, 15, 18, 21] : [6, 12, 18], id: \.self) { h in
            let lx = Double(h) / Replay.dayHours * w
            let clear = abs(lx - x) < 48
            Text(Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: .now)?.formatted(.dateTime.hour()) ?? "")
                .font(Typo.mono(10, .regular)).foregroundStyle(Tok.ink3)
                .fixedSize()
                .position(x: lx, y: 44)
                .opacity(clear ? 0 : 1)
                .animation(Motion.easeOut(0.16), value: clear)
        }
        Capsule().fill(Tok.ink).frame(width: 2, height: 34).offset(x: x - 1, y: 2)
        Text(clock(r.hour)).font(Typo.mono(10.5)).monospacedDigit().foregroundStyle(Tok.paper)
            .padding(.horizontal, 6).frame(height: 16)
            .background(Tok.ink, in: .capsule)
            .fixedSize()
            .position(x: min(max(x, 31), max(31, w - 31)), y: 44)
    }

    /// Above the bar, centred on its marker: the entries of the cluster under the pointer, or around the current one.
    @ViewBuilder private func tip(_ xs: [Double], _ groups: [ClosedRange<Int>]) -> some View {
        let r = model.replay
        let current = r.reached - 1
        let group: ClosedRange<Int>? = switch r.tip {
        case .hover(let i)?: groups.indices.contains(i) ? groups[i] : nil
        case .key?, .land?: groups.first { $0.contains(current) }
        case nil: nil
        }
        if let g = group {
            // A step or a landing marks the current entry in its cluster, and a long cluster lists the rows around it.
            let mark = r.tip?.hovering == false && g.count > 1 ? current : -1
            let first = max(g.lowerBound, min(mark - 1, g.upperBound - 3))
            let rows = Array(r.items[first..<min(first + 4, g.upperBound + 1)].enumerated())
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.element.id) { i, item in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.title).font(Typo.ui(13, .medium)).foregroundStyle(Tok.ink).lineLimit(1).frame(height: 18)
                        Text("\(Text(clock(item.hour)).font(Typo.mono(11, .regular))) · \(Text(item.kind.noun).foregroundStyle(item.kind.ink))")
                            .font(Typo.ui(11)).foregroundStyle(Tok.ink3).lineLimit(1).frame(height: 14)
                    }
                    .padding(.vertical, 2)
                    .padding(.leading, mark >= 0 ? 6 : 0)
                    .overlay(alignment: .leading) {
                        if mark >= 0 { Rectangle().fill(first + i == mark ? Tok.ink : .clear).frame(width: 2) }
                    }
                }
                if g.count > rows.count {
                    Text("+\(g.count - rows.count) more").font(Typo.ui(11)).foregroundStyle(Tok.ink3).padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassPanel(radius: Radius.card)
            // ponytail: not clamped to the window; the bar is centred and wide enough that a 240 pt tip stays on screen.
            .frame(width: 240, height: 200, alignment: .bottom)
            // 8 pt above the bar, whose top is 6 pt above the track.
            .offset(x: (xs[g.lowerBound] + xs[g.upperBound]) / 2 - 120, y: -214)
            .allowsHitTesting(false)
        }
    }

    private var valueText: String {
        let r = model.replay
        let count = "\(r.reached) of \(r.items.count)"
        if r.playing { return "Playing, \(count)" }
        let current = r.reached > 0 ? r.items[r.reached - 1] : nil
        return [clock(r.hour), current.map { "\($0.kind.noun), \($0.title)" }, count].compactMap { $0 }.joined(separator: ", ")
    }

    /// A time of the replayed day on this Mac's clock, e.g. "3:12 PM".
    private func clock(_ hour: Double) -> String {
        let m = min(Int((hour * 60).rounded()), 24 * 60 - 1)
        let base = LocalDay.date(model.day) ?? .now
        return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: base)?.formatted(date: .omitted, time: .shortened) ?? ""
    }

    private func nearest(_ x: CGFloat, _ xs: [Double], within reach: CGFloat) -> Int? {
        var best: Int?, distance = reach
        for (i, v) in xs.enumerated() where abs(v - x) <= distance {
            best = i
            distance = abs(v - x)
        }
        return best
    }

    private func groupAt(_ x: CGFloat, _ xs: [Double], _ groups: [ClosedRange<Int>]) -> Int? {
        groups.firstIndex { g in
            let half = g.count == 1 ? 10 : max(26, xs[g.upperBound] - xs[g.lowerBound] + 20) / 2
            return abs(x - (xs[g.lowerBound] + xs[g.upperBound]) / 2) <= half + 2
        }
    }
}

/// The entries as 20 pt discs, filled once their card is on the canvas; close ones merge into a count. Redraws only when
/// an entry lands or leaves, or the track resizes.
private struct ReplayMarkers: View, Equatable {
    let items: [DayReplay.Item]
    let xs: [Double]
    let groups: [ClosedRange<Int>]
    let reached: Int

    var body: some View {
        ForEach(groups, id: \.lowerBound) { g in
            let a = g.lowerBound, b = g.upperBound
            let current = g.contains(reached - 1)
            if a == b {
                let item = items[a], landed = a < reached
                Image(systemName: item.kind.symbol).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(landed ? Tok.paper : item.kind.ink)
                    .frame(width: 20, height: 20)
                    .background(landed ? item.kind.tint : Tok.paper, in: .circle)
                    .overlay { if !landed { Circle().strokeBorder(item.kind.tint.opacity(0.6), lineWidth: 1) } }
                    .overlay { if current { ring(Circle()) } }
                    .offset(x: xs[a] - 10, y: 2)
            } else {
                let width = max(26, xs[b] - xs[a] + 20), landed = b < reached
                Text("\(g.count)").font(Typo.mono(10.5)).monospacedDigit()
                    .foregroundStyle(landed ? Tok.paper : Tok.ink2)
                    .frame(width: width, height: 20)
                    .background(landed ? Tok.ink : Tok.paper, in: .capsule)
                    .overlay { if !landed { Capsule().strokeBorder(Tok.borderStrong, lineWidth: 1) } }
                    .overlay { if current { ring(Capsule()) } }
                    .offset(x: (xs[a] + xs[b]) / 2 - width / 2, y: 2)
            }
        }
    }

    /// ring-2 ink with a 2 pt paper offset: the entry the playhead is on.
    private func ring(_ shape: some InsettableShape) -> some View {
        ZStack {
            shape.strokeBorder(Tok.paper, lineWidth: 2).padding(-2)
            shape.strokeBorder(Tok.ink, lineWidth: 2).padding(-4)
        }
    }
}

private extension EntryKind {
    var ink: Color {
        switch self {
        case .moment: Tok.momentInk
        case .voice: Tok.echoInk
        case .still: Tok.stillInk
        case .reflection: Tok.reflectionInk
        case .music: Tok.music
        }
    }
}
