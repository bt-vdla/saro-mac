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
    let theirs = [(other.minX, other), (other.midX, other), (other.maxX, other)]
    // A card whose left edge is 4 pt right of the other's left edge snaps 4 pt left.
    let s = CanvasMath.snap([104, 204, 304], to: theirs, reach: 6)
    #expect(s?.delta == -4 && s?.at == 100)
    // Nothing within reach: no snap.
    #expect(CanvasMath.snap([120, 220, 320], to: theirs, reach: 6) == nil)
}
