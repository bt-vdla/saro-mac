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

    /// The nearest edge or centre alignment within `reach` on one axis: how far to move, the line it lands on, and the
    /// cards that share that line (cardGeometry.ts snaps left/centre/right and top/middle/bottom to other cards).
    public static func snap(_ mine: [CGFloat], to theirs: [(CGFloat, CGRect)], reach: CGFloat) -> (delta: CGFloat, at: CGFloat, rects: [CGRect])? {
        var pick: (delta: CGFloat, at: CGFloat, rects: [CGRect])?
        for a in mine {
            for (b, r) in theirs where abs(b - a) <= reach {
                if let p = pick, abs((b - a) - p.delta) < 0.5 {
                    pick?.rects.append(r)
                } else if pick == nil || abs(b - a) < abs(pick!.delta) {
                    pick = (b - a, b, [r])
                }
            }
        }
        return pick
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
