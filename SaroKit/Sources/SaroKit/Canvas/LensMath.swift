import CoreGraphics
import Foundation

/// Every local day from the 1st of the first month through today, as 7-column month blocks (lensLayout.ts's
/// buildCalendar). World units: a day tile is 1×1 and tiles sit `pitch` apart. Weeks start on `weekStart` (0 is Sunday;
/// the app passes Calendar.current.firstWeekday − 1, where the web hard-codes Sunday).
public struct LensCalendar: Sendable {
    public struct Day: Sendable, Hashable {
        public let key: String
        /// Noon on that local day.
        public let date: Date
        public let dayOfMonth: Int
        public let block: Int
        public let col: Int
        public let row: Int
    }

    public struct Block: Sendable, Hashable {
        public let year: Int
        public let month: Int
        public let firstDay: Int
        public let dayCount: Int
        /// The weekday column of the 1st.
        public let offset: Int
        public let rows: Int
        /// Top of the block's tiles in the column layout.
        public let columnY: CGFloat
        public var height: CGFloat { CGFloat(rows) * LensMath.pitch - (LensMath.pitch - 1) }
    }

    public let days: [Day]
    public let blocks: [Block]

    public init(from first: String, through today: String, weekStart: Int = 0) {
        let cal = Calendar(identifier: .gregorian)
        let p = { (d: String) in d.split(separator: "-").compactMap { Int($0) } }
        let (f, t) = (p(first), p(today))
        var days: [Day] = [], blocks: [Block] = []
        guard f.count == 3, t.count == 3 else { (self.days, self.blocks) = ([], []); return }
        var (y, m) = (f[0], f[1])
        var top = LensMath.labelH
        while (y, m) <= (t[0], t[1]) {
            let firstDate = cal.date(from: DateComponents(year: y, month: m, day: 1, hour: 12)) ?? .now
            let offset = (cal.component(.weekday, from: firstDate) - 1 - weekStart + 14) % 7
            let length = cal.range(of: .day, in: .month, for: firstDate)?.count ?? 30
            let count = (y, m) == (t[0], t[1]) ? min(length, t[2]) : length
            let index = blocks.count, firstDay = days.count
            for d in 1...max(1, count) where d <= count {
                let key = String(format: "%04d-%02d-%02d", y, m, d)
                let slot = offset + d - 1
                days.append(Day(key: key, date: LocalDay.date(key) ?? firstDate, dayOfMonth: d, block: index, col: slot % 7, row: slot / 7))
            }
            let rows = (offset + count - 1) / 7 + 1
            blocks.append(Block(year: y, month: m, firstDay: firstDay, dayCount: count, offset: offset, rows: rows, columnY: top))
            top += CGFloat(rows) * LensMath.pitch - (LensMath.pitch - 1) + LensMath.columnGap + LensMath.labelH
            (y, m) = m == 12 ? (y + 1, 1) : (y, m + 1)
        }
        (self.days, self.blocks) = (days, blocks)
    }

    public func index(of key: String) -> Int? {
        guard let first = days.first, let last = days.last, key >= first.key, key <= last.key else { return nil }
        return days.firstIndex { $0.key == key }
    }

    /// The first and last day of what `level` frames around `focus`: its week row, its month, or everything.
    public func unit(_ focus: Int, _ level: LensMath.Level) -> ClosedRange<Int> {
        guard !days.isEmpty else { return 0...0 }
        if level == .year { return 0...(days.count - 1) }
        let d = days[focus.clamped(0, days.count - 1)], b = blocks[d.block]
        if level == .month { return b.firstDay...(b.firstDay + b.dayCount - 1) }
        return (b.firstDay + max(0, d.row * 7 - b.offset))...(b.firstDay + min(b.dayCount - 1, d.row * 7 + 6 - b.offset))
    }
}

/// The time lens's pure geometry and physics (the web's lensLayout.ts): z is the continuous zoom, 0 week, 1 month, 2 year;
/// below 0 pulls into a day. Week and month stack the month blocks in one column; the year re-flows them into a grid.
public enum LensMath {
    public enum Level: Int, CaseIterable, Sendable {
        case week, month, year
        public var title: String {
            switch self {
            case .week: "Week"
            case .month: "Month"
            case .year: "Year"
            }
        }
    }

    public static let pitch: CGFloat = 1.1
    public static let blockW: CGFloat = 7 * pitch - (pitch - 1)
    public static let labelH: CGFloat = 1.2
    static let columnGap: CGFloat = 0.9
    static let gridGapX: CGFloat = 1.5
    static let gridGapY: CGFloat = 0.6
    static let gridBlockH: CGFloat = labelH + 6 * pitch - (pitch - 1)
    static let maxWeekTile: CGFloat = 196

    /// The window, and the room kept clear for the header and the footer.
    public struct Viewport: Sendable, Equatable {
        public var width: CGFloat, height: CGFloat, top: CGFloat, bottom: CGFloat
        public init(width: CGFloat, height: CGFloat, top: CGFloat, bottom: CGFloat) { (self.width, self.height, self.top, self.bottom) = (width, height, top, bottom) }
    }

    public struct Geometry: Sendable, Equatable {
        public let cols: Int, rows: Int
        public let weekScale: CGFloat, monthScale: CGFloat, yearScale: CGFloat
        public let gridW: CGFloat
        /// Grid-world y of the year's tiles' centre, which sits at the view centre.
        public let yearY: CGFloat
        /// The centre of the free band, in points.
        public let cx: CGFloat, cy: CGFloat
    }

    /// A month block on screen: its tiles' top-left corner, points per world unit, and how strongly it is emphasised.
    public struct Transform: Sendable, Equatable {
        public var x: CGFloat, y: CGFloat, scale: CGFloat, emphasis: CGFloat
    }

    public enum Move: Sendable { case left, right, up, down, pageUp, pageDown, home, end }

    private static func smooth(_ t: CGFloat) -> CGFloat { t * t * (3 - 2 * t) }
    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    private static func gridOrigin(_ m: Int, _ cols: Int) -> CGPoint {
        CGPoint(x: CGFloat(m % cols) * (blockW + gridGapX), y: CGFloat(m / cols) * (gridBlockH + gridGapY) + labelH)
    }

    private static func gridSize(_ cal: LensCalendar, _ cols: Int) -> (rows: Int, w: CGFloat, bottom: CGFloat) {
        let bottom = cal.blocks.enumerated().map { gridOrigin($0.offset, cols).y + $0.element.height }.max() ?? 0
        return ((cal.blocks.count + cols - 1) / cols, CGFloat(cols) * blockW + CGFloat(cols - 1) * gridGapX, bottom)
    }

    /// The scales of each level in this window: the year takes whichever column count (1–6) gives the biggest tiles.
    public static func measure(_ cal: LensCalendar, _ vp: Viewport) -> Geometry {
        let availW = vp.width - 2 * max(20, vp.width * 0.04)
        let availH = max(120, vp.height - vp.top - vp.bottom)
        var best = (cols: 1, scale: CGFloat(0))
        for cols in 1...max(1, min(6, cal.blocks.count)) {
            let g = gridSize(cal, cols)
            let scale = min(availW / g.w, availH / (g.bottom + labelH))
            if scale > best.scale { best = (cols, scale) }
        }
        let g = gridSize(cal, best.cols)
        return Geometry(cols: best.cols, rows: g.rows, weekScale: min(maxWeekTile, availW / blockW, availH * 0.42),
                        monthScale: min(availW / blockW, availH / (gridBlockH + 0.4)), yearScale: best.scale, gridW: g.w,
                        yearY: (labelH + g.bottom) / 2, cx: vp.width / 2, cy: vp.top + availH / 2)
    }

    /// Column-world centres of the tile, its week row and its month's tiles.
    private static func anchors(_ cal: LensCalendar, _ index: Int) -> (tile: CGPoint, week: CGPoint, month: CGPoint) {
        let d = cal.days[index.clamped(0, cal.days.count - 1)], b = cal.blocks[d.block]
        let rowY = b.columnY + CGFloat(d.row) * pitch + 0.5
        return (CGPoint(x: CGFloat(d.col) * pitch + 0.5, y: rowY), CGPoint(x: blockW / 2, y: rowY), CGPoint(x: blockW / 2, y: b.columnY + b.height / 2))
    }

    /// Column-world y at the view centre when framing `level` (week or month) around `focus`.
    public static func framingY(_ cal: LensCalendar, _ focus: Int, _ level: Level) -> CGFloat {
        let a = anchors(cal, focus)
        return level == .week ? a.week.y : a.month.y
    }

    /// Every block's transform at zoom `z` and vertical `pan` (column-world units, week and month only), and how strongly
    /// week rows are emphasised (1 at week level, 0 from month up).
    public static func transforms(_ cal: LensCalendar, _ geo: Geometry, focus: Int, z: CGFloat, pan: CGFloat) -> (blocks: [Transform], rowBand: CGFloat) {
        guard !cal.days.isEmpty else { return ([], 0) }
        let a = anchors(cal, focus)
        // A month's emphasis follows whichever month is under the view centre, fading across the gap between months.
        let monthEmphasis = { (b: LensCalendar.Block, camY: CGFloat) -> CGFloat in
            let d = max(0, b.columnY - labelH - camY, camY - (b.columnY + b.height))
            return 1 - 0.6 * smooth((d / (columnGap + labelH)).clamped(0, 1))
        }
        if z <= 1 {
            var s: CGFloat, camX = a.week.x, tileY = geo.cy
            if z <= 0 {
                // Pulling in past the week grows the focus tile where it sits.
                s = geo.weekScale * exp(-z * 1.1)
                camX = a.tile.x - (a.tile.x - a.week.x) * (geo.weekScale / s)
            } else {
                // Week to month: the column stays centred and the focus row eases from the centre to its place in the month.
                s = exp(lerp(log(geo.weekScale), log(geo.monthScale), z))
                tileY = geo.cy + (a.tile.y - a.month.y) * geo.monthScale * z
            }
            let camY = a.tile.y - (tileY - geo.cy) / s + pan
            let out = cal.blocks.map { b in
                Transform(x: (0 - camX) * s + geo.cx, y: (b.columnY - camY) * s + geo.cy, scale: s, emphasis: monthEmphasis(b, camY))
            }
            return (out, 1 - z.clamped(0, 1))
        }
        let yearS = geo.yearScale * (z > 2 ? exp(-(z - 2) * 1.1) : 1)
        let gx = geo.gridW / 2, gy = geo.yearY
        if z >= 2 {
            return (cal.blocks.indices.map { m in
                let g = gridOrigin(m, geo.cols)
                return Transform(x: (g.x - gx) * yearS + geo.cx, y: (g.y - gy) * yearS + geo.cy, scale: yearS, emphasis: 1)
            }, 0)
        }
        // Month to year: blocks leave the column for their grid cells, further months later; ones that were off screen start
        // just past the edge. Progress is linear in z, so the blocks stay under the fingers.
        let t = z - 1, sA = geo.monthScale, camY = a.month.y + pan
        let focusBlock = cal.days[focus.clamped(0, cal.days.count - 1)].block
        return (cal.blocks.enumerated().map { m, b in
            let h = b.height
            let delay = min(0.4, CGFloat(abs(m - focusBlock)) * 0.045)
            let e = ((t - delay) / (1 - delay)).clamped(0, 1)
            let ay = ((b.columnY + h / 2 - camY) * sA + geo.cy).clamped(-geo.cy * 1.2, geo.cy * 3.2)
            let g = gridOrigin(m, geo.cols)
            let bx = (g.x + blockW / 2 - gx) * geo.yearScale + geo.cx, by = (g.y + h / 2 - gy) * geo.yearScale + geo.cy
            let s = exp(lerp(log(sA), log(geo.yearScale), e))
            return Transform(x: lerp(geo.cx, bx, e) - blockW / 2 * s, y: lerp(ay, by, e) - h / 2 * s, scale: s,
                             emphasis: lerp(monthEmphasis(b, camY), 1, e))
        }, 0)
    }

    public struct Flight: Sendable, Equatable {
        /// The resting centre of the flight tile, and how much it must grow to cover the window.
        public let x: CGFloat, y: CGFloat, cover: CGFloat
    }

    /// The entry and exit flight at `f` (0 at rest, 1 the tile covers the window): the whole lens zooms about one tile,
    /// whose centre travels to the window's centre. Returns the tile it flew about, so the day can take the inverse path.
    @discardableResult
    public static func applyFlight(_ cal: LensCalendar, _ t: inout [Transform], f: CGFloat, index: Int, width: CGFloat, height: CGFloat) -> Flight? {
        guard let r = tileRect(cal, t, index), r.width > 0 else { return nil }
        let flight = Flight(x: r.midX, y: r.midY, cover: max(width, height) / r.width)
        guard f > 0 else { return flight }
        let k = pow(flight.cover, f), tx = lerp(flight.x, width / 2, f), ty = lerp(flight.y, height / 2, f)
        for m in t.indices {
            t[m].x = (t[m].x - flight.x) * k + tx
            t[m].y = (t[m].y - flight.y) * k + ty
            t[m].scale *= k
        }
        return flight
    }

    /// Zoom as the log of the focus tile's size, so pinches and wheels scale the tiles 1:1: piecewise linear in ln(scale)
    /// through the three levels, and on past them at 1.1 per e-fold, where rubber-banding takes over.
    public static func zOfLog(_ geo: Geometry, _ l: CGFloat) -> CGFloat {
        let (lw, lm, ly) = (log(geo.weekScale), log(geo.monthScale), log(geo.yearScale))
        if l >= lw { return -(l - lw) / 1.1 }
        if l >= lm { return (lw - l) / (lw - lm) }
        if l >= ly { return 1 + (lm - l) / (lm - ly) }
        return 2 + (ly - l) / 1.1
    }

    public static func logOfZ(_ geo: Geometry, _ z: CGFloat) -> CGFloat {
        let (lw, lm, ly) = (log(geo.weekScale), log(geo.monthScale), log(geo.yearScale))
        if z <= 0 { return lw - z * 1.1 }
        if z <= 1 { return lw - z * (lw - lm) }
        if z <= 2 { return lm - (z - 1) * (lm - ly) }
        return ly - (z - 2) * 1.1
    }

    /// A day's tile on screen under the given transforms.
    public static func tileRect(_ cal: LensCalendar, _ t: [Transform], _ index: Int) -> CGRect? {
        guard cal.days.indices.contains(index) else { return nil }
        let d = cal.days[index], b = t[d.block]
        return CGRect(x: b.x + CGFloat(d.col) * pitch * b.scale, y: b.y + CGFloat(d.row) * pitch * b.scale, width: b.scale, height: b.scale)
    }

    /// The day whose tile is under a point, or nil. `slack` (points) widens each tile to catch taps in the gutters.
    public static func tileAt(_ cal: LensCalendar, _ t: [Transform], _ p: CGPoint, slack: CGFloat = 0) -> Int? {
        for m in cal.blocks.indices.reversed() {
            let b = cal.blocks[m], s = t[m].scale, k = slack / s
            let lx = (p.x - t[m].x) / s, ly = (p.y - t[m].y) / s
            if lx < -k || ly < -k || lx > blockW + k || ly > b.height + k { continue }
            let col = Int(floor((lx + (pitch - 1) / 2) / pitch)).clamped(0, 6)
            let row = Int(floor((ly + (pitch - 1) / 2) / pitch)).clamped(0, b.rows - 1)
            let inTile = abs(lx - CGFloat(col) * pitch - 0.5) <= 0.5 + k && abs(ly - CGFloat(row) * pitch - 0.5) <= 0.5 + k
            let date = row * 7 + col - b.offset
            if inTile && date >= 0 && date < b.dayCount { return b.firstDay + date }
        }
        return nil
    }

    /// Where a key moves the focus: a day, a week, a month (same day of the month, clamped), or the ends of the week row.
    public static func move(_ cal: LensCalendar, _ index: Int, _ key: Move) -> Int {
        let last = cal.days.count - 1, d = cal.days[index], b = cal.blocks[d.block]
        let month = { (step: Int) -> Int in
            let target = cal.blocks[(d.block + step).clamped(0, cal.blocks.count - 1)]
            return target.firstDay + min(d.dayOfMonth, target.dayCount) - 1
        }
        switch key {
        case .left: return (index - 1).clamped(0, last)
        case .right: return (index + 1).clamped(0, last)
        case .up: return (index - 7).clamped(0, last)
        case .down: return (index + 7).clamped(0, last)
        case .pageUp: return month(-1)
        case .pageDown: return month(1)
        case .home: return b.firstDay + max(0, d.row * 7 - b.offset)
        case .end: return b.firstDay + min(b.dayCount - 1, d.row * 7 + 6 - b.offset)
        }
    }

    /// Where a vertical pan comes to rest: the week row or month nearest `worldY`, keeping the weekday or day of the month.
    public static func snapFocus(_ cal: LensCalendar, _ focus: Int, _ level: Level, worldY: CGFloat) -> Int {
        let d = cal.days[focus]
        var best = focus, bestD = CGFloat.infinity
        if level == .month {
            for (m, b) in cal.blocks.enumerated() {
                let dist = abs(framingY(cal, b.firstDay, .month) - worldY)
                if dist >= bestD { continue }
                bestD = dist
                best = m == d.block ? focus : b.firstDay + min(d.dayOfMonth, b.dayCount) - 1
            }
            return best
        }
        for b in cal.blocks {
            for row in 0..<b.rows {
                let dist = abs(b.columnY + CGFloat(row) * pitch + 0.5 - worldY)
                if dist >= bestD { continue }
                bestD = dist
                let first = max(0, row * 7 - b.offset), lastInRow = min(b.dayCount - 1, row * 7 + 6 - b.offset)
                best = b.firstDay + (row * 7 + d.col - b.offset).clamped(first, lastInRow)
            }
        }
        return best
    }

    // MARK: Physics (Apple's "Designing Fluid Interfaces")

    /// The resting distance of a flick at `velocity` units/s, decelerating by `rate` a millisecond.
    public static func project(_ velocity: CGFloat, rate: CGFloat = 0.998) -> CGFloat { velocity / 1000 * rate / (1 - rate) }

    /// Progressive resistance past a boundary: it follows less the further it is pulled, never more than `dimension`.
    public static func rubberband(_ overshoot: CGFloat, _ dimension: CGFloat, _ c: CGFloat = 0.55) -> CGFloat {
        let x = abs(overshoot)
        return (overshoot < 0 ? -1 : 1) * x * dimension * c / (dimension + c * x)
    }

    public static func unrubberband(_ shown: CGFloat, _ dimension: CGFloat, _ c: CGFloat = 0.55) -> CGFloat {
        let y = min(abs(shown), dimension * 0.999)
        return (shown < 0 ? -1 : 1) * y * dimension / (c * (dimension - y))
    }

    /// Below the week the zoom pulls into the day; past the year it resists.
    public static func zShown(_ raw: CGFloat) -> CGFloat { raw < 0 ? rubberband(raw, 1.2, 0.7) : raw > 2 ? 2 + rubberband(raw - 2, 1) : raw }
    public static func zRaw(_ shown: CGFloat) -> CGFloat { shown < 0 ? unrubberband(shown, 1.2, 0.7) : shown > 2 ? 2 + unrubberband(shown - 2, 1) : shown }

    /// A spring's position and velocity.
    public struct Spring: Sendable, Equatable {
        public var x: CGFloat, v: CGFloat = 0
        public init(_ x: CGFloat, v: CGFloat = 0) { (self.x, self.v) = (x, v) }

        /// Advances toward `target` (response in s; damping 1 never overshoots). True once settled.
        public mutating func step(to target: CGFloat, dt: CGFloat, response: CGFloat = 0.4, damping: CGFloat = 1, epsilon: CGFloat = 0.0005) -> Bool {
            let k = pow(2 * .pi / response, 2), c = 4 * .pi * damping / response
            let steps = max(1, Int(ceil(dt * 240))), h = dt / CGFloat(steps)
            for _ in 0..<steps {
                v += (-k * (x - target) - c * v) * h
                x += v * h
            }
            guard abs(x - target) < epsilon && abs(v) < epsilon * 10 else { return false }
            (x, v) = (target, 0)
            return true
        }
    }

    /// Where a zoom gesture settles: the projected z rounded to a level, but at least one level on once the gesture
    /// clearly moved; nil means it pulled far enough into the focused day to open it.
    public static func settle(z: CGFloat, velocity: CGFloat, from start: Int) -> Int? {
        let projected = z + project(velocity, rate: 0.994)
        if projected < -0.45 { return nil }
        var target = Int(projected.rounded()).clamped(0, 2)
        let moved = z - CGFloat(start)
        if target == start && abs(moved) > 0.18 { target = (start + (moved > 0 ? 1 : -1)).clamped(0, 2) }
        return target
    }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}
