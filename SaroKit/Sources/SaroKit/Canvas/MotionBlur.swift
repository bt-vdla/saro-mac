import CoreGraphics
import Foundation

/// Directional motion blur for things in flight (lib/motionBlur.ts): a Gaussian spread along each axis taken from where
/// the thing is drawn, frame to frame. It starts above 0.6 pt/ms, grows 2.2 pt per pt/ms past that up to 6 pt and decays
/// over 60 ms; a thing covering 30-50% of the viewport fades it out, and one that stops comes to rest crisp.
public struct MotionBlur: Sendable {
    static let start = 0.6, gain = 2.2, cap = 6.0, decayMs = 60.0
    /// A drawn position that hasn't moved for this long is still (useCardGesture.ts STILL_MS).
    static let stillMs = 40.0

    private var sx = 0.0, sy = 0.0
    private var last: Double?
    private var moved: (at: Double, p: CGPoint)?
    /// Screen points per ms, smoothed as the web smooths a held card's pointer.
    private var vx = 0.0, vy = 0.0

    public init() {}

    /// Feeds where the thing is drawn (screen points) at `now` (seconds) and the share of the viewport it covers; returns
    /// the spread along x and y in screen points, an axis under 0.15 pt reading as none.
    public mutating func track(_ p: CGPoint, at now: Double, coverage: Double) -> CGSize {
        if let m = moved {
            let ms = (now - m.at) * 1000
            if p != m.p {
                let dt = max(ms, 4)
                vx = vx * 0.4 + Double(p.x - m.p.x) / dt * 0.6
                vy = vy * 0.4 + Double(p.y - m.p.y) / dt * 0.6
                moved = (now, p)
            } else if ms >= Self.stillMs {
                vx = 0
                vy = 0
            }
        } else {
            moved = (now, p)
        }

        let dt = last.map { min(100, (now - $0) * 1000) } ?? 16
        last = now
        let decay = exp(-dt / Self.decayMs)
        let t = min(max((coverage - 0.3) / 0.2, 0), 1)
        let damp = 1 - t * t * (3 - 2 * t)
        sx = max(Self.target(vx) * damp, sx * decay)
        sy = max(Self.target(vy) * damp, sy * decay)
        if sx < 0.15 && sy < 0.15 {
            sx = 0
            sy = 0
            last = nil
            return .zero
        }
        return CGSize(width: sx < 0.15 ? 0 : sx, height: sy < 0.15 ? 0 : sy)
    }

    static func target(_ v: Double) -> Double { min(cap, max(0, abs(v) - start) * gain) }
}
