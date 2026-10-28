import SaroKit
import SwiftUI

/// The day's mood (InsightSection.tsx, accent): its symbol in its colour, changing with a replace effect, the label and
/// summary, and, open, what it was read from or the person's own note. Right-click or 'Change' adjusts it.
struct MoodSection: View {
    @Environment(AppModel.self) private var model
    let reading: DayReading
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        @Bindable var r = model.reflection
        let mood = r.mood(reading)
        let mine = r.state.lockedMood != nil
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Button(action: toggle) {
                    HStack(spacing: 8) {
                        Image(systemName: MoodSymbol.of(mood)).font(.system(size: 16, weight: .semibold)).foregroundStyle(MoodPalette.color(mood))
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                        Text(mood.rawValue).font(Typo.ui(16.5, .semibold)).foregroundStyle(Tok.echoInk)
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("The day’s mood: \(mood.rawValue)")
                .accessibilityValue(open ? "Expanded" : "Collapsed")
                Button("Change") { r.adjustingMood = true }
                    .buttonStyle(.plain)
                    .font(Typo.ui(12, .medium)).foregroundStyle(Tok.echoInk)
                    .padding(.horizontal, 8).frame(minHeight: 24)
                    .background(Tok.echo.opacity(0.08), in: .capsule)
                    .accessibilityLabel("Adjust emotion")
                    .popover(isPresented: $r.adjustingMood, arrowEdge: .leading) { AdjustMoodView(current: mood) }
                Button(action: toggle) { Chevron(open: open, tint: Tok.echoInk) }.buttonStyle(.plain).accessibilityHidden(true)
            }
            Text(mood.summary).font(Typo.ui(13.5)).lineSpacing(2).foregroundStyle(Tok.echoInk)
                .lineLimit(open ? nil : 3).fixedSize(horizontal: false, vertical: true)
            if open {
                VStack(alignment: .leading, spacing: 4) {
                    if mine {
                        Text("You set this mood.").font(Typo.mono(10)).textCase(.uppercase).foregroundStyle(Tok.ink3)
                        if let note = r.state.moodNote { Text("“\(note)”").font(Typo.serif(14.5, italic: true)).foregroundStyle(Tok.ink2) }
                    } else if let basis = reading.moodBasis, !basis.isEmpty {
                        Text("From: \(basis)").font(Typo.ui(12)).foregroundStyle(Tok.ink3)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .transition(.opacity)
            }
        }
        .animation(Motion.small, value: mood)
        .contentShape(.rect)
        .contextMenu {
            Button("Adjust emotion", systemImage: "slider.horizontal.3") { r.adjustingMood = true }
            Button("Copy emotion tag", systemImage: "doc.on.doc") { r.copy(CopyText.emotion(mood), toast: "Emotion copied") }
        }
    }
}
