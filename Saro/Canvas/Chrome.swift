import SaroKit
import SwiftUI

/// Top-left: the Monolith and the search pill (OrbitNav.tsx).
struct OrbitNav: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Image("Logo").resizable().scaledToFit().frame(width: 44, height: 44)
                .accessibilityLabel("Saro")
            Button { model.searchOpen = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium))
                    Text("Search").font(Typo.ui(13))
                    Text("⌘K").font(Typo.mono(10)).foregroundStyle(Tok.ink3)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Tok.surface.opacity(0.5), in: .rect(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Tok.line))
                }
                .foregroundStyle(Tok.ink2)
                .padding(.horizontal, 16).frame(height: 40)
                .background(.ultraThinMaterial, in: .capsule)
                .overlay(Capsule().strokeBorder(Tok.rim.opacity(0.6)))
            }
            .buttonStyle(PressStyle())
        }
    }
}

/// The bottom glass bar (BottomLeftStatus.tsx, one row): day and mood ribbon, capture, then History and Recenter.
struct BottomBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dateDirection: CGFloat = 0

    var body: some View {
        HStack(spacing: 2) {
            iconButton("chevron.left", "Previous day") { model.slide(-1) }.help("Previous day  ⌘[")
            VStack(spacing: 4) {
                Text(DayFormat.bar(model.day)).monoCaps(11.5, tracking: 0.04).foregroundStyle(Tok.sageDark)
                    .id(model.day)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(x: 8 * dateDirection).combined(with: .opacity), removal: .opacity))
                MoodRibbon()
            }
            .frame(minWidth: 132)
            .tourAnchor(.dayNav)
            .contentShape(.rect)
            .onTapGesture { if !model.isToday { model.slide(to: LocalDay.today()) } }
            .help(model.isToday ? "Today" : "Back to today  ⌘T")
            iconButton("chevron.right", "Next day") { model.slide(1) }.help("Next day  ⌘]")
            Divider().frame(height: 26).padding(.horizontal, 4)
            CaptureTile(title: "Moment", symbol: "video", tint: Tok.momentInk) { model.recorderKind = .moment }
                .keyboardShortcut("n", modifiers: .command).help("Record a moment  ⌘N")
                .tourAnchor(.recordButton)
            CaptureTile(title: "Voice", symbol: "waveform", tint: Tok.echoInk) { model.recorderKind = .voice }
                .keyboardShortcut("n", modifiers: [.command, .shift]).help("Leave a voice note  ⇧⌘N")
            CaptureTile(title: "Still", symbol: "photo", tint: Tok.stillInk) { model.pickStill() }
                .help("Add a photo (or drop or paste one onto the canvas)")
            CaptureTile(title: "Write", symbol: "text.alignleft", tint: Tok.reflectionInk) {
                Task { if let e = await model.newWriting() { model.openEntryID = e.id } }
            }
            .keyboardShortcut("w", modifiers: [.command, .option]).help("Write  ⌥⌘W")
            Divider().frame(height: 26).padding(.horizontal, 4)
            iconButton("clock.arrow.circlepath", "History") { model.sidebarVisible.toggle() }
                .help("Days, Trash and Decisions")
                .tourAnchor(.history)
            iconButton("scope", "Recenter") { model.camera = .fit(UUID()) }
                .keyboardShortcut("0", modifiers: .command).help("Fit the day  ⌘0")
        }
        .padding(6)
        .glassPanel(radius: Radius.sheet)
        .animation(Motion.pick(Motion.small, reduce: reduceMotion), value: model.day)
        .onChange(of: model.day) { old, new in dateDirection = new > old ? 1 : -1 }
        .tourAnchor(.captureBar)
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

/// A capture (CaptureDock.tsx): the type's ink glyph over an 11 pt label that turns ink on hover.
private struct CaptureTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(tint).frame(height: 20)
                Text(title).font(Typo.ui(11, .medium)).foregroundStyle(hover ? Tok.ink : Tok.ink2)
            }
            .frame(width: 68, height: 52)
            .contentShape(.rect(cornerRadius: Radius.panel))
        }
        .buttonStyle(PressStyle(hoverFill: true, radius: Radius.panel))
        .onHover { hover = $0 }
    }
}

/// The last 7 days' moods as 14 × 4 bars over weekday initials (MoodRibbon.tsx). A held day shows no mood.
struct MoodRibbon: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 3) {
            ForEach(model.week, id: \.day) { d in
                Capsule().fill(d.mood.map(MoodPalette.color) ?? Tok.ink4.opacity(0.35))
                    .frame(width: 14, height: 4)
                    .overlay { if d.day == model.day { Capsule().strokeBorder(Tok.sage, lineWidth: 1).padding(-1.5) } }
                    .help("\(DayFormat.sidebar(d.day))\(d.mood.map { ": \($0.rawValue)" } ?? "")")
            }
        }
    }
}

enum MoodPalette {
    /// The web's moodColor (lib/daylight.ts), ported in SaroKit's `Sky`.
    static func color(_ m: Mood) -> Color {
        let hex = Sky.moodColor(m.rawValue)
        return Color(hex, hex)
    }
}

/// Press feedback on pointer-down (0.96 on the press spring), with an optional ink/5 hover fill.
struct PressStyle: ButtonStyle {
    var hoverFill = false
    var radius: CGFloat = 14
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hoverFill && hover ? Tok.ink.opacity(0.05) : .clear, in: .rect(cornerRadius: radius))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
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

/// The insight surface (InsightBar.tsx): one shape that is a 64 pt spine, then the 360 pt "What Saro noticed" panel,
/// then the 540 pt letter, morphing between them on the surface spring.
struct InsightSurface: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let height: CGFloat

    private var size: CGSize {
        switch model.insight {
        case .spine: CGSize(width: 64, height: min(320, height))
        case .panel: CGSize(width: 360, height: min(640, height))
        case .letter: CGSize(width: 540, height: min(760, height))
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch model.insight {
            case .spine: spine.transition(.opacity.animation(.easeOut(duration: 0.15).delay(0.12)))
            case .panel: NoticedView().transition(.opacity.animation(.easeOut(duration: 0.15).delay(0.12)))
            case .letter: LetterView().transition(.opacity.animation(.easeOut(duration: 0.15).delay(0.12)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Tok.paper.opacity(0.9), in: .rect(cornerRadius: model.insight == .spine ? 32 : Radius.sheet))
        .background(.regularMaterial, in: .rect(cornerRadius: model.insight == .spine ? 32 : Radius.sheet))
        .overlay(RoundedRectangle(cornerRadius: model.insight == .spine ? 32 : Radius.sheet).strokeBorder(Tok.rim.opacity(0.6)))
        .clipShape(.rect(cornerRadius: model.insight == .spine ? 32 : Radius.sheet))
        .shadow(color: .black.opacity(0.2), radius: 30, y: 24)
        .animation(Motion.pick(Motion.surface, reduce: reduceMotion), value: model.insight)
        .tourAnchor(.noticedButton)
    }

    private var spine: some View {
        Button { model.insight = .panel } label: {
            VStack(spacing: 14) {
                Image(systemName: "sparkles").font(.system(size: 16)).foregroundStyle(Tok.voice)
                Text("WHAT SARO NOTICED").font(Typo.mono(10)).tracking(1.4).foregroundStyle(Tok.ink2)
                    .fixedSize().rotationEffect(.degrees(90)).frame(width: 20, height: 150)
                Spacer(minLength: 0)
                Circle().fill(model.dayReading.map { MoodPalette.color($0.payload.reading.mood) } ?? Tok.ink4.opacity(0.4))
                    .frame(width: 10, height: 10)
                if model.dayStatus == .ready {
                    Image(systemName: "envelope").font(.system(size: 13)).foregroundStyle(Tok.ink3)
                }
            }
            .padding(.vertical, 20)
            .frame(width: 64)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("i", modifiers: [.command, .option])
        .help("What Saro noticed  ⌥⌘I")
    }
}
