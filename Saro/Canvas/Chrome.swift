import SaroKit
import SwiftUI

/// Top-left: the Monolith and the search pill (OrbitNav.tsx).
struct OrbitNav: View {
    @Environment(AppModel.self) private var model
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Image("Logo").resizable().scaledToFit().frame(width: 72, height: 72)
                .accessibilityLabel("Saro")
            Button { model.searchOpen = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).frame(width: 18, height: 18)
                    Text("Search").font(Typo.ui(13, .medium))
                    Text("⌘K").font(Typo.mono(10)).foregroundStyle(Tok.ink3)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Tok.surface.opacity(0.5), in: .rect(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Tok.line))
                }
                .foregroundStyle(Tok.sageDark)
                .padding(.leading, 14).padding(.trailing, 12).frame(height: 44)
                .background(Tok.bg.opacity(hover ? 0.4 : 0.2), in: .capsule)
                .background(.frosted(), in: .capsule)
                .overlay(Capsule().strokeBorder(Tok.rim.opacity(0.6)))
                .elevation(.lift)
                .animation(Motion.fade, value: hover)
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .onHover { hover = $0 }
        }
    }
}

/// The bottom glass bar (BottomLeftStatus.tsx): day and mood ribbon, capture, then History and Recenter, in one row when
/// it fits and two below that (the day over the captures, History beside the day and Recenter beside the captures), so
/// large text never pushes a control off it. The day and the
/// replay share one cell, so opening the replay never resizes the bar; its track grows out of the date. The day view
/// publishes its height for the surfaces that sit above it.
struct BottomBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var cell
    /// The date button, which takes the focus back when the date picker closes and keyboard navigation is on.
    @FocusState private var dateFocused: Bool
    /// The capture button with the keys (Full Keyboard Access); a closed recorder or music field hands them back to it.
    @FocusState private var tile: EntryKind?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                replayCell { HStack(spacing: 2) { dayCell(.long); divider; captures } }
                divider
                trailing
            }
            HStack(spacing: 2) {
                replayCell {
                    VStack(spacing: 2) {
                        HStack(spacing: 2) { dayCell(.short) }
                        HStack(spacing: 2) { captures }
                    }
                }
                // 44 + 18 + 44 lines up with the rows' 52 + 2 + 52.
                VStack(spacing: 18) { trailing }
            }
        }
        .padding(6)
        .glassPanel(radius: Radius.sheet)
        .overlay(alignment: .topLeading) { ShellPanelLayer() }
        .animation(model.replay.animated ? Motion.pick(Motion.small, reduce: reduceMotion) : nil, value: model.replay.active)
        // After the canvas takes the keys back, so a button that can't hold them (no Full Keyboard Access) leaves them there.
        .onChange(of: model.recorderKind) { old, new in if new == nil, let old { DispatchQueue.main.async { tile = old } } }
        .onChange(of: CaptureUI.shared.musicOpen) { _, open in if !open { DispatchQueue.main.async { tile = .music } } }
        .tourAnchor(.captureBar)
    }

    private var divider: some View { Divider().frame(height: 26).padding(.horizontal, 4) }

    private func replayCell(@ViewBuilder _ content: () -> some View) -> some View {
        let replaying = model.replay.active
        return content()
            .opacity(replaying ? 0 : 1)
            .allowsHitTesting(!replaying)
            .accessibilityHidden(replaying)
            .overlay {
                ReplayBar(namespace: cell)
                    .opacity(replaying ? 1 : 0)
                    .allowsHitTesting(replaying)
                    .accessibilityHidden(!replaying)
            }
    }

    /// History turns into Close in place; it and Recenter never move.
    @ViewBuilder private var trailing: some View {
        history
            .tourAnchor(.history)
        iconButton("scope", "Recenter") { model.camera = .fit(UUID()) }
            .keyboardShortcut(KeyboardShortcut(.fitDay)).help("Fit the day  \(Shortcut.fitDay.keys)")
    }

    private enum Width { case long, short }

    /// ‹ the date and the week's moods › — the date opens the date picker. Hovering a chevron reads its day ahead.
    private func dayCell(_ width: Width) -> some View {
        let atToday = model.day >= LocalDay.today()
        return Group {
            AvatarButton()
            iconButton("chevron.left", "Previous day") { model.slide(-1) }.help("Previous day  \(Shortcut.previousDay.keys)")
                .onHover { if $0 { model.arm(LocalDay.adding(-1, to: model.day)) } }
            Button { toggleDatePicker() } label: {
                VStack(spacing: 4) {
                    DateLabel(width: width == .long ? 260 : 120)
                    MoodRibbon()
                }
                .padding(.horizontal, 8)
                .frame(minWidth: 132, minHeight: 44)
                .contentShape(.rect(cornerRadius: 22))
            }
            .buttonStyle(PressStyle(hoverFill: true, radius: 22))
            // In one row it hugs its date (the web's flex-none button); two rows give it 120 pt to shorten into.
            .fixedSize(horizontal: width == .long, vertical: false)
            .background {
                if !model.replay.active { Color.clear.matchedGeometryEffect(id: reduceMotion ? "date" : "replayTrack", in: cell) }
            }
            .focused($dateFocused)
            .onChange(of: model.datePickerOpen) { _, open in if !open && NSApp.isFullKeyboardAccessEnabled { dateFocused = true } }
            .tourAnchor(.dayNav)
            .accessibilityLabel("Open date picker")
            .accessibilityValue(DayFormat.relative(model.day))
            .help("Go to a day  \(Shortcut.goToDate.keys)")
            iconButton("chevron.right", "Next day") { model.slide(1) }
                .opacity(atToday ? 0.4 : 1)
                .help(atToday ? "Nothing after today yet" : "Next day  \(Shortcut.nextDay.keys)")
                .onHover { if $0 { model.arm(LocalDay.adding(1, to: model.day)) } }
        }
    }

    private func toggleDatePicker() {
        withAnimation(Motion.byKey || reduceMotion ? nil : Motion.small) { model.datePickerOpen.toggle() }
    }

    @ViewBuilder private var captures: some View {
        // Switching kind under a live recorder would keep the camera running behind the voice pill.
        Group {
                recorderTile(.moment)
                    .keyboardShortcut(KeyboardShortcut(.recordMoment)).help("Record a moment  \(Shortcut.recordMoment.keys)")
                    .tourAnchor(.recordButton)
                recorderTile(.voice)
                    .keyboardShortcut(KeyboardShortcut(.voiceNote)).help("Leave a voice note  \(Shortcut.voiceNote.keys)")
                CaptureTile(face: CaptureFace(title: "Still", symbol: "photo", tint: Tok.stillInk)) { model.pickStill() }
                    .focused($tile, equals: .still)
                    .help("Add a photo (or drop or paste one onto the canvas)")
                CaptureTile(face: CaptureFace(title: "Reflection", symbol: "text.alignleft", tint: Tok.reflectionInk)) {
                    Task { if let e = await model.newWriting() { model.openEntryID = e.id } }
                }
                .focused($tile, equals: .reflection)
                .keyboardShortcut(KeyboardShortcut(.write)).help("Write a reflection  \(Shortcut.write.keys)")
                CaptureTile(face: CaptureFace(title: "Music", symbol: "opticaldisc", tint: Tok.music)) {
                    CaptureUI.shared.musicGrows = !Motion.byKey
                    CaptureUI.shared.musicOpen = true
                }
                .focused($tile, equals: .music)
                .opacity(CaptureUI.shared.musicOpen && CaptureUI.shared.musicGrows ? 0 : 1)
                .anchorPreference(key: CaptureOriginKey.self, value: .bounds) { [.music: $0] }
                .help("Add a song from a link")
            }
            .disabled(model.recorderKind != nil)
    }

    /// Moment and Voice: a click (not ⌘N) lets the recorder grow out of the button, which waits hidden under it until the
    /// recorder closes (captureMorph with `hide`).
    private func recorderTile(_ kind: EntryKind) -> some View {
        let hidden = model.recorderGrows && model.recorderKind == kind
        return CaptureTile(face: .of(kind)) {
            model.recorderKind = kind
            model.recorderGrows = !Motion.byKey
        }
        .focused($tile, equals: kind)
        .opacity(hidden ? 0 : 1)
        .animation(nil, value: hidden)
        .anchorPreference(key: CaptureOriginKey.self, value: .bounds) { [kind: $0] }
    }

    private var history: some View {
        let replaying = model.replay.active
        let empty = model.replayItems.isEmpty
        let label = replaying ? "Close replay" : model.isToday ? "Replay today"
            : "Replay \(LocalDay.date(model.day)?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? "")"
        return iconButton(replaying ? "xmark" : "clock.arrow.circlepath", label) {
            if replaying { model.replay.exit(animated: true) } else { model.startReplay(animated: true) }
        }
        .background(Tok.ink.opacity(replaying ? 0.06 : 0), in: .circle)
        .opacity(!replaying && empty ? 0.4 : 1)
        .help(replaying ? "Close replay  Esc" : empty ? "Nothing to replay yet" : label)
    }

    /// ICON_BUTTON: a sage-dark glyph in a 44 pt circle that fills on hover.
    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(Tok.sageDark)
                .frame(width: 44, height: 44).contentShape(.circle)
        }
        .buttonStyle(PressStyle(hoverFill: true, radius: 22))
        .accessibilityLabel(label)
    }
}

/// Where the bar's Moment and Voice buttons are, so the recorder can grow out of the one that opened it.
struct CaptureOriginKey: PreferenceKey {
    static let defaultValue: [EntryKind: Anchor<CGRect>] = [:]
    static func reduce(value: inout [EntryKind: Anchor<CGRect>], nextValue: () -> [EntryKind: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A capture's face: the type's ink glyph over an 11 pt label, ink when lit. The recorder's flight starts as a copy of it.
struct CaptureFace: View {
    let title: String
    let symbol: String
    let tint: Color
    var lit = false

    static func of(_ kind: EntryKind) -> CaptureFace {
        kind == .voice ? CaptureFace(title: "Voice", symbol: "waveform", tint: Tok.echoInk)
            : CaptureFace(title: "Moment", symbol: "video", tint: Tok.momentInk)
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(tint).frame(height: 20)
            Text(title).font(Typo.ui(11, .medium)).foregroundStyle(lit ? Tok.ink : Tok.ink2).fixedSize()
        }
        // Larger text widens it rather than cutting its label, so the bar drops to two rows first.
        .frame(minWidth: 68, minHeight: 52)
    }
}

/// A capture (CaptureDock.tsx): its face, whose label turns ink on hover. A double click, or a held key's repeats within
/// 500 ms, counts as one press, so one press never makes two entries.
private struct CaptureTile: View {
    let face: CaptureFace
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false
    @State private var last: ContinuousClock.Instant?

    var body: some View {
        Button {
            let now = ContinuousClock.now
            defer { last = now }
            if let last, now - last < .milliseconds(500) { return }
            action()
        } label: {
            CaptureFace(title: face.title, symbol: face.symbol, tint: face.tint, lit: hover)
                .contentShape(.rect(cornerRadius: Radius.panel))
        }
        .buttonStyle(PressStyle(hoverFill: true, radius: Radius.panel))
        .opacity(enabled ? 1 : 0.4)
        .onHover { hover = $0 }
    }
}

/// The last 7 days' moods as 14 × 4 bars over weekday initials (MoodRibbon.tsx), each fading to its colour; a bar's
/// tooltip reads "Tuesday · Calm" and a click goes to that day. A held day shows no mood.
struct MoodRibbon: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(model.week, id: \.day) { d in
                VStack(spacing: 3) {
                    Capsule().fill(d.mood.map(MoodPalette.color) ?? Tok.ink.opacity(0.1))
                        .frame(width: 14, height: 4)
                        .animation(Motion.easeOut(0.4), value: d.mood)
                    Text(LocalDay.date(d.day)?.formatted(.dateTime.weekday(.narrow)) ?? "")
                        .font(Typo.mono(10)).textCase(.uppercase)
                        .foregroundStyle(d.day == model.day ? Tok.ink : Tok.ink3)
                }
                .frame(width: 14)
                .contentShape(.rect)
                .onTapGesture { if d.day != model.day { model.slide(to: d.day) } }
                .help("\(Self.weekday(d.day)) · \(d.mood?.rawValue ?? "No mood")")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Moods for the last 7 days. " + model.week.map { "\(Self.weekday($0.day)): \($0.mood?.rawValue.lowercased() ?? "no mood")" }
            .joined(separator: ", "))
    }

    private static func weekday(_ day: String) -> String { LocalDay.date(day)?.formatted(.dateTime.weekday(.wide)) ?? day }
}

/// The bar's day (BottomLeftStatus.tsx): "TODAY · 4:16 PM" on the Mac's own clock, updated every 30 s, "YESTERDAY", or
/// "TUE 22 SEP" (with the year in another year); without the time when narrower, "THU 24" when tiny. A pointer's day
/// change steps it in 8 pt from the side the day came from; a key's swaps it at once.
private struct DateLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let width: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { t in
            ViewThatFits(in: .horizontal) {
                ForEach(DayFormat.bar(model.day, now: t.date), id: \.self) { label in
                    Text(label).monoCaps(11.5, tracking: 0.04).foregroundStyle(Tok.sageDark).monospacedDigit().lineLimit(1).fixedSize()
                }
            }
            .frame(maxWidth: width)
        }
        .id(model.day)
        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(x: 8 * model.slideDirection).combined(with: .opacity), removal: .identity))
        // Only a change that came animated (a pointer's slide) steps in, on the small spring.
        .transaction { if $0.animation != nil { $0.animation = Motion.pick(Motion.small, reduce: reduceMotion) } }
    }
}

enum MoodPalette {
    /// The web's moodColor (lib/daylight.ts), ported in SaroKit's `Sky`.
    static func color(_ m: Mood) -> Color { color(m.rawValue) }

    static func color(_ label: String) -> Color {
        let hex = Sky.moodColor(label)
        return Color(hex, hex)
    }
}

/// Press feedback on pointer-down (0.96 on the press spring), with an optional ink/5 hover fill.
struct PressStyle: ButtonStyle {
    var hoverFill = false
    var radius: CGFloat = 14
    var scale: CGFloat = 0.96
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hoverFill && hover ? Tok.ink.opacity(0.05) : .clear, in: .rect(cornerRadius: radius))
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .focusRing(radius: radius)
            .onHover { hover = $0 }
    }
}

extension DayFormat {
    /// The bar's day, longest form first: "Today · 4:16 PM", "Today", "Thu 24".
    static func bar(_ day: String, now: Date = .now) -> [String] {
        let label = relative(day)
        let short = LocalDay.date(day)?.formatted(.dateTime.weekday(.abbreviated).day()) ?? day
        let full = day == LocalDay.today() ? "\(label) · \(now.formatted(date: .omitted, time: .shortened))" : label
        return [full, label, short].reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}
