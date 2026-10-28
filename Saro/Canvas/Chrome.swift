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

/// The bottom glass bar (BottomLeftStatus.tsx, one row): day and mood ribbon, capture, then History and Recenter. The day
/// and the replay share one cell, so opening the replay never resizes the bar; its track grows out of the date.
struct BottomBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dateDirection: CGFloat = 0
    @Namespace private var cell

    var body: some View {
        let replaying = model.replay.active
        HStack(spacing: 2) {
            day
                .opacity(replaying ? 0 : 1)
                .allowsHitTesting(!replaying)
                .accessibilityHidden(replaying)
                .overlay {
                    ReplayBar(namespace: cell)
                        .opacity(replaying ? 1 : 0)
                        .allowsHitTesting(replaying)
                        .accessibilityHidden(!replaying)
                }
            Divider().frame(height: 26).padding(.horizontal, 4)
            // History turns into Close in place; it and Recenter never move.
            history
                .tourAnchor(.history)
            iconButton("scope", "Recenter") { model.camera = .fit(UUID()) }
                .keyboardShortcut("0", modifiers: .command).help("Fit the day  ⌘0")
        }
        .padding(6)
        .glassPanel(radius: Radius.sheet)
        .animation(model.replay.animated ? Motion.pick(Motion.small, reduce: reduceMotion) : nil, value: replaying)
        .animation(Motion.pick(Motion.small, reduce: reduceMotion), value: model.day)
        .onChange(of: model.day) { old, new in dateDirection = new > old ? 1 : -1 }
        .tourAnchor(.captureBar)
    }

    private var day: some View {
        HStack(spacing: 2) {
            iconButton("chevron.left", "Previous day") { model.slide(-1) }.help("Previous day  ⌘[")
            VStack(spacing: 4) {
                Text(DayFormat.bar(model.day)).monoCaps(11.5, tracking: 0.04).foregroundStyle(Tok.sageDark)
                    .id(model.day)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(x: 8 * dateDirection).combined(with: .opacity), removal: .opacity))
                MoodRibbon()
            }
            .frame(minWidth: 132)
            .background {
                if !model.replay.active { Color.clear.matchedGeometryEffect(id: reduceMotion ? "date" : "replayTrack", in: cell) }
            }
            .tourAnchor(.dayNav)
            .contentShape(.rect)
            .onTapGesture { if !model.isToday { model.slide(to: LocalDay.today()) } }
            .help(model.isToday ? "Today" : "Back to today  ⌘T")
            iconButton("chevron.right", "Next day") { model.slide(1) }.help("Next day  ⌘]")
            Divider().frame(height: 26).padding(.horizontal, 4)
            // Switching kind under a live recorder would keep the camera running behind the voice pill.
            Group {
                recorderTile(.moment)
                    .keyboardShortcut("n", modifiers: .command).help("Record a moment  ⌘N")
                    .tourAnchor(.recordButton)
                recorderTile(.voice)
                    .keyboardShortcut("n", modifiers: [.command, .shift]).help("Leave a voice note  ⇧⌘N")
                CaptureTile(face: CaptureFace(title: "Still", symbol: "photo", tint: Tok.stillInk)) { model.pickStill() }
                    .help("Add a photo (or drop or paste one onto the canvas)")
                CaptureTile(face: CaptureFace(title: "Write", symbol: "text.alignleft", tint: Tok.reflectionInk)) {
                    Task { if let e = await model.newWriting() { model.openEntryID = e.id } }
                }
                .keyboardShortcut("w", modifiers: [.command, .option]).help("Write  ⌥⌘W")
            }
            .disabled(model.recorderKind != nil)
        }
    }

    /// Moment and Voice: a click (not ⌘N) lets the recorder grow out of the button, which waits hidden under it until the
    /// recorder closes (captureMorph with `hide`).
    private func recorderTile(_ kind: EntryKind) -> some View {
        let hidden = model.recorderGrows && model.recorderKind == kind
        return CaptureTile(face: .of(kind)) {
            model.recorderKind = kind
            model.recorderGrows = !Motion.byKey
        }
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
            Text(title).font(Typo.ui(11, .medium)).foregroundStyle(lit ? Tok.ink : Tok.ink2)
        }
        .frame(width: 68, height: 52)
    }
}

/// A capture (CaptureDock.tsx): its face, whose label turns ink on hover.
private struct CaptureTile: View {
    let face: CaptureFace
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            CaptureFace(title: face.title, symbol: face.symbol, tint: face.tint, lit: hover)
                .contentShape(.rect(cornerRadius: Radius.panel))
        }
        .buttonStyle(PressStyle(hoverFill: true, radius: Radius.panel))
        .opacity(enabled ? 1 : 0.4)
        .onHover { hover = $0 }
    }
}

/// The last 7 days' moods as 14 × 4 bars over weekday initials (MoodRibbon.tsx). A held day shows no mood.
struct MoodRibbon: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 3) {
            ForEach(model.week, id: \.day) { d in
                VStack(spacing: 3) {
                    Capsule().fill(d.mood.map(MoodPalette.color) ?? Tok.ink.opacity(0.1))
                        .frame(width: 14, height: 4)
                    Text(LocalDay.date(d.day)?.formatted(.dateTime.weekday(.narrow)) ?? "")
                        .font(Typo.mono(10)).textCase(.uppercase)
                        .foregroundStyle(d.day == model.day ? Tok.ink : Tok.ink3)
                }
                .frame(width: 14)
                .help("\(DayFormat.sidebar(d.day))\(d.mood.map { ": \($0.rawValue)" } ?? "")")
            }
        }
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
            .onHover { hover = $0 }
    }
}

extension DayFormat {
    /// "TUE 27 OCT" (mono caps in the bar).
    static func bar(_ day: String) -> String {
        guard let d = LocalDay.date(day) else { return day }
        let prefix = day == LocalDay.today() ? "Today · " : ""
        return prefix + d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
