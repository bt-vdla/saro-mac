import SaroKit
import SwiftUI

extension AppModel {
    /// Opens a voice note in place, or folds it with nil. Pointer only: a key sets `openVoiceID` directly, unanimated.
    func openVoice(_ id: String?, reduceMotion: Bool) {
        withAnimation(reduceMotion ? nil : Motion.easeOut(0.26)) { openVoiceID = id }
    }
}

/// A voice note on the canvas (VoiceEchoCard.tsx): the orb and a one-line pill or, tapped, the player in place. One orb
/// glides between its two spots while the incoming view settles in from 0.6; the outgoing one goes at once.
struct VoiceFace: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    var selected = false
    var open = false
    @State private var player: PlayerModel?
    /// Loaded with the card, so the panel opens with its transcript and the summary test sees it.
    @State private var sentences: [TimedSentence] = []

    private static let settle = AnyTransition.asymmetric(
        insertion: .modifier(active: Fade(opacity: 0.6), identity: Fade(opacity: 1)),
        removal: AnyTransition.modifier(active: Fade(opacity: 0), identity: Fade(opacity: 1)).animation(nil))

    var body: some View {
        ZStack(alignment: .topLeading) {
            if open {
                VoicePanel(entry: entry, player: player, sentences: sentences, selected: selected).transition(Self.settle)
            } else {
                collapsed.transition(Self.settle)
            }
            EchoOrb(size: 80, playing: player?.playing ?? false)
                .scaleEffect(open ? 0.8 : 1, anchor: .topLeading)
                .offset(x: open ? 20 : 0, y: open ? 20 : 6)
                .allowsHitTesting(false)
        }
        // Opening plays it, as a tap on the web's orb does; folding stops it and starts it from the top next time.
        .onChange(of: open, initial: true) { _, open in
            player?.stop()
            player = nil
            guard open, let url = model.mediaURL(for: entry), FileManager.default.fileExists(atPath: url.path) else { return }
            player = PlayerModel(url: url)
            player?.player.play()
        }
        .onDisappear { player?.stop() }
        .task(id: entry.processingStatus) {
            guard let id = entry.mediaId, let words = try? await model.ledger.transcript(mediaId: id) else { return }
            sentences = timedSentences(words)
        }
    }

    /// The orb's spot and a "title · time · duration" pill that hugs its words; the selection ring hugs both.
    private var collapsed: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 80, height: 80).contentShape(.circle)
            HStack(spacing: 6) {
                Text(model.title(for: entry)).font(Typo.ui(12, .medium)).foregroundStyle(Tok.ink).lineLimit(1)
                Text("·")
                Text(entry.capturedAt.formatted(date: .omitted, time: .shortened)).fixedSize()
                if let ms = model.media[entry.mediaId ?? ""]?.durationMs {
                    Text("·")
                    Text(Duration.milliseconds(ms).formatted(.time(pattern: .minuteSecond))).fixedSize()
                }
                if let s = model.status(for: entry) {
                    Text(s).monoCaps(9.5, tracking: 0.06).foregroundStyle(Tok.ink3).lineLimit(1).fixedSize()
                }
            }
            .font(Typo.ui(12)).foregroundStyle(Tok.ink2)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Tok.paper.opacity(0.8), in: .capsule)
            .overlay(Capsule().strokeBorder(Tok.rim.opacity(0.6)))
            .elevation(.lift)
        }
        .overlay { if selected { Capsule().strokeBorder(Tok.sage.opacity(0.6), lineWidth: 2).padding(-4) } }
        .frame(width: CanvasMath.size(.voice).width, height: CanvasMath.size(.voice).height, alignment: .leading)
    }
}

private struct Fade: ViewModifier {
    let opacity: Double
    func body(content: Content) -> some View { content.opacity(opacity) }
}

/// The open voice note: play/pause under the orb, a 6 pt track with mono times, then the title, Saro's line and the
/// timed transcript in a scroller capped at 480 pt. "What Saro heard" opens the full detail.
private struct VoicePanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: Entry
    let player: PlayerModel?
    let sentences: [TimedSentence]
    let selected: Bool
    @State private var contentHeight: CGFloat = 0
    @State private var closeHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Button { player?.toggle() } label: { Color.clear.frame(width: 64, height: 64).contentShape(.circle) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player?.playing == true ? "Pause" : "Play")
                track
            }
            .padding(.trailing, 48)
            ScrollView {
                details
                    .padding(.trailing, 4)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, 480))
            .padding(.top, 16)
            footer.padding(.top, 14)
        }
        .padding(20)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .background(Tok.surface, in: .rect(cornerRadius: Radius.sheet))
        .cardSurface(radius: Radius.sheet, tint: Tok.echo, tintOpacity: 0.3)
        .overlay(alignment: .topTrailing) { close.padding(16) }
        .overlay {
            if selected { RoundedRectangle(cornerRadius: Radius.sheet + 4).strokeBorder(Tok.sage.opacity(0.6), lineWidth: 2).padding(-4) }
        }
    }

    private var totalMs: Int? {
        [model.media[entry.mediaId ?? ""]?.durationMs, player?.durationMs].compactMap { $0 }.first { $0 > 0 }
    }

    private func clock(_ ms: Int) -> String { Duration.milliseconds(ms).formatted(.time(pattern: .minuteSecond)) }

    private var track: some View {
        let total = totalMs
        let now = min(player?.timeMs ?? 0, total ?? 0)
        let progress = total.map { Double(now) / Double($0) } ?? 0
        return VStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Tok.echo.opacity(0.25)
                    Tok.echoInk.frame(width: g.size.width * progress)
                }
                .frame(height: 6)
                .clipShape(.capsule)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    guard let total, g.size.width > 0 else { return }
                    player?.seek(ms: Int((v.location.x / g.size.width).clamped(to: 0...1) * Double(total)), play: false)
                })
            }
            .frame(height: 20)
            .animation(.linear(duration: 0.25), value: progress)
            HStack {
                Text(clock(now))
                Spacer()
                Text(total.map(clock) ?? "–:––")
            }
            .font(Typo.mono(11, .regular)).foregroundStyle(Tok.ink3)
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(clock(now)) of \(total.map(clock) ?? "unknown length")")
        .accessibilityAdjustableAction { direction in
            guard let total, let player else { return }
            player.seek(ms: (player.timeMs + (direction == .increment ? 5000 : -5000)).clamped(to: 0...total), play: false)
        }
    }

    private var details: some View {
        let title = model.title(for: entry)
        // The person's own summary (Edit Details) outranks Saro's (DR-04).
        let own = entry.summaryUser?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = own.flatMap { $0.isEmpty ? nil : $0 } ?? model.summary(for: entry).flatMap {
            Heuristics.summaryAddsSomething($0, title: title, transcript: sentences.map(\.text).joined(separator: " ")) ? $0 : nil
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text(title).font(Typo.ui(16, .semibold)).lineSpacing(2).foregroundStyle(Tok.echoInk)
            Eyebrow(entry: entry, noun: false).padding(.top, 4)
            if let summary {
                Text(Letter.typeset(summary)).font(Typo.serif(16, italic: true)).lineSpacing(4).foregroundStyle(Tok.ink2).padding(.top, 16)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Transcript").monoCaps(10.5, tracking: 0.12).foregroundStyle(Tok.ink3)
                TranscriptLines(entry: entry, sentences: sentences, player: player, size: 14.5)
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The entry's honest status, and the way to everything Saro said about it (or the SafetyCard in its place).
    private var footer: some View {
        HStack(spacing: 8) {
            if let s = model.status(for: entry) { Text(s).monoCaps(9.5, tracking: 0.06).foregroundStyle(Tok.ink3).lineLimit(1) }
            Spacer(minLength: 0)
            Button { model.openEntryID = entry.id } label: {
                HStack(spacing: 4) {
                    Text("What Saro heard")
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                }
                .font(Typo.ui(12, .medium)).foregroundStyle(Tok.echoInk)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
    }

    private var close: some View {
        Button { model.openVoice(nil, reduceMotion: reduceMotion) } label: {
            Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tok.ink)
                .frame(width: 36, height: 36)
                .background(closeHover ? Tok.bg : Tok.surface, in: .circle)
                .elevation(.lift)
                .contentShape(Circle().inset(by: -4))
        }
        .buttonStyle(PressStyle())
        .onHover { closeHover = $0 }
        .animation(Motion.fade, value: closeHover)
        .help("Close  esc")
        .accessibilityLabel("Close voice note")
    }
}
