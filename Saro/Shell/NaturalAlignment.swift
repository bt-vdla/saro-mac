import SaroKit
import SwiftUI

extension View {
    /// The person's text in its own direction (dir="auto"): right to left when its first strong character is, so a
    /// Hebrew or Urdu title sits right in an English window. Put it outside the text's frame, which then aligns with it.
    func naturalAlignment(for text: String) -> some View {
        environment(\.layoutDirection, ShellText.isRightToLeft(text) ? .rightToLeft : .leftToRight)
    }

    /// The 2 pt sage ring, 2 pt out, on a control with keyboard focus (globals.css :focus-visible), which a custom
    /// button style otherwise loses under Full Keyboard Access.
    func focusRing(radius: CGFloat) -> some View { modifier(FocusRing(radius: radius)) }
}

private struct FocusRing: ViewModifier {
    @Environment(\.isFocused) private var focused
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            if focused {
                RoundedRectangle(cornerRadius: radius + 4).strokeBorder(Tok.sage, lineWidth: 2).padding(-4).allowsHitTesting(false)
            }
        }
    }
}
