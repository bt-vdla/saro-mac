#if DOGFOOD
import SaroKit
import SwiftUI

/// Developer → Light Lab (components/dev/LightLab.tsx): a floating chip that flips the palette and pins the clock, to
/// see the ground and palette at any hour. ⌥L shows and hides it; `-SaroHour 19.5` pins the clock at launch.
struct LightLab: View {
    private static let moments: [(name: String, hour: Double)] = [("Dawn", 6.5), ("Noon", 13), ("Dusk", 19.5), ("Night", 23)]

    var body: some View {
        @Bindable var daylight = Daylight.shared
        HStack(spacing: 10) {
            Text("LIGHT LAB").font(Typo.mono(9.5)).tracking(0.8).foregroundStyle(Tok.ink3)
            Picker("Palette", selection: $daylight.mode) {
                Text("Auto").tag(Daylight.Mode.clock)
                Text("Light").tag(Daylight.Mode.light)
                Text("Dark").tag(Daylight.Mode.dark)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Divider().frame(height: 20)
            ForEach(Self.moments, id: \.name) { m in
                Button(m.name) { daylight.pinnedHour = m.hour }
                    .buttonStyle(.plain)
                    .font(Typo.ui(12, daylight.pinnedHour == m.hour ? .semibold : .regular))
                    .foregroundStyle(daylight.pinnedHour == m.hour ? Tok.sageDark : Tok.ink2)
            }
            Slider(value: Binding(get: { daylight.pinnedHour ?? Sky.localHour(.now) }, set: { daylight.pinnedHour = ($0 * 4).rounded() / 4 }),
                   in: 0...24)
                .frame(width: 140)
                .accessibilityLabel("Hour")
            Text(label(daylight.pinnedHour)).font(Typo.mono(11)).monospacedDigit().foregroundStyle(Tok.ink).frame(width: 48, alignment: .leading)
            Button("Clock") { daylight.pinnedHour = nil }.buttonStyle(.plain).font(Typo.ui(12, .medium)).foregroundStyle(Tok.sageDark)
                .disabled(daylight.pinnedHour == nil)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassPanel(radius: 999)
        .padding(.top, 44)
    }

    private func label(_ hour: Double?) -> String {
        guard let hour else { return "clock" }
        let m = Int((hour * 60).rounded())
        return String(format: "%02d:%02d", (m / 60) % 24, m % 60)
    }
}
#endif
