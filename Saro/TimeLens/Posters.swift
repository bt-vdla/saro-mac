import AVFoundation
import ImageIO
import SaroKit
import UniformTypeIdentifiers

/// Each moment's and still's key frame (lib/keyframes.ts), made once and kept beside its day as a JPEG, so the lens
/// opens with pictures and a moment card never shows the camera's warm-up black. 256 pt on the short side, at most 512 on
/// the long, quality 0.82; a video's first frame that isn't black, else its brightest probe.
@MainActor
enum Posters {
    private static var images: [String: CGImage] = [:]
    /// Files that couldn't be read aren't tried again this session.
    private static var broken: Set<String> = []

    static func image(for media: MediaAsset) -> CGImage? { images[media.id] }
    static func image(id: String) -> CGImage? { images[id] }

    /// Makes (or reads back) the poster, keyed by the media id and its file's modification time.
    static func ensure(_ media: MediaAsset, in ledger: Ledger) async {
        guard media.state == "ready", media.kind != .audio, images[media.id] == nil, !broken.contains(media.id) else { return }
        let source = ledger.url(for: media)
        let stamp = ((try? source.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970).map(Int.init) ?? 0
        let file = Keyframe.file(for: media, stamp: stamp)
        let target = ledger.mediaURL.appending(path: file)
        if (try? await ledger.poster(mediaId: media.id)) == file, let kept = await Task.detached(operation: { read(target) }).value {
            images[media.id] = kept
            return
        }
        let made: CGImage? = media.kind == .video
            ? await frame(source, longSide: 2 * Keyframe.shortSide).map(fitted)
            : await Task.detached { still(source) }.value
        guard let made, await Task.detached(operation: { write(made, to: target) }).value else {
            broken.insert(media.id)
            return
        }
        try? await ledger.setPoster(mediaId: media.id, file: file)
        images[media.id] = made
    }

    /// Posters for the media given, in that order (nearest the opening day first), two videos and four stills at a time;
    /// `each` hears every media id as its poster is ready.
    static func backfill(_ media: [MediaAsset], in ledger: Ledger, each: @escaping @MainActor (String) -> Void) async {
        async let v: Void = run(media.filter { $0.kind == .video }, width: 2, ledger, each)
        async let s: Void = run(media.filter { $0.kind == .image }, width: 4, ledger, each)
        _ = await (v, s)
    }

    private static func run(_ media: [MediaAsset], width: Int, _ ledger: Ledger, _ each: @escaping @MainActor (String) -> Void) async {
        await withTaskGroup(of: String.self) { group in
            for (i, m) in media.enumerated() {
                if i >= width, let done = await group.next() { each(done) }
                group.addTask { await ensure(m, in: ledger); return m.id }
            }
            for await done in group { each(done) }
        }
    }

    /// A video's first frame that isn't warm-up black, probed at 0.05, 0.4, 1, 2 and 3.5 s against a 32×18 luma check,
    /// else the brightest probe. The moment cards' thumbnails come from here too, at their own size.
    nonisolated static func frame(_ url: URL, longSide: Int) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: longSide, height: longSide)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        let duration = try? await asset.load(.duration)
        var best: (image: CGImage, share: Double)?
        for t in Keyframe.seekTimes(duration.flatMap { $0.isNumeric ? $0.seconds : nil }) {
            guard let image = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image else { continue }
            let rgba = probe(image)
            if !Keyframe.isBlack(rgba) { return image }
            let share = Keyframe.luma(rgba).brightShare
            if best.map({ share > $0.share }) ?? true { best = (image, share) }
        }
        return best?.image
    }

    /// 32×18 RGBA samples of a frame.
    private nonisolated static func probe(_ image: CGImage) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: 32 * 18 * 4)
        px.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: 32, height: 18, bitsPerComponent: 8, bytesPerRow: 128,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 18))
        }
        return px
    }

    /// The poster size: 256 on the short side, at most 512 on the long.
    private nonisolated static func fitted(_ image: CGImage) -> CGImage {
        let (w, h) = Keyframe.fit(width: image.width, height: image.height)
        guard w != image.width || h != image.height,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    private nonisolated static func still(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let (fw, fh) = Keyframe.fit(width: w, height: h)
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(fw, fh),
        ] as CFDictionary)
    }

    private nonisolated static func read(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private nonisolated static func write(_ image: CGImage, to url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }
}
