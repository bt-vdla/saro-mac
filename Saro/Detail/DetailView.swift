import AVKit
import SaroKit
import SwiftUI

/// The opened card: an AVKit player with a timed transcript for moments and voice notes, an editor for writing,
/// and the image with its note and metadata for stills. Saro's reading sits beside it, or the state that stands in for it.
struct DetailView: View {
    @Environment(AppModel.self) private var model
    let entry: Entry

    var body: some View {
        Group {
            switch entry.kind {
            case .moment, .voice: MediaDetail(entry: entry)
            case .reflection, .music: WritingEditor(entry: entry)
            case .still: StillDetail(entry: entry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tok.surface)
        .overlay(alignment: .topTrailing) {
            Button { model.openEntryID = nil } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tok.ink2)
                    .frame(width: 36, height: 36)
                    .background(.frosted(), in: .circle)
                    .background(Tok.surface.opacity(0.8), in: .circle)
            }
            .buttonStyle(PressStyle())
            .keyboardShortcut(.cancelAction)
            .help("Close  esc")
            .padding(16)
        }
    }
}

/// The mono eyebrow over a detail: "TODAY · 4:16 PM · 0:42 · TURN 2".
struct Eyebrow: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    var noun = true
    var ink = Tok.ink3

    var body: some View {
        let day = entry.localDay == LocalDay.today() ? "Today" : DayFormat.sidebar(entry.localDay)
        let parts = [day, entry.capturedAt.formatted(date: .omitted, time: .shortened),
                     model.media[entry.mediaId ?? ""]?.durationMs.map { Duration.milliseconds($0).formatted(.time(pattern: .minuteSecond)) },
                     entry.sessionId != nil ? entry.turnNumber.map { "Turn \($0)" } : nil, noun ? entry.kind.noun : nil]
        Text(parts.compactMap { $0 }.joined(separator: " · ")).monoCaps(10.5, tracking: 0.12).foregroundStyle(ink)
    }
}

// MARK: Moments and voice notes

@Observable @MainActor
final class PlayerModel {
    let player: AVPlayer
    var timeMs = 0
    var playing = false
    /// The file's own length, for a recording whose row has none.
    var durationMs: Int?
    @ObservationIgnored private var token: Any?
    @ObservationIgnored private var ended: (any NSObjectProtocol)?

    init(url: URL) {
        player = AVPlayer(url: url)
        #if DOGFOOD
        // Snapshots run unattended, often at night.
        player.isMuted = UserDefaults.standard.string(forKey: "SaroSnapshot") != nil
        #endif
        // The observer also fires whenever playback starts or stops.
        token = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 5), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let m = self else { return }
                m.timeMs = Int(t.seconds * 1000)
                m.playing = m.player.rate != 0
                if let d = m.player.currentItem?.duration, d.isNumeric { m.durationMs = Int(d.seconds * 1000) }
            }
        }
        // ...but not when it plays to its end: its last call still sees rate 1. Back to the top, as the web's onEnded.
        ended = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem,
                                                       queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.playing = false
                self?.timeMs = 0
            }
        }
    }

    func seek(ms: Int, play: Bool = true) {
        player.seek(to: CMTime(value: Int64(ms), timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        if play { player.play() }
    }

    /// A note that played to its end starts again from the top.
    func toggle() {
        if player.rate != 0 {
            player.pause()
            return
        }
        if let item = player.currentItem, item.currentTime() >= item.duration { player.seek(to: .zero) }
        player.play()
    }

    func stop() {
        player.pause()
        if let token { player.removeTimeObserver(token) }
        token = nil
        if let ended { NotificationCenter.default.removeObserver(ended) }
        ended = nil
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
        GeometryReader { geo in
            if entry.kind == .moment {
                // Two columns from the web's VideoPlayerModal: [1fr, min(420, 40%)]. The video is black and flush with
                // the sheet's left, top and bottom edges; the sheet's own radius clips its corners.
                HStack(spacing: 0) {
                    playerArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                    side
                        .padding(.horizontal, 32).padding(.top, 32).padding(.bottom, 24)
                        .frame(width: min(420, geo.size.width * 0.4))
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    side(player: true)
                }
                .padding(.horizontal, 36).padding(.top, 32)
            }
        }
        .task(id: entry.id) {
            if let url = model.mediaURL(for: entry), FileManager.default.fileExists(atPath: url.path) { player = PlayerModel(url: url) }
            if let ms = model.memory.takePlayFrom(entry.id) { player?.seek(ms: ms) }
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

    private var side: some View { side(player: false) }

    private func side(player showPlayer: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(entry: entry)
                    TitleField(entry: entry)
                }
                .padding(.trailing, 44)
                if showPlayer { playerArea.frame(height: 56).clipShape(.rect(cornerRadius: Radius.field)) }
                ReadingSection(entry: entry, onQuote: { q in
                    if let s = sentences.first(where: { $0.text.contains(q) || q.contains($0.text) }) { player?.seek(ms: s.startMs) }
                })
                transcript
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.never)
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript").monoCaps(10.5, tracking: 0.12).foregroundStyle(Tok.ink3)
                Spacer()
                if !sentences.isEmpty {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(sentences.map(\.text).joined(separator: " "), forType: .string)
                        model.show(Toast("Transcript copied"))
                    }
                    .font(Typo.ui(12, .medium)).buttonStyle(.plain).foregroundStyle(Tok.ink2)
                    .padding(.horizontal, 12).frame(height: 28).background(Tok.ink.opacity(0.06), in: .capsule)
                }
            }
            TranscriptLines(entry: entry, sentences: sentences, player: player)
        }
    }
}

/// The timed transcript: tap a sentence to play from it; the playing one is lit. Or the honest state in its place.
struct TranscriptLines: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    let sentences: [TimedSentence]
    let player: PlayerModel?
    var size: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sentences.isEmpty {
                Text(state).font(Typo.ui(13)).foregroundStyle(Tok.ink3)
                if entry.processingStatus == ProcessingStatus.transcriptUnavailable {
                    Button("Try again") { model.retranscribe(entry) }.font(Typo.ui(12, .medium))
                }
            } else {
                ForEach(sentences) { s in
                    let current = (player?.timeMs ?? -1) >= s.startMs && (player?.timeMs ?? -1) < s.endMs
                    Button { player?.seek(ms: s.startMs) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Duration.milliseconds(s.startMs).formatted(.time(pattern: .minuteSecond)))
                                .font(Typo.mono(10)).foregroundStyle(Tok.ink4).frame(width: 34, alignment: .leading)
                            Text(s.text).font(Typo.ui(size)).lineSpacing(size * 0.4).foregroundStyle(current ? Tok.ink : Tok.ink2)
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

    private var state: String {
        switch entry.processingStatus {
        case ProcessingStatus.recording: "Still recording."
        case ProcessingStatus.pending, ProcessingStatus.transcribing: "Transcribing on this Mac…"
        case ProcessingStatus.transcriptUnavailable: "Transcript not ready. The recording is saved and plays; Saro tries again at launch, or now."
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
        TextField(model.title(for: entry), text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Typo.ui(20, .semibold))
            .lineLimit(1...3)
            .foregroundStyle(Tok.ink)
            .saroWritingTools()
            .onAppear { text = entry.titleUser ?? "" }
            .onSubmit { save() }
            .onDisappear { save() }
            .onQuit { save(quitting: true) }
    }

    private func save(quitting: Bool = false) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != (entry.titleUser ?? "") else { return }
        let title = t.isEmpty ? nil : t
        if quitting { model.ledger.updateEntryTextBeforeQuit(id: entry.id, body: entry.body, titleUser: title, captionUser: entry.captionUser); return }
        Task {
            try? await model.ledger.updateEntryText(id: entry.id, body: entry.body, titleUser: title, captionUser: entry.captionUser)
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
    /// The question the page answers (its prompt row), if it has one.
    @State private var prompt: String?

    var body: some View {
        // The web's reading page: the user's words in Geist 17/1.7, at most ~62 characters a line.
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(entry: entry)
                // Never on a held day: an older hand-off could have kept the day's reading question here (SR-13).
                if let prompt, !model.isDayHeld {
                    Text(prompt).font(Typo.serif(22)).tracking(-0.22).lineSpacing(4).foregroundStyle(Tok.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Prompt: \(prompt)")
                }
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Write what's on your mind. The first line becomes the title.")
                            .font(Typo.ui(17)).foregroundStyle(Tok.ink4).padding(.top, 1).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(Typo.ui(17))
                        .lineSpacing(8)
                        .foregroundStyle(Tok.ink)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .saroWritingTools()
                }
            }
            .frame(maxWidth: 600, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 48).padding(.top, 40).padding(.bottom, 24)
            Spacer(minLength: 24)
            ScrollView { ReadingSection(entry: entry, onQuote: nil).padding(.top, 72).padding(.trailing, 24) }
                .scrollIndicators(.never)
                .frame(width: 260)
        }
        .onAppear {
            text = entry.body ?? ""
            loaded = true
        }
        .task(id: entry.id) { prompt = try? await model.ledger.turns(entryId: entry.id).first { $0.kind == .prompt }?.question }
        .task(id: text) {
            guard loaded else { return }
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            await save(process: false)
        }
        .onDisappear { Task { await save(process: true) } }
        .onQuit {
            guard loaded, text != (model.entry(entry.id)?.body ?? "") else { return }
            model.ledger.updateEntryTextBeforeQuit(id: entry.id, body: text, titleUser: entry.titleUser)
        }
    }

    private func save(process: Bool) async {
        let body = text
        if body != (model.entry(entry.id)?.body ?? "") {
            try? await model.ledger.updateEntryText(id: entry.id, body: body, titleUser: entry.titleUser, captionUser: entry.captionUser)
            await model.edited(entry.id)
        }
        guard process else { return }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try? await model.ledger.discardIfEmpty(entry.id) }
        await model.reload()
        // Always, even when emptied (an entry that was gated is kept, and must not stay pending): the pipeline skips text
        // it has already gated and read, and an autosave may have saved the edit.
        model.process(entry.id)
    }
}

// MARK: Stills

/// The opened still is the photo alone, in its own shape (EntryViews.tsx StillView): the flight lands on it, and what
/// Saro sees sits under it on the scrim (`StillBelow`).
private struct StillDetail: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    @State private var image: NSImage?
    @State private var missing = false

    var body: some View {
        ZStack {
            Tok.still.opacity(0.15)
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .accessibilityLabel(model.caption(for: entry) ?? "Still")
            } else if missing {
                ContentUnavailableView("Photo not found", systemImage: "photo", description: Text("The file for this still is missing."))
            }
        }
        .task(id: entry.id) {
            guard let url = model.mediaURL(for: entry), FileManager.default.fileExists(atPath: url.path) else {
                missing = true
                return
            }
            // The card's thumbnail first, so the flight lands on the photo, then a sharp one decoded off the main actor.
            image = await ThumbCache.image(for: url, kind: .still)
            if let sharp = await Task.detached(operation: { ThumbCache.thumbnail(url, max: 2400) }).value {
                image = NSImage(cgImage: sharp, size: NSSize(width: sharp.width, height: sharp.height))
            }
        }
    }
}

/// Under the opened photo (P-STILLS): what Saro sees, its tags and provenance, editable in place, the date and the
/// photo's details. An edit is the user's caption, gated like any typed text, and outranks Saro's (DR-04); clearing it
/// brings Saro's back.
struct StillBelow: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    @State private var caption = ""
    @State private var described: StillCaption?
    @State private var loaded = false
    @State private var pixels: CGSize?
    /// The run that stood when Describe again was pressed; the spinner shows while that pass is queued or under way.
    @State private var asked: String??
    @FocusState private var editing: Bool

    /// The room `CanvasMath.stillFrame` leaves under the photo: a hold shows the helplines.
    static func room(held: Bool) -> CGFloat { held ? 400 : 172 }

    private var verdict: String? { model.verdicts[entry.id]?.verdict }
    private var held: Bool { verdict == "safety_hold" }
    private var yours: String? { entry.captionUser.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } }
    /// Saro's description, only while the still's newest check is a clear and nothing since has held the description or
    /// left it waiting (a hold deletes it, SR-15), and never on a held day (SR-13).
    private var saros: String? {
        guard !model.isDayHeld, verdict == "clear" || verdict == "unavailable_clear", let d = described, !d.standsHeld else { return nil }
        return d.caption
    }
    private var showingSaros: Bool { yours == nil && saros != nil && caption.trimmingCharacters(in: .whitespaces) == saros }
    private var working: Bool { model.isQueued(entry.id) && (asked != nil || described == nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(showingSaros || working && yours == nil ? "Saro sees" : "Your caption")
                    .monoCaps(10.5, tracking: 0.12).foregroundStyle(showingSaros ? Tok.voice : Tok.ink2)
                Spacer(minLength: 16)
                // ink-2, not ink-3: this line sits on the see-through scrim, not a surface.
                Eyebrow(entry: entry, noun: false, ink: Tok.ink2)
            }
            // Saro's words in Newsreader, the user's in Geist: typing over Saro's description makes it yours.
            TextField("Caption", text: $caption, prompt: Text(saros ?? "Add a caption…").foregroundStyle(Tok.ink4), axis: .vertical)
                .textFieldStyle(.plain)
                .font(showingSaros ? Typo.serif(18) : Typo.ui(15, .medium))
                .lineSpacing(3)
                .foregroundStyle(Tok.ink)
                .lineLimit(1...4)
                .saroWritingTools()
                .focused($editing)
                .onSubmit { save() }
                .onChange(of: editing) { _, now in if !now { save() } }
                .accessibilityLabel(showingSaros ? "Saro's description" : "Your caption")
            below
            HStack(alignment: .center, spacing: 16) {
                Text(details).monoCaps(10, tracking: 0.08).foregroundStyle(Tok.ink3).lineLimit(1)
                Spacer(minLength: 0)
                if !model.isDayHeld, model.mediaURL(for: entry) != nil { describeButton }
            }
            .padding(.top, 2)
        }
        .contentShape(.rect)
        .animation(Motion.fade, value: described?.runId)
        .animation(Motion.fade, value: working)
        .onDisappear { save() }
        .onQuit { save(quitting: true) }
        .task(id: entry.id) {
            guard let url = model.mediaURL(for: entry) else { return }
            pixels = await Task.detached { StillVision.pixelSize(at: url) }.value
        }
        .task(id: "\(entry.processingStatus)\(entry.captionUser ?? "")\(verdict ?? "")\(model.verdicts[entry.id]?.id ?? "")\(model.annotations[entry.id]?.id ?? "")") {
            described = try? await model.ledger.stillCaption(entryId: entry.id)
            loaded = true
            if let a = asked, described?.runId != a { asked = nil }
            if !editing { caption = yours ?? saros ?? "" }
        }
    }

    private var describeButton: some View {
        Button(action: describeAgain) {
            Label(described == nil ? "Describe" : "Describe again", systemImage: "arrow.clockwise")
                .font(Typo.ui(12, .medium)).foregroundStyle(Tok.ink2)
                .padding(.horizontal, 10).frame(height: 26).background(Tok.ink.opacity(0.06), in: .capsule)
        }
        .buttonStyle(PressStyle())
        .disabled(working)
        .keyboardShortcut("r", modifiers: .command)
        .help("Describe this photo again on this Mac  ⌘R")
    }

    @ViewBuilder private var below: some View {
        if held {
            SafetyNotice()
        } else if model.isDayHeld {
            // A safety hold anywhere that day hides every entry's AI text (SR-13).
            Text("Saro isn't writing about this day. This photo is kept, and your caption is always yours to change.")
                .font(Typo.ui(13)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
        } else if working {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Saro is looking at this photo…").font(Typo.ui(13)).foregroundStyle(Tok.ink2)
            }
            .accessibilityElement(children: .combine)
        } else if yours != nil, verdict == "unavailable_caution" {
            // The user's own caption waits for a check (SR-14): nothing of Saro's shows until it is checked.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Saro will read this when Apple Intelligence is ready.").font(Typo.ui(13)).foregroundStyle(Tok.ink2)
                Button("Talk to someone") { model.safetyCardRequested = true }.buttonStyle(.link).font(Typo.ui(12))
            }
        } else if let saros, let d = described {
            if yours != nil {
                Text("Saro sees “\(saros)”").font(Typo.serif(14, italic: true)).foregroundStyle(Tok.ink2)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                if !d.tags.isEmpty {
                    Text(d.tags.joined(separator: "  ·  ")).monoCaps(10, tracking: 0.08).foregroundStyle(Tok.stillInk).lineLimit(1)
                        .accessibilityLabel("Tags: \(d.tags.joined(separator: ", "))")
                }
                Spacer(minLength: 0)
                Text(provenance(d)).monoCaps(10, tracking: 0.08).foregroundStyle(Tok.ink3).lineLimit(1)
                    .accessibilityLabel(d.executor == "heuristic" ? "Described on this Mac by Vision" : "Described on this Mac by Apple Intelligence")
            }
        } else if yours == nil, let line = statusLine {
            Text(line).font(Typo.ui(13)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The honest line when there is no description to show.
    private var statusLine: String? {
        switch described?.status {
        case "guardrail", "refusal": "Saro didn't describe this photo. A caption of your own is always welcome."
        case "unreadable": "Saro couldn't open this photo to describe it."
        case StillCaption.caution: "Saro will describe this when Apple Intelligence is ready."
        case nil where loaded: "Saro hasn't described this photo yet."
        default: nil
        }
    }

    /// "4032 × 3024 · FROM DROPPED · LOCATION REMOVED".
    private var details: String {
        let size = pixels.map { "\(Int($0.width)) × \(Int($0.height))" }
        return [size, model.media[entry.mediaId ?? ""].map { "From \($0.origin)" }, "Location removed"].compactMap { $0 }.joined(separator: " · ")
    }

    /// "ON DEVICE · AFM 3 CORE ADVANCED · GUIDED · 940 MS", or Vision's.
    private func provenance(_ d: StillCaption) -> String {
        let parts = d.executor == "heuristic" ? ["Vision", "on this Mac"] : ["On device", d.variant, d.rung]
        return (parts + [d.latencyMs.map { "\($0) ms" }]).compactMap { $0 }.joined(separator: " · ").uppercased()
    }

    private func describeAgain() {
        save()
        asked = .some(described?.runId)
        Task {
            await model.pipeline.describeAgain(entry.id)
            model.process(entry.id)
        }
    }

    private func save(quitting: Bool = false) {
        let c = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        // Saro's words left as they were stay Saro's (DR-04): only an edit becomes the user's caption.
        let mine = c.isEmpty || yours == nil && c == saros ? nil : c
        guard mine != yours else { return }
        if quitting { model.ledger.updateEntryTextBeforeQuit(id: entry.id, body: entry.body, titleUser: entry.titleUser, captionUser: mine); return }
        Task {
            try? await model.ledger.updateEntryText(id: entry.id, body: entry.body, titleUser: entry.titleUser, captionUser: mine)
            await model.reload()
            // Always: a cleared caption brings Saro's description back as the still's reading.
            model.process(entry.id)
        }
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
            Text("What Saro heard").monoCaps(10.5, tracking: 0.12).foregroundStyle(Tok.ink3)
            content
        }
        .task(id: model.annotations[entry.id]?.aiRunId) { await loadProvenance() }
    }

    @ViewBuilder private var content: some View {
        switch model.verdicts[entry.id]?.verdict {
        case "safety_hold":
            SafetyNotice()
        case "technical_hold":
            Text("Saro couldn't hear this one clearly. The recording is saved and plays.").font(Typo.ui(13)).foregroundStyle(Tok.ink2)
            Button("Try again") { model.retranscribe(entry) }.font(Typo.ui(12, .medium))
        case "unavailable_caution":
            Text("Saro will read this when Apple Intelligence is ready.").font(Typo.ui(13)).foregroundStyle(Tok.ink2)
            Button("Talk to someone") { model.safetyCardRequested = true }
                .buttonStyle(.link).font(Typo.ui(12))
        case "clear", "unavailable_clear":
            // A safety hold anywhere that day hides every entry's reading, mood, quote and 'In your words' (SR-13).
            if model.isDayHeld {
                Text("Saro isn't writing about this day. This entry is kept, and you can play or read it any time.")
                    .font(Typo.ui(13)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
            } else if let a = model.annotations[entry.id] {
                annotation(a)
            } else {
                Text("Reading…").font(Typo.ui(13)).foregroundStyle(Tok.ink3)
            }
        default:
            Text(entry.kind == .still && entry.captionUser == nil ? "Add a note and Saro will read it." : "Saro reads each entry on this Mac once it's saved.")
                .font(Typo.ui(13)).foregroundStyle(Tok.ink3)
        }
    }

    @ViewBuilder private func annotation(_ a: EntryAnnotation) -> some View {
        if a.generator == "heuristic" {
            Text("IN YOUR WORDS").font(Typo.mono(9.5)).foregroundStyle(Tok.voice)
        }
        if let s = a.summary { Text(Letter.typeset(s)).font(Typo.serif(17, italic: true)).foregroundStyle(Tok.voice).fixedSize(horizontal: false, vertical: true) }
        if let q = a.quote {
            Button { onQuote?(q) } label: {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle().fill(Tok.sageSoft).frame(width: 2)
                    Text("“\(q)”").font(Typo.serif(14.5, italic: true)).foregroundStyle(Tok.ink2).multilineTextAlignment(.leading)
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

private extension View {
    /// ⌘Q never runs onDisappear: an edit not yet saved is written here, before the app exits.
    func onQuit(_ action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in action() }
    }
}

/// A safety hold never shows nothing (§13.2): the entry stays saved and playable, and the resources take the reading's place.
struct SafetyNotice: View {
    var body: some View {
        Text("Saro saved this and won't write about it. If any of it is weighing on you, these people will listen.")
            .font(Typo.ui(13)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
        SafetyCardView(compact: true)
    }
}
