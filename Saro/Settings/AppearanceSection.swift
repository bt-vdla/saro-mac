import SaroKit
import SwiftUI

/// 04 Appearance: the day/night palette, and Preview the day, which scrubs this window's own lit ground and palette
/// through the hours and goes back to now when you let go (PersonalizationSheet.tsx PreviewDay).
struct AppearanceSection: View {
    @Binding var previewHour: Double?
    @State private var save = Autosave()
    @State private var hour = Sky.localHour(.now)
    @State private var dragging = false
    @State private var settle: Task<Void, Never>?

    var body: some View {
        SettingsCard(label: "Appearance", title: "Light that follows your day", autosave: save) {
            VStack(alignment: .leading, spacing: 10) { DaylightPicker().labelsHidden() }
                .padding(.bottom, 16)
                .onChange(of: Daylight.shared.mode) { save.saved() }
            RowRule()
            SettingsRow("Preview the day", caption: "Drag through the hours to see the light. It goes back to now when you let go.") {
                HStack(spacing: 12) {
                    Slider(value: $hour, in: 0...24, step: 0.25) { editing in
                        dragging = editing
                        if !editing { release() }
                    }
                    .frame(width: 200)
                    .accessibilityLabel("Preview the day")
                    .accessibilityValue(Rhythm.formatClock(Int(hour * 60)))
                    Text(Rhythm.formatClock(Int(hour * 60))).font(Typo.mono(12)).monospacedDigit().foregroundStyle(Tok.ink2)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
        .onChange(of: hour) {
            guard dragging || previewHour != nil || abs(hour - Sky.localHour(.now)) > 0.13 else { return }
            previewHour = hour
            Daylight.shared.replayHour = hour
            // Arrow keys have no "let go": the light goes back once they stop.
            settle?.cancel()
            if !dragging { settle = Task { try? await Task.sleep(for: .seconds(1.5)); if !Task.isCancelled, !dragging { release() } } }
        }
        .onDisappear(perform: release)
    }

    private func release() {
        settle?.cancel()
        previewHour = nil
        Daylight.shared.replayHour = nil
        hour = Sky.localHour(.now)
    }
}
