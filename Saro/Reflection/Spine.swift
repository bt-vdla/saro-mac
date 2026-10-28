import SaroKit
import SwiftUI

/// The insight surface (InsightBar.tsx): one shape that is a 64 pt spine, then the 360 pt "What Saro noticed" panel, then
/// the 540 pt letter, morphing between them. From the pointer it springs on the surface spring; from the keyboard it is
/// simply there (the frequency rule); the evening arrival eases in over 0.7 s, its words from 0.3 s. Reduce Motion fades,
/// and Reduce Transparency makes it solid paper.
struct InsightSurface: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let height: CGFloat
    @State private var hover = false
    @State private var pressed = false
    @FocusState private var spineFocused: Bool

    /// With no room for all of it, the spine folds into a 44 pt sun toggle.
    private var folded: Bool { height < Self.spineMin }
    private static let spineMin: CGFloat = 320

    private var size: CGSize {
        switch model.insight {
        case .spine: folded ? CGSize(width: 44, height: 44) : CGSize(width: 64, height: spineHeight)
        case .panel: CGSize(width: 360, height: min(640, height))
        case .letter: CGSize(width: 540, height: min(760, height))
        }
    }

    /// Content-sized, never under 320 pt, so the commitment marks always fit.
    private var spineHeight: CGFloat {
        let r = model.reflection
        let marks = min(3, r.commitments.count) + (r.carryOvers.isEmpty ? 0 : 1) + 1
        let group = CGFloat(marks) * 20 + (r.commitments.count > 3 ? 12 : 0) + CGFloat(marks - (r.commitments.count > 3 ? 0 : 1)) * 6
        return max(Self.spineMin, 48 + 141 + group)
    }

    private var radius: CGFloat { model.insight == .spine ? size.width / 2 : Radius.sheet }

    /// The spine sits centred on the canvas (web: 7.5vh + 42.5vh − 160); the panel and letter start at the top.
    // ponytail: recovers the canvas height from DayView's `height` (0.925·H − 120); pass H in if that layout changes.
    private var spineDrop: CGFloat {
        max(0, min((height + 120) / 0.925 * 0.425 - 160, height - size.height))
    }

    private var empty: Bool { model.entries.isEmpty }
    private var spine: Bool { model.insight == .spine }
    /// The day replays over the bar; the spine steps aside for its tooltip.
    private var stepAside: Bool { spine && model.replay.active }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        ZStack(alignment: .topLeading) {
            switch model.insight {
            case .spine:
                SpineColumn(folded: folded, focused: $spineFocused, hover: $hover, pressed: $pressed).transition(contentIn)
            case .panel: NoticedView().transition(contentIn)
            case .letter: LetterView().transition(contentIn)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background {
            if reduceTransparency { shape.fill(Tok.paper) } else { shape.fill(Tok.paper.opacity(0.9)).background(.regularMaterial, in: shape) }
        }
        .overlay(shape.strokeBorder(Tok.rim.opacity(0.6)))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.2), radius: 30, y: 24)
        .scaleEffect(spine && pressed ? 0.98 : 1)
        .offset(y: spine && hover && !reduceMotion ? -2 : 0)
        .animation(Motion.lift, value: hover)
        .animation(Motion.lift, value: pressed)
        .overlay(alignment: .trailing) {
            if spine && empty && (hover || spineFocused) {
                EmptyDayTip(today: model.isToday).frame(width: 220, alignment: .trailing).offset(x: -size.width - 12).transition(.opacity)
            }
        }
        .animation(Motion.fade, value: hover || spineFocused)
        .overlay(alignment: .topLeading) {
            if spine && model.reflection.letterAvailable && !empty && !model.isDayHeld {
                LetterButton(instant: model.reflection.how == .instant).offset(x: -54, y: folded ? 0 : 16)
            }
        }
        .overlay(alignment: spine ? .top : .topTrailing) {
            ReadingBadge().offset(x: spine ? 0 : -24, y: -12)
        }
        .opacity(stepAside ? 0 : 1)
        .allowsHitTesting(!stepAside)
        .accessibilityHidden(stepAside)
        .tourAnchor(.noticedButton)
        .padding(.top, spine ? spineDrop : 0)
        .animation(surfaceAnimation, value: model.insight)
        .animation(Motion.pick(Motion.small, reduce: reduceMotion), value: stepAside)
    }

    /// Under Reduce Motion the shape changes at once and only its content fades.
    private var surfaceAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return switch model.reflection.how {
        case .instant: nil
        case .arrive: Motion.easeOut(0.7)
        case .morph: Motion.surface
        }
    }

    /// What's on the surface fades in once it has started to grow; from the keyboard it's simply there.
    private var contentIn: AnyTransition {
        switch model.reflection.how {
        case .instant: .identity
        case .arrive: .opacity.animation(Motion.easeOut(0.2).delay(reduceMotion ? 0 : 0.3))
        case .morph: .opacity.animation(reduceMotion ? Motion.fade : Motion.easeOut(0.15).delay(0.12))
        }
    }
}

/// The web's icon column: moment, echo and still marks over a rule, then the day's commitments (up to three, '+N'), the
/// dashed ring of yesterday's still waiting, and a plus. While the day's own records load it keeps its footprint with
/// four shimmering dots, after 150 ms so a quick load never flashes.
private struct SpineColumn: View {
    @Environment(AppModel.self) private var model
    let folded: Bool
    var focused: FocusState<Bool>.Binding
    @Binding var hover: Bool
    @Binding var pressed: Bool
    @State private var loading = false

    var body: some View {
        let r = model.reflection
        let waiting = r.day != model.day
        Group {
            if loading && waiting {
                VStack(spacing: 20) {
                    if !folded { ForEach(0..<4, id: \.self) { i in Shimmer(height: 20, delay: Double(i) * 0.08).frame(width: 20) } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement()
                .accessibilityLabel("Loading insights")
            } else {
                Button {
                    hover = false
                    pressed = false
                    model.insight = .panel
                } label: {
                    glyphs.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(.rect)
                }
                .buttonStyle(PressReport(pressed: $pressed))
                .focused(focused)
                .help(model.entries.isEmpty ? "" : "What Saro noticed  ⌥⌘I")
                .accessibilityLabel("Expand insights")
                .accessibilityHint(carryHint)
            }
        }
        .onHover { hover = $0 }
        .task(id: waiting) {
            loading = false
            guard waiting else { return }
            try? await Task.sleep(for: .milliseconds(150))
            loading = true
        }
        .onChange(of: r.refocusSpine) { _, now in
            guard now else { return }
            r.refocusSpine = false
            focused.wrappedValue = true
        }
    }

    private var carryHint: String {
        switch model.reflection.carryOvers.count {
        case 0: ""
        case 1: "A commitment from yesterday is waiting."
        case let n: "\(n) commitments from yesterday are waiting."
        }
    }

    @ViewBuilder private var glyphs: some View {
        let r = model.reflection
        let dim = model.entries.isEmpty ? 0.6 : 1
        if folded {
            glyph("sun.max", Tok.moment).opacity(dim)
        } else {
            VStack(spacing: 20) {
                glyph("sun.max", Tok.moment)
                glyph("water.waves", Tok.echo)
                glyph("questionmark.circle", Tok.still)
                Rectangle().fill(Tok.ink.opacity(0.1)).frame(width: 20, height: 1)
                VStack(spacing: 6) {
                    if !r.carryOvers.isEmpty {
                        Circle().strokeBorder(Tok.voice, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])).frame(width: 20, height: 20)
                    }
                    ForEach(r.commitments.prefix(3)) { c in
                        glyph(c.done ? "checkmark.circle.fill" : "circle", c.done ? Tok.moment : Tok.reflection)
                    }
                    if r.commitments.count > 3 {
                        Text("+\(r.commitments.count - 3)").font(Typo.ui(10, .medium)).foregroundStyle(Tok.reflectionInk).frame(height: 12)
                    }
                    glyph("plus", Tok.moment)
                }
            }
            .opacity(dim)
            .animation(Motion.small, value: r.commitments)
        }
    }

    private func glyph(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint).frame(width: 20, height: 20)
    }
}

/// The empty-day tooltip, to the spine's left (InsightBar's insight-spine-empty): ink, caption type, at most 220 pt.
private struct EmptyDayTip: View {
    let today: Bool

    var body: some View {
        Text(today ? "Nothing yet today. Add a moment, an echo, or a still. Insights appear once there’s something to read."
                   : "Nothing saved on this day.")
            .font(Typo.ui(12)).foregroundStyle(Tok.surface)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: 220, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(Tok.ink, in: .rect(cornerRadius: Radius.control))
            .elevation(.float)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Once the letter is available it tucks in beside the spine: a 44 pt round button with an unread dot, sliding in 12 pt
/// on the small spring after 0.2 s (at once from the keyboard or under Reduce Motion).
private struct LetterButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let instant: Bool
    @State private var shown = false

    var body: some View {
        let unread = model.reflection.letterUnread
        Button { model.insight = .letter } label: {
            Image(systemName: "envelope").font(.system(size: 16)).foregroundStyle(Tok.voice)
                .frame(width: 44, height: 44)
                .background(Tok.paper.opacity(reduceTransparency ? 1 : 0.95), in: .circle)
                .overlay(Circle().strokeBorder(Tok.rim.opacity(0.8)))
                .overlay(alignment: .topTrailing) {
                    if unread {
                        Circle().fill(Tok.voice).frame(width: 8, height: 8).overlay(Circle().strokeBorder(Tok.paper, lineWidth: 2)).padding(8)
                    }
                }
                .elevation(.float)
                .contentShape(.circle)
        }
        .buttonStyle(PressStyle())
        .help("Open the evening letter  ⌥⌘L")
        .accessibilityLabel("\(model.isToday ? "Open today’s letter" : "Open this day’s letter")\(unread ? ", unread" : "")")
        .opacity(shown ? 1 : 0)
        .offset(x: shown || reduceMotion ? 0 : 12)
        .onAppear {
            guard !instant else { return shown = true }
            withAnimation(Motion.pick(Motion.small, reduce: reduceMotion).delay(0.2)) { shown = true }
        }
    }
}

/// Pending-insight feedback, with no Update button: a breathing voice dot while the day is being read, then a sage check
/// reading 'Updated' for 1.2 s when the new reading lands.
private struct ReadingBadge: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        Group {
            if model.reflection.updated {
                Label("Updated", systemImage: "checkmark").font(Typo.ui(10.5, .medium)).foregroundStyle(Tok.sageTeal)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Tok.surface, in: .capsule)
                    .overlay(Capsule().strokeBorder(Tok.rim.opacity(0.6)))
                    .shadow(color: Tok.sage.opacity(0.35), radius: 11)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .accessibilityLabel("Insights updated")
            } else if model.dayStatus == .working && !model.entries.isEmpty {
                Circle().fill(Tok.voice).frame(width: 8, height: 8)
                    .shadow(color: Tok.voice.opacity(0.45), radius: 6)
                    .opacity(breathe || reduceMotion ? 1 : 0.35)
                    .padding(6)
                    .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever()) { breathe = true } }
                    .onDisappear { breathe = false }
                    .transition(.opacity)
                    .accessibilityLabel("Saro is reading your day")
            }
        }
        .animation(Motion.fade, value: model.reflection.updated)
        .allowsHitTesting(false)
    }
}

/// Hands the spine's press up, so the whole surface takes the 0.98 and not just its glyphs.
private struct PressReport: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.onChange(of: configuration.isPressed) { _, p in pressed = p }
    }
}
