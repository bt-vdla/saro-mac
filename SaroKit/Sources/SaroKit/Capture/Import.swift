import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Files dropped, pasted or picked (Canvas.tsx captureFile): each becomes the entry it is.
public enum Import {
    /// An image is a still, audio a voice note, a movie a moment; anything else isn't Saro's to keep.
    public static func kind(of type: UTType) -> EntryKind? {
        if type.conforms(to: .image) { return .still }
        if type.conforms(to: .audio) { return .voice }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .moment }
        return nil
    }

    public static func kind(of url: URL) -> EntryKind? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType).flatMap(kind(of:))
            ?? UTType(filenameExtension: url.pathExtension).flatMap(kind(of:))
    }

    /// Where a batch lands (Canvas.tsx handleDrop): a near-square grid centred where it was let go, each cell the widest
    /// card (a moment) by the tallest (a still) plus a 24 pt gap, so no two overlap.
    public static func grid(count: Int, around p: CGPoint) -> [CGPoint] {
        guard count > 0 else { return [] }
        let cols = Int(Double(count).squareRoot().rounded(.up)), rows = (count + cols - 1) / cols
        let cell = CGSize(width: CanvasMath.size(.moment).width + 24, height: CanvasMath.size(.still).height + 24)
        return (0..<count).map { i in
            CGPoint(x: p.x + (CGFloat(i % cols) - CGFloat(cols - 1) / 2) * cell.width,
                    y: p.y + (CGFloat(i / cols) - CGFloat(rows - 1) / 2) * cell.height)
        }
    }
}
