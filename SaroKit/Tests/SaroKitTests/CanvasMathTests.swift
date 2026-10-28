import CoreGraphics
import Testing
@testable import SaroKit

@Test func placementNeverOverlaps() {
    var rects: [CGRect] = []
    for i in 0..<30 {
        let kind: EntryKind = [.moment, .voice, .reflection, .still][i % 4]
        let c = CanvasMath.place(kind, id: "e\(i)", avoiding: rects)
        let r = CGRect(center: c, size: CanvasMath.size(kind))
        #expect(!rects.contains { $0.intersects(r) })
        rects.append(r)
    }
}

@Test func gridIsBottomAlignedAndOrdered() {
    let out = CanvasMath.grid([
        (id: "b", center: CGPoint(x: 500, y: 100), size: CGSize(width: 248, height: 132)),
        (id: "a", center: CGPoint(x: 100, y: 300), size: CGSize(width: 248, height: 196)),
    ])
    let a = out["a"]!, b = out["b"]!
    #expect(a.x < b.x)
    #expect(abs((a.y + 98) - (b.y + 66)) < 0.001)
    #expect(abs(b.x - a.x - (248 + CanvasMath.gap)) < 0.001)
}

@Test func fanIsCentred() {
    let pts = CanvasMath.fan(count: 3, size: CGSize(width: 100, height: 50), around: CGPoint(x: 0, y: 0))
    #expect(pts.count == 3)
    #expect(abs(pts.map(\.x).reduce(0, +)) < 0.001)
    #expect(pts.allSatisfy { $0.y == 0 })
}

@Test func snapPicksTheNearestAlignment() {
    let other = CGRect(x: 100, y: 0, width: 200, height: 100)
    let theirs = CanvasMath.cardLines([other], axis: 0)
    #expect(theirs.map(\.pos) == [100, 200, 300])
    // A card whose left edge is 4 pt right of the other's left edge snaps 4 pt left.
    let s = CanvasMath.snap([104, 204, 304], to: theirs, reach: 6)
    #expect(s?.delta == -4 && s?.at == 100 && s?.rects == [other])
    // Nothing within reach: no snap.
    #expect(CanvasMath.snap([120, 220, 320], to: theirs, reach: 6) == nil)
}

// Reference values from the web's cardGeometry.ts (node), so the grid lands where it does there.
@Test func rhythmMatchesTheWeb() {
    #expect(abs(CanvasMath.hash(0, 0, 0, 0) - 0.8140980841126293) < 1e-12)
    #expect(abs(CanvasMath.hash(-3, 1, -2, 9) - 0.9983757685404271) < 1e-12)
    #expect([0.2, 0.5, 0.69, 1, 1.4, 3].map { CanvasMath.rhythmLevel(zoom: $0) } == [2, 1, 0, 0, -1, -2])
    let lines = CanvasMath.rhythmLines(axis: 0, from: -300, to: 500, level: 0)
    #expect(lines.map(\.pos) == [-296, -272, -232, -128, -64, -24, 0, 24, 128, 192, 232, 256, 320, 360, 464])
    #expect(abs(lines[0].seed - 0.16281321411952376) < 1e-12)
    #expect(CanvasMath.rhythmLines(axis: 1, from: 0, to: 1000, level: 1).map(\.pos) == [0, 208, 336, 384, 464, 592, 640, 848, 928, 976])
    #expect(CanvasMath.rhythmLines(axis: 0, from: -100, to: 100, level: -2).map(\.pos)
        == [-100, -84, -58, -32, -16, -10, 0, 26, 36, 52, 58, 68, 94, 100])
}

@Test func rhythmCatchesOnlyCloseEdgesAndCardsWin() {
    let snap = { (mine: [CGFloat], cards: [CanvasMath.GuideLine]) in
        CanvasMath.snap(mine, cards: cards, reach: 6, axis: 0, level: 0, rhythmReach: 3)
    }
    // The rhythm has a line at 128: a right edge 2 pt short lands on it, with no card to draw the guide to.
    let r = snap([-82, 23, 126], [])
    #expect(r?.delta == 2 && r?.at == 128 && r?.rects.isEmpty == true)
    // 4 pt off is too far for the rhythm, and a centre near a rhythm line doesn't count.
    #expect(snap([-60, 36, 132], []) == nil)
    #expect(snap([-77, 23, 123], []) == nil)
    // Another card's edge within 6 pt wins over a nearer rhythm line.
    let other = CGRect(x: 131, y: 0, width: 100, height: 100)
    #expect(snap([-82, 23, 126], CanvasMath.cardLines([other], axis: 0))?.at == 131)
}

@Test func flightGrowsEvenlyOutOfItsButton() {
    let button = CGRect(x: 100, y: 700, width: 68, height: 52), frame = CGRect(x: 24, y: 24, width: 1272, height: 812)
    #expect(CanvasMath.flightBox(from: button, to: frame, v: 0) == button)
    let end = CanvasMath.flightBox(from: button, to: frame, v: 1)
    #expect(abs(end.minX - 24) < 1e-9 && abs(end.minY - 24) < 1e-9 && abs(end.width - 1272) < 1e-9 && abs(end.height - 812) < 1e-9)
    // Halfway the size is the geometric mean and the centre the midpoint.
    let mid = CanvasMath.flightBox(from: button, to: frame, v: 0.5)
    #expect(abs(mid.width - (68 * 1272).squareRoot()) < 1e-9 && abs(mid.height - (52 * 812).squareRoot()) < 1e-9)
    #expect(abs(mid.midX - (button.midX + frame.midX) / 2) < 1e-9 && abs(mid.midY - (button.midY + frame.midY) / 2) < 1e-9)
}

@Test func flightCrossfadesAsTheWebDoes() {
    #expect(CanvasMath.flightFades(0) == (1, 0))
    #expect(CanvasMath.flightFades(0.05).leaving == 1)
    #expect(abs(CanvasMath.flightFades(0.3).leaving - 0.5) < 1e-12)
    #expect(CanvasMath.flightFades(0.35).arriving == 1)
    #expect(CanvasMath.flightFades(0.55).leaving == 0)
    #expect(CanvasMath.flightFades(1) == (0, 1))
}

@Test func trashedCardIsAbsorbedByTheToast() {
    #expect(CanvasMath.absorbed(0) == 1)
    #expect(CanvasMath.absorbed(0.3) == 1)
    #expect(abs(CanvasMath.absorbed(0.6) - 0.5) < 1e-12)
    #expect(CanvasMath.absorbed(0.9) == 0)
    #expect(CanvasMath.absorbed(1) == 0)
}

@Test func shimmerSweepsAsTheWebKeyframesDo() {
    let w: CGFloat = 220
    let period = 2 * w
    for p in stride(from: 0.0, through: 1, by: 0.05) {
        let start = CanvasMath.shimmerOffset(width: w, progress: p)
        // CSS puts the repeating image's origin at -2w + 4w·p; each point of the block must show the same place in it.
        let css = -2 * w + 4 * w * p
        for x in stride(from: 0, through: w, by: w / 4) {
            #expect(x - start >= 0 && x - start <= 2 * period)
            let drawn = (x - start).truncatingRemainder(dividingBy: period)
            let web = ((x - css).truncatingRemainder(dividingBy: period) + period).truncatingRemainder(dividingBy: period)
            #expect(min(abs(drawn - web), period - abs(drawn - web)) < 1e-6)
        }
    }
}

// Reference boxes from the web's resizeRect (node), x/y the top-left as there.
@Test func resizeMatchesTheWeb() throws {
    let video = try #require(CanvasMath.resizeSpec(.moment)), text = try #require(CanvasMath.resizeSpec(.reflection))
    let m = CGRect(x: 100, y: 50, width: 420, height: 284), r = CGRect(x: -20, y: 10, width: 360, height: 212)
    func same(_ a: CGRect, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Bool {
        abs(a.minX - x) < 1e-9 && abs(a.minY - y) < 1e-9 && abs(a.width - w) < 1e-9 && abs(a.height - h) < 1e-9
    }
    let resize = { (s: CGRect, h: CanvasMath.Handle, dx: CGFloat, dy: CGFloat, spec: CanvasMath.ResizeSpec) in
        CanvasMath.resize(s, h, by: CGSize(width: dx, height: dy), spec: spec)
    }
    #expect(same(resize(m, .se, 100, 10, video), 100, 50, 493.263413419644, 333.5400224075688))
    #expect(same(resize(m, .nw, -60, -20, video), 49.54562429976346, 15.883231669363852, 470.45437570023654, 318.11676833063615))
    #expect(same(resize(m, .e, 2000, 0, video), 100, 50, 960, 649.1428571428571))
    #expect(same(resize(m, .n, 0, 300, video), 100, 171.71428571428572, 240, 162.28571428571428))
    #expect(same(CanvasMath.resize(m, .se, by: CGSize(width: 100, height: 10), spec: video, free: true), 100, 50, 520, 294))
    #expect(same(CanvasMath.resize(m, .e, by: CGSize(width: 37, height: 0), spec: video, snapX: { ($0 / 50).rounded() * 50 }),
                 100, 50, 450, 304.2857142857143))
    #expect(same(resize(r, .w, -50, 0, text), -70, 10, 410, 212))
    #expect(same(resize(r, .sw, 500, 900, text), 80, 10, 260, 960))
    #expect(same(CanvasMath.resize(r, .n, by: CGSize(width: 0, height: -33), spec: text, snapY: { ($0 / 40).rounded() * 40 }),
                 -20, -40, 360, 262))
    #expect(CanvasMath.resizeSpec(.voice) == nil)
}

@Test func storedSizesAndContentHeights() {
    for kind in EntryKind.allCases { #expect(CanvasMath.size(kind, w: nil, h: nil) == CanvasMath.size(kind)) }
    #expect(CanvasMath.size(.moment, w: 840, h: nil) == CGSize(width: 840, height: CanvasMath.momentMediaHeight * 2 + 48))
    #expect(CanvasMath.size(.still, w: 130, h: nil) == CGSize(width: 130, height: CanvasMath.stillMediaHeight / 2 + 48))
    #expect(CanvasMath.size(.reflection, w: 500, h: nil) == CGSize(width: 500, height: 212))
    #expect(CanvasMath.size(.moment, w: 500, h: 600) == CGSize(width: 500, height: 600))
}
