import AppKit
import AVFoundation
import SaroKit
import SwiftUI
import UniformTypeIdentifiers

extension EntryKind {
    var pluralNoun: String {
        switch self {
        case .moment: "moments"
        case .voice: "voice notes"
        case .still: "stills"
        case .reflection: "pieces of writing"
        case .music: "songs"
        }
    }

    /// The trash toast names what went (trash-undo.tsx): "Voice note moved to Trash", "3 stills moved to Trash".
    static func trashTitle(_ kinds: [EntryKind], count: Int) -> String {
        guard let k = kinds.first else { return "Moved to Trash" }
        if count == 1 { return "\(k.noun) moved to Trash" }
        return kinds.allSatisfy { $0 == k } ? "\(count) \(k.pluralNoun) moved to Trash" : "\(count) items moved to Trash"
    }

    /// The extension a copy is saved with.
    var exportExtension: String {
        switch self {
        case .moment: "mov"
        case .voice: "m4a"
        case .still: "heic"
        case .reflection, .music: "txt"
        }
    }

    var hasFile: Bool { self == .moment || self == .voice || self == .still }
}

/// The card and Entry menus' actions (CanvasContextMenu.tsx, CanvasItemView.tsx).
extension AppModel {
    /// What the Entry menu acts on: the open entry, else the selection.
    var entryTargets: [Entry] {
        if let id = openEntryID, let e = entry(id) { return [e] }
        return entries.filter { selection.contains($0.id) }
    }

    /// Deletes from Trash for good (TrashContext.tsx permanentlyDelete). Returns whether it landed.
    @discardableResult
    func deleteForever(_ ids: [String]) async -> Bool {
        do {
            try await ledger.hardDelete(ids: ids)
            saves.forget(ids)
            return true
        } catch {
            show(.failed(ids.count == 1 ? "Couldn't delete that item" : "Couldn't delete \(ids.count) items", error,
                         context: ids.count == 1 ? nil : "They're still in the trash."))
            return false
        }
    }

    /// A copy on another day (FR-DAY-07), the same media and verdict, backdated, left out of engine counts.
    func duplicate(_ id: String, to day: String) async {
        guard day <= LocalDay.today() else {
            return show(Toast(title: "That day hasn't happened yet", detail: "Duplicate to today or an earlier day."))
        }
        let label = DayFormat.sidebar(day)
        let key = "duplicate:\(id):\(day)"
        do {
            try await saves.track(key) { [weak self] in
                guard let self else { return }
                let copy = try await ledger.duplicate(id: id, toDay: day)
                if day == self.day { await reload() }
                process(copy.id)
            }
            show(Toast("Duplicated to \(label)"))
        } catch DuplicateError.futureDay {
            show(Toast(title: "That day hasn't happened yet", detail: "Duplicate to today or an earlier day."))
        } catch {
            show(.failed("Couldn't duplicate to \(label)", error, retry: { [weak self] in Task { await self?.saves.retry(key) } }))
        }
    }

    func editDetails(_ id: String) { ShellPanels.shared.sheet = .edit(id) }

    /// The person's own words, or a recording's transcript; a still's caption is Saro's only once checked, on a day not
    /// held (SR-13). Empty when there's nothing to copy.
    func plainText(_ e: Entry) async -> String {
        switch e.kind {
        case .reflection: return [e.titleUser, e.body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        case .still: return caption(for: e) ?? ""
        case .music: return [e.titleUser, e.captionUser, e.body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        case .moment, .voice:
            guard let id = e.mediaId, let words = try? await ledger.transcript(mediaId: id) else { return "" }
            return words.map(\.text).joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }

    /// Copies an entry's text; one with no words leaves the clipboard as it was. Returns whether it copied.
    @discardableResult
    func copyText(_ e: Entry, toast: Bool = true) async -> Bool {
        let text = await plainText(e)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if toast { show(Toast(title: "Nothing to copy yet", detail: e.kind.hasFile ? "Its transcript isn't ready." : nil)) }
            return false
        }
        NSPasteboard.general.clearContents()
        let ok = NSPasteboard.general.setString(text, forType: .string)
        if toast { show(ok ? Toast("Copied") : Toast(title: "Couldn't copy that", detail: "Try again in a moment.", style: .destructive)) }
        return ok
    }

    func showInFinder(_ es: [Entry]) {
        let urls = es.compactMap { mediaURL(for: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return show(Toast(title: "The file isn't on this Mac", detail: "It may have been moved or deleted.")) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Saves a copy with a readable name ("Saro moment, 27 Oct 2026.mov"); a stack's turns go into one folder.
    func exportCopy(_ es: [Entry]) async {
        guard let first = es.first else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let folder = es.count > 1
        panel.nameFieldStringValue = ShellText.exportName(first.kind, day: first.localDay, ext: folder ? "" : first.kind.exportExtension)
        if !folder, let type = UTType(filenameExtension: first.kind.exportExtension) { panel.allowedContentTypes = [type] }
        panel.message = folder ? "Saro saves each turn in this folder." : "Saro saves a copy here. The entry stays in your journal."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if folder {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                for (i, e) in es.enumerated() { try await writeCopy(e, to: url.appending(path: "Turn \(i + 1).\(e.kind.exportExtension)")) }
            } else {
                try await writeCopy(first, to: url)
            }
            show(Toast(title: "Saved a copy", detail: url.lastPathComponent))
        } catch {
            show(.failed("Couldn't save a copy", error))
        }
    }

    func writeCopy(_ e: Entry, to url: URL) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        switch e.kind {
        case .moment, .still:
            guard let src = mediaURL(for: e) else { throw CocoaError(.fileNoSuchFile) }
            try fm.copyItem(at: src, to: url)
        case .voice:
            guard let src = mediaURL(for: e) else { throw CocoaError(.fileNoSuchFile) }
            guard let session = AVAssetExportSession(asset: AVURLAsset(url: src), presetName: AVAssetExportPresetAppleM4A) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try await session.export(to: url, as: .m4a)
        case .reflection, .music:
            try await plainText(e).write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// Under a recording's transcript (EntryViews.tsx): Export a copy (which also drags out as a file), Show in Finder, and
/// Copy transcript, which says Copied in place for 2 s.
struct EntryActionsRow: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            pill("Export a copy", "square.and.arrow.up") { Task { await model.exportCopy([entry]) } }
                .onDrag { entry.itemProvider(model) }
                .help("Save a copy, or drag it out")
            pill("Show in Finder", "folder") { model.showInFinder([entry]) }
            pill(copied ? "Copied" : "Copy transcript", copied ? "checkmark" : "doc.on.doc") {
                Task {
                    guard await model.copyText(entry, toast: false) else {
                        return model.show(Toast(title: "Nothing to copy yet", detail: "Its transcript isn't ready."))
                    }
                    copied = true
                    AccessibilityNotification.Announcement("Copied").post()
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            }
            .animation(Motion.fade, value: copied)
        }
        .padding(.top, 4)
    }

    private func pill(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Typo.ui(12, .medium)).foregroundStyle(Tok.ink2)
                .padding(.horizontal, 12).frame(height: 28)
                .background(Tok.ink.opacity(0.06), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(PressStyle(radius: 14))
    }
}

/// An entry dragged out of Saro lands as a copy with its readable name (a file promise; the journal keeps its own).
extension Entry {
    @MainActor func itemProvider(_ model: AppModel) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = ShellText.exportName(kind, day: localDay, ext: "")
        let type = UTType(filenameExtension: kind.exportExtension) ?? .data
        let entry = self
        provider.registerFileRepresentation(for: type, visibility: .all) { done in
            // ponytail: NSItemProvider's completion may be called from any thread; the SDK just doesn't mark it Sendable.
            nonisolated(unsafe) let done = done
            Task { @MainActor in
                let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
                    .appending(path: ShellText.exportName(entry.kind, day: entry.localDay, ext: entry.kind.exportExtension))
                do {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try await model.writeCopy(entry, to: url)
                    done(url, false, nil)
                } catch {
                    done(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }
}
