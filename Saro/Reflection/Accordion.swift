import SaroKit
import SwiftUI

/// The panel's sections (InsightBar.tsx): only one is open at a time, the narrative by default.
enum PanelSection: Hashable { case narrative, mood, question }

/// A section's chevron: up when open, turning over 200 ms.
struct Chevron: View {
    let open: Bool
    let tint: Color

    var body: some View {
        Image(systemName: "chevron.up").font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            .rotationEffect(.degrees(open ? 0 : 180))
            .animation(Motion.easeOut(0.2), value: open)
            .frame(width: 24, height: 24)
            .contentShape(.rect)
    }
}

/// SHIMMER (types.ts): a line-coloured bar with a light passing over it. Reduce Motion keeps it still.
struct Shimmer: View {
    var height: CGFloat = 10
    var delay = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        Capsule().fill(Tok.line.opacity(0.6))
            .overlay {
                GeometryReader { g in
                    LinearGradient(colors: [.clear, Tok.surfaceAlt.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width)
                        .offset(x: phase * g.size.width)
                }
                .clipShape(.capsule)
            }
            .frame(height: height)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.6).delay(delay).repeatForever(autoreverses: false)) { phase = 1 }
            }
            .accessibilityHidden(true)
    }
}

/// Pulse rows that stand in for text while it is being read or written, 80 ms apart.
struct ShimmerLines: View {
    let widths: [CGFloat]
    var height: CGFloat = 10
    var spacing: CGFloat = 12

    var body: some View {
        GeometryReader { g in
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(widths.enumerated()), id: \.offset) { i, w in
                    Shimmer(height: height, delay: Double(i) * 0.08).frame(width: g.size.width * w)
                }
            }
        }
        .frame(height: CGFloat(widths.count) * (height + spacing) - spacing)
    }
}

/// An entry kind's mark (LAST_INFERRED_META): its symbol in the light colour, its words in the AA ink twin.
enum KindStyle {
    static func symbol(_ k: EntryKind) -> String {
        switch k {
        case .moment: "video"
        case .voice: "waveform"
        case .still: "photo"
        case .reflection: "text.alignleft"
        case .music: "music.note"
        }
    }

    static func tint(_ k: EntryKind) -> Color {
        switch k {
        case .moment: Tok.moment
        case .voice: Tok.echo
        case .still: Tok.still
        case .reflection: Tok.reflection
        case .music: Tok.music
        }
    }

    static func ink(_ k: EntryKind) -> Color {
        switch k {
        case .moment: Tok.momentInk
        case .voice: Tok.echoInk
        case .still: Tok.stillInk
        case .reflection: Tok.reflectionInk
        case .music: Tok.music
        }
    }

    /// "moment", "voice note", … for "open the moment this is from".
    static func noun(_ k: EntryKind) -> String {
        switch k {
        case .moment: "moment"
        case .voice: "voice note"
        case .still: "still"
        case .reflection: "reflection"
        case .music: "song"
        }
    }

    /// PENDING_INPUT_MESSAGES, with the native ending: the reading lands on its own.
    static func pending(_ k: EntryKind) -> String {
        switch k {
        case .moment: "New moment saved. Saro is reading it…"
        case .voice: "New voice note saved. Saro is reading it…"
        case .still: "New still saved. Saro is reading it…"
        case .reflection: "New reflection saved. Saro is reading it…"
        case .music: "New music saved. Saro is reading it…"
        }
    }
}

/// EMOTION_ICON_MAP, as SF Symbols.
enum MoodSymbol {
    static func of(_ m: Mood) -> String {
        switch m {
        case .calm: "wind"
        case .reflective: "moon"
        case .grateful: "face.smiling"
        case .frustrated: "flame"
        case .tender: "heart"
        case .anxious: "brain"
        case .energised: "bolt"
        case .neutral: "equal.circle"
        case .bittersweet: "heart.text.square"
        case .surprised: "sparkles"
        case .overwhelmed: "cloud.bolt"
        case .inspired: "water.waves"
        }
    }

    /// EMOTION_OPTIONS' emoji, for the Adjust emotion grid.
    static func emoji(_ m: Mood) -> String {
        switch m {
        case .calm: "😌"
        case .reflective: "😔"
        case .grateful: "😊"
        case .frustrated: "😤"
        case .tender: "😢"
        case .anxious: "😰"
        case .energised: "😁"
        case .neutral: "😐"
        case .bittersweet: "🥲"
        case .surprised: "😮"
        case .overwhelmed: "🌀"
        case .inspired: "✨"
        }
    }
}

extension View {
    /// The Writing Tools pref (FR-SET-03): off unless chosen, since it may use Private Cloud Compute.
    func writingToolsFollowPref() -> some View {
        writingToolsBehavior(PrefsStore.shared.writingTools ? .automatic : .disabled)
    }
}
