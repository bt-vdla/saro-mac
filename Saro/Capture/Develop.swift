import AVFoundation
import SaroKit
import SwiftUI

/// The last frame, frozen as Finish saves, developing like a print (VideoReflectionScreen.tsx DEVELOPED / EXPOSED): over
/// 1 s it washes to brightness 1.85, contrast 0.7, saturation 0.25, sepia 0.25 and blur 4 at 12% of the way, then settles.
/// "Saved to today." sits over it. Under Reduce Motion the frame fades in over 0.2 s instead.
struct DevelopedFrame: View {
    let image: CGImage
    let day: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            // 0 developed, 1 exposed; every filter moves between its two ends together.
            Image(decorative: image, scale: 1).resizable().scaledToFill()
                .keyframeAnimator(initialValue: 0.0, trigger: shown && !reduceMotion) { view, x in
                    view.brightness(0.42 * x)
                        .contrast(1 - 0.3 * x)
                        .saturation(1 - 0.75 * x)
                        .overlay(Rectangle().fill(Color(red: 0.44, green: 0.26, blue: 0.08).opacity(0.25 * x)).blendMode(.color))
                        .blur(radius: 4 * x)
                } keyframes: { _ in
                    CubicKeyframe(1, duration: 0.12)
                    CubicKeyframe(0, duration: 0.88)
                }
                .opacity(reduceMotion && !shown ? 0 : 1)
            Text(day == LocalDay.today() ? "Saved to today." : "Saved to \(DayFormat.sidebar(day)).")
                .font(Typo.serif(22)).foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(.black.opacity(0.3), in: .capsule)
                .legible()
                .opacity(shown ? 1 : 0)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 56)
        }
        .clipped()
        .animation(reduceMotion ? .easeOut(duration: 0.2) : CaptureMotion.out(0.3), value: shown)
        .onAppear {
            shown = true
            AccessibilityNotification.Announcement(day == LocalDay.today() ? "Saved to today." : "Saved to \(DayFormat.sidebar(day)).").post()
        }
        .allowsHitTesting(false)
    }

    /// The part's last frame, mirrored like the preview, at most 1280 px.
    static func lastFrame(of url: URL) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isNumeric else { return nil }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1280, height: 1280)
        gen.requestedTimeToleranceBefore = .positiveInfinity
        let at = CMTimeSubtract(duration, CMTime(value: 1, timescale: 10))
        guard let frame = try? await gen.image(at: CMTimeMaximum(at, .zero)).image,
              let ctx = CGContext(data: nil, width: frame.width, height: frame.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: CGFloat(frame.width), y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        return ctx.makeImage()
    }
}
