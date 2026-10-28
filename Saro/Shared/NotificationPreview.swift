import AppKit
import SwiftUI

/// Saro's reminder exactly as macOS will show it, drawn like a banner (NotificationPreview.tsx): the first week shows it
/// before asking, and Settings → Rhythm reuses it. A new time crossfades in.
struct NotificationPreview: View {
    /// As the banner shows it, e.g. "9:30 PM".
    let time: String
    let title: String
    let message: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(time: String, title: String = Reminders.title, body: String = Reminders.body) {
        self.time = time
        self.title = title
        message = body
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(time)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .animation(Motion.pick(Motion.surface, reduce: reduceMotion), value: time)
                }
                Text(message).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: 360, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
            if reduceTransparency { shape.fill(Tok.surface) } else { shape.fill(.regularMaterial) }
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(Tok.rim.opacity(0.5), lineWidth: 0.5))
        .elevation(.float)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reminder preview, at \(time). \(title) \(message)")
    }
}
