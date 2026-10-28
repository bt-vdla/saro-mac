import AppKit
import AVFoundation
import ImageIO
import Observation
import SaroKit
import UniformTypeIdentifiers

/// Capture's own window state, beside the model: the music field and the card being edited in place.
@Observable @MainActor
final class CaptureUI {
    static let shared = CaptureUI()

    /// The music field is up; `musicGrows` when a click opened it, so it grows out of its button.
    var musicOpen = false
    var musicGrows = false
    /// The reflection card whose title or body is being typed into, and which.
    var editing: (id: String, field: CardField)?
    /// A developed frame flying from the recorder into its card.
    var landing: Landing?
    /// The set's Play all: the moment detail opens playing every turn in order.
    var playAll = false
    /// Each entry's prompt: the question its recording answered or its page was started from.
    private(set) var prompts: [String: ReflectionTurn] = [:]

    enum CardField { case title, body }

    struct Landing: Equatable {
        let id = UUID()
        let image: CGImage
        /// Where the frame was, in the day's space.
        let from: CGRect
        let entryId: String

        static func == (a: Landing, b: Landing) -> Bool { a.id == b.id }
    }

    private init() {}

    /// The day's prompt rows, read again whenever its entries change.
    func loadPrompts(_ model: AppModel) async {
        let rows = (try? await model.ledger.turns(day: model.day, kind: .prompt)) ?? []
        prompts = Dictionary(rows.compactMap { t in t.entryId.map { ($0, t) } }, uniquingKeysWith: { a, _ in a })
    }
}

extension AppModel {
    /// The question an entry answers, never on a held day (SR-13), and never an emptied one.
    func prompt(for e: Entry) -> String? {
        guard !isDayHeld, let q = CaptureUI.shared.prompts[e.id]?.question, !q.isEmpty else { return nil }
        return q
    }

    /// A page's title field with nothing typed: what the card shows for it (its first line, or Saro's title once read),
    /// else "Untitled".
    func untitled(_ e: Entry) -> String {
        var bare = e
        bare.titleUser = nil
        let t = title(for: bare)
        return t == e.kind.noun ? "Untitled" : t
    }

    /// The person's own words for an entry (DR-04), keeping the fields not edited; changed text is gated and read again.
    @discardableResult
    func saveText(_ e: Entry, body: String?, title: String?, caption: String?) async -> Bool {
        do {
            try await saves.track(e.id) { [weak self] in
                try await self?.ledger.updateEntryText(id: e.id, body: body, titleUser: title, captionUser: caption)
                await self?.reload()
                self?.process(e.id)
            }
            return true
        } catch {
            show(.failed("Couldn't save your changes", error, retry: { [weak self] in Task { await self?.saves.retry(e.id) } }))
            return false
        }
    }

    // MARK: Stills

    /// Adds photos chosen in an open panel as stills on the day on screen, fanned from `at` when given.
    func pickStill(at point: CGPoint? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose photos to keep as stills. Location data is removed."
        guard panel.runModal() == .OK else { return }
        Task { await importMedia(panel.urls, at: point) }
    }

    /// Saves a dropped or pasted image as HEIC, at most 4096 px (FR-CAP-07), with no metadata but its orientation (DR-11:
    /// stills lose GPS).
    @discardableResult
    func importStill(_ data: Data, origin: String, at world: CGPoint?, toast: Bool = true, day: String? = nil) async -> Entry? {
        var entry = Entry(kind: .still, localDay: day ?? self.day, processingStatus: ProcessingStatus.pending)
        let asset = MediaAsset(fileName: "\(entry.localDay)/stills/\(entry.id).heic", kind: .image, origin: origin, state: "ready")
        entry.mediaId = asset.id
        let url = ledger.url(for: asset)
        do {
            // Off the main actor: the HEIC encoder's setup and a large photo's encode stall the UI (a main-thread runtime issue).
            guard try await Task.detached(operation: { try Self.writeHEIC(data, to: url) }).value else {
                show(Toast(title: "That file isn't an image Saro can read", detail: "Try a JPEG, PNG or HEIC photo.", style: .destructive))
                return nil
            }
            let id = entry.id
            try await saves.track(id) { [weak self, ledger, entry] in
                if try await ledger.media(asset.id) == nil { try await ledger.insertMedia(asset) }
                if try await ledger.entry(id) == nil { try await ledger.insertEntry(entry) }
                Task { await Posters.ensure(asset, in: ledger) }
                if let world { await self?.place(id, at: world) }
                await self?.reload()
                self?.process(id)
            }
            if toast { show(Toast("Still saved to \(DayFormat.sidebar(entry.localDay))")) }
            return entry
        } catch {
            show(.failed("Couldn't save the still", error, retry: { [weak self, id = entry.id] in Task { await self?.saves.retry(id) } }))
            return nil
        }
    }

    /// False when `data` isn't an image ImageIO can read.
    private nonisolated static func writeHEIC(_ data: Data, to url: URL) throws -> Bool {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let image = StillVision.keepable(src) else { return false }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let orientation = props?[kCGImagePropertyOrientation] ?? 1
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.heic" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85, kCGImagePropertyOrientation: orientation] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return true
    }

    // MARK: Music

    /// A song from a link (FR-CAP-09): the link is the person's own words, kept in the body, and read offline only. No AI
    /// reads it, so it is done as soon as it is saved.
    @discardableResult
    func newMusic(url: URL, at world: CGPoint?) async -> Entry? {
        let e = Entry(kind: .music, body: url.absoluteString, localDay: day, processingStatus: ProcessingStatus.done)
        do {
            try await saves.track(e.id) { [weak self, ledger] in
                if try await ledger.entry(e.id) == nil { try await ledger.insertEntry(e) }
                if let world { await self?.place(e.id, at: world) }
                await self?.reload()
            }
            return e
        } catch {
            show(.failed("Couldn't save the song", error, retry: { [weak self] in Task { await self?.saves.retry(e.id) } }))
            return nil
        }
    }

    // MARK: Import (FR-CAP-09)

    /// File > Import Media…: photos, audio and video, any number at once.
    func pickMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .audio, .movie]
        panel.allowsMultipleSelection = true
        panel.message = "Choose photos, audio or video to add to \(DayFormat.sidebar(day))."
        panel.prompt = "Import"
        guard panel.runModal() == .OK else { return }
        Task { await importMedia(panel.urls, at: nil) }
    }

    /// Each file becomes the entry it is; a batch dropped at a point lands on a grid around it.
    func importMedia(_ urls: [URL], at world: CGPoint?, origin: String = "picked", day: String? = nil) async {
        let files = urls.compactMap { url in Import.kind(of: url).map { (url, $0) } }
        if files.count < urls.count { show(Toast("Saro keeps photos, audio and video", style: .destructive)) }
        let spots = world.map { Import.grid(count: files.count, around: $0) }
        var added = 0
        for (i, (url, kind)) in files.enumerated() {
            let at = spots?[i]
            if kind == .still {
                guard let data = await Task.detached(operation: { try? Data(contentsOf: url) }).value else { continue }
                if await importStill(data, origin: origin, at: at, toast: files.count == 1, day: day) != nil { added += 1 }
            } else if await importRecording(url, kind: kind, origin: origin, at: at, day: day) != nil {
                added += 1
            }
        }
        if files.count > 1, added > 0 { show(Toast("Added \(added) to \(DayFormat.sidebar(day ?? self.day))")) }
    }

    /// An audio file as a voice note, a video as a moment: copied into Media/<day>/imported/, its length read, then
    /// transcribed, gated and read like a recording.
    @discardableResult
    func importRecording(_ source: URL, kind: EntryKind, origin: String = "picked", at world: CGPoint?, day: String? = nil) async -> Entry? {
        var e = Entry(kind: kind, localDay: day ?? self.day, processingStatus: ProcessingStatus.pending)
        let ext = source.pathExtension.isEmpty ? (kind == .voice ? "m4a" : "mov") : source.pathExtension.lowercased()
        let asset = MediaAsset(fileName: "\(e.localDay)/imported/\(e.id).\(ext)", kind: kind == .voice ? .audio : .video, origin: origin,
                               state: "ready")
        e.mediaId = asset.id
        let url = ledger.url(for: asset)
        do {
            try await Task.detached {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: url)
            }.value
            let duration = try? await AVURLAsset(url: url).load(.duration)
            var a = asset
            a.durationMs = duration.flatMap { $0.isNumeric ? Int($0.seconds * 1000) : nil }
            a.bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            try await ledger.insertMedia(a)
            try await ledger.insertEntry(e)
            if let world { await place(e.id, at: world) }
            await reload()
            process(e.id)
            return e
        } catch {
            try? FileManager.default.removeItem(at: url)
            show(.failed("Couldn't add \(source.lastPathComponent)", error))
            return nil
        }
    }
}
