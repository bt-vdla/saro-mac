import AppKit
import SwiftUI

extension View {
    /// Settings → Comfort for a scene root: Reduce motion and Reduce transparency become the device's setting OR Saro's
    /// own switch, through SwiftUI's settable keys, so every `accessibilityReduceMotion` read below follows both.
    func comfortEnvironment() -> some View { modifier(ComfortEnvironment()) }

    /// Writing Tools in Saro's editors: off unless chosen in Settings → Comfort (FR-SET-03).
    func saroWritingTools() -> some View { modifier(SaroWritingTools()) }
}

private struct ComfortEnvironment: ViewModifier {
    func body(content: Content) -> some View {
        let prefs = PrefsStore.shared
        content
            .environment(\._accessibilityReduceMotion, prefs.reduceMotionEffective)
            .environment(\._accessibilityReduceTransparency, prefs.reduceTransparencyEffective)
    }
}

private struct SaroWritingTools: ViewModifier {
    func body(content: Content) -> some View {
        content.writingToolsBehavior(PrefsStore.shared.writingTools ? .complete : .disabled)
    }
}

/// Frosted glass that turns solid under Reduce transparency, the device's or Saro's own: `solid` in place of the blur.
struct Frosted: ShapeStyle {
    var material: Material
    var solid: Color

    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        environment.accessibilityReduceTransparency ? AnyShapeStyle(solid) : AnyShapeStyle(material)
    }
}

extension ShapeStyle where Self == Frosted {
    static func frosted(_ material: Material = .ultraThinMaterial, solid: Color = Tok.surface) -> Frosted { .init(material: material, solid: solid) }
}

/// Settings → Comfort → Haptics: a light trackpad tap when a dragged card snaps to a guide.
@MainActor
enum Haptics {
    static func snap() {
        guard PrefsStore.shared.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
