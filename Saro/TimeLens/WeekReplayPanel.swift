import SaroKit
import SwiftUI

/// Plays the week on screen (WeekReplay.tsx): the days light up in order, each entry arrives at its time in its kind's
/// colour, and the week's mood line draws in behind the playhead; the lit day's tile in the grid wears a ring of sage
/// light. 1.6 s a day with entries, a quarter of that for an empty one. A day chosen here opens in its own replay.
struct WeekReplayPanel: View {
    let lens: LensState
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var at: Double = 0
    @State private var playing = false
    @State private var startedAt: Date?
    @State private var startT: Double = 0

    private var days: [Int] { Array(lens.cal.unit(lens.focus, .week)) }
    private var span: Double { Double(days.count) * Replay.dayHours }
    private var lapse: Replay.Lapse { Replay.weekLapse(days.map { lens.summaries[$0]?.total ?? 0 }) }

    /// Each card of the week at its hour from the week's start.
    private var entries: [(kind: EntryKind, at: Double, mood: Mood?)] {
        let keys = days.map { lens.cal.days[$0].key }
        return lens.weekEntries.compactMap { e in
            keys.firstIndex(of: e.day).map { (e.kind, Double($0) * Replay.dayHours + Replay.hour(of: e.capturedAt), e.mood) }
        }
    }

    private var lit: Int? { playing || (at > 0 && at < span) ? min(days.count - 1, Int(at / Replay.dayHours)) : nil }

    var body: some View {
        ZStack {
            if let lit, let r = LensMath.tileRect(lens.cal, lens.blocks, days[lit]) {
                RoundedRectangle(cornerRadius: min(14, max(1.5, r.width * 0.085)) + 2)
                    .strokeBorder(Tok.sage.opacity(0.7), lineWidth: 2)
                    .shadow(color: Tok.sage.opacity(0.35), radius: 24)
                    .frame(width: r.width + 4, height: r.height + 4)
                    .position(x: r.midX, y: r.midY)
                    .animation(reduceMotion ? nil : Motion.easeOut(0.3), value: lit)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            panel
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 56)
        }
        .background { TimelineView(.animation(paused: !playing)) { t in Color.clear.onChange(of: t.date) { _, d in advance(d) } } }
        .onChange(of: days.first) { pause(); at = 0 }
    }

    private var panel: some View {
        HStack(spacing: 8) {
            Button { playing ? pause() : play() } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 14)).foregroundStyle(.white)
                    .offset(x: playing ? 0 : 1)
                    .frame(width: 40, height: 40)
                    .background(Tok.sage, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(PressStyle(radius: 20, scale: 0.95))
            .accessibilityLabel(playing ? "Pause the week" : "Play the week")
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(Array(days.enumerated()), id: \.element) { i, day in column(i, day) }
                }
                GeometryReader { g in
                    let w = g.size.width
                    // Each entry arrives at its time.
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                        let shown = e.at <= at
                        Circle().fill(e.kind.tint).frame(width: 6, height: 6)
                            .scaleEffect(shown || reduceMotion ? 1 : 0.5)
                            .opacity(shown ? 1 : 0)
                            .animation(Motion.easeOut(0.2), value: shown)
                            .position(x: w * e.at / span, y: 30)
                    }
                    // The mood line, drawn up to the playhead, under a 2 pt playhead.
                    Capsule().fill(Tok.ink.opacity(0.07)).frame(width: w - 8, height: 3).position(x: w / 2, y: g.size.height - 9.5)
                    Canvas { ctx, size in
                        for s in moodSegments() {
                            let x0 = 4 + (size.width - 8) * s.from / span, x1 = 4 + (size.width - 8) * min(s.to, at) / span
                            if x1 > x0 { ctx.fill(Path(CGRect(x: x0, y: size.height - 11, width: x1 - x0, height: 3)), with: .color(MoodPalette.color(s.label))) }
                        }
                    }
                    .allowsHitTesting(false)
                    if playing || (at > 0 && at < span) {
                        Capsule().fill(Tok.ink.opacity(0.7)).frame(width: 2, height: 32).position(x: w * at / span, y: 36)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .frame(height: 56)
        }
        .padding(.horizontal, 10)
        .frame(height: 72)
        .frame(maxWidth: 640)
        .glassPanel(radius: Radius.sheet)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Week replay")
    }

    private func column(_ i: Int, _ day: Int) -> some View {
        let state = lit.map { i < $0 ? 1 : i == $0 ? 2 : 0 } ?? (at >= span ? 1 : 0)
        let date = lens.cal.days[day].date
        return Button {
            pause()
            model.requestReplay(lens.cal.days[day].key)
            lens.pick(day, how: Motion.byKey ? .instant : .animated)
        } label: {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased() + " \(lens.cal.days[day].dayOfMonth)")
                .font(Typo.mono(10.5)).tracking(0.42).monospacedDigit()
                .foregroundStyle(state == 2 ? Tok.ink : state == 1 ? Tok.ink2 : Tok.ink3)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Tok.ink.opacity(state == 2 ? 0.07 : 0), in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
                .animation(Motion.easeOut(0.2), value: state)
        }
        .buttonStyle(PressStyle(hoverFill: true, radius: 8))
        .accessibilityLabel("Replay \(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
    }

    /// Each entry's mood from its time to the next mood, the last to the day's end; a day without any takes its reading's.
    private func moodSegments() -> [(from: Double, to: Double, label: String)] {
        days.enumerated().flatMap { i, day -> [(from: Double, to: Double, label: String)] in
            let base = Double(i) * Replay.dayHours
            let marks = entries.filter { Int($0.at / Replay.dayHours) == i }.compactMap { e in e.mood.map { (hour: e.at - base, label: $0.rawValue) } }
            if marks.isEmpty, let mood = lens.summaries[day]?.mood { return [(base, base + Replay.dayHours, mood.rawValue)] }
            return Replay.moodSegments(marks).map { (base + $0.from, base + $0.to, $0.label) }
        }
    }

    private func play() {
        startT = at >= span - 1e-6 ? 0 : lapse.time(at: at)
        startedAt = .now
        playing = true
    }

    private func pause() {
        guard playing else { return }
        playing = false
        announce()
    }

    private func advance(_ now: Date) {
        guard playing, let startedAt else { return }
        let t = startT + now.timeIntervalSince(startedAt)
        at = min(span, lapse.hour(at: t))
        if t >= lapse.length {
            at = span
            pause()
        }
    }

    private func announce() {
        let reached = entries.filter { $0.at <= at }.count
        let text = at >= span ? "Played the week: \(entries.count) \(entries.count == 1 ? "entry" : "entries")." : "\(reached) of \(entries.count) entries."
        AccessibilityNotification.Announcement(text).post()
    }
}
