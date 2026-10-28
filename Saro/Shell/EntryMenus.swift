import AppKit
import Observation
import SaroKit
import SwiftUI

/// One entry menu item, drawn by the card's context menu, the Entry menu and the ⇧F10 menu alike, so they never drift.
struct EntryMenuItem: Identifiable {
    enum Body { case run(@MainActor () -> Void), submenu([EntryMenuItem]), divider }
    var id: String
    var title = ""
    var symbol: String?
    var keys: KeyboardShortcut?
    var destructive = false
    var enabled = true
    var body: Body

    static func divider(_ id: String) -> EntryMenuItem { EntryMenuItem(id: id, body: .divider) }
}

extension AppModel {
    /// The items for `targets` (CanvasContextMenu.tsx:84-200, per type): one entry gets Open, Edit Details, Duplicate To,
    /// Export a Copy, Show in Finder and Copy Text where they make sense, then Move to Trash; a stack is opened, exported
    /// as a folder, shown or trashed; several get Stack, Grid and Move to Trash.
    func entryMenu(_ targets: [Entry], stack: Bool = false, undoManager: UndoManager? = nil) -> [EntryMenuItem] {
        let ids = Set(targets.map(\.id))
        let trash = EntryMenuItem(id: "trash", title: "Move to Trash", symbol: "trash", keys: KeyboardShortcut(.moveToTrash),
                                  destructive: true, body: .run { [weak self] in
            let flies = !Motion.byKey && !PrefsStore.shared.reduceMotionEffective
            // A menu bar menu may have no undo manager of its own; the journal window's takes the ⌘Z.
            let undo = undoManager ?? NSApp.keyWindow?.undoManager
            Task { await self?.trash(ids, undoManager: undo, flies: flies) }
        })
        guard let e = targets.first else { return [] }
        if targets.count > 1 && !stack {
            return [
                EntryMenuItem(id: "stack", title: "Stack", symbol: "square.stack.3d.up", body: .run { [weak self] in
                    withAnimation(Motion.byKey ? nil : Motion.small) { self?.stack(ids) }
                }),
                EntryMenuItem(id: "grid", title: "Grid", symbol: "rectangle.grid.1x2", body: .run { [weak self] in
                    withAnimation(Motion.byKey ? nil : Motion.small) { self?.grid(ids) }
                }),
                .divider("d1"), trash,
            ]
        }
        let open = EntryMenuItem(id: "open", title: "Open", symbol: "arrow.up.left.and.arrow.down.right", body: .run { [weak self] in
            guard let self else { return }
            if stack, let sid = layouts[e.id]?.stackId { openStackID = sid } else { openEntryID = e.id }
        })
        let export = EntryMenuItem(id: "export", title: "Export a Copy…", symbol: "square.and.arrow.up", keys: KeyboardShortcut(.exportCopy),
                                   body: .run { [weak self] in Task { await self?.exportCopy(targets) } })
        let finder = EntryMenuItem(id: "finder", title: "Show in Finder", symbol: "folder", keys: KeyboardShortcut(.showInFinder),
                                   enabled: e.kind.hasFile, body: .run { [weak self] in self?.showInFinder(targets) })
        if stack { return [open, .divider("d0"), export, finder, .divider("d1"), trash] }
        let today = LocalDay.today()
        let days: [EntryMenuItem] = [
            EntryMenuItem(id: "today", title: "Today", body: .run { [weak self] in Task { await self?.duplicate(e.id, to: today) } }),
            EntryMenuItem(id: "yesterday", title: "Yesterday", body: .run { [weak self] in
                Task { await self?.duplicate(e.id, to: LocalDay.adding(-1, to: today)) }
            }),
            .divider("dd"),
            EntryMenuItem(id: "pick", title: "Choose a Day…", body: .run { ShellPanels.shared.sheet = .duplicate(e.id) }),
        ]
        return [
            open,
            EntryMenuItem(id: "edit", title: "Edit Details…", symbol: "pencil", keys: KeyboardShortcut(.editDetails),
                          body: .run { [weak self] in self?.editDetails(e.id) }),
            EntryMenuItem(id: "duplicate", title: "Duplicate To", symbol: "plus.square.on.square", body: .submenu(days)),
            .divider("d0"),
            export,
            finder,
            EntryMenuItem(id: "copy", title: "Copy Text", symbol: "doc.on.doc", keys: KeyboardShortcut(.copyText),
                          body: .run { [weak self] in Task { await self?.copyText(e) } }),
            .divider("d1"),
            trash,
        ]
    }
}

/// The items as SwiftUI menu content, for a context menu (which shows their keys) or the Entry menu (which holds them).
struct EntryMenuContent: View {
    let items: [EntryMenuItem]

    var body: some View {
        ForEach(items) { item in
            switch item.body {
            case .divider: Divider()
            case .submenu(let sub):
                Menu { EntryMenuContent(items: sub) } label: { label(item) }.disabled(!item.enabled)
            case .run(let action):
                Button(role: item.destructive ? .destructive : nil, action: action) { label(item) }
                    .keyboardShortcut(item.keys)
                    .disabled(!item.enabled)
            }
        }
    }

    @ViewBuilder private func label(_ item: EntryMenuItem) -> some View {
        if let symbol = item.symbol { Label(item.title, systemImage: symbol) } else { Text(item.title) }
    }
}

/// A card's right-click menu: the card, or the whole selection when the card is part of it.
struct CardMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let item: CanvasItem

    var body: some View {
        let ids = Set(item.entries.map(\.id))
        let several = model.selection.count > 1 && ids.isSubset(of: model.selection) && !(item.isStack && model.selection == ids)
        let targets = several ? model.entries.filter { model.selection.contains($0.id) } : item.entries
        EntryMenuContent(items: model.entryMenu(targets, stack: !several && item.isStack, undoManager: undoManager))
    }
}

/// Entry in the menu bar: the same items for the open entry or the selection, with their keys.
struct EntryCommands: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let targets = model.entryTargets
        let stack = targets.count > 1 && Set(targets.compactMap { model.layouts[$0.id]?.stackId }).count == 1
            && targets.allSatisfy { model.layouts[$0.id]?.stackId != nil }
        let items = targets.isEmpty ? Self.placeholder : model.entryMenu(targets, stack: stack, undoManager: undoManager)
        EntryMenuContent(items: items.map { item in
            // ⌘⌫ in a text field deletes to the line's start, as it always does; only off the editor does it trash.
            guard item.id == "trash", case .run(let run) = item.body else { return item }
            var i = item
            i.body = .run {
                if NSApp.keyWindow?.firstResponder is NSTextView {
                    NSApp.sendAction(#selector(NSTextView.deleteToBeginningOfLine(_:)), to: nil, from: nil)
                } else {
                    run()
                }
            }
            return i
        })
        .disabled(model.showsOnboarding)
    }

    /// Nothing selected: the items show, greyed, so their keys can be learned.
    private static let placeholder: [EntryMenuItem] = [
        EntryMenuItem(id: "open", title: "Open", enabled: false, body: .run {}),
        EntryMenuItem(id: "edit", title: "Edit Details…", keys: KeyboardShortcut(.editDetails), enabled: false, body: .run {}),
        .divider("d0"),
        EntryMenuItem(id: "export", title: "Export a Copy…", keys: KeyboardShortcut(.exportCopy), enabled: false, body: .run {}),
        EntryMenuItem(id: "finder", title: "Show in Finder", keys: KeyboardShortcut(.showInFinder), enabled: false, body: .run {}),
        EntryMenuItem(id: "copy", title: "Copy Text", keys: KeyboardShortcut(.copyText), enabled: false, body: .run {}),
        .divider("d1"),
        EntryMenuItem(id: "trash", title: "Move to Trash", keys: KeyboardShortcut(.moveToTrash), enabled: false, body: .run {}),
    ]
}

/// The canvas background's right-click menu (CanvasBackgroundContextMenu.tsx): something new at the point clicked,
/// Paste, Recenter and Export Day as Image.
struct CanvasMenu: View {
    @Environment(AppModel.self) private var model
    /// Where it was opened, in the day's world space, read when an item is chosen.
    let at: () -> CGPoint?

    var body: some View {
        Menu {
            Button("Moment", systemImage: "video") { record(.moment) }
            Button("Voice Note", systemImage: "waveform") { record(.voice) }
            Button("Still…", systemImage: "photo") { model.pickStill(at: at()) }
            Button("Reflection", systemImage: "text.alignleft") {
                let p = at()
                Task { await model.newWriting(at: p) }
            }
        } label: {
            Label("New", systemImage: "plus.circle")
        }
        .disabled(model.recorderKind != nil)
        Button("Paste", systemImage: "doc.on.clipboard") {
            let p = at()
            Task { await model.paste(at: p) }
        }
            .disabled(!NSPasteboard.general.canReadObject(forClasses: [NSImage.self, NSString.self], options: nil))
        Divider()
        Button("Recenter", systemImage: "scope") { model.camera = .fit(UUID()) }.keyboardShortcut(KeyboardShortcut(.fitDay))
        Button("Export Day as Image…", systemImage: "photo.on.rectangle") { Task { await model.exportDayImage() } }
    }

    /// The recording's card lands where the menu opened.
    private func record(_ kind: EntryKind) {
        model.pane = .day
        model.recorderKind = kind
        model.recorderLandsAt = at()
    }
}

extension AppModel {
    /// A new page placed at `at`: an empty one opens to be written; a pasted one is read as it stands.
    func newWriting(at point: CGPoint?, body: String = "") async {
        guard let e = await newWriting(body: body) else { return }
        if let point { await place(e.id, at: point) }
        if body.isEmpty { openEntryID = e.id } else { process(e.id) }
    }

    /// Copied files become what they are, an image a still, a music link a song and other text a page, at the point
    /// (Canvas.tsx's paste).
    func paste(at point: CGPoint?) async {
        let pb = NSPasteboard.general
        if let files = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
            await importMedia(files, at: point, origin: "pasted")
        } else if let image = (pb.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first, let tiff = image.tiffRepresentation {
            await importStill(tiff, origin: "pasted", at: point)
        } else {
            await CaptureInput.pasted(pb.string(forType: .string), at: point, model: self)
        }
    }

    /// A new card's place, tracked on its own: a layout that doesn't land leaves the entry saved.
    func place(_ id: String, at p: CGPoint) async {
        let l = CardLayout(entryId: id, x: p.x, y: p.y, z: (layouts.values.map(\.z).max() ?? 0) + 1, userPlaced: true)
        try? await saves.track("layout:\(id)") { [weak self] in
            try await self?.ledger.setLayouts([l])
            await self?.reload()
        }
    }
}

/// ⇧F10 and the Menu key open the selection's menu beside it (CanvasContextMenu.tsx's keyboard route).
@MainActor
enum CardMenuKeys {
    private static var monitor: Any?
    /// Each card's place in its window, so the menu opens beside the card it is for.
    static var frames: [String: CGRect] = [:]

    static func install(_ model: AppModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
            MainActor.assumeIsolated { model.map { open(for: event, $0) } ?? false } ? nil : event
        }
    }

    private static func open(for event: NSEvent, _ model: AppModel) -> Bool {
        // 109 is F10, 110 the PC keyboard's Menu key.
        guard event.keyCode == 110 || event.keyCode == 109 && event.modifierFlags.contains(.shift), !Locker.shared.locked,
              event.window != nil, event.window === JournalWindow.shared.window,
              !(event.window?.firstResponder is NSTextView) else { return false }
        let targets = model.entryTargets
        guard !targets.isEmpty, let view = event.window?.contentView else { return false }
        let stack = targets.count > 1 && targets.allSatisfy { model.layouts[$0.id]?.stackId != nil }
        let menu = NSMenu()
        // Items keep the enabled state they were given (Show in Finder on a page): no validateMenuItem re-enables them.
        menu.autoenablesItems = false
        for item in model.entryMenu(targets, stack: stack, undoManager: event.window?.undoManager) { menu.addItem(nsItem(item)) }
        let frame = targets.compactMap { frames[$0.id] ?? model.layouts[$0.id]?.stackId.flatMap { frames["stack:\($0)"] } }.first
        let p = frame.map { CGPoint(x: $0.minX + 8, y: view.isFlipped ? $0.maxY : view.bounds.height - $0.maxY) }
            ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        menu.popUp(positioning: nil, at: p, in: view)
        return true
    }

    private static func nsItem(_ item: EntryMenuItem) -> NSMenuItem {
        switch item.body {
        case .divider: return .separator()
        case .submenu(let sub):
            let m = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            m.submenu = NSMenu(title: item.title)
            m.submenu?.autoenablesItems = false
            m.isEnabled = item.enabled
            for s in sub { m.submenu?.addItem(nsItem(s)) }
            return m
        case .run(let run):
            let m = ClosureMenuItem(title: item.title, run: run)
            m.isEnabled = item.enabled
            m.image = item.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            return m
        }
    }

    private final class ClosureMenuItem: NSMenuItem {
        let run: @MainActor () -> Void

        init(title: String, run: @escaping @MainActor () -> Void) {
            self.run = run
            super.init(title: title, action: #selector(fire), keyEquivalent: "")
            target = self
        }

        required init(coder: NSCoder) { fatalError() }

        @objc private func fire() {
            let run = run
            MainActor.assumeIsolated { run() }
        }
    }
}

/// The journal's window, and whether it is the key one: the Entry menu and ⇧F10 act on its cards only from there, never
/// from Settings, About, the capture panel, or a sheet or save panel over it. Observed, so the menu greys as focus moves.
@Observable @MainActor
final class JournalWindow {
    // ponytail: one per process like ShellPanels; the journal is a single Window scene.
    static let shared = JournalWindow()
    /// Set by the journal's root view; a view leaving it doesn't clear it.
    @ObservationIgnored weak var window: NSWindow? { didSet { refresh() } }
    private(set) var isKey = true

    private init() {
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { JournalWindow.shared.refresh() }
        }
    }

    private func refresh() {
        guard let key = NSApp.keyWindow else { return }
        if isKey != (key === window) { isKey = key === window }
    }
}

extension View {
    /// A card's right-click menu, and its place in the window for ⇧F10.
    func cardMenu(_ item: CanvasItem) -> some View {
        contextMenu { CardMenu(item: item) }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { CardMenuKeys.frames[item.id] = $0 }
    }
}
