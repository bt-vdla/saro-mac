import QuartzCore
import SaroKit
import SwiftUI

extension View {
    /// Blurs along x and y by `sigma` points of this view's space (MotionBlur.metal); nothing at zero. The shader can't
    /// sample AppKit-backed views (players, editors, scrollers), so keep it to plain SwiftUI content.
    func motionBlur(_ sigma: CGSize) -> some View {
        layerEffect(ShaderLibrary.motionBlur(.float2(1, 0), .float(sigma.width)),
                    maxSampleOffset: CGSize(width: 3 * sigma.width, height: 0), isEnabled: sigma.width > 0)
            .layerEffect(ShaderLibrary.motionBlur(.float2(0, 1), .float(sigma.height)),
                         maxSampleOffset: CGSize(width: 0, height: 3 * sigma.height), isEnabled: sigma.height > 0)
    }
}

/// A `MotionBlur` fed from inside `body`, so a plain class SwiftUI doesn't watch.
@MainActor final class MotionBlurTracker {
    private var blur = MotionBlur()

    func track(_ p: CGPoint, coverage: Double) -> CGSize { blur.track(p, at: CACurrentMediaTime(), coverage: coverage) }

    func reset() -> CGSize {
        blur = MotionBlur()
        return .zero
    }
}

/// Blurs a view along its screen velocity while it moves fast (lib/motionBlur.ts). `position` is where the view is drawn
/// and animates with it, so every frame is sampled; while a blur shows, a timeline keeps sampling, so a card held still
/// or landed comes to rest crisp. Apply it after any scale, so its units are screen points.
struct MotionBlurred: ViewModifier, @MainActor Animatable {
    var position: CGPoint
    /// The share of the viewport the view covers.
    var coverage: Double
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tracker = MotionBlurTracker()
    @State private var live = false

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(position.x, position.y) }
        set { position = CGPoint(x: newValue.first, y: newValue.second) }
    }

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !live)) { _ in
            let sigma = enabled && !reduceMotion ? tracker.track(position, coverage: coverage) : tracker.reset()
            content.motionBlur(sigma).onChange(of: sigma != .zero) { _, showing in live = showing }
        }
    }
}
