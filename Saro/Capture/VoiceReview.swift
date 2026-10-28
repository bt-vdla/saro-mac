import SaroKit
import SwiftUI

/// Listening back before keeping a voice note (VoiceEchoOverlay.tsx review): an ink play disc, 40 bars drawn from the
/// level history (played in echo, the rest at echo/30), "00:12 / 00:40", and the file transcript as sentences that seek
/// by their real word times. ✕, Record again and Keep this (Return); Space plays and pauses. Nothing is processed until Keep.
struct VoiceReview: View {
    let again: () -> Void
    let discard: () -> Void
    let keep: () -> Void

    @State private var player: PlayerModel?
    private var capture: CaptureController { .shared }

    var body: some View {
        let sentences = capture.review.map(timedSentences) ?? []
        VStack(alignment: .leading, spacing: 12) {
            if capture.interrupted {
                Text("Recording stopped because the microphone disconnected. What you said so far is kept.")
                    .font(Typo.ui(12)).foregroundStyle(Night.ink2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button { player?.toggle() } label: {
                    Image(systemName: player?.playing == true ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold)).offset(x: player?.playing == true ? 0 : 1)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(CaptureButtonStyle(fill: Night.ink, hover: Night.ink.opacity(0.9), ink: Night.bg, diameter: 40))
                .keyboardShortcut(.space, modifiers: [])
                .disabled(player == nil)
                .accessibilityLabel(player?.playing == true ? "Pause" : "Play")
                bars
                Text("\(clock(player?.timeMs ?? 0)) / \(clock(duration))")
                    .font(Typo.mono(11.5, .regular)).monospacedDigit().foregroundStyle(Night.ink2)
                    .fixedSize()
            }
            transcript(sentences)
            HStack(spacing: 8) {
                Button(action: discard) { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)) }
                    .buttonStyle(CaptureButtonStyle.nightIcon)
                    .accessibilityLabel("Discard voice note")
                    .help("Discard voice note")
                Button(action: again) { Label("Record again", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(CaptureButtonStyle(fill: .clear, hover: Night.glass.opacity(0.6), ink: Night.ink2, padding: 14, size: 13))
                Spacer(minLength: 8)
                Button("Keep this", action: keep)
                    .buttonStyle(CaptureButtonStyle(fill: Night.sage, hover: Night.sageDark, ink: Night.bg, padding: 18, size: 13))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .task(id: capture.takeURL) {
            player?.stop()
            player = capture.takeURL.map { PlayerModel(url: $0) }
        }
        .onDisappear { player?.stop() }
    }

    private var duration: Int { player?.durationMs ?? capture.lastPart.map { Int($0 / .milliseconds(1)) } ?? 0 }

    /// 40 bars, each the loudest sample of its share of the note.
    private var bars: some View {
        let levels = capture.levels
        let played = duration > 0 ? Double(player?.timeMs ?? 0) / Double(duration) : 0
        return HStack(spacing: 2) {
            ForEach(0..<40, id: \.self) { i in
                let slice = levels.isEmpty ? [] : levels[(i * levels.count / 40)..<max((i + 1) * levels.count / 40, i * levels.count / 40 + 1)]
                Capsule()
                    .fill(Night.echo.opacity(Double(i) / 40 < played ? 1 : 0.3))
                    .frame(width: 3, height: 28 * max(0.12, slice.max() ?? 0))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func transcript(_ sentences: [TimedSentence]) -> some View {
        if capture.review == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text("Transcribing on this Mac…")
            }
            .font(Typo.ui(13)).foregroundStyle(Night.ink3)
        } else if sentences.isEmpty {
            Text("No transcript for this one.").font(Typo.ui(13)).foregroundStyle(Night.ink3)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sentences) { s in
                        let now = player?.timeMs ?? -1
                        let current = now >= s.startMs && now < s.endMs
                        Button { player?.seek(ms: s.startMs) } label: {
                            Text(s.text).font(Typo.serif(15)).foregroundStyle(current ? Night.ink : Night.ink3)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help("Play from here")
                    }
                }
            }
            .frame(maxHeight: 15 * PrefsStore.shared.textScale * 7.2)
            .scrollIndicators(.never)
        }
    }

    private func clock(_ ms: Int) -> String { Duration.milliseconds(ms).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2))) }
}
