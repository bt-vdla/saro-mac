import AppKit
import SaroKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// How far a long export or import has got, for Settings → Your data; nil when none is running.
@MainActor @Observable
final class DataProgress {
    static let shared = DataProgress()
    var exporting: Double?
    var importing: Double?
}

extension AppModel {
    // MARK: Settings values

    /// Every setting Say it can change, as it stands.
    var settingsValues: SettingsValues {
        SettingsValues(prefs: PrefsStore.shared.prefs, profile: profile, theme: .init(rawValue: Daylight.shared.mode.rawValue) ?? .clock)
    }

    /// Writes one setting as `v` has it (Say it's Apply and Undo). Turning the reminder on is the click that asks macOS.
    func write(_ key: ParseIntent.Key, from v: SettingsValues) async throws {
        let prefs = PrefsStore.shared
        switch key {
        case .reminder:
            if v.reminderOn, !prefs.reminderOn { _ = await Reminders.shared.request() }
            prefs.reminderOn = v.reminderOn
            if prefs.ritualMinutes != v.reminderMinutes {
                prefs.ritualMinutes = v.reminderMinutes
                prefs.ritualSource = .user
            }
            Reminders.shared.scheduleRitual()
        case .letterTime:
            prefs.letterMinutes = v.letterMinutes
            await Reminders.shared.moveTodaysLetter(to: v.letterMinutes)
        case .theme: Daylight.shared.mode = Daylight.Mode(rawValue: v.theme.rawValue) ?? .clock
        case .textScale: prefs.textScale = v.textScale
        case .captionsAlways: prefs.captionsAlways = v.captionsAlways
        case .reduceMotion: prefs.reduceMotion = v.reduceMotion
        case .reduceTransparency: prefs.reduceTransparency = v.reduceTransparency
        case .sounds: prefs.sounds = v.sounds
        case .haptics: prefs.haptics = v.haptics
        case .tone: try await updateProfile { $0.tone = v.tone ?? .neutral }
        case .focus: try await updateProfile { $0.focusAreas = v.focus ?? [] }
        case .memoryPaused: try await updateProfile { $0.memoryPaused = v.memoryPaused }
        }
    }

    /// Like `saveProfile`, but a failed write throws, so Settings can say Couldn't save · Retry.
    func updateProfile(_ change: (inout Profile) -> Void) async throws {
        var p = if let profile { profile } else { try await ledger.profile() }
        change(&p)
        try await ledger.saveProfile(p)
        profile = try await ledger.profile()
    }

    // MARK: Export, import, erase

    /// Export everything (DR-20, FR-EXP-01): a `.saroexport` folder with every ledger row and this Mac's prefs as JSON,
    /// and the media files beside them. A folder that syncs to iCloud Drive asks first.
    func exportEverything() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose where to put the Saro export. It contains your words and recordings."
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        if Self.syncsToICloud(dir), !Self.confirmICloud() { return }
        let name = "Saro-\(LocalDay.today()).saroexport"
        let dest = dir.appending(path: name, directoryHint: .isDirectory)
        DataProgress.shared.exporting = 0
        defer { DataProgress.shared.exporting = nil }
        do {
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try await ledger.exportEverything(to: dest, prefs: PrefsStore.shared.export()) { f in
                Task { @MainActor in if DataProgress.shared.exporting != nil { DataProgress.shared.exporting = f } }
            }
            show(Toast("Exported to \(dir.lastPathComponent)/\(name)"))
        } catch {
            show(Toast("Export failed: \(error.localizedDescription)", style: .error))
        }
    }

    /// File → Import… (FR-EXP-02): adds what an export holds that this journal doesn't, by id; nothing here is replaced.
    func importJournal() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.folder, .json]
        panel.prompt = "Import"
        panel.message = "Choose a Saro export (a .saroexport folder). What’s already in this journal stays as it is; only what’s missing is added."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        DataProgress.shared.importing = 0
        defer { DataProgress.shared.importing = nil }
        do {
            let added = try await ledger.importExport(from: url) { f in
                Task { @MainActor in if DataProgress.shared.importing != nil { DataProgress.shared.importing = f } }
            }
            await loadProfile()
            await reload()
            // Imported entries the other Mac never finished reading go through this one's gate.
            for e in (try? await ledger.unfinishedEntries()) ?? [] { process(e.id) }
            show(Toast(added.rows == 0 && added.files == 0 ? "Nothing new: this journal already holds everything in that export."
                : "Imported \(added.rows) \(added.rows == 1 ? "row" : "rows") and \(added.files) \(added.files == 1 ? "file" : "files")."))
        } catch {
            show(Toast("Import failed: \(error.localizedDescription)", style: .error))
        }
    }

    /// Erase everything on this Mac (DR-16): every row, recording, photo and backup, every scheduled reminder, and
    /// every preference. The window goes back to the welcome door.
    func eraseEverything() async throws {
        try await ledger.eraseAll()
        Reminders.shared.removeAll()
        PrefsStore.shared.eraseAll()
        // The quick-capture panel's half-written note is journal text too.
        CapturePanelController.shared.draft = ""
        for key in Self.erasedDefaults { UserDefaults.standard.removeObject(forKey: key) }
        Daylight.shared.mode = .clock
        profile = try await ledger.profile()
        starter = nil
        openEntryID = nil
        selection = []
        insight = .spine
        pane = .day
        day = LocalDay.today()
        await reload()
    }

    /// What Saro keeps in UserDefaults outside PrefsStore: the capture draft, the light, and the capture devices.
    static let erasedDefaults = ["captureDraft", "daylight", "videoQuality", "captureCameraID", "captureMicID"]

    /// The Book of `year`, as HTML or PDF, saved where the person picks.
    func exportBook(year: Int, pdf: Bool) async throws -> Bool {
        let html = Book.build(year: year, name: profile?.address, days: try await ledger.bookDays(year: year))
        let panel = NSSavePanel()
        panel.nameFieldStringValue = pdf ? "saro-book-of-\(year).pdf" : Book.fileName(year)
        panel.allowedContentTypes = [pdf ? .pdf : .html]
        panel.message = "Your words and the letters you kept, one chapter a month."
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        if pdf { try await BookPDF.write(html, to: url) } else { try Data(html.utf8).write(to: url, options: .atomic) }
        return true
    }

    static func syncsToICloud(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true || url.path.contains("/Library/Mobile Documents/")
    }

    private static func confirmICloud() -> Bool {
        let alert = NSAlert()
        alert.messageText = "This folder syncs with iCloud Drive."
        alert.informativeText = "Your export holds every entry and recording. Saved here, iCloud uploads a copy to Apple’s servers. A folder that stays on this Mac keeps it private."
        alert.addButton(withTitle: "Choose Another Folder")
        alert.addButton(withTitle: "Export Here Anyway")
        return alert.runModal() == .alertSecondButtonReturn
    }
}

/// The Book as a paginated PDF: the HTML printed by an offscreen WKWebView straight to a file. Nothing is fetched; the
/// page is self-contained.
@MainActor
enum BookPDF {
    static func write(_ html: String, to url: URL) async throws {
        let page = NSRect(x: 0, y: 0, width: 612, height: 792)
        let web = WKWebView(frame: page)
        let window = NSWindow(contentRect: page, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = web
        let loader = Loader()
        web.navigationDelegate = loader
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            loader.done = c
            web.loadHTMLString(html, baseURL: nil)
        }
        let info = NSPrintInfo(dictionary: [.jobSavingURL: url])
        info.jobDisposition = .save
        info.paperSize = NSSize(width: 612, height: 792)
        (info.topMargin, info.bottomMargin, info.leftMargin, info.rightMargin) = (54, 54, 54, 54)
        info.isVerticallyCentered = false
        let op = web.printOperation(with: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.view?.frame = page
        let printed = Printed()
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            printed.done = c
            op.runModal(for: window, delegate: printed, didRun: #selector(Printed.printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
        withExtendedLifetime((web, window, loader)) {}
        guard ok, FileManager.default.fileExists(atPath: url.path) else {
            throw Failed(errorDescription: "The PDF couldn’t be written. The HTML book still works in any browser.")
        }
    }

    struct Failed: LocalizedError { var errorDescription: String? }

    private final class Loader: NSObject, WKNavigationDelegate {
        var done: CheckedContinuation<Void, Error>?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            done?.resume()
            done = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            done?.resume(throwing: error)
            done = nil
        }
    }

    private final class Printed: NSObject {
        var done: CheckedContinuation<Bool, Never>?

        @objc func printOperationDidRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
            done?.resume(returning: success)
            done = nil
        }
    }
}
