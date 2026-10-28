import Foundation

/// A day's key frame, the poster the time lens and the moment cards show (the web's lib/keyframes.ts helpers).
public enum Keyframe {
    public static let shortSide = 256

    /// The poster's size for a `width`×`height` source: the short side becomes `target` (never upscaled) and the long
    /// side stays within twice that, keeping the aspect.
    public static func fit(width: Int, height: Int, target: Int = shortSide) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (target, target) }
        let s = min(1, Double(target) / Double(min(width, height)), Double(target * 2) / Double(max(width, height)))
        return (max(1, Int((Double(width) * s).rounded())), max(1, Int((Double(height) * s).rounded())))
    }

    /// Mean luma (0–255) of RGBA pixels, and the share brighter than `bright`.
    public static func luma(_ rgba: [UInt8], bright: Double = 24) -> (mean: Double, brightShare: Double) {
        let pixels = rgba.count / 4
        guard pixels > 0 else { return (0, 0) }
        var sum = 0.0, lit = 0
        for i in stride(from: 0, to: pixels * 4, by: 4) {
            let y = 0.2126 * Double(rgba[i]) + 0.7152 * Double(rgba[i + 1]) + 0.0722 * Double(rgba[i + 2])
            sum += y
            if y > bright { lit += 1 }
        }
        return (sum / Double(pixels), Double(lit) / Double(pixels))
    }

    /// Camera warm-up and fade-in frames: almost nothing brighter than a dim grey.
    public static func isBlack(_ rgba: [UInt8]) -> Bool { luma(rgba).brightShare < 0.02 }

    /// Where to look for the first frame that isn't black: inside the clip when its length is known.
    public static func seekTimes(_ duration: Double?) -> [Double] {
        let probes = [0.05, 0.4, 1, 2, 3.5]
        guard let duration, duration.isFinite, duration > 0 else { return probes }
        let inside = probes.filter { $0 < duration * 0.9 }
        return inside.isEmpty ? [duration / 2] : inside
    }

    /// Where a media file's poster lives, relative to the ledger's media folder: beside its day, named by its id and the
    /// file's modification time, so a replaced file gets a new poster.
    public static func file(for media: MediaAsset, stamp: Int) -> String {
        let day = media.fileName.split(separator: "/").first.map(String.init) ?? "posters"
        return "\(day)/posters/\(media.id)-\(stamp).jpg"
    }
}
