import AppKit
import Observation
import SaroKit
import SwiftUI

/// A recording turn whose rows exist before its first frame (DR-12).
struct TurnTicket: Sendable, Hashable {
    let entryId: String
    let mediaId: String
    let url: URL
}

enum Pane: Hashable {
    case day
    case trash
    case decisions
}

/// The app's root state. One per process; every surface reads it from the environment.
@Observable @MainActor
final class AppModel {
    let ledger: Ledger
    var pane: Pane = .day
    var day: String = LocalDay.today()
    var days: [(day: String, count: Int)] = []
    var entries: [Entry] = []
    var media: [String: MediaAsset] = [:]
    var layouts: [String: CardLayout] = [:]
    var annotations: [String: EntryAnnotation] = [:]
    var verdicts: [String: SafetyVerdictRow] = [:]
    var selection: Set<String> = []
    var openEntryID: String?
    var toast: Toast?
    var showNoticed = false
    var devNotesVisible = false
    var screen: ScreenID = .canvas
    /// Non-nil while the in-window recorder is up.
    var recorderKind: EntryKind?

    init(ledger: Ledger) {
        self.ledger = ledger
    }

    static func boot() -> Result<AppModel, Error> {
        Typo.registerFonts()
        do { return .success(AppModel(ledger: try Ledger())) } catch { return .failure(error) }
    }

    var isToday: Bool { day == LocalDay.today() }

    func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }

    func mediaURL(for entry: Entry) -> URL? {
        guard let id = entry.mediaId, let m = media[id] else { return nil }
        return ledger.url(for: m)
    }

    // MARK: Loading

    func reload() async {
        do {
            days = try await ledger.days()
            entries = try await ledger.entries(day: day)
            layouts = try await ledger.layouts(day: day)
            annotations = try await ledger.annotations(day: day)
            verdicts = try await ledger.verdicts(day: day)
            var m: [String: MediaAsset] = [:]
            for e in entries { if let id = e.mediaId, let a = try await ledger.media(id) { m[id] = a } }
            media = m
            selection = selection.filter { id in entries.contains { $0.id == id } }
        } catch {
            show(Toast("Couldn't read the journal: \(error.localizedDescription)", style: .error))
        }
    }

    func go(to day: String) {
        guard day != self.day || pane != .day else { return }
        self.day = day
        pane = .day
        openEntryID = nil
        selection = []
        Task { await reload() }
    }

    func goToday() { go(to: LocalDay.today()) }
    func goPrevious() { go(to: LocalDay.adding(-1, to: day)) }
    func goNext() { go(to: LocalDay.adding(1, to: day)) }

    // MARK: Capture

    /// Creates the media and entry rows (state `recording`) and returns where the turn's file goes:
    /// `Media/<local_day>/<session>/part-<n>.mov` for moments, `Media/<local_day>/voice/<entry>.mov` for voice notes.
    /// `day` defaults to the day on screen (a past day backdates); the floating panel passes today.
    func beginTurn(kind: EntryKind, sessionId: String, turn: Int, day: String? = nil) async throws -> TurnTicket {
        let entry = Entry(kind: kind, sessionId: sessionId, turnNumber: turn, localDay: day ?? self.day, processingStatus: ProcessingStatus.recording)
        let rel = kind == .moment ? "\(entry.localDay)/\(sessionId)/part-\(turn).mov" : "\(entry.localDay)/voice/\(entry.id).mov"
        let asset = MediaAsset(fileName: rel, kind: kind == .moment ? .video : .audio, origin: "recorded")
        var e = entry
        e.mediaId = asset.id
        let url = ledger.url(for: asset)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await ledger.insertMedia(asset)
        try await ledger.insertEntry(e)
        return TurnTicket(entryId: e.id, mediaId: asset.id, url: url)
    }

    /// Marks the turn's file ready (or failed) and starts processing it.
    func finishTurn(_ ticket: TurnTicket, durationMs: Int, error: Error?) async {
        let bytes = (try? ticket.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        let exists = FileManager.default.fileExists(atPath: ticket.url.path)
        try? await ledger.updateMedia(id: ticket.mediaId, state: exists ? "ready" : "failed", durationMs: durationMs, bytes: bytes)
        try? await ledger.setProcessingStatus(id: ticket.entryId, exists ? ProcessingStatus.pending : ProcessingStatus.failed)
        if let error, !exists { show(Toast("That recording couldn't be saved: \(error.localizedDescription)", style: .error)) }
        await reload()
        if exists { process(ticket.entryId) }
    }

    /// A new, empty piece of writing on the current day.
    func newWriting(body: String = "", day: String? = nil) async -> Entry? {
        let e = Entry(kind: .reflection, body: body, localDay: day ?? self.day)
        do {
            try await ledger.insertEntry(e)
            await reload()
            return e
        } catch {
            show(Toast("Couldn't save: \(error.localizedDescription)", style: .error))
            return nil
        }
    }

    func saveWriting(id: String, body: String, title: String?) async {
        do {
            try await ledger.updateEntryText(id: id, body: body, titleUser: title)
            await reload()
            process(id)
        } catch {
            show(Toast("Couldn't save: \(error.localizedDescription)", style: .error))
        }
    }

    /// Placeholder until the pipeline lands: transcription → safety gate → reading.
    func process(_ entryId: String) {}

    // MARK: Toasts

    func show(_ toast: Toast) {
        self.toast = toast
        let id = toast.id
        Task {
            try? await Task.sleep(for: .seconds(toast.undo == nil ? 2.4 : 5))
            if self.toast?.id == id { self.toast = nil }
        }
    }
}

struct Toast: Identifiable, Equatable {
    enum Style { case info, error }
    let id = UUID()
    let text: String
    let style: Style
    let undo: (@MainActor () -> Void)?

    init(_ text: String, style: Style = .info, undo: (@MainActor () -> Void)? = nil) {
        self.text = text
        self.style = style
        self.undo = undo
    }

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}
