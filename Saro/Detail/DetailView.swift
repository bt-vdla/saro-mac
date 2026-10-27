import AVKit
import SaroKit
import SwiftUI

/// The opened card: an AVKit player with a timed transcript for moments and voice notes, an editor for writing,
/// and the image with its palette for stills. Saro's reading sits beside it, or the state that stands in for it.
struct DetailView: View {
    @Environment(AppModel.self) private var model
    let entry: Entry

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Tok.border)
            switch entry.kind {
            case .moment, .voice: MediaDetail(entry: entry)
            case .reflection, .music: WritingEditor(entry: entry)
            case .still: StillDetail(entry: entry)
            }
        }
        .background(Tok.surface)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(entry.kind.tint).frame(width: 8, height: 8)
            Text(entry.kind.noun.uppercased()).font(Typo.mono(10.5)).foregroundStyle(Tok.ink2)
            Text(entry.capturedAt.formatted(.dateTime.weekday(.wide).day().month().hour().minute()).uppercased())
                .font(Typo.mono(10.5)).foregroundStyle(Tok.ink3)
            if let n = entry.turnNumber, entry.sessionId != nil { Text("TURN \(n)").font(Typo.mono(10.5)).foregroundStyle(Tok.ink3) }
            Spacer()
            Button { model.openEntryID = nil } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26)
                    .background(Tok.bg, in: .circle)
            }
            .buttonStyle(.plain).foregroundStyle(Tok.ink2)
            .keyboardShortcut(.cancelAction)
            .help("Close  esc")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

// MARK: Moments and voice notes

@Observable @MainActor
final class PlayerModel {
    let player: AVPlayer
    var timeMs = 0
    @ObservationIgnored private var token: Any?

    init(url: URL) {
        player = AVPlayer(url: url)
        token = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 5), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.timeMs = Int(t.seconds * 1000) }
        }
    }

    func seek(ms: Int) {
        player.seek(to: CMTime(value: Int64(ms), timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    func stop() {
        player.pause()
        if let token { player.removeTimeObserver(token) }
        token = nil
    }
}

struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    var compact = false

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = compact ? .inline : .floating
        v.showsFullScreenToggleButton = !compact
        v.videoGravity = .resizeAspect
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
    }
}

struct TimedSentence: Identifiable, Hashable {
    let id: Int
    let text: String
    let startMs: Int
    let endMs: Int
}

/// Transcript sentences with an end time, so the playing one can be highlighted.
func timedSentences(_ words: [TranscriptWord]) -> [TimedSentence] {
    let s = Transcriber.sentences(from: words)
    let end = words.last.map { $0.startMs + $0.durMs } ?? 0
    return s.enumerated().map { i, x in
        TimedSentence(id: i, text: x.text, startMs: x.startMs, endMs: i + 1 < s.count ? s[i + 1].startMs : end)
    }
}

private struct MediaDetail: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    @State private var player: PlayerModel?
    @State private var sentences: [TimedSentence] = []

    var body: some View {
        Group {
            if entry.kind == .moment {
                HStack(spacing: 0) {
                    playerArea.frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
                    Divider().overlay(Tok.border)
                    side.frame(width: 360)
                }
            } else {
                VStack(spacing: 0) {
                    playerArea.frame(height: 64).padding(.horizontal, 20).padding(.top, 12)
                    side
                }
            }
        }
        .task(id: entry.id) {
            if let url = model.mediaURL(for: entry), FileManager.default.fileExists(atPath: url.path) { player = PlayerModel(url: url) }
            await loadTranscript()
        }
        .onChange(of: entry.processingStatus) { _, _ in Task { await loadTranscript() } }
        .onDisappear { player?.stop() }
    }

    private func loadTranscript() async {
        guard let id = entry.mediaId, let words = try? await model.ledger.transcript(mediaId: id) else { return }
        sentences = timedSentences(words)
    }

    @ViewBuilder private var playerArea: some View {
        if let player {
            PlayerSurface(player: player.player, compact: entry.kind == .voice)
        } else {
            ContentUnavailableView("Recording not found", systemImage: "exclamationmark.triangle",
                                   description: Text("The file for this entry is missing."))
        }
    }

    private var side: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TitleField(entry: entry)
                ReadingSection(entry: entry, onQuote: { q in
                    if let s = sentences.first(where: { $0.text.contains(q) || q.contains($0.text) }) { player?.seek(ms: s.startMs) }
                })
                transcript
            }
            .padding(20)
        }
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRANSCRIPT").font(Typo.mono(10)).foregroundStyle(Tok.ink3)
            if sentences.isEmpty {
                Text(transcriptState).font(Typo.ui(13)).foregroundStyle(Tok.ink3)
            } else {
                ForEach(sentences) { s in
                    let current = (player?.timeMs ?? -1) >= s.startMs && (player?.timeMs ?? -1) < s.endMs
                    Button { player?.seek(ms: s.startMs) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Duration.milliseconds(s.startMs).formatted(.time(pattern: .minuteSecond)))
                                .font(Typo.mono(10)).foregroundStyle(Tok.ink4).frame(width: 34, alignment: .leading)
                            Text(s.text).font(Typo.ui(13.5)).foregroundStyle(current ? Tok.ink : Tok.ink2)
                                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 4).padding(.horizontal, 6)
                        .background(current ? Tok.sage.opacity(0.1) : .clear, in: .rect(cornerRadius: 6))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Play from here")
                }
            }
        }
    }

    private var transcriptState: String {
        switch entry.processingStatus {
        case ProcessingStatus.recording: "Still recording."
        case ProcessingStatus.pending, ProcessingStatus.transcribing: "Transcribing on this Mac…"
        case ProcessingStatus.transcriptUnavailable: "Transcript not ready. The recording is saved and plays; Saro will try again."
        default: "No speech heard."
        }
    }
}

/// The user's own title; it outranks Saro's (DR-04).
private struct TitleField: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    @State private var text = ""

    var body: some View {
        TextField(model.title(for: entry), text: $text)
            .textFieldStyle(.plain)
            .font(Typo.serif(22, .medium))
            .foregroundStyle(Tok.ink)
            .onAppear { text = entry.titleUser ?? "" }
            .onSubmit { save() }
            .onDisappear { save() }
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != (entry.titleUser ?? "") else { return }
        Task {
            try? await model.ledger.updateEntryText(id: entry.id, body: entry.body, titleUser: t.isEmpty ? nil : t, captionUser: entry.captionUser)
            await model.reload()
        }
    }
}

// MARK: Writing

private struct WritingEditor: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Write what's on your mind. The first line becomes the title.")
                        .font(Typo.serif(19)).foregroundStyle(Tok.ink4).padding(.top, 1).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(Typo.serif(19))
                    .lineSpacing(5)
                    .foregroundStyle(Tok.ink)
                    .scrollContentBackground(.hidden)
                    .writingToolsBehavior(.disabled)
            }
            .padding(.horizontal, 56).padding(.vertical, 36)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(Tok.border)
            ScrollView { ReadingSection(entry: entry, onQuote: nil).padding(20) }.frame(width: 320)
        }
        .onAppear {
            text = entry.body ?? ""
            loaded = true
        }
        .task(id: text) {
            guard loaded else { return }
            try? await Task.sleep(for: .milliseconds(800))
            await save(process: false)
        }
        .onDisappear { Task { await save(process: true) } }
    }

    private func save(process: Bool) async {
        let body = text
        let changed = body != (model.entry(entry.id)?.body ?? "")
        if changed { try? await model.ledger.updateEntryText(id: entry.id, body: body, titleUser: entry.titleUser) }
        if process {
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try? await model.ledger.discardIfEmpty(entry.id)
                await model.reload()
                return
            }
            await model.reload()
            if changed || model.verdicts[entry.id] == nil { model.process(entry.id) }
        }
    }
}

// MARK: Stills

private struct StillDetail: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    @State private var image: NSImage?
    @State private var palette: [Color] = []
    @State private var caption = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("PALETTE").font(Typo.mono(10)).foregroundStyle(Tok.ink3)
                ForEach(Array(palette.enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 8).fill(c).frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Tok.border))
                }
                Spacer()
            }
            .padding(20)
            ZStack {
                Tok.bg
                if let image { Image(nsImage: image).resizable().scaledToFit().padding(24) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 14) {
                Text("NOTE").font(Typo.mono(10)).foregroundStyle(Tok.ink3)
                TextField("Write a note…", text: $caption, axis: .vertical)
                    .textFieldStyle(.plain).font(Typo.serif(16)).lineLimit(3...10)
                    .onSubmit { save() }
                Divider()
                if let image {
                    meta("SIZE", "\(Int(image.size.width)) × \(Int(image.size.height))")
                }
                meta("SAVED", entry.capturedAt.formatted(date: .abbreviated, time: .shortened))
                meta("FROM", model.media[entry.mediaId ?? ""]?.origin.uppercased() ?? "—")
                meta("LOCATION", "REMOVED")
                Spacer()
            }
            .padding(20)
            .frame(width: 280)
        }
        .onAppear { caption = entry.captionUser ?? "" }
        .onDisappear { save() }
        .task(id: entry.id) {
            guard let url = model.mediaURL(for: entry) else { return }
            image = NSImage(contentsOf: url)
            if let cg = ThumbCache.thumbnail(url, max: 48) { palette = Palette.colors(cg).map { Color(cgColor: $0) } }
        }
    }

    private func meta(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Typo.mono(10)).foregroundStyle(Tok.ink3)
            Spacer()
            Text(v.uppercased()).font(Typo.mono(10)).foregroundStyle(Tok.ink2)
        }
    }

    private func save() {
        let c = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard c != (entry.captionUser ?? "") else { return }
        Task {
            try? await model.ledger.updateEntryText(id: entry.id, body: entry.body, titleUser: entry.titleUser, captionUser: c.isEmpty ? nil : c)
            await model.reload()
            if !c.isEmpty { model.process(entry.id) }
        }
    }
}

enum Palette {
    /// ponytail: 4-bit-per-channel buckets over a 48 px thumbnail, top five distinct; k-means if it ever matters.
    static func colors(_ image: CGImage, count: Int = 5) -> [CGColor] {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var buckets: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            let cur = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (cur.n + 1, cur.r + r, cur.g + g, cur.b + b)
        }
        var picked: [(Int, Int, Int)] = []
        for v in buckets.values.sorted(by: { $0.n > $1.n }) {
            let c = (v.r / v.n, v.g / v.n, v.b / v.n)
            if picked.allSatisfy({ abs($0.0 - c.0) + abs($0.1 - c.1) + abs($0.2 - c.2) > 60 }) { picked.append(c) }
            if picked.count == count { break }
        }
        return picked.map { CGColor(srgbRed: CGFloat($0.0) / 255, green: CGFloat($0.1) / 255, blue: CGFloat($0.2) / 255, alpha: 1) }
    }
}

// MARK: Saro's reading, or the honest state in its place (§13.2)

struct ReadingSection: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    let onQuote: ((String) -> Void)?
    @State private var provenance: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT SARO HEARD").font(Typo.mono(10)).foregroundStyle(Tok.ink3)
            content
        }
        .padding(14)
        .background(Tok.bg.opacity(0.6), in: .rect(cornerRadius: 12))
        .task(id: model.annotations[entry.id]?.aiRunId) { await loadProvenance() }
    }

    @ViewBuilder private var content: some View {
        switch model.verdicts[entry.id]?.verdict {
        case "safety_hold":
            SafetyNotice()
        case "technical_hold":
            Text("Saro couldn't hear this one clearly. The recording is saved and plays.").font(Typo.ui(13)).foregroundStyle(Tok.ink2)
            Button("Try again") { model.process(entry.id) }.font(Typo.ui(12, .medium))
        case "unavailable_caution":
            Text("Saro will read this when Apple Intelligence is ready.").font(Typo.ui(13)).foregroundStyle(Tok.ink2)
            Button("Talk to someone") { NotificationCenter.default.post(name: .showSafetyCard, object: nil) }
                .buttonStyle(.link).font(Typo.ui(12))
        case "clear", "unavailable_clear":
            if let a = model.annotations[entry.id] { annotation(a) } else { Text("Reading…").font(Typo.ui(13)).foregroundStyle(Tok.ink3) }
        default:
            Text(entry.kind == .still && entry.captionUser == nil ? "Add a note and Saro will read it." : "Saro reads each entry on this Mac once it's saved.")
                .font(Typo.ui(13)).foregroundStyle(Tok.ink3)
        }
    }

    @ViewBuilder private func annotation(_ a: EntryAnnotation) -> some View {
        if a.generator == "heuristic" {
            Text("IN YOUR WORDS").font(Typo.mono(9.5)).foregroundStyle(Tok.voice)
        }
        if let s = a.summary { Text(s).font(Typo.serif(16)).foregroundStyle(Tok.voice).fixedSize(horizontal: false, vertical: true) }
        if let q = a.quote {
            Button { onQuote?(q) } label: {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle().fill(Tok.sageSoft).frame(width: 2)
                    Text("“\(q)”").font(Typo.serif(14.5)).italic().foregroundStyle(Tok.ink2).multilineTextAlignment(.leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .disabled(onQuote == nil)
            .help(onQuote == nil ? "" : "Play from here")
        }
        if let m = a.moodLabel {
            Text(m.uppercased()).font(Typo.mono(10)).foregroundStyle(Tok.sageTeal)
                .padding(.horizontal, 8).padding(.vertical, 3).background(Tok.sage.opacity(0.1), in: .capsule)
        }
        if let provenance { Text(provenance).font(Typo.mono(9)).foregroundStyle(Tok.ink4) }
    }

    private func loadProvenance() async {
        guard let id = model.annotations[entry.id]?.aiRunId,
              let r = try? await model.ledger.run("SELECT executor, ladder_rung, variant, latency_ms FROM ai_run WHERE id=?", [.text(id)]).first
        else { provenance = nil; return }
        let parts = [r["executor"]?.string, r["variant"]?.string, r["ladder_rung"]?.string, r["latency_ms"]?.int.map { "\($0) MS" }]
        provenance = parts.compactMap { $0?.replacingOccurrences(of: "_", with: " ").uppercased() }.joined(separator: " · ")
    }
}

extension Notification.Name {
    static let showSafetyCard = Notification.Name("saro.showSafetyCard")
}

/// A safety hold never shows nothing (§13.2): the entry stays saved and playable, and the resources take the reading's place.
struct SafetyNotice: View {
    var body: some View {
        Text("Saro saved this and won't write about it. If any of it is weighing on you, these people will listen.")
            .font(Typo.ui(13)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
        SafetyCardView(compact: true)
    }
}
