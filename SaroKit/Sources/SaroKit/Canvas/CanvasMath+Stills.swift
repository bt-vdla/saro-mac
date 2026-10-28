import CoreGraphics

extension CanvasMath {
    /// The opened still (EntryViews.tsx StillView): a frame in the photo's own aspect (4:3 until it is known), as large as
    /// fits in 86% × 74% of the window with `below` left under it for the caption, the pair centred.
    public static func stillFrame(in window: CGSize, aspect: CGFloat?, below: CGFloat) -> CGRect {
        let ratio = aspect.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 4 / 3
        let w = min(window.width * 0.86, max(0, min(window.height * 0.74, window.height - below - 48)) * ratio)
        let h = w / ratio
        return CGRect(x: (window.width - w) / 2, y: max(24, (window.height - h - below) / 2), width: w, height: h)
    }
}
