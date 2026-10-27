import CoreGraphics
import Foundation

/// Placement and arrangement on the day canvas. World units are points at zoom 1; a position is a card's centre.
public enum CanvasMath {
    public static let cardWidth: CGFloat = 248
    static let gap: CGFloat = 28
    static let origin = CGPoint(x: 190, y: 230)
    static let columns = 3

    public static func cardHeight(_ kind: EntryKind) -> CGFloat {
        switch kind {
        case .moment, .still: 196
        case .voice: 132
        case .reflection, .music: 168
        }
    }

    public static func size(_ kind: EntryKind) -> CGSize { CGSize(width: cardWidth, height: cardHeight(kind)) }

    /// The first free slot in reading order (rows of `columns`) that doesn't overlap an existing card,
    /// with a small seeded jitter so the day doesn't look like a spreadsheet.
    public static func place(_ kind: EntryKind, id: String, avoiding occupied: [CGRect]) -> CGPoint {
        let cell = CGSize(width: cardWidth + gap * 2, height: 196 + gap * 2)
        for slot in 0..<400 {
            let col = slot % columns, row = slot / columns
            let j = jitter(id)
            let c = CGPoint(x: origin.x + CGFloat(col) * cell.width + j.x, y: origin.y + CGFloat(row) * cell.height + j.y)
            let rect = CGRect(center: c, size: size(kind)).insetBy(dx: -gap / 2, dy: -gap / 2)
            if !occupied.contains(where: { $0.intersects(rect) }) { return c }
        }
        return origin
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

    /// Fanned-out stack: a centred row around `center`, wrapping after `perRow`.
    public static func fan(count: Int, size: CGSize, around center: CGPoint, perRow: Int = 5) -> [CGPoint] {
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
