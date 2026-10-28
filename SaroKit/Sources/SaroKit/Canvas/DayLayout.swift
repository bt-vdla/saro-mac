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

    /// Every dropped file on its own cell of a grid centred where they were let go (Canvas.tsx, B-021): a cell is the
    /// widest card (a moment) by the tallest (a still), each plus 24, so no two cards overlap. World centres.
    public static func dropGrid(count: Int, at point: CGPoint) -> [CGPoint] {
        let cols = max(1, Int(Double(count).squareRoot().rounded(.up))), rows = (count + cols - 1) / cols
        let cell = CGSize(width: CanvasMath.size(.moment).width + 24, height: CanvasMath.size(.still).height + 24)
        return (0..<count).map { i in
            CGPoint(x: point.x + (CGFloat(i % cols) - CGFloat(cols - 1) / 2) * cell.width,
                    y: point.y + (CGFloat(i / cols) - CGFloat(rows - 1) / 2) * cell.height)
        }
    }
}
