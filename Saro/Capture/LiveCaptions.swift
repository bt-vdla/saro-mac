import AppKit
import SaroKit
import SwiftUI

/// The live transcript's status, as each recorder words it.
extension CaptureController.Live {
    func line(paused: Bool, voice: Bool) -> String? {
        if paused, self != .off { return "Paused" }
        switch self {
        case .connecting: return voice ? "Connecting…" : "Connecting to live transcript…"
        case .unavailable: return "Live transcript unavailable. Your \(voice ? "voice" : "video") is still recording."
        case .off, .listening: return nil
        }
    }
}

/// The status line over the captions: a 6 pt dot, breathing while it connects.
struct CaptionStatus: View {
    let text: String?
    var connecting = false
    var night = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if let text {
                Circle().fill(connecting ? (night ? Tok.warning : .white.opacity(0.7)) : .white.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .breathing(connecting && !reduceMotion)
                Text(text)
            }
        }
        .font(Typo.ui(12))
        .foregroundStyle(night ? Night.ink2 : .white.opacity(0.75))
        .frame(minHeight: 18)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Two-line subtitles in Newsreader (LiveCaptions in VideoReflectionScreen.tsx): the newest words on the bottom line,
/// older lines rolling up into a fade. Each word fades in over 200 ms, and a word shown keeps its line. On screen only.
struct LiveCaptions: View {
    let words: [LiveWord]
    let placeholder: String?
    var size: CGFloat = 19
    @State private var lines = CaptionLines()
    @State private var width: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lineHeight: CGFloat { size * PrefsStore.shared.textScale * 1.35 }

    var body: some View {
        let texts = words.map(\.text)
        let shown = lines.lines.suffix(3)
        ZStack(alignment: .bottomLeading) {
            if texts.isEmpty {
                if let placeholder {
                    Text(placeholder).font(Typo.serif(size, italic: true)).foregroundStyle(.white.opacity(0.6))
                        .frame(height: lineHeight)
                        .transition(.opacity)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown), id: \.lowerBound) { range in
                        HStack(spacing: 0) {
                            ForEach(range.filter { $0 < texts.count }, id: \.self) { i in
                                Text(verbatim: (i == range.lowerBound ? "" : " ") + texts[i])
                                    .transition(.opacity.animation(.easeOut(duration: 0.2)))
                            }
                        }
                        .frame(height: lineHeight, alignment: .leading)
                    }
                }
                .font(Typo.serif(size))
                .foregroundStyle(.white)
                .animation(reduceMotion ? nil : Motion.small, value: lines.lines.count)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .frame(height: lineHeight * 2, alignment: .bottomLeading)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.42)], startPoint: .top, endPoint: .bottom))
        .legible()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: texts, initial: true) { _, t in relayout(t) }
        .onChange(of: width) { _, _ in relayout(texts) }
        .accessibilityHidden(true)
    }

    private func relayout(_ words: [String]) {
        guard width > 0 else { return }
        if words.isEmpty { lines.reset(); return }
        let font = NSFont(name: "Newsreader16pt-Regular", size: size * PrefsStore.shared.textScale) ?? .systemFont(ofSize: size)
        lines.update(words, maxWidth: width) { NSAttributedString(string: $0, attributes: [.font: font]).size().width }
    }
}

/// The voice pill's one caption line (VoiceEchoOverlay.tsx): the last 14 words, right-aligned, fading off on the left.
struct PillCaption: View {
    let words: [LiveWord]

    var body: some View {
        let last = words.suffix(14).map(\.text).joined(separator: " ")
        ZStack(alignment: .trailing) {
            if last.isEmpty {
                Text("Start speaking…").font(Typo.serif(15, italic: true)).foregroundStyle(Night.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            } else {
                Text(last).font(Typo.serif(15)).foregroundStyle(Night.ink).lineLimit(1).fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22)],
                                         startPoint: .leading, endPoint: .trailing))
                    .animation(Motion.small, value: last)
            }
        }
        .clipped()
        .animation(Motion.fade, value: last.isEmpty)
        .accessibilityHidden(true)
    }
}
