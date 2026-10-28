import AppKit
import SaroKit
import SwiftUI
import UserNotifications

/// "Your first week", Seven Sunrises (FirstWeekScreen.tsx): the window is the sky at the ritual hour and the week stands
/// on one horizon, a light under each numeral, brighter day by day to the letter's. The ritual time and the days are
/// the reminder's; the reminder is shown word for word before macOS is asked.
struct FirstWeekView: View {
    @Environment(AppModel.self) private var model
    @Environment(OnboardingFlow.self) private var flow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    private let prefs = PrefsStore.shared

    /// The entrance plays once per pass through About you; coming back to it lands at rest.
    @MainActor private static var enteredFor: String?

    @State private var start = Date.now
    @State private var suggestion = FirstWeek.RitualSuggestion(minutes: FirstWeek.defaultMinutes, source: .default)
    @State private var minutes = FirstWeek.defaultMinutes
    @State private var previous = FirstWeek.defaultMinutes
    @State private var weekdays = Prefs.everyDay
    @State private var ready = false
    /// The entrance's one clock; nil once everything is at rest.
    @State private var entrance: Date?
    @State private var still = false
    @State private var stillShown = false
    /// A sweep of the ground from one hour to another after the time changes.
    @State private var sweep: (from: Double, to: Double, at: Date)?
    @State private var focusDay = 0
    @State private var pressed = -1
    @State private var announcement = ""
    @State private var monitor: Any?
    /// The palette's change to the ritual hour, due mid-sweep; leaving cancels it, so it can't land after the clock is back.
    @State private var palette: Task<Void, Never>?
    /// While the time is being typed, Return is the pill's.
    @State private var editingTime = false
    @FocusState private var weekFocused: Bool
    @AccessibilityFocusState private var titleFocused: Bool

    private static let hour12 = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? true
    private var step: Double { WeekLight.stepWide }
    private var hour: Double { Double(minutes) / 60 }
    private var startDay: Int { Calendar.current.component(.weekday, from: start) - 1 }
    private var dates: [Date] { (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: start)! } }
    private var on: [Bool] { FirstWeek.weekOn(weekdays, startDay: startDay) }
    private var goal: String? { flow.keptPicks.first { $0.kind == .goal }?.text }
    private var plan: [FirstWeek.DayPlan] { FirstWeek.plan(on: on, name: flow.keptName, goal: goal) }
    private var dayNames: [String] { dates.map { $0.formatted(.dateTime.weekday(.wide)) } }
    private var day0: String { FirstWeek.hourCopy(Sky.localHour(start)).day0 }

    var body: some View {
        TimelineView(.animation(paused: entrance == nil && sweep == nil)) { context in
            let t = entrance.map { context.date.timeIntervalSince($0) } ?? .infinity
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    LitGround(hour: groundHour(t, now: context.date)).ignoresSafeArea()
                    if ready {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                header(t)
                                week(t, size: geo.size)
                                rest(t).padding(.top, 28)
                            }
                            .padding(.horizontal, 48)
                            .padding(.top, 52)
                            .padding(.bottom, 24)
                            .frame(maxWidth: 1400)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollIndicators(.never)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .onChange(of: t >= WeekLight.entranceEnd(step: step)) { _, done in if done { land() } }
            .onChange(of: sweep.map { context.date.timeIntervalSince($0.at) >= 0.6 } ?? false) { _, done in if done { sweep = nil } }
        }
        .opacity(still && !stillShown ? 0 : 1)
        .animation(Motion.easeOut(0.2), value: stillShown)
        .background {
            Button("Back to the last time") { restore() }.keyboardShortcut(.cancelAction).opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
        .announces(announcement)
        .task { begin() }
        .onDisappear(perform: leave)
    }

    // MARK: Ground and clock

    /// The hour the ground shows: sweeping from now to the ritual hour as the entrance begins, then to a new time.
    private func groundHour(_ t: Double, now: Date) -> Double {
        if let sweep {
            let p = WeekLight.easeInOut(min(1, now.timeIntervalSince(sweep.at) / 0.6))
            return sweep.from + FirstWeek.hourDelta(from: sweep.from, to: sweep.to) * p
        }
        guard t.isFinite else { return hour }
        let from = Sky.localHour(start)
        return from + FirstWeek.hourDelta(from: from, to: hour) * WeekLight.easeInOut(min(1, t / WeekLight.sweep))
    }

    private func begin() {
        let picks = flow.keptPicks
        suggestion = FirstWeek.ritualFromSpans(picks)
        // A time they set stands until their answers suggest a different one (Replay onboarding with a new answer).
        let saved = prefs.weekStartedOn != nil
        let keep = saved && (prefs.ritualSuggested == suggestion.minutes || suggestion.source == .default)
        minutes = keep ? prefs.ritualMinutes : suggestion.minutes
        previous = minutes
        weekdays = saved ? prefs.ritualWeekdays : Prefs.everyDay
        let moved = prefs.ritualMinutes != minutes || prefs.ritualWeekdays != weekdays
        prefs.ritualMinutes = minutes
        prefs.ritualWeekdays = weekdays
        prefs.ritualSource = keep && minutes != suggestion.minutes ? .user : suggestion.source
        prefs.ritualSuggested = suggestion.minutes
        prefs.weekStartedOn = LocalDay.today()
        // A replay whose answers suggest a new time moves reminders already on to it.
        if moved { reschedule() }
        let fresh = Self.enteredFor != flow.starter.id
        Self.enteredFor = flow.starter.id
        still = !fresh || reduceMotion || reduceTransparency
        ready = true
        titleFocused = true
        if still {
            Daylight.shared.replayHour = hour
            stillShown = true
            return
        }
        entrance = .now
        // The palette changes where the sweep crosses into the other half of the day, once, mid-sweep.
        setPalette(hour, after: WeekLight.sweep / 2)
        // The first click or key lands everything at rest.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
            MainActor.assumeIsolated { land() }
            return event
        }
    }

    private func land() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        entrance = nil
        Daylight.shared.replayHour = hour
    }

    /// Leaving: the ground and the palette go back to the real clock.
    private func leave() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        palette?.cancel()
        Daylight.shared.replayHour = nil
    }

    private func setPalette(_ hour: Double, after seconds: Double) {
        palette?.cancel()
        palette = Task {
            guard (try? await Task.sleep(for: .seconds(seconds))) != nil else { return }
            Daylight.shared.replayHour = hour
        }
    }

    /// 0–1 from `at` over `duration`, eased; 1 at rest.
    private func progress(_ t: Double, at: Double, duration: Double, curve: @Sendable (Double) -> Double = WeekLight.easeOut) -> Double {
        curve(min(1, max(0, (t - at) / duration)))
    }

    // MARK: Header

    private func header(_ t: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your first week · shown at \(FirstWeek.clockLabel(minutes, hour12: Self.hour12))")
                .monoCaps(10.5).foregroundStyle(Tok.ink2)
                .entering(progress(t, at: 0, duration: 0.5), y: 8)
            Text("Here’s your first week.")
                .font(Typo.serif(56)).tracking(-1.7).foregroundStyle(Tok.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
                .padding(.top, 14)
                .entering(progress(t, at: 0.05, duration: 0.5), y: 8)
            Text("A minute most \(FirstWeek.hourCopy(hour).part.rawValue.lowercased()). By \(dayNames[6]) I’ll have something real to tell you.")
                .font(Typo.serif(20, italic: true)).foregroundStyle(Tok.ink2)
                .frame(maxWidth: 580, alignment: .leading)
                .padding(.top, 12)
                .entering(progress(t, at: 0.1, duration: 0.5), y: 8)
        }
    }

    // MARK: The week

    private func week(_ t: Double, size: CGSize) -> some View {
        let width = min(size.width, 1400) - 96 - 56
        let column = width / 7
        let numH = column * 0.6
        let sky = max(36, min(220, size.height * 0.5 - 196 - numH))
        let ignition = WeekLight.ignition(t, step: step)
        let plan = plan
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                WeekSky(levels: plan.map { WeekLight.dayLevel($0.index, on: $0.on) }, ignition: ignition, lights: WeekLight.dayLights(hour: hour),
                        dark: scheme == .dark, column: column, sky: sky, numH: numH)
                    .frame(width: width + 188, height: sky + numH)
                    .offset(x: -48)
                    .animation(Motion.small, value: weekdays)
                HStack(spacing: 0) {
                    ForEach(plan, id: \.index) { day in
                        WeekDay(day: day, date: dates[day.index], day0: day0, column: column, sky: sky, numH: numH,
                                silhouette: scheme == .dark && day.on, focused: weekFocused && focusDay == day.index, pressed: pressed == day.index,
                                rise: progress(t, at: WeekLight.dayAt(day.index, step: step) - 0.05, duration: 0.6),
                                flash: flash(t, day.index), label: progress(t, at: WeekLight.dayAt(day.index, step: step) + 0.05, duration: 0.25),
                                note: progress(t, at: WeekLight.dayAt(day.index, step: step) + 0.1, duration: 0.35),
                                accessibility: dayLabel(day)) { toggle(day.index) } onPress: { pressed = $0 ? day.index : -1 }
                    }
                }
                .frame(width: width)
                // The one horizon, edge to edge, drawn out from the centre.
                Rectangle().fill(scheme == .dark ? Tok.line : Tok.borderStrong)
                    .frame(width: size.width, height: 1)
                    .scaleEffect(x: ignition.horizon, anchor: .center)
                    .offset(x: -48, y: sky + numH)
                    .accessibilityHidden(true)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($weekFocused)
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end, .space]) { press in
                switch press.key {
                case .home: focusDay = 0
                case .end: focusDay = 6
                case .rightArrow, .downArrow: focusDay = min(6, focusDay + 1)
                case .leftArrow, .upArrow: focusDay = max(0, focusDay - 1)
                default: toggle(focusDay)
                }
                return .handled
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Your first week")
        }
        .padding(.top, 8)
    }

    /// The foot of a numeral catching the flash as its light ignites, then cooling (0 → 0.85 → 0 over 0.78 s).
    private func flash(_ t: Double, _ i: Int) -> Double {
        let dt = t - WeekLight.dayAt(i, step: step)
        guard dt > 0, dt < 0.78 else { return 0 }
        return dt < 0.08 ? 0.85 * dt / 0.08 : 0.85 * (1 - WeekLight.easeOut((dt - 0.08) / 0.7))
    }

    private func dayLabel(_ day: FirstWeek.DayPlan) -> String {
        let date = dates[day.index].formatted(.dateTime.weekday(.wide).day().month(.wide))
        let what = day.milestone.map { " \($0.title)\($0.title.hasSuffix(",") ? "" : ".") \($0.note)" } ?? ""
        return "\(date)\(day.index == 0 ? ", today" : ""), reminder \(day.on ? "on" : "off").\(what)"
    }

    private func toggle(_ index: Int) {
        focusDay = index
        guard index > 0 else {
            announcement = ""
            announcement = "Today stays on. It’s your baseline."
            return
        }
        let before = plan
        withAnimation(Motion.small) { weekdays = FirstWeek.toggleWeekday(weekdays, startDay: startDay, index: index) }
        prefs.ritualWeekdays = weekdays
        announcement = FirstWeek.weekChange(before: before, after: plan, index: index, dayNames: dayNames)
        reschedule()
    }

    // MARK: The ritual, the reminder and the way on

    private func rest(_ t: Double) -> some View {
        let restAt = WeekLight.restAt(step: step)
        return HStack(alignment: .top, spacing: 40) {
            ritual.frame(maxWidth: .infinity, alignment: .leading)
                .entering(progress(t, at: restAt, duration: 0.35), y: 8)
            VStack(alignment: .leading, spacing: 10) {
                Text("Exactly what you’ll see").monoCaps(10.5).foregroundStyle(Tok.ink2)
                NotificationPreview(time: Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: start)!
                    .formatted(.dateTime.hour().minute()))
            }
            .frame(width: 340, alignment: .leading)
            .entering(progress(t, at: restAt + 0.04, duration: 0.35), y: 8)
            VStack(alignment: .leading, spacing: 22) {
                ReminderAsk(announce: { announcement = $0 })
                    .entering(progress(t, at: restAt + 0.08, duration: 0.35), y: 8)
                HStack(spacing: 6) {
                    Button { flow.go(.findLight, nav: pressedByKey() ? .key : .pointer, model: model) } label: {
                        Text("Start \(day0 == "TONIGHT" ? "tonight’s" : "today’s") moment").font(Typo.ui(14, .semibold)).frame(height: 44)
                    }
                    .buttonStyle(PrimaryStyle())
                    .keyboardShortcut(.defaultAction)
                    Button { Task { await flow.finish(nil, model: model) } } label: {
                        Text("Later").font(Typo.ui(14, .medium)).foregroundStyle(Tok.ink2).padding(.horizontal, 12).frame(height: 44).contentShape(.rect)
                    }
                    .buttonStyle(PressStyle(hoverFill: true, radius: Radius.control, scale: 0.97))
                }
                .entering(progress(t, at: restAt + 0.12, duration: 0.35), y: 8)
            }
            .frame(width: 300, alignment: .leading)
        }
    }

    private var ritual: some View {
        let count = on.filter { $0 }.count
        return VStack(alignment: .leading, spacing: 0) {
            Text("Your ritual").monoCaps(10.5).foregroundStyle(Tok.ink2).accessibilityAddTraits(.isHeader)
            HStack(alignment: .center, spacing: 10) {
                Text("\(FirstWeek.hourCopy(hour).part.rawValue), around").font(Typo.serif(28)).foregroundStyle(Tok.ink)
                RitualTimePill(minutes: minutes, hour12: Self.hour12, onCommit: { commit($0, announce: FirstWeek.timeChange($0, hour12: Self.hour12)) },
                               onRestore: restore)
            }
            .padding(.top, 8)
            Group {
                if minutes != suggestion.minutes {
                    Text("Yours now. Change it any time.")
                } else if let span = suggestion.span {
                    Text("From what you told me: \(Text(marked(span.text)))")
                } else {
                    Text("A starting point. Change it any time.")
                }
            }
            .font(Typo.ui(13)).foregroundStyle(Tok.ink2).padding(.top, 10)
            Text("\(count == 7 ? "Every day this week." : "\(count) of 7 days.") Choose a day to skip it.")
                .font(Typo.ui(13)).foregroundStyle(Tok.ink2).padding(.top, 4)
                .contentTransition(.numericText())
                .animation(Motion.small, value: count)
        }
    }

    private func marked(_ text: String) -> AttributedString {
        var s = AttributedString(" \(text) ")
        s.foregroundColor = Tok.ink
        s.backgroundColor = Tok.voiceBright.opacity(0.25)
        return s
    }

    private func commit(_ m: Int, announce: String) {
        guard m != minutes else { return }
        previous = minutes
        sweep = (hour, Double(m) / 60, .now)
        minutes = m
        prefs.ritualMinutes = m
        prefs.ritualSource = m == suggestion.minutes ? suggestion.source : .user
        announcement = announce
        reschedule()
        setPalette(Double(m) / 60, after: 0.3)
    }

    /// Esc puts the previous time back.
    private func restore() {
        guard previous != minutes else { return }
        commit(previous, announce: "Back to \(FirstWeek.clockLabel(previous, hour12: Self.hour12)).")
    }

    private func reschedule() {
        guard prefs.reminderOn else { return }
        Task { await Reminders.shared.scheduleRitual() }
    }
}

private extension View {
    /// An element of the entrance at `p` (0 hidden, 1 at rest): rising `y` as it fades in.
    func entering(_ p: Double, y: CGFloat) -> some View { opacity(p).offset(y: (1 - p) * y) }
}

/// One day: the whole column is its reminder toggle. The numeral stands on the horizon over its light, then its label
/// and its milestone. Skipped, the numeral sinks 30% and fades back.
private struct WeekDay: View {
    let day: FirstWeek.DayPlan
    let date: Date
    let day0: String
    let column: CGFloat, sky: CGFloat, numH: CGFloat
    let silhouette: Bool
    let focused: Bool
    let pressed: Bool
    let rise: Double, flash: Double, label: Double, note: Double
    let accessibility: String
    let toggle: () -> Void
    let onPress: (Bool) -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hover = false

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 0) {
                Color.clear.frame(height: sky)
                numeral
                    .frame(width: column, height: numH, alignment: .bottom)
                    .clipped()
                labelText
                    .padding(.top, 14)
                    .opacity(label)
                milestone
                    .frame(width: max(0, column - 16))
                    .padding(.top, 8)
                    .opacity(note)
                    .offset(y: (1 - note) * 6)
            }
            .frame(width: column)
            .padding(.bottom, 8)
            .background(alignment: .top) {
                RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Tok.sage, lineWidth: 2)
                    .frame(height: numH + 60).offset(y: sky - 6)
                    .opacity(focused ? 1 : 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(DayPress(onPress: onPress))
        .focusable(false)
        .onHover { hover = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(day.on ? "On" : "Off")
    }

    private var numeral: some View {
        Text(date.formatted(.dateTime.day()))
            .font(Typo.serif(column * 0.77, .light))
            .tracking(-column * 0.77 * 0.05)
            .monospacedDigit()
            .foregroundStyle(silhouette ? Tok.bg : Tok.ink)
            .opacity(day.on ? 1 : scheme == .dark ? 0.9 : 0.7)
            .overlay {
                // The foot catches the flash as the light ignites, then cools.
                Text(date.formatted(.dateTime.day()))
                    .font(Typo.serif(column * 0.77, .light))
                    .tracking(-column * 0.77 * 0.05)
                    .monospacedDigit()
                    .foregroundStyle(scheme == .dark ? Color(0xFFF6EC, 0xFFF6EC) : Tok.voiceBright)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0.38), .init(color: .black, location: 0.5)], startPoint: .top, endPoint: .bottom))
                    .opacity(flash)
            }
            .scaleEffect(pressed ? 0.96 : 1, anchor: .bottom)
            .animation(Motion.press, value: pressed)
            .alignmentGuide(.bottom) { $0[.lastTextBaseline] }
            .offset(y: numH * ((1 - rise) * 1.05 + (day.on ? 0 : 0.3) - (hover && day.index > 0 ? 0.04 : 0)))
            .animation(Motion.small, value: day.on)
            .animation(Motion.easeOut(0.24), value: hover)
    }

    private var labelText: some View {
        let short = date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
        return Text("\(short)\(day.index == 0 ? Text(" · \(day0)").fontWeight(.semibold) : Text(""))\(day.on ? "" : " · no reminder")")
            .font(Typo.mono(11))
            .tracking(0.9)
            .foregroundStyle(Tok.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var milestone: some View {
        ZStack(alignment: .top) {
            if let m = day.milestone {
                VStack(spacing: 4) {
                    if m.kind == .letter {
                        Text(m.title).font(Typo.serif(24, italic: true)).foregroundStyle(Tok.voice)
                    } else {
                        Text(m.title).font(Typo.serif(20)).foregroundStyle(Tok.ink)
                    }
                    Text(m.note).font(Typo.ui(13)).foregroundStyle(Tok.ink2)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .id("\(m.kind.rawValue)|\(m.note)")
                .transition(.opacity.animation(Motion.easeOut(0.16)))
            } else {
                Circle().fill(Tok.ink4).frame(width: 4, height: 4).padding(.top, 6)
            }
        }
        .frame(minHeight: 70, alignment: .top)
    }
}

private struct DayPress: ButtonStyle {
    let onPress: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.onChange(of: configuration.isPressed) { _, p in onPress(p) }
    }
}

/// The week's light: each day's sun risen behind its numeral, a bloom along the horizon, and an eighth sun cresting
/// past the end of the week. Every day's light is its own colour, from the hour's light round to Saro's voice.
private struct WeekSky: View {
    let levels: [WeekLight.DayLevel]
    let ignition: WeekLight.Ignition
    let lights: [WeekLight.DayLight]
    let dark: Bool
    let column: CGFloat, sky: CGFloat, numH: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let horizon = sky + numH
            // The week starts 48 pt in, so the first day's light can spread past it.
            ctx.translateBy(x: 48, y: 0)
            ctx.clip(to: Path(CGRect(x: -48, y: 0, width: size.width, height: horizon + 2)))
            let voice = Color(red: 242 / 255, green: 160 / 255, blue: 120 / 255)
            // The bloom lies along the horizon, building toward the letter.
            let bloomW = column * 7.4, bloomH = numH * 1.3
            ctx.drawLayer { c in
                c.translateBy(x: column * 3.5, y: horizon)
                c.scaleBy(x: bloomW / bloomH, y: 1)
                c.fill(Path(ellipseIn: CGRect(x: -bloomH, y: -bloomH, width: bloomH * 2, height: bloomH * 2)),
                       with: .radialGradient(Gradient(colors: [voice.opacity((dark ? 0.22 : 0.14) * ignition.horizon * ignition.surge), voice.opacity(0)]),
                                             center: .zero, startRadius: 0, endRadius: bloomH))
            }
            for i in 0..<7 {
                let level = levels[i], d = ignition.days[i]
                let rgb = dark ? lights[i].night : lights[i].day
                let color = Color(red: Double(rgb.x) / 255, green: Double(rgb.y) / 255, blue: Double(rgb.z) / 255)
                let strength = min(1.4, level.power * d.glow * ignition.surge) * (dark ? 1 : 0.5)
                guard strength > 0.001 else { continue }
                let rx = column * 0.78 * d.size * level.size, ry = numH * 1.0 * d.size * level.size
                let cx = column * (Double(i) + 0.5), cy = horizon - numH * 0.45 + level.sink
                ctx.drawLayer { c in
                    c.translateBy(x: cx, y: cy)
                    c.scaleBy(x: rx / ry, y: 1)
                    c.fill(Path(ellipseIn: CGRect(x: -ry, y: -ry, width: ry * 2, height: ry * 2)),
                           with: .radialGradient(Gradient(stops: [.init(color: color.opacity(min(1, strength)), location: 0),
                                                                  .init(color: color.opacity(min(1, strength) * 0.8), location: 0.6),
                                                                  .init(color: color.opacity(0), location: 1)]),
                                                 center: .zero, startRadius: 0, endRadius: ry))
                }
                // The white-hot core as the day ignites.
                let core = max(0, d.core - 1)
                if core > 0 {
                    let r = column * 0.16
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 1.6, y: horizon - r, width: r * 3.2, height: r * 2)),
                             with: .radialGradient(Gradient(colors: [Color.white.opacity(min(1, core * 1.2)), color.opacity(0)]),
                                                   center: CGPoint(x: cx, y: horizon), startRadius: 0, endRadius: r * 1.6))
                }
            }
            // The eighth sun, cresting past the end of the week.
            if ignition.crest > 0 {
                let r = column * 0.24
                let x = column * 7 + 40
                let y = horizon + r * 1.2 - (r * 1.2 + r * 0.22) * ignition.crest
                ctx.fill(Path(ellipseIn: CGRect(x: x - r * 2.4, y: y - r * 2.4, width: r * 4.8, height: r * 4.8)),
                         with: .radialGradient(Gradient(colors: [voice.opacity(0.35 * ignition.crest), voice.opacity(0)]), center: CGPoint(x: x, y: y),
                                               startRadius: r * 0.9, endRadius: r * 2.4))
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [voice.opacity(0.9 * ignition.crest), voice.opacity(0.55 * ignition.crest)]),
                                               center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The ritual time as a pill: click to type ("7:30", "9 pm", "21:15"), ↑ and ↓ move 15 minutes, Esc puts the last
/// time back. A typed time lands 150 ms after the last key.
private struct RitualTimePill: View {
    let minutes: Int
    let hour12: Bool
    let onCommit: (Int) -> Void
    let onRestore: () -> Void
    @State private var hover = false

    var body: some View {
        PillField(minutes: minutes, hour12: hour12, onCommit: onCommit, onRestore: onRestore)
            .frame(width: 104, height: 24)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Tok.surfaceAlt.opacity(hover ? 0.85 : 0.6), in: .rect(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(hover ? Tok.ink3 : Tok.borderStrong))
            .onHover { hover = $0 }
            .animation(Motion.fade, value: hover)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Reminder time")
            .accessibilityValue(FirstWeek.clockLabel(minutes, hour12: hour12))
            .accessibilityAdjustableAction { direction in
                onCommit((minutes + (direction == .increment ? 15 : 1425)) % 1440)
            }
    }
}

private struct PillField: NSViewRepresentable {
    let minutes: Int
    let hour12: Bool
    let onCommit: (Int) -> Void
    let onRestore: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.alignment = .center
        f.font = NSFont(name: "GeistMono-Regular", size: 15) ?? .monospacedSystemFont(ofSize: 15, weight: .regular)
        f.textColor = NSColor(Tok.ink)
        f.delegate = context.coordinator
        f.stringValue = FirstWeek.clockLabel(minutes, hour12: hour12)
        f.cell?.usesSingleLineMode = true
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        context.coordinator.parent = self
        if f.currentEditor() == nil { f.stringValue = FirstWeek.clockLabel(minutes, hour12: hour12) }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PillField
        private var debounce: Task<Void, Never>?

        init(_ parent: PillField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let f = note.object as? NSTextField else { return }
            debounce?.cancel()
            let text = f.stringValue
            debounce = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, let m = FirstWeek.parseTyped(text, near: parent.minutes) else { return }
                parent.onCommit(m)
            }
        }

        func controlTextDidEndEditing(_ note: Notification) {
            (note.object as? NSTextField)?.stringValue = FirstWeek.clockLabel(parent.minutes, hour12: parent.hour12)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
                let m = (parent.minutes + (selector == #selector(NSResponder.moveUp(_:)) ? 15 : 1425)) % 1440
                debounce?.cancel()
                parent.onCommit(m)
                textView.string = FirstWeek.clockLabel(m, hour12: parent.hour12)
                textView.selectAll(nil)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                debounce?.cancel()
                parent.onRestore()
                control.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                debounce?.cancel()
                if let m = FirstWeek.parseTyped(textView.string, near: parent.minutes) { parent.onCommit(m) }
                control.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }
    }
}

/// 'I ask only after you've seen it': the permission ask, then a test of the reminder, word for word.
private struct ReminderAsk: View {
    let announce: (String) -> Void
    private let prefs = PrefsStore.shared
    @State private var standing: Permission?
    @State private var state: AskState = .idle

    enum AskState { case idle, requesting, granted, denied }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if standing == .denied || state == .denied {
                Text("Notifications are off for Saro.").font(Typo.ui(13)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
                Text("The week works without reminders. You can turn them on in System Settings → Notifications any time.")
                    .font(Typo.ui(12)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings") {
                    let id = Bundle.main.bundleIdentifier ?? ""
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(LinkStyle())
            } else if standing != nil {
                Text("I ask only after you’ve seen it").monoCaps(10.5).foregroundStyle(Tok.ink2)
                Button(standing == .authorized ? "Show it to me once" : "Allow this reminder") { Task { await allow() } }
                    .buttonStyle(QuietStyle())
                    .disabled(state == .requesting)
                if let line {
                    Text(line).font(Typo.ui(12)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true).transition(.opacity)
                }
            }
        }
        .animation(Motion.fade, value: state)
        .task { standing = .init(await Reminders.shared.status()) }
    }

    private var line: String? {
        switch state {
        case .idle: nil
        case .requesting: "Waiting for macOS…"
        case .granted: "Allowed. That was a test, word for word."
        case .denied: nil
        }
    }

    private func allow() async {
        guard state != .requesting else { return }
        state = .requesting
        let ok = await Reminders.shared.request()
        if ok {
            prefs.reminderOn = true
            await Reminders.shared.scheduleRitual()
            await Reminders.shared.sendTest()
            state = .granted
            standing = .authorized
            announce("Allowed. That was a test, word for word.")
        } else {
            state = .denied
            announce("Notifications are off for Saro.")
        }
    }
}

/// Whether notifications are allowed, denied or not yet asked, as this screen tells them apart.
private enum Permission: Equatable {
    case notDetermined, denied, authorized

    init(_ s: UNAuthorizationStatus) {
        switch s {
        case .denied: self = .denied
        case .authorized, .provisional, .ephemeral: self = .authorized
        default: self = .notDetermined
        }
    }
}
