import SaroKit
import SwiftUI

/// The drag grid (DragGuides.tsx). While a card is held, uneven hairlines draw outward from it: other cards' edges and
/// centres over the seeded rhythm in world space, each line with its own reach, fading out radially, with small dots
/// where they cross. The line the card snapped to becomes a solid guide with dots at the aligned points.
struct DragGrid {
    struct Accent {
        var at: CGFloat
        var rects: [CGRect]
        let since: Date
        var gone: Date?
    }

    let started = Date.now
    var ended: Date?
    /// The moving cards, world units, after snapping.
    var rect: CGRect
    let cardX: [CanvasMath.GuideLine]
    let cardY: [CanvasMath.GuideLine]
    let level: Int
    var accentX: Accent?
    var accentY: Accent?

    /// `others` are measured once: they hold still while a card moves.
    init(rect: CGRect, others: [CGRect], zoom: CGFloat) {
        self.rect = rect
        cardX = CanvasMath.cardLines(others, axis: 0)
        cardY = CanvasMath.cardLines(others, axis: 1)
        level = CanvasMath.rhythmLevel(zoom: zoom)
    }

    mutating func move(to rect: CGRect, x: CanvasMath.Snap?, y: CanvasMath.Snap?) {
        self.rect = rect
        let now = Date.now
        Self.accent(&accentX, x, now)
        Self.accent(&accentY, y, now)
    }

    private static func accent(_ a: inout Accent?, _ snap: CanvasMath.Snap?, _ now: Date) {
        if let snap {
            if let cur = a, cur.gone == nil, cur.at == snap.at { a?.rects = snap.rects } else {
                a = Accent(at: snap.at, rects: snap.rects, since: now)
                Task { @MainActor in Haptics.snap() }
            }
        } else if a?.gone == nil {
            a?.gone = now
        }
    }
}

/// Drawn every frame while a grid is up, above the ground and below the cards: a quiet green guide by day, violet at night.
struct DragGridLayer: View {
    let grid: DragGrid
    let camera: Camera
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    static let retract = 0.15

    private struct Drawn {
        /// Screen position across the line's axis, and its distance from the focus.
        var at, d, reach, half: CGFloat
        var alpha, shown: Double
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, _ in draw(&ctx, now: tl.date) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, now: Date) {
        let night = scheme == .dark
        let (rhythmA, cardA, dotA, accentA, accentDotA) = night ? (0.055, 0.075, 0.13, 0.36, 0.5) : (0.06, 0.085, 0.15, 0.42, 0.55)
        let ease = { (t: Double) in CaptureMotion.outCurve.value(at: t.clamped(to: 0...1)) }
        let retract = 1 - ease(grid.ended.map { now.timeIntervalSince($0) / Self.retract } ?? 0)
        let since = now.timeIntervalSince(grid.started)
        // Each line grows out from the focus and fades in, later the further out it is (0.25 ms a point, at most
        // 160 ms). Reduce Motion: no drawing in or out, only a fade.
        let grow: (CGFloat) -> Double = reduceMotion ? { _ in 1 } : { d in retract * ease((since - min(0.16, d * 0.00025)) / 0.22) }
        let fade: (CGFloat) -> Double = reduceMotion ? { _ in retract * (since / Self.retract).clamped(to: 0...1) } : grow

        let z = camera.zoom, pan = camera.pan
        let fx = pan.width + grid.rect.midX * z, fy = pan.height + grid.rect.midY * z
        let vs = lines(grid.cardX, axis: 0, origin: pan.width, focus: fx, alphas: (rhythmA, cardA), grow: grow, fade: fade)
        let hs = lines(grid.cardY, axis: 1, origin: pan.height, focus: fy, alphas: (rhythmA, cardA), grow: grow, fade: fade)

        let px = { (v: CGFloat) in ((v * displayScale).rounded() + 0.5) / displayScale }
        for (l, vertical) in vs.map({ ($0, true) }) + hs.map({ ($0, false) }) where l.half >= 0.5 && l.shown > 0.004 {
            let c = px(l.at)
            let a0 = vertical ? CGPoint(x: c, y: fy - l.half) : CGPoint(x: fx - l.half, y: c)
            let a1 = vertical ? CGPoint(x: c, y: fy + l.half) : CGPoint(x: fx + l.half, y: c)
            let stops = (0...6).map { i in
                let u = (CGFloat(i) / 3 - 1) * l.half
                return Gradient.Stop(color: Tok.ink.opacity(l.alpha * l.shown * falloff(hypot(l.d, u) / l.reach)), location: CGFloat(i) / 6)
            }
            ctx.stroke(Path { $0.move(to: a0); $0.addLine(to: a1) }, with: .linearGradient(Gradient(stops: stops), startPoint: a0, endPoint: a1),
                       lineWidth: 1 / displayScale)
        }

        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color) {
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color))
        }
        // Small dots where two drawn lines cross.
        for v in vs {
            for h in hs where abs(h.at - fy) <= v.half && abs(v.at - fx) <= h.half {
                let r = hypot(v.at - fx, h.at - fy)
                let alpha = dotA * min(v.shown * falloff(r / v.reach), h.shown * falloff(r / h.reach))
                if alpha >= 0.01 { dot(v.at, h.at, 1.1, Tok.ink.opacity(alpha)) }
            }
        }

        // The snapped guide: solid but quiet, through the aligned edges (12 pt past them, 56 past a rhythm line), with
        // dots where it meets them and where it crosses the grid.
        let screen = { (r: CGRect) in CGRect(x: pan.width + r.minX * z, y: pan.height + r.minY * z, width: r.width * z, height: r.height * z) }
        let card = screen(grid.rect)
        let width = max(1, displayScale.rounded())
        for (accent, vertical) in [(grid.accentX, true), (grid.accentY, false)] {
            guard let a = accent else { continue }
            let alpha = retract * (a.gone.map { 1 - (now.timeIntervalSince($0) / 0.08).clamped(to: 0...1) }
                ?? (reduceMotion ? 1 : (now.timeIntervalSince(a.since) / 0.08).clamped(to: 0...1)))
            guard alpha > 0 else { continue }
            let at = (vertical ? pan.width : pan.height) + a.at * z
            let c = ((at * displayScale).rounded() + (Int(width) % 2 == 1 ? 0.5 : 0)) / displayScale
            let rects = [card] + a.rects.map(screen)
            let ends = rects.flatMap { vertical ? [$0.minY, $0.maxY] : [$0.minX, $0.maxX] }
            let pad: CGFloat = a.rects.isEmpty ? 56 : 12
            let lo = ends.min()! - pad, hi = ends.max()! + pad
            ctx.stroke(Path { p in
                p.move(to: vertical ? CGPoint(x: c, y: lo) : CGPoint(x: lo, y: c))
                p.addLine(to: vertical ? CGPoint(x: c, y: hi) : CGPoint(x: hi, y: c))
            }, with: .color(Tok.guide.opacity(alpha * accentA)), lineWidth: width / displayScale)
            let color = Tok.guide.opacity(alpha * accentDotA)
            for e in ends { dot(vertical ? at : e, vertical ? e : at, 2, color) }
            for l in vertical ? hs : vs where l.at > lo && l.at < hi && l.shown > 0.2 { dot(vertical ? at : l.at, vertical ? l.at : at, 1.25, color) }
        }
    }

    /// One axis's lines near the focus: each reaches 450–650 pt by its seed (a circle around the focus); lines under
    /// 4 pt apart are drawn as one, and at most the 48 nearest.
    private func lines(_ cards: [CanvasMath.GuideLine], axis: Int, origin: CGFloat, focus: CGFloat, alphas: (rhythm: Double, card: Double),
                       grow: (CGFloat) -> Double, fade: (CGFloat) -> Double) -> [Drawn] {
        let z = camera.zoom
        var out: [Drawn] = []
        func add(_ l: CanvasMath.GuideLine, _ alpha: Double) {
            let at = origin + l.pos * z, d = abs(at - focus), reach = 450 + 200 * l.seed
            guard d < reach else { return }
            out.append(Drawn(at: at, d: d, reach: reach, half: sqrt(reach * reach - d * d) * grow(d), alpha: alpha * (0.85 + 0.3 * l.seed), shown: fade(d)))
        }
        for l in CanvasMath.rhythmLines(axis: axis, from: (focus - 650 - origin) / z, to: (focus + 650 - origin) / z, level: grid.level) { add(l, alphas.rhythm) }
        for l in cards { add(l, alphas.card) }
        // Lines a few points apart read as one smudge (cards laid out with a little jitter nearly align): keep the stronger.
        out.sort { $0.at < $1.at }
        var kept: [Drawn] = []
        for l in out {
            if let last = kept.last, l.at - last.at < 4 {
                if l.alpha > last.alpha { kept[kept.count - 1] = l }
            } else {
                kept.append(l)
            }
        }
        return kept.count > 48 ? Array(kept.sorted { $0.d < $1.d }.prefix(48)) : kept
    }

    /// Full strength near the focus, gone at the line's reach.
    private func falloff(_ q: CGFloat) -> Double {
        let x = ((q - 0.35) / 0.65).clamped(to: 0...1)
        return 1 - x * x * (3 - 2 * x)
    }
}
