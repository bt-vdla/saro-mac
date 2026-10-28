import Foundation

/// "Find your light" (light-check.ts): reads a 64×36 RGBA thumbnail of the camera frame for light, the light's
/// direction and framing. Pure; nothing is kept. Frames never leave the Mac.
public enum LightRead {
    /// The one calibration knob. Tune these against real cameras, not the code.
    public enum Light {
        public static let sampleMs = 166, settleMs = 1200, hold = 3, tipMinMs = 2000
        public static let dark = 0.2, bright = 0.82, clip = 0.96, clipShare = 0.25, backlitEdge = 0.45, backlitGap = 0.22
    }

    public static let width = 64, height = 36

    // Where a face sits: the centre box of the thumbnail; everything else is "edge".
    static func inCentre(_ x: Int, _ y: Int) -> Bool { (20..<44).contains(x) && (5..<26).contains(y) }

    public enum Verdict: String, Sendable { case good, backlit, dark, bright }

    static func luma(_ rgba: [UInt8], _ i: Int) -> Double {
        (0.2126 * Double(rgba[i]) + 0.7152 * Double(rgba[i + 1]) + 0.0722 * Double(rgba[i + 2])) / 255
    }

    public static func readLight(_ rgba: [UInt8]) -> Verdict {
        var all = 0.0, centre = 0.0, edge = 0.0, centreN = 0.0, clipped = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let l = luma(rgba, (y * width + x) * 4)
                all += l
                if inCentre(x, y) {
                    centre += l
                    centreN += 1
                    if l > Light.clip { clipped += 1 }
                } else {
                    edge += l
                }
            }
        }
        let n = Double(width * height)
        let mean = all / n, centreMean = centre / centreN, edgeMean = edge / (n - centreN)
        if edgeMean - centreMean > Light.backlitGap, edgeMean > Light.backlitEdge { return .backlit }
        if mean < Light.dark { return .dark }
        if mean > Light.bright || clipped / centreN > Light.clipShare { return .bright }
        return .good
    }

    public enum Side: String, Sendable { case left, right, above, below }

    /// Where the light comes from, in the person's own terms (the camera image is unmirrored, so its right is their
    /// left). `angle` is in degrees for the mirrored view (0 = their right, 90 = below); `strength` is the brightness
    /// centroid's offset from the face centre.
    public static func lightDirection(_ rgba: [UInt8]) -> (angle: Double, strength: Double, side: Side) {
        var edgeSum = 0.0, edgeN = 0.0
        for y in 0..<height { for x in 0..<width where !inCentre(x, y) { edgeSum += luma(rgba, (y * width + x) * 4); edgeN += 1 } }
        let meanEdge = edgeSum / edgeN
        var w = 0.0, cx = 0.0, cy = 0.0
        for y in 0..<height {
            for x in 0..<width where !inCentre(x, y) {
                let weight = max(0, luma(rgba, (y * width + x) * 4) - meanEdge)
                w += weight
                cx += weight * (Double(x) + 0.5)
                cy += weight * (Double(y) + 0.5)
            }
        }
        // An even frame has no direction (and float noise would otherwise pick one).
        let lit = w / edgeN > 0.005
        let fx = lit ? cx / w / Double(width) - 0.5 : 0
        let fy = lit ? cy / w / Double(height) - 0.44 : 0
        let nx = -fx / 0.19, ny = fy / 0.38
        let side: Side = abs(nx) >= abs(ny) ? (nx < 0 ? .left : .right) : (ny < 0 ? .above : .below)
        return (atan2(ny, nx) * 180 / .pi, hypot(fx, fy), side)
    }

    /// The light arc's opacity for a direction strength.
    public static func arcOpacity(_ strength: Double) -> Double { min(1, max(0, (strength - 0.04) / 0.12)) }
    /// Above this, the Light row names the side too.
    public static let sideStrength = 0.08

    public enum Framing: String, Sendable { case none, close, far, off, high, low, good }

    /// A face box normalised to the frame (0–1, origin top left), or nil when no face was found.
    public static func readFraming(_ box: CGRect?) -> Framing {
        guard let box else { return .none }
        if box.width > 0.55 { return .close }
        if box.width < 0.18 { return .far }
        if abs(box.minX + box.width / 2 - 0.5) > 0.15 { return .off }
        let eyes = box.minY + 0.4 * box.height
        if eyes < 0.25 { return .high }
        if eyes > 0.45 { return .low }
        return .good
    }

    /// A reading shows only after it holds for `hold` samples in a row, and changes at most once per `minMs`.
    public struct Hold<T: Equatable & Sendable>: Sendable {
        let hold: Int, minMs: Double
        public private(set) var shown: T?
        var candidate: T?
        var run = 0
        var changedAt = -Double.infinity

        public init(hold: Int = Light.hold, minMs: Double = Double(Light.tipMinMs)) {
            self.hold = hold
            self.minMs = minMs
        }

        /// Takes a reading at `now` (ms) and returns what to show, nil until something holds.
        public mutating func callAsFunction(_ value: T, now: Double) -> T? {
            run = value == candidate ? run + 1 : 1
            candidate = value
            if run >= hold, value != shown, now - changedAt >= minMs {
                shown = value
                changedAt = now
            }
            return shown
        }
    }

    // MARK: Copy

    public static func tip(_ v: Verdict) -> (title: String, body: String) {
        switch v {
        case .good: ("There you are.", "You look clear. Begin whenever you like.")
        case .backlit: ("The window is behind you.", "Turn a little toward it, or put a lamp in front of you.")
        case .dark: ("It’s a little dark.", "A lamp in front of you, at eye level, helps most.")
        case .bright: ("The light is very strong.", "Step back from it, or draw a curtain halfway.")
        }
    }

    public static func row(_ v: Verdict) -> String {
        switch v {
        case .good: "Soft and even."
        case .backlit: "Backlit. Face the window, or add a lamp."
        case .dark: "A little dark."
        case .bright: "Very bright."
        }
    }

    public static func row(_ s: Side) -> String {
        switch s {
        case .left: "Brightest on your left."
        case .right: "Brightest on your right."
        case .above: "Brightest above you."
        case .below: "Brightest below you."
        }
    }

    public static func row(_ f: Framing) -> String {
        switch f {
        case .none: "I can’t see your face yet."
        case .close: "Sit back a little."
        case .far: "Come a little closer."
        case .off: "Come a little to the centre."
        case .high: "Bring your eyes down toward the marks."
        case .low: "Bring your eyes up toward the marks."
        case .good: "Eyes near the top third. Perfect."
        }
    }

    public enum Mic: String, Sendable { case waiting, heard, silent }

    public static func row(_ m: Mic) -> String {
        switch m {
        case .waiting: "Say hello."
        case .heard: "I can hear you."
        case .silent: "I can’t hear you yet. Check the mic isn’t muted."
        }
    }

    /// The mic's state from when it was last heard and when it started (seconds): heard in the last 1.5 s; silent once
    /// 4 s pass without a sound.
    public static func mic(now: Double, started: Double, lastHeard: Double?) -> Mic {
        if let lastHeard, now - lastHeard < 1.5 { return .heard }
        return lastHeard == nil && now - started > 4 ? .silent : .waiting
    }
}
