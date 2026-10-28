import SaroKit
import SwiftUI

/// Toasts (toast.tsx, toaster.tsx): glass, bottom-left, 8 pt above the bar and above the voice pill, up to three stacked
/// with the newest on top. One slides up 8 pt as it arrives and leaves to the left; dragging it left dismisses it. A
/// card trashed by a click flies into its toast, and a click on Undo flies it back out (Canvas.tsx's handleDeleteCard).
struct ToastHost: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The cards of a trash flight, as the canvas under the toasts draws them; nil where there is no canvas.
    var flying: [String: FlyingCard]?
    /// Where each toast sits, so a flight finds its toast and Undo can fly out of it after it has gone.
    @State private var frames: [UUID: CGRect] = [:]

    private nonisolated static let space = "toasts"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            ForEach(model.toasts) { toast in
                ToastRow(toast: toast, undo: { undo(toast) })
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[toast.id] = $0 }
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(y: 8).combined(with: .opacity),
                                                                       removal: .offset(x: -24).combined(with: .opacity)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 8 pt above the bar (20 pt off the bottom, 64 tall), and above the voice pill while it's up.
        // ponytail: the pill's resting height (98) as a constant; a preference from the recorder if it starts to vary.
        .padding(.leading, 24).padding(.bottom, 92 + (model.recorderKind == .voice ? 106 : 0))
        .animation(Motion.pick(Motion.easeOut(0.24), reduce: reduceMotion), value: model.toasts.map(\.id))
        .animation(Motion.pick(Motion.small, reduce: reduceMotion), value: model.recorderKind == .voice)
        .onChange(of: model.toasts.map(\.id)) { _, ids in frames = frames.filter { ids.contains($0.key) } }
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { if flying != nil { ShellPanels.shared.toastOrigin = $0 } }
        .overlay {
            if let flight = model.trashFlight, let flying {
                GeometryReader { geo in
                    TrashFlightLayer(flight: flight, cards: flying.mapValues { (place: geo[$0.place], face: $0.face) },
                                     toast: flight.back?.frame ?? target(of: flight), viewport: geo.size)
                }
                .id(flight.id)
                // Back in its place, the card shows again under the stand-in, which fades off it (MorphLayer.tsx's end).
                .transition(.asymmetric(insertion: .identity, removal: flight.into ? .identity : .opacity.animation(.easeOut(duration: 0.12))))
            }
        }
        .coordinateSpace(.named(Self.space))
    }

    /// The toast holding the flight's cards, once it is on screen.
    private func target(of flight: TrashFlight) -> CGRect? {
        let ids = Set(flight.cards.map(\.id))
        return model.toasts.first { $0.trashed.contains { ids.contains($0.id) } }.flatMap { frames[$0.id] }
    }

    /// A click flies the cards back out of the toast to their places; a key brings them back where they are.
    private func undo(_ toast: Toast) {
        if !toast.trashed.isEmpty, flying != nil, let frame = frames[toast.id], !Motion.byKey, !reduceMotion {
            model.trashFlight = TrashFlight(cards: toast.trashed, back: (toast, frame))
        }
        toast.action?.run()
        model.dismiss(toast.id)
    }
}

/// One toast on the stack: its face, a timer that stops while the pointer or VoiceOver is on it, and a drag to the left
/// that dismisses it.
private struct ToastRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let toast: Toast
    let undo: () -> Void
    @State private var hover = false
    @State private var drag: CGFloat = 0
    /// VoiceOver lands on the toast's parts, not on the toast, so each part reports it.
    @AccessibilityFocusState private var voiceOver: ToastPart?

    var body: some View {
        ToastFace(toast: toast, act: { toast.undo != nil ? undo() : run() }, dismiss: { model.dismiss(toast.id) }, voiceOver: $voiceOver)
            .offset(x: drag)
            .opacity(1 - Double(min(1, -drag / 240)))
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { drag = min(0, $0.translation.width) }
                    .onEnded { v in
                        if v.translation.width < -80 || v.predictedEndTranslation.width < -200 {
                            model.dismiss(toast.id)
                        } else {
                            withAnimation(Motion.pick(Motion.small, reduce: reduceMotion)) { drag = 0 }
                        }
                    }
            )
            .onHover { hover = $0 }
            .onChange(of: hover || voiceOver != nil || drag != 0, initial: true) { _, held in
                if held { model.heldToasts.insert(toast.id) } else { model.heldToasts.remove(toast.id) }
            }
    }

    private func run() {
        toast.action?.run()
        model.dismiss(toast.id)
    }
}

enum ToastPart: Hashable { case text, action, dismiss }

/// The toast itself: its title, the line under it, its action and the dismiss. The copy that flies out of it does nothing.
private struct ToastFace: View {
    let toast: Toast
    var act: () -> Void = {}
    var dismiss: () -> Void = {}
    var voiceOver: AccessibilityFocusState<ToastPart?>.Binding?

    var body: some View {
        let destructive = toast.style == .destructive
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(Typo.ui(13.5, .semibold)).foregroundStyle(destructive ? Tok.danger : Tok.ink)
                if let detail = toast.detail {
                    Text(detail).font(Typo.ui(12)).lineSpacing(2).foregroundStyle(destructive ? Tok.danger.opacity(0.9) : Tok.ink2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .voiceOverFocus(voiceOver, .text)
            if let action = toast.action {
                Button(action: act) {
                    Text(action.label).font(Typo.ui(13, .semibold)).padding(.horizontal, 12).frame(minHeight: 32)
                }
                .buttonStyle(ToastControl(chip: true, destructive: destructive))
                .accessibilityHint(action.label == "Undo" ? "Undoes this" : "Tries again")
                .voiceOverFocus(voiceOver, .action)
            }
        }
        .padding(.vertical, 12).padding(.leading, 16).padding(.trailing, 44)
        .frame(width: 360)
        .background((destructive ? Tok.dangerBg : Tok.paper).opacity(0.95), in: .rect(cornerRadius: Radius.panel))
        .background(.frosted(solid: destructive ? Tok.dangerBg : Tok.paper), in: .rect(cornerRadius: Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(destructive ? Tok.dangerBorder : Tok.rim.opacity(0.7)))
        .overlay(alignment: .trailing) {
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .medium)).frame(width: 32, height: 32)
            }
            .buttonStyle(ToastControl(chip: false, destructive: destructive))
            .accessibilityLabel("Dismiss")
            .voiceOverFocus(voiceOver, .dismiss)
            .padding(.trailing, 8)
        }
        .elevation(.float)
        .accessibilityElement(children: .contain)
    }
}

private extension View {
    @ViewBuilder func voiceOverFocus(_ focus: AccessibilityFocusState<ToastPart?>.Binding?, _ part: ToastPart) -> some View {
        if let focus { accessibilityFocused(focus, equals: part) } else { self }
    }
}

/// toast.tsx's controls: the action chip (ink/5, ink/10 on hover; danger/10 on a failure) and the round dismiss
/// (ink-3, ink/5 and ink on hover; danger on a failure).
private struct ToastControl: ButtonStyle {
    let chip: Bool
    var destructive = false
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        let ink = destructive ? Tok.danger : chip ? Tok.sageDark : hover ? Tok.ink : Tok.ink3
        let fill = destructive ? Tok.danger.opacity(chip ? (hover ? 0.15 : 0.1) : hover ? 0.08 : 0)
            : Tok.ink.opacity((chip ? 0.05 : 0) + (hover ? 0.05 : 0))
        configuration.label
            .foregroundStyle(ink)
            .background(fill, in: .rect(cornerRadius: chip ? Radius.control : 16))
            .contentShape(.rect)
            .focusRing(radius: chip ? Radius.control : 16)
            .onHover { hover = $0 }
    }
}

// MARK: The trash flight (Canvas.tsx, MorphLayer.tsx)

/// A card of a trash flight as its stage draws it: where it sits and its face.
struct FlyingCard {
    let place: Anchor<CGRect>
    let face: Image
}

struct TrashFlightKey: PreferenceKey {
    static var defaultValue: [String: FlyingCard] { [:] }
    static func reduce(value: inout [String: FlyingCard], nextValue: () -> [String: FlyingCard]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Trashed cards flying into the Undo toast, which absorbs them as they arrive, or Undo flying them back out to their
/// places. Each waits where it starts until both ends are on screen.
private struct TrashFlightLayer: View {
    @Environment(AppModel.self) private var model
    let flight: TrashFlight
    let cards: [String: (place: CGRect, face: Image)]
    let toast: CGRect?
    let viewport: CGSize
    @State private var v = 0.0

    var body: some View {
        let ready = toast != nil && cards.count == flight.cards.count
        // MorphLayer.tsx: a flight over 18% of the viewport is a big surface (spring.surface), others take spring.small.
        let big = cards.values.contains { $0.place.width * $0.place.height > 0.18 * viewport.width * viewport.height }
        ZStack(alignment: .topLeading) {
            ForEach(flight.cards) { c in
                if let card = cards[c.id] {
                    TrashFlightBox(card: c, face: card.face, place: card.place, toast: toast ?? card.place, back: flight.back?.toast,
                                   big: big, viewport: viewport, v: v)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: ready, initial: true) { _, ready in
            guard ready else { return }
            #if DOGFOOD
            if let frozen = Snapshots.trashFreeze { return v = frozen }
            #endif
            withAnimation(big ? Motion.surface : Motion.small) { v = 1 } completion: { end() }
        }
        // MorphLayer.tsx's watchdog: a flight that can't land (the day changed under it) ends rather than hold a card hidden.
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            #if DOGFOOD
            if Snapshots.trashFreeze != nil { return }
            #endif
            end()
        }
    }

    private func end() {
        if model.trashFlight?.id == flight.id { model.trashFlight = nil }
    }
}

/// One card's stand-in: a box flying between its place and the toast (size in log space, centre in a straight line)
/// holding the card's face, and on the way out the toast's too, each scaled to cover it, centred across, from the top.
/// Into the toast it keeps the card's radius as it shrinks and is absorbed; out of it, it rounds from the toast's to the card's.
struct TrashFlightBox: View, @MainActor Animatable {
    let card: StageCard
    let face: Image
    let place: CGRect
    let toast: CGRect
    /// Undo: the toast it flies out of; nil on the way in.
    let back: Toast?
    let big: Bool
    let viewport: CGSize
    var v: Double

    var animatableData: Double {
        get { v }
        set { v = newValue }
    }

    var body: some View {
        let box = back == nil ? CanvasMath.flightBox(from: place, to: toast, v: v) : CanvasMath.flightBox(from: toast, to: place, v: v)
        let fades = CanvasMath.flightFades(v)
        let landed = card.radius * place.width / card.size.width
        let radius = back == nil ? card.radius * box.width / card.size.width : big ? landed : Radius.panel + (landed - Radius.panel) * v
        ZStack(alignment: .top) {
            if let back {
                ToastFace(toast: back).frame(width: toast.width, height: toast.height)
                    .scaleEffect(max(box.width / toast.width, box.height / toast.height), anchor: .top)
                    .opacity(fades.leaving)
            }
            face.frame(width: card.size.width, height: card.size.height)
                .scaleEffect(max(box.width / card.size.width, box.height / card.size.height), anchor: .top)
                .opacity(back == nil ? fades.leaving : fades.arriving)
        }
        .frame(width: box.width, height: box.height, alignment: .top)
        .clipShape(.rect(cornerRadius: radius))
        .opacity(back == nil ? CanvasMath.absorbed(v) : 1)
        .modifier(MotionBlurred(position: CGPoint(x: box.midX, y: box.midY),
                                coverage: box.width * box.height / max(1, viewport.width * viewport.height)))
        .position(x: box.midX, y: box.midY)
    }
}
