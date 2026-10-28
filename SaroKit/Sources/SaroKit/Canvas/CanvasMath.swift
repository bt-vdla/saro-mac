import CoreGraphics
import Foundation

/// Placement and arrangement on the day canvas. World units are points at zoom 1; a position is a card's centre.
public enum CanvasMath {
    static let gap: CGFloat = 40
    static let origin = CGPoint(x: 120, y: 130)
    /// ponytail: a fixed row width for first placement; the camera fits the day, so wide days just zoom out.
    static let rowWidth: CGFloat = 1400
    public static let momentMediaHeight: CGFloat = 236
    public static let stillMediaHeight: CGFloat = 252
    public static let stackSize = CGSize(width: 220, height: 200)

    /// Card sizes from the web build (lib/canvas/camera.ts).
    public static func size(_ kind: EntryKind) -> CGSize {
        switch kind {
        case .moment: CGSize(width: 420, height: momentMediaHeight + 48)
        case .voice: CGSize(width: 300, height: 92)
        case .still: CGSize(width: 260, height: stillMediaHeight + 48)
        case .reflection: CGSize(width: 360, height: 212)
        case .music: CGSize(width: 280, height: 88)
        }
    }

    public static func radius(_ kind: EntryKind) -> CGFloat {
        switch kind {
        case .moment, .reflection: 28
        case .still: 24
        case .voice, .music: 18
        }
    }

    /// The first free spot in reading order on a 24 pt lattice, with the web's small jitter and alternate-card wave.
    public static func place(_ kind: EntryKind, id: String, avoiding occupied: [CGRect]) -> CGPoint {
        let s = size(kind), j = jitter(id)
        let wave: CGFloat = occupied.count % 2 == 1 ? 18 : 0
        var y = origin.y + s.height / 2
        while y < 20_000 {
            var x = origin.x + s.width / 2
            while x + s.width / 2 <= origin.x + rowWidth {
                let c = CGPoint(x: x + j.x * 0.4, y: y + j.y * 0.6 + wave)
                let r = CGRect(center: c, size: s).insetBy(dx: -gap / 2, dy: -gap / 2)
                if !occupied.contains(where: { $0.intersects(r) }) { return c }
                x += 24
            }
            y += 24
        }
        return origin
    }

    /// How far to move, the line it lands on, and the cards that share that line (none for the rhythm).
    public typealias Snap = (delta: CGFloat, at: CGFloat, rects: [CGRect])

    /// The nearest line to any of `mine` within `reach` on one axis.
    public static func snap(_ mine: [CGFloat], to lines: [GuideLine], reach: CGFloat) -> Snap? {
        var pick: Snap?
        for a in mine {
            for l in lines where abs(l.pos - a) <= reach {
                if let p = pick, abs((l.pos - a) - p.delta) < 0.5 {
                    if let r = l.card, !pick!.rects.contains(r) { pick?.rects.append(r) }
                } else if pick == nil || abs(l.pos - a) < abs(pick!.delta) {
                    pick = (l.pos - a, l.pos, l.card.map { [$0] } ?? [])
                }
            }
        }
        return pick
    }

    /// One axis of a moving box (`mine` is left, centre, right or top, middle, bottom): other cards' lines catch any of
    /// them within `reach`; failing that, the rhythm catches an edge within `rhythmReach` (cardGeometry.ts). The rhythm is
    /// dense, so it only catches an edge that's very close: a card never feels notchy crossing the canvas.
    public static func snap(_ mine: [CGFloat], cards: [GuideLine], reach: CGFloat, axis: Int, level: Int, rhythmReach: CGFloat) -> Snap? {
        guard let lo = mine.first, let hi = mine.last else { return nil }
        return snap(mine, to: cards, reach: reach)
            ?? snap([lo, hi], to: rhythmLines(axis: axis, from: lo - rhythmReach, to: hi + rhythmReach, level: level), reach: rhythmReach)
    }

    // MARK: The uneven guide rhythm (cardGeometry.ts)

    /// Empty canvas still shows structure: lines at a seeded order of these spacings per block, the same wherever and
    /// whenever you look, because every block's order comes from its index.
    public static let rhythm: [CGFloat] = [24, 40, 64, 104]

    public struct GuideLine: Equatable, Sendable {
        /// World x (a vertical line) or y (a horizontal one).
        public let pos: CGFloat
        /// 0–1, fixed per line: its reach and weight.
        public let seed: Double
        /// The card this line comes from (its edge or centre); nil for the rhythm.
        public var card: CGRect?
    }

    /// The rhythm's density for a zoom: spacings double or halve so lines stay 40–80 screen points apart on average.
    public static func rhythmLevel(zoom: CGFloat) -> Int { Int(ceil(log2(40 / (58 * zoom)))) }

    /// Rhythm lines along one axis (0 = vertical lines at x, 1 = horizontal at y) with pos in from...to.
    public static func rhythmLines(axis: Int, from: CGFloat, to: CGFloat, level: Int) -> [GuideLine] {
        let unit = pow(2, CGFloat(level)), block = 232 * unit
        var out: [GuideLine] = []
        for k in stride(from: Int(floor(from / block)), through: Int(floor(to / block)), by: 1) {
            var order = [0, 1, 2, 3]
            for i in stride(from: 3, to: 0, by: -1) { order.swapAt(i, Int(hash(k, axis, level, i) * Double(i + 1))) }
            var pos = CGFloat(k) * block
            for i in 0..<4 {
                if pos >= from && pos <= to { out.append(GuideLine(pos: pos, seed: hash(k, axis, level, 8 + i))) }
                pos += rhythm[order[i]] * unit
            }
        }
        return out
    }

    /// Alignment lines from other cards: their left, centre and right (axis 0) or top, middle and bottom.
    public static func cardLines(_ rects: [CGRect], axis: Int) -> [GuideLine] {
        rects.enumerated().flatMap { i, r in
            (0..<3).map { j in
                GuideLine(pos: (axis == 0 ? r.minX : r.minY) + (axis == 0 ? r.width : r.height) * CGFloat(j) / 2, seed: hash(i, axis, j, 7), card: r)
            }
        }
    }

    /// A deterministic 0–1 hash of a few integers, bit for bit the web's (so the grid sits where it does there).
    static func hash(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Double {
        var h: UInt32 = 0x811c9dc5
        for v in [a, b, c, d] {
            h = (h ^ UInt32(truncatingIfNeeded: v)) &* 0x01000193
            h ^= h >> 15
            h = h &* 0x2c1b3c6d
            h ^= h >> 12
        }
        return Double(h) / 4_294_967_296
    }

    /// The smallest rectangle around a set of cards (for fitting the camera to a day).
    public static func bounds(_ rects: [CGRect]) -> CGRect? {
        guard var u = rects.first else { return nil }
        for r in rects.dropFirst() { u = u.union(r) }
        return u
    }

    /// Selected cards glide into a packed, bottom-aligned row with even gaps, in their current left-to-right order.
    public static func grid(_ items: [(id: String, center: CGPoint, size: CGSize)]) -> [String: CGPoint] {
        guard !items.isEmpty else { return [:] }
        let sorted = items.sorted { $0.center.x < $1.center.x }
        let baseline = items.map { $0.center.y + $0.size.height / 2 }.max() ?? 0
        var x = (sorted.map { $0.center.x - $0.size.width / 2 }.min() ?? 0)
        var out: [String: CGPoint] = [:]
        for item in sorted {
            out[item.id] = CGPoint(x: x + item.size.width / 2, y: baseline - item.size.height / 2)
            x += item.size.width + gap
        }
        return out
    }

    /// A loose pile: each card below the top one sits slightly off and turned (degrees), seeded by its id.
    public static func pileOffset(_ id: String, depth: Int) -> (dx: CGFloat, dy: CGFloat, degrees: Double) {
        guard depth > 0 else { return (0, 0, 0) }
        let j = jitter(id)
        return (j.x * 0.6, -CGFloat(depth) * 5 + j.y * 0.3, Double(j.x) / 3)
    }

    /// Fanned-out stack: a centred row around `center`, wrapping after `perRow` (1-3 in a row, 4 as 2×2, then rows of 3).
    public static func fan(count: Int, size: CGSize, around center: CGPoint, perRow: Int = 3) -> [CGPoint] {
        let perRow = count == 4 ? 2 : perRow
        let cols = min(count, perRow), rows = (count + perRow - 1) / perRow
        let w = CGFloat(cols) * size.width + CGFloat(cols - 1) * gap
        let h = CGFloat(rows) * size.height + CGFloat(rows - 1) * gap
        return (0..<count).map { i in
            CGPoint(x: center.x - w / 2 + size.width / 2 + CGFloat(i % perRow) * (size.width + gap),
                    y: center.y - h / 2 + size.height / 2 + CGFloat(i / perRow) * (size.height + gap))
        }
    }

    /// A morph flight's box at progress `v` (morph.ts, MorphLayer.tsx): its size moves in log space and its centre in a
    /// straight line, so growing many times over looks even.
    public static func flightBox(from: CGRect, to: CGRect, v: CGFloat) -> CGRect {
        let size = CGSize(width: from.width * pow(to.width / from.width, v), height: from.height * pow(to.height / from.height, v))
        return CGRect(center: CGPoint(x: from.midX + (to.midX - from.midX) * v, y: from.midY + (to.midY - from.midY) * v), size: size)
    }

    /// What a flight leaves fades out from 5% to 55% of the way; what it reaches is in by 35%.
    public static func flightFades(_ v: Double) -> (leaving: Double, arriving: Double) {
        (1 - min(max((v - 0.05) / 0.5, 0), 1), min(max(v / 0.35, 0), 1))
    }

    /// A flight into something that stays as it is (a card into the Undo toast) is absorbed from 30% to 90% of the way.
    public static func absorbed(_ v: Double) -> Double { 1 - min(max((v - 0.3) / 0.6, 0), 1) }

    /// Where a skeleton block's shimmer gradient starts, `progress` (eased, 0…1) through the web's `shimmer` keyframes,
    /// which slide a gradient repeating every 2 widths from background-position 200% to -200%: 4 widths in all. Drawn as
    /// two of its periods (4 widths) from here, in [-2w, 0), it covers the block at every step.
    public static func shimmerOffset(width w: CGFloat, progress: Double) -> CGFloat {
        (4 * w * progress).truncatingRemainder(dividingBy: 2 * w) - 2 * w
    }

    /// Deterministic ±12 pt jitter from an id.
    static func jitter(_ id: String) -> CGPoint {
        let h = id.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return CGPoint(x: CGFloat(Int(h % 25)) - 12, y: CGFloat(Int((h >> 8) % 25)) - 12)
    }
}

extension CGRect {
    public init(center: CGPoint, size: CGSize) {
        self.init(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}
