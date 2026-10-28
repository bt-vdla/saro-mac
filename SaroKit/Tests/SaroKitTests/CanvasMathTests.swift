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
