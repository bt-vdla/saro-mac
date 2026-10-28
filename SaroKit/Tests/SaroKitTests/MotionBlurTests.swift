import CoreGraphics
import Testing
@testable import SaroKit

/// Moves a point at `speed` pt/ms along x (and `dy` along y) for `frames` 16 ms frames; returns the last spread.
private func fly(_ blur: inout MotionBlur, speed: Double, dy: Double = 0, frames: Int, from t0: Double = 0, coverage: Double = 0.05) -> CGSize {
    var out = CGSize.zero
    for i in 0..<frames {
        let ms = Double(i) * 16
        out = blur.track(CGPoint(x: speed * ms, y: dy * ms), at: t0 + ms / 1000, coverage: coverage)
    }
    return out
}

@Test func motionBlurFollowsTheWebCurve() {
    var slow = MotionBlur()
    #expect(fly(&slow, speed: 0.5, frames: 20) == .zero)

    var steady = MotionBlur()
    let s = fly(&steady, speed: 2.6, frames: 20)
    #expect(abs(s.width - (2.6 - 0.6) * 2.2) < 0.01)
    #expect(s.height == 0)

    var fast = MotionBlur()
    let f = fly(&fast, speed: 4, dy: -3, frames: 20)
    #expect(f.width == 6)
    #expect(abs(f.height - (3 - 0.6) * 2.2) < 0.01)
}

@Test func motionBlurFadesOnBigSurfaces() {
    var third = MotionBlur(), twoFifths = MotionBlur(), half = MotionBlur()
    #expect(fly(&third, speed: 4, frames: 20, coverage: 0.3).width == 6)
    #expect(abs(fly(&twoFifths, speed: 4, frames: 20, coverage: 0.4).width - 3) < 0.01)
    #expect(fly(&half, speed: 4, frames: 20, coverage: 0.5) == .zero)
}

@Test func motionBlurComesToRestCrisp() {
    var blur = MotionBlur()
    #expect(fly(&blur, speed: 4, frames: 20).width == 6)
    let stop = CGPoint(x: 4 * 19 * 16, y: 0)
    // Still for under 40 ms keeps the last velocity, as a held card between pointer moves.
    #expect(blur.track(stop, at: 0.304 + 0.016, coverage: 0.05).width == 6)
    // Then it decays over 60 ms and drops to none.
    var last = CGSize(width: 6, height: 0)
    var at = 0.304 + 0.048
    while last != .zero && at < 1 {
        let next = blur.track(stop, at: at, coverage: 0.05)
        #expect(next.width < last.width)
        last = next
        at += 0.016
    }
    #expect(last == .zero)
    #expect(at < 0.304 + 0.048 + 0.4)
}
