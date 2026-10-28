import SaroKit
import SwiftUI

/// Every day of the lens as a tile (lensScene.ts and LensView.tsx's labels): drawn in one Canvas, only what is on
/// screen, smeared along its velocity while it moves fast. Underneath sits a real grid of days for VoiceOver.
struct LensGrid: View {
    let lens: LensState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    @Namespace private var rotor

    static let kinds: [EntryKind] = [.moment, .voice, .still, .reflection, .music]

    var body: some View {
        let smear = lens.smear
        Canvas { ctx, _ in draw(&ctx) }
            .layerEffect(ShaderLibrary.lensSmear(.float2(smear)), maxSampleOffset: CGSize(width: 6, height: 6),
                         isEnabled: smear != .zero && !reduceMotion)
            // Rows outside the free band fade into the ground under the header and the footer over 48 pt; a tile flying to
            // cover the window isn't cut by it.
            .mask {
                let vp = lens.viewport, h = max(1, vp.height), f = lens.flightShown
                LinearGradient(stops: [.init(color: .black.opacity(f), location: 0),
                                       .init(color: .black.opacity(f), location: max(0, vp.top - 48) / h),
                                       .init(color: .black, location: vp.top / h),
                                       .init(color: .black, location: (h - vp.bottom) / h),
                                       .init(color: .black.opacity(f), location: min(h, h - vp.bottom + 48) / h),
                                       .init(color: .black.opacity(f), location: 1)], startPoint: .top, endPoint: .bottom)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(LensHeader.title(lens))
            .accessibilityChildren { LensAccessibilityGrid(lens: lens, rotor: rotor) }
            .accessibilityRotor("Months") {
                ForEach(lens.cal.blocks.indices, id: \.self) { m in
                    AccessibilityRotorEntry(Text(Self.monthName(lens.cal, m)), id: m, in: rotor)
                }
            }
    }

    private static func smooth01(_ t: CGFloat) -> CGFloat {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    static func monthName(_ cal: LensCalendar, _ m: Int) -> String {
        cal.days[cal.blocks[m].firstDay].date.formatted(.dateTime.month(.wide).year())
    }

    private func draw(_ ctx: inout GraphicsContext) {
        let cal = lens.cal, t = lens.blocks, vp = lens.viewport
        guard t.count == cal.blocks.count, !cal.days.isEmpty else { return }
        let night = scheme == .dark, plain = reduceTransparency || contrast == .increased
        let now = Date.now
        let focusS = t[cal.days[lens.focus].block].scale
        let labelSize = min(10.5 * PrefsStore.shared.textScale, 13)
        let weekDetail = focusS >= 128
        let dayDip = Self.smooth01(abs(focusS - 128) / 14)
        for (m, b) in cal.blocks.enumerated() {
            let s = t[m].scale
            let blockRect = CGRect(x: t[m].x, y: t[m].y, width: LensMath.blockW * s, height: b.height * s)
            guard blockRect.maxX > 0, blockRect.minX < vp.width, blockRect.maxY > -40, blockRect.minY < vp.height else { continue }
            let r = min(14, max(1.5, s * 0.085))
            let labels = Self.smooth01((s - 46) / 16)
            for i in b.firstDay..<(b.firstDay + b.dayCount) where i != lens.hidden {
                let d = cal.days[i]
                let rect = CGRect(x: t[m].x + CGFloat(d.col) * LensMath.pitch * s, y: t[m].y + CGFloat(d.row) * LensMath.pitch * s, width: s, height: s)
                guard rect.maxX > 0, rect.minX < vp.width, rect.maxY > 0, rect.minY < vp.height else { continue }
                // The same emphasis for tile and label: its month, and at week level its row.
                let row = 1 - 0.6 * Self.smooth01((abs(rect.midY - lens.geo.cy) - 0.62 * s) / (0.68 * s))
                let e = t[m].emphasis
                let alpha = e + (min(e, row) - e) * lens.rowBand
                guard alpha > 0.01 else { continue }
                var tile = ctx
                tile.opacity = alpha
                let shape = Path(roundedRect: rect, cornerRadius: r, style: .continuous)
                let summary = lens.summaries[i]
                let total = summary?.total ?? 0
                let fadeIn = lens.arrived[i].map { Self.smooth01(now.timeIntervalSince($0) / 0.24) } ?? 1
                tile.fill(shape, with: .color(total > 0 ? Tok.surface : Tok.bg))
                tile.fill(shape, with: .color(Tok.ink.opacity(total > 0 ? 0.075 : 0.045)))
                let mood = summary?.mood.map(MoodPalette.color)
                if let frame = lens.frames[i] {
                    var clip = tile
                    clip.clip(to: shape)
                    clip.opacity = alpha * fadeIn
                    clip.draw(Image(decorative: frame, scale: 1), in: Self.cover(CGSize(width: frame.width, height: frame.height), rect))
                    if let mood, !plain {
                        clip.fill(shape, with: .linearGradient(Gradient(stops: [.init(color: mood.opacity(0.18), location: 0.25),
                                                                               .init(color: mood.opacity(0.4), location: 1)]),
                                                               startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                    }
                } else if let mood {
                    tile.fill(shape, with: .color(mood.opacity((night ? 0.3 : 0.62) * fadeIn)))
                }
                if lens.hover == i { tile.fill(shape, with: .color(.white.opacity(0.05))) }
                tile.stroke(shape, with: .color(Tok.ink.opacity(0.08)), lineWidth: 1 / displayScale)
                if i == lens.todayIndex {
                    let dot = min(6, max(3, s * 0.05)), inset = max(3, s * 0.07)
                    tile.fill(Path(ellipseIn: CGRect(x: rect.maxX - inset - dot, y: rect.minY + inset, width: dot, height: dot)), with: .color(Tok.sage))
                }
                if lens.focusVisible && i == lens.focus {
                    ctx.stroke(Path(roundedRect: rect.insetBy(dx: -4, dy: -4), cornerRadius: r + 4, style: .continuous), with: .color(Tok.sage), lineWidth: 2)
                }
                guard labels > 0.02 else { continue }
                var label = ctx
                label.opacity = alpha * labels * dayDip
                let inset = max(4, s * 0.055)
                let framed = lens.frames[i] != nil
                let date = Text(weekDetail ? d.date.formatted(.dateTime.weekday(.abbreviated)).uppercased() + " \(d.dayOfMonth)" : "\(d.dayOfMonth)")
                    .font(Typo.mono(labelSize / PrefsStore.shared.textScale, i == lens.todayIndex ? .semibold : .medium))
                    .foregroundStyle(i == lens.todayIndex ? Tok.sage : total == 0 ? Tok.ink3 : Tok.ink)
                chip(&label, label.resolve(date), at: CGPoint(x: rect.minX + inset, y: rect.minY + inset), anchor: .topLeading, framed: framed)
                guard let summary, total > 0 else { continue }
                var count = Text("\(total)")
                if weekDetail {
                    let dots = Self.kinds.filter { (summary.counts[$0] ?? 0) > 0 }.map { Text(Image(systemName: "circle.fill")).font(.system(size: 5)).foregroundStyle($0.tint) }
                    let gap = Text(" ").font(.system(size: 3))
                    count = Text("\(dots.reduce(Text("")) { Text("\($0)\($1)\(gap)") }) \(count)")
                }
                chip(&label, label.resolve(count.font(Typo.mono(labelSize / PrefsStore.shared.textScale)).foregroundStyle(Tok.ink).monospacedDigit()),
                     at: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset), anchor: .bottomTrailing, framed: framed)
            }
            // Month names above each block: "September 2026", or "Sep" once tiles are small ("Jan 2026" in January).
            let monthDip = Self.smooth01(abs(focusS - 64) / 8)
            let y = t[m].y - min(LensMath.labelH * s * 0.62, 30) - 11
            let a = t[m].emphasis * monthDip
            if a > 0.02, y > -14, y < vp.height {
                let first = cal.days[b.firstDay].date
                let name = focusS < 64
                    ? (m == 0 || b.month == 1 ? first.formatted(.dateTime.month(.abbreviated).year()) : first.formatted(.dateTime.month(.abbreviated)))
                    : first.formatted(.dateTime.month(.wide).year())
                var month = ctx
                month.opacity = a
                month.draw(Text(name.uppercased()).font(Typo.mono(11)).tracking(0.66).foregroundStyle(Tok.ink2), at: CGPoint(x: t[m].x, y: y), anchor: .topLeading)
            }
        }
    }

    /// A label on its own, or on a surface chip with a small shadow when it sits on a picture.
    private func chip(_ ctx: inout GraphicsContext, _ text: GraphicsContext.ResolvedText, at p: CGPoint, anchor: UnitPoint, framed: Bool) {
        let size = text.measure(in: CGSize(width: 400, height: 40))
        let box = CGRect(x: p.x - anchor.x * (size.width + 10), y: p.y - anchor.y * (size.height + 6), width: size.width + 10, height: size.height + 6)
        if framed {
            var shadow = ctx
            shadow.addFilter(.shadow(color: Tok.shadow.opacity(0.14), radius: 1, y: 1))
            shadow.fill(Path(roundedRect: box, cornerRadius: 5), with: .color(reduceTransparency ? Tok.surface : Tok.surface.opacity(0.9)))
        }
        ctx.draw(text, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
    }

    /// `image` filling `rect`, cropped to it.
    private static func cover(_ image: CGSize, _ rect: CGRect) -> CGRect {
        let k = max(rect.width / max(1, image.width), rect.height / max(1, image.height))
        let size = CGSize(width: image.width * k, height: image.height * k)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
}

/// One tile as a view, for a picked day's flight into the canvas: its key frame under the mood wash, else its mood.
struct LensTile: View {
    let summary: DaySummary?
    let frame: CGImage?
    let night: Bool

    var body: some View {
        let mood = summary?.mood.map(MoodPalette.color)
        ZStack {
            Tok.surface
            if let frame {
                Image(decorative: frame, scale: 1).resizable().scaledToFill()
                if let mood { LinearGradient(stops: [.init(color: mood.opacity(0.18), location: 0.25), .init(color: mood.opacity(0.4), location: 1)], startPoint: .top, endPoint: .bottom) }
            } else if let mood {
                mood.opacity(night ? 0.3 : 0.62)
            } else {
                Tok.ink.opacity(0.075)
            }
        }
    }
}

/// The lens's days for VoiceOver: a grid with a row per week inside each month, every day a button read as "Tuesday,
/// 27 October 2026, today. 3 entries: 1 moment, 2 voice notes. Mood: calm." A held day is read without a mood.
private struct LensAccessibilityGrid: View {
    let lens: LensState
    let rotor: Namespace.ID

    var body: some View {
        VStack {
            ForEach(lens.cal.blocks.indices, id: \.self) { m in
                let b = lens.cal.blocks[m]
                VStack {
                    ForEach(0..<b.rows, id: \.self) { row in
                        HStack {
                            ForEach(days(b, row), id: \.self) { i in
                                Button(label(i)) { lens.pick(i, how: .instant) }
                                    .accessibilityAddTraits(i == lens.selectedIndex ? .isSelected : [])
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Week of \(lens.cal.days[days(b, row).first ?? b.firstDay].date.formatted(.dateTime.day().month(.wide)))")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(LensGrid.monthName(lens.cal, m))
                .accessibilityRotorEntry(id: m, in: rotor)
            }
        }
    }

    private func days(_ b: LensCalendar.Block, _ row: Int) -> [Int] {
        (0..<7).compactMap { c in
            let date = row * 7 + c - b.offset
            return date >= 0 && date < b.dayCount ? b.firstDay + date : nil
        }
    }

    private func label(_ i: Int) -> String {
        let d = lens.cal.days[i]
        let head = d.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()) + (i == lens.todayIndex ? ", today" : "")
        guard let s = lens.summaries[i], s.total > 0 else { return "\(head). No entries." }
        // The canvas's own nouns: "1 moment, 2 writings".
        let parts = LensGrid.kinds.compactMap { k in s.counts[k].flatMap { $0 > 0 ? "\($0) \(k.noun.lowercased())\($0 == 1 ? "" : "s")" : nil } }
        let mood = s.mood.map { " Mood: \($0.rawValue.lowercased())." } ?? ""
        return "\(head). \(s.total) \(s.total == 1 ? "entry" : "entries"): \(parts.joined(separator: ", ")).\(mood)"
    }
}
