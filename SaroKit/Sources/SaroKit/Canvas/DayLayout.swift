import CoreGraphics
import Foundation

/// Where a day's cards go (the web's components/canvas/dayLayout.ts). World units; rects are top-left based here, and
/// the app converts to its card centres.
public enum DayLayout {
    public struct Item: Sendable, Hashable {
        public let id: String
        public let kind: EntryKind
        public let size: CGSize
        public init(id: String, kind: EntryKind, size: CGSize) { (self.id, self.kind, self.size) = (id, kind, size) }
    }

    private static let maxPerRow = 6
    private static let overlap: CGFloat = 15
    private static let chunkGap: CGFloat = 60
    private static let rowGap: CGFloat = 80

    /// A day opened with no positions: cards grouped by type in creation order (only like cards overlap), in chunks of
    /// up to six side by side; chunks pack into rows that wrap at the width giving the day the visible area's shape, and
    /// rows stack around `center` with an alternating ±25 wave and a little jitter. Returns each card's centre.
    public static func layoutDay(_ items: [Item], center: CGPoint, visible: CGSize, seed: UInt64 = 1) -> [String: CGPoint] {
        var rng = seed == 0 ? 1 : seed
        func random() -> CGFloat {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            return CGFloat(rng % 10_000) / 10_000
        }
        let area = items.reduce(0) { $0 + ($1.size.width - overlap) * ($1.size.height + rowGap) }
        let limit = max(visible.width, 320, (area * visible.width / max(1, visible.height)).squareRoot())
        struct Placed { let id: String; let x: CGFloat; let jitterY: CGFloat; let h: CGFloat; let w: CGFloat }
        struct Row { var items: [Placed] = []; var width: CGFloat = 0; var height: CGFloat = 0 }
        var rows: [Row] = [], row = Row()
        let groups = Dictionary(grouping: items, by: \.kind.rawValue)
        for kind in groups.keys.sorted() {
            let group = groups[kind] ?? []
            let (w, h) = (group[0].size.width, group[0].size.height)
            let step = w - overlap
            let perRow = max(1, min(maxPerRow, Int((limit - w) / step) + 1))
            for start in stride(from: 0, to: group.count, by: perRow) {
                let chunk = group[start..<min(group.count, start + perRow)]
                let chunkWidth = CGFloat(chunk.count - 1) * step + w
                if row.width > 0 && row.width + chunkGap + chunkWidth > limit {
                    rows.append(row)
                    row = Row()
                }
                let x0 = row.width > 0 ? row.width + chunkGap : 0
                for (i, e) in chunk.enumerated() {
                    row.items.append(Placed(id: e.id, x: x0 + CGFloat(i) * step + (random() - 0.5) * 10, jitterY: (random() - 0.5) * 15,
                                            h: e.size.height, w: e.size.width))
                }
                row.width = x0 + chunkWidth
                row.height = max(row.height, h)
            }
        }
        if !row.items.isEmpty { rows.append(row) }
        let total = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * rowGap
        var out: [String: CGPoint] = [:], y = center.y - total / 2
        for r in rows {
            let x0 = center.x - r.width / 2
            for (i, p) in r.items.enumerated() {
                let top = y + (r.height - p.h) / 2 + p.jitterY + (i % 2 == 0 ? -25 : 25)
                out[p.id] = CGPoint(x: x0 + p.x + p.w / 2, y: top + p.h / 2)
            }
            y += r.height + rowGap
        }
        return out
    }

    /// `layoutDay` around `visible`'s middle for the cards nobody moved, keeping clear of the `taken` ones that were: a
    /// card whose new place would touch one goes to the free spot nearest the middle instead, in view if there's room,
    /// else in the area around it (the camera then fits the day); it stays only when even that is full.
    public static func relayout(_ items: [Item], in visible: CGRect, avoiding taken: [CGRect]) -> [String: CGPoint] {
        var at = layoutDay(items, center: CGPoint(x: visible.midX, y: visible.midY), visible: visible.size)
        let rect = { (i: Item) in at[i.id].map { CGRect(center: $0, size: i.size) } }
        let clashing = Set(items.filter { i in rect(i).map { r in taken.contains { $0.intersects(r) } } ?? false }.map(\.id))
        var occupied = taken + items.filter { !clashing.contains($0.id) }.compactMap(rect)
        let room = [visible, visible.insetBy(dx: -visible.width, dy: -visible.height)]
        for i in items where clashing.contains(i.id) {
            guard let corner = room.lazy.compactMap({ freeSpot(i.size, in: $0, avoiding: occupied) }).first else { continue }
            let r = CGRect(origin: corner, size: i.size)
            at[i.id] = CGPoint(x: r.midX, y: r.midY)
            occupied.append(r)
        }
        return at
    }

    private static func overlaps(_ a: CGRect, _ b: CGRect, _ gap: CGFloat) -> Bool { a.insetBy(dx: -gap, dy: -gap).intersects(b) }

    /// The spot nearest `center` (a top-left corner) where a card of `size` sits wholly in `visible` without touching any
    /// `taken` rect: rings of half-card steps, nearest first. Nil when the visible area has no room left.
    // ponytail: O(candidates × cards), a few ms at worst; index the rects if it ever shows.
    public static func freeSpot(_ size: CGSize, in visible: CGRect, avoiding taken: [CGRect], gap: CGFloat = 24) -> CGPoint? {
        let center = CGPoint(x: visible.midX, y: visible.midY)
        let rings = Int(ceil(max(visible.width / (size.width + gap), visible.height / (size.height + gap))))
        for ring in 0...max(0, rings) {
            for gx in -ring...ring {
                for gy in -ring...ring where max(abs(gx), abs(gy)) == ring {
                    let spot = CGRect(x: center.x - size.width / 2 + CGFloat(gx) * (size.width + gap) / 2,
                                      y: center.y - size.height / 2 + CGFloat(gy) * (size.height + gap) / 2, width: size.width, height: size.height)
                    if visible.contains(spot) && !taken.contains(where: { overlaps(spot, $0, gap) }) { return spot.origin }
                }
            }
        }
        return nil
    }

    /// A burst of new cards as one block in the middle of `visible`: tallest first, in rows as wide as the visible area,
    /// each centred. Nil when the block doesn't fit or would touch a `taken` card; the burst then goes card by card.
    public static func packBurst(_ sizes: [CGSize], in visible: CGRect, avoiding taken: [CGRect], gap: CGFloat = 24) -> [CGPoint]? {
        var rows: [(items: [Int], w: CGFloat, h: CGFloat)] = []
        for i in sizes.indices.sorted(by: { sizes[$0].height > sizes[$1].height }) {
            let s = sizes[i]
            if let last = rows.last, last.w + gap + s.width <= visible.width {
                rows[rows.count - 1] = (last.items + [i], last.w + gap + s.width, max(last.h, s.height))
            } else {
                rows.append(([i], s.width, s.height))
            }
        }
        let height = rows.reduce(0) { $0 + $1.h } + CGFloat(max(0, rows.count - 1)) * gap
        guard height <= visible.height, !rows.contains(where: { $0.w > visible.width }) else { return nil }
        var spots = [CGPoint](repeating: .zero, count: sizes.count), y = visible.midY - height / 2
        for r in rows {
            var x = visible.midX - r.w / 2
            for i in r.items {
                spots[i] = CGPoint(x: x, y: y + (r.h - sizes[i].height) / 2)
                x += sizes[i].width + gap
            }
            y += r.h + gap
        }
        let fits = sizes.indices.allSatisfy { i in !taken.contains { overlaps(CGRect(origin: spots[i], size: sizes[i]), $0, gap) } }
        return fits ? spots : nil
    }

    /// The card an arrow key moves the selection to: the nearest centre ahead of `from` in `direction`, sideways distance
    /// counting double, so ↓ from a card picks the one below rather than one far to the side. Nil when nothing lies that way.
    public static func neighbour(of from: CGPoint, toward direction: CGVector, among cards: [(id: String, center: CGPoint)]) -> String? {
        cards.compactMap { c -> (id: String, cost: CGFloat)? in
            let d = CGVector(dx: c.center.x - from.x, dy: c.center.y - from.y)
            let along = d.dx * direction.dx + d.dy * direction.dy
            guard along > 1 else { return nil }
            return (c.id, along + 2 * abs(d.dx * direction.dy - d.dy * direction.dx))
        }
        .min { $0.cost < $1.cost }?.id
    }
}
