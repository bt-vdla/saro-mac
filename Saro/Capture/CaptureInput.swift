import AppKit
import SaroKit
import SwiftUI
import UniformTypeIdentifiers

/// Capture from anywhere on the canvas (Canvas.tsx): a paste or a drop becomes the entry it carries (a photo a still, audio
/// a voice note, video a moment, a music link a song, other text a reflection), and a bare Space opens the voice pill.
@MainActor
enum CaptureInput {
    static let pasteTypes: [UTType] = [.fileURL, .image, .png, .tiff, .heic, .jpeg, .movie, .audio, .url, .plainText]
    static let dropTypes: [UTType] = [.fileURL, .image, .movie, .audio]

    /// Not over the recorder, an opened entry or set, or ⌘K.
    static func canCapture(_ model: AppModel) -> Bool {
        model.pane == .day && model.recorderKind == nil && model.openEntryID == nil && model.openStackID == nil && !model.searchOpen
    }

    static func paste(_ providers: [NSItemProvider], model: AppModel) {
        guard canCapture(model) else { return }
        if providers.contains(where: { p in dropTypes.contains { p.hasItemConformingToTypeIdentifier($0.identifier) } }) {
            _ = drop(providers, at: nil, origin: "pasted", model: model)
            return
        }
        guard let p = providers.first else { return }
        let done: @Sendable (String?) -> Void = { text in Task { @MainActor in await pasted(text, model: model) } }
        if p.canLoadObject(ofClass: String.self) {
            _ = p.loadObject(ofClass: String.self) { s, _ in done(s) }
        } else if p.canLoadObject(ofClass: URL.self) {
            _ = p.loadObject(ofClass: URL.self) { u, _ in done(u?.absoluteString) }
        }
    }

    /// A music link is a song; any other text is a new reflection holding it, saved and read at once.
    private static func pasted(_ text: String?, model: AppModel) async {
        let text = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if Music.isMusicLink(text), let url = Music.link(text) {
            await model.newMusic(url: url, at: nil)
        } else if let e = await model.newWriting(body: text) {
            model.process(e.id)
        }
    }

    /// Every file shows at once, on a grid around where it was let go. False when nothing in it is Saro's to keep. The
    /// capture panel passes today, and isn't held back by the window's recorder.
    @discardableResult
    static func drop(_ providers: [NSItemProvider], at world: CGPoint?, origin: String = "dropped", day: String? = nil, model: AppModel,
                     done: (@MainActor () -> Void)? = nil) -> Bool {
        guard day != nil || canCapture(model), !providers.isEmpty else { return false }
        Task {
            var files: [(url: URL, temporary: Bool)] = []
            for p in providers { if let f = await file(p) { files.append(f) } }
            await model.importMedia(files.map(\.url), at: world, origin: origin, day: day)
            for f in files where f.temporary { try? FileManager.default.removeItem(at: f.url) }
            done?()
        }
        return true
    }

    /// A text field, an editor or a capture button has the keys: an ancestor's key handler sees them first and must let
    /// them through.
    static var typing: Bool { NSApp.keyWindow?.firstResponder is NSText || CaptureUI.shared.tileFocused }

    /// Space: the voice pill, with no growing (it came from a key). Never inside a field, or while something else holds the keys.
    static func space(_ model: AppModel) -> KeyPress.Result {
        guard !typing, canCapture(model), model.openVoiceID == nil, !model.replay.active else { return .ignored }
        model.recorderKind = .voice
        return .handled
    }

    /// What the drag holds, for the overlay's icon.
    static func kind(_ info: DropInfo) -> EntryKind {
        info.hasItemsConforming(to: [.movie]) ? .moment : info.hasItemsConforming(to: [.audio]) ? .voice : .still
    }

    /// A file the provider holds: the dropped file itself, or a copy of what it carries (a photo out of a browser, a
    /// movie out of Photos) in the temporary folder.
    private static func file(_ p: NSItemProvider) async -> (url: URL, temporary: Bool)? {
        if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { c in _ = p.loadObject(ofClass: URL.self) { u, _ in c.resume(returning: u) } }
            if let url { return (url, false) }
        }
        guard let type = [UTType.movie, .audio, .image].first(where: { p.hasItemConformingToTypeIdentifier($0.identifier) }) else { return nil }
        let copy: URL? = await withCheckedContinuation { c in
            _ = p.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                guard let url else { return c.resume(returning: nil) }
                let to = FileManager.default.temporaryDirectory.appending(path: "saro-import-\(UUID().uuidString).\(url.pathExtension)")
                c.resume(returning: (try? FileManager.default.copyItem(at: url, to: to)).map { to })
            }
        }
        return copy.map { ($0, true) }
    }
}

/// The canvas's drop target: the overlay follows the drag, and the drop lands where it was let go.
struct CaptureDrop: DropDelegate {
    let model: AppModel
    @Binding var kind: EntryKind?
    let world: (CGPoint) -> CGPoint

    func validateDrop(info: DropInfo) -> Bool { CaptureInput.canCapture(model) && info.hasItemsConforming(to: CaptureInput.dropTypes) }
    func dropEntered(info: DropInfo) { kind = CaptureInput.kind(info) }
    func dropExited(info: DropInfo) { kind = nil }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func performDrop(info: DropInfo) -> Bool {
        kind = nil
        return CaptureInput.drop(info.itemProviders(for: CaptureInput.dropTypes), at: world(info.location), model: model)
    }
}
