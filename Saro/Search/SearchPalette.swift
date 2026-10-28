import AppKit
import SaroKit
import SwiftUI

extension View {
    /// The ⌘K palette over the whole window. It opens and closes with no animation (frequency rule: ⌘K is a key).
    func searchPalette(isPresented: Binding<Bool>) -> some View {
        overlay {
            if isPresented.wrappedValue { SearchPalette(isPresented: isPresented).transition(.identity) }
        }
    }
}

struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var keywords = ""
    var shortcut: String?
    /// Offered only when this holds (Read the day again, on a day that can be read).
    var available: @MainActor (AppModel) -> Bool = { _ in true }
    /// A setting's current value, shown on the row; running it keeps the palette open and flashes the new value.
    var value: (@MainActor (AppModel) -> String)?
    let run: @MainActor (AppModel) -> Void

    func matches(_ query: String) -> Bool { CommandMatch.matches(query, title: title, keywords: keywords) }
}

private enum Row: Identifiable {
    case entry(SearchHit)
    case command(PaletteCommand)
    case day(String)
    case scope(EntryKind)
    case write(String)
    case memory(Memory)
    /// The index couldn't be read: Try again.
    case retry
    /// A scoped search found nothing: search every type.
    case widen

    var id: String {
        switch self {
        case .entry(let h): "e:\(h.entryId)"
        case .command(let c): "c:\(c.id)"
        case .day(let d): "d:\(d)"
        case .scope(let k): "s:\(k.rawValue)"
        case .write: "w"
        case .memory(let m): "m:\(m.key)"
        case .retry: "retry"
        case .widen: "widen"
        }
    }
}

/// ⌘K on an entry row (SearchPalette.tsx's actions menu), plus Move to Trash.
private enum EntryAction: CaseIterable {
    case open, replay, day, copy, trash

    var title: String {
        switch self {
        case .open: "Open on canvas"
        case .replay: "Replay that day"
        case .day: "Go to that day"
        case .copy: "Copy text"
        case .trash: "Move to Trash"
        }
    }

    var key: String? {
        switch self {
        case .open: "↵"
        case .replay: "⌘↵"
        case .copy: "⇧⌘C"
        case .day, .trash: nil
        }
    }
}

private struct PaletteSection: Identifiable {
    let id: String
    var title: String?
    var count: String?
    var note: String?
    var miss: String?
    var rows: [Row] = []
}

private extension EntryKind {
    var plural: String {
        switch self {
        case .moment: "Moments"
        case .voice: "Voice notes"
        case .reflection: "Writing"
        case .still: "Stills"
        case .music: "Songs"
        }
    }

    /// Typed words that scope the palette; the plural ones scope it as soon as a space follows them.
    var aliases: (singular: [String], plural: [String]) {
        switch self {
        case .moment: (["moment", "video"], ["moments", "videos"])
        case .voice: (["voice", "audio"], ["voices"])
        case .reflection: (["writing", "reflection"], ["reflections"])
        case .still: (["still", "photo"], ["stills", "photos"])
        case .music: ([], [])
        }
    }
}

/// ⌘K: search every entry and run commands. Keyboard all the way: ↑↓ move, ↵ runs, ⌘↵ replays the row's day,
/// ⌘P (or "moments ", or a type and Tab) scopes, ⌘K opens an entry's actions, Esc steps back through the actions,
/// the query and scope, then closes.
struct SearchPalette: View {
    @Binding var isPresented: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var query = ""
    @State private var scope: EntryKind?
    @State private var hits: [SearchHit] = []
    /// The query and scope `hits` belong to; until it matches, the last results stay up instead of flashing empty.
    @State private var hitsKey: String?
    @State private var selected: String?
    /// Where the highlighted row sits in the window, so a click on it flies its entry out of the row.
    @State private var currentFrame: CGRect?
    @State private var window: NSWindow?
    @State private var monitor: Any?
    @State private var mouse: CGPoint?
    @State private var actionsOpen = false
    /// The highlighted action; nil until a key or the pointer picks one (a click opens the menu with none).
    @State private var action: Int?
    @State private var flash = ""
    @State private var flashOn = false
    @State private var flashTask: Task<Void, Never>?
    @State private var searching = false
    @State private var failed = false
    @State private var attempt = 0
    /// The ⌘P menu of types, and its highlighted row.
    @State private var scopeMenu = false
    @State private var scopeRow = 0

    private static let limit = 50
    private static let scopes: [EntryKind] = [.moment, .voice, .reflection, .still]
    private static let commands: [PaletteCommand] = {
        var all = [
            PaletteCommand(id: "today", title: "Today", symbol: "sun.max", keywords: "go now day home", shortcut: "⌘T") { $0.goToday() },
            PaletteCommand(id: "replay", title: "Replay today", symbol: "clock.arrow.circlepath", keywords: "play timelapse rewind history") {
                $0.requestReplay(LocalDay.today())
            },
            PaletteCommand(id: "moment", title: "Record a moment", symbol: "video", keywords: "video camera capture new", shortcut: "⌘N") {
                $0.pane = .day
                $0.recorderKind = .moment
            },
            PaletteCommand(id: "voice", title: "Voice note", symbol: "waveform", keywords: "audio record speak microphone new", shortcut: "⇧⌘N") {
                $0.pane = .day
                $0.recorderKind = .voice
            },
            PaletteCommand(id: "write", title: "Write", symbol: "square.and.pencil", keywords: "writing reflection text page journal new",
                           shortcut: "⌥⌘W") { write("", in: $0) },
            PaletteCommand(id: "still", title: "Add a still", symbol: "photo", keywords: "photo image picture import") { m in
                m.pane = .day
                m.pickStill()
            },
            PaletteCommand(id: "date", title: "Go to date…", symbol: "calendar", keywords: "calendar day jump picker", shortcut: "⌥⌘G") { m in
                m.pane = .day
                m.datePickerOpen = true
            },
            PaletteCommand(id: "lens", title: "Open time lens", symbol: "square.grid.3x3", keywords: "week month year overview zoom calendar",
                           shortcut: "⌥⌘T") { m in
                m.pane = .day
                m.openLens()
            },
            PaletteCommand(id: "recenter", title: "Recenter canvas", symbol: "scope", keywords: "fit day zoom reset center", shortcut: "⌘0") { m in
                m.pane = .day
                m.camera = .fit(UUID())
            },
            PaletteCommand(id: "dayimage", title: "Export day image", symbol: "photo.badge.arrow.down", keywords: "png picture save share canvas") { m in
                m.pane = .day
                Task { await m.exportDayImage() }
            },
            PaletteCommand(id: "appearance", title: "Appearance", symbol: "circle.lefthalf.filled", keywords: "theme dark light night mode day",
                           value: { _ in Daylight.shared.mode.title }) { _ in
                let all = Daylight.Mode.allCases
                Daylight.shared.mode = all[((all.firstIndex(of: Daylight.shared.mode) ?? 0) + 1) % all.count]
            },
            PaletteCommand(id: "noticed", title: "What Saro noticed", symbol: "sparkles", keywords: "insight inspector patterns mood",
                           shortcut: "⌥⌘I") {
                $0.pane = .day
                $0.showNoticed = true
            },
            PaletteCommand(id: "letter", title: "Evening letter", symbol: "envelope.open", keywords: "letter night reading") {
                $0.pane = .day
                $0.showLetter = true
            },
            PaletteCommand(id: "reread", title: "Read the day again", symbol: "arrow.clockwise", keywords: "refresh insights update reading noticed",
                           available: { $0.reflection.canRefresh }) { m in
                m.pane = .day
                Task { await m.reflection.refreshInsights() }
            },
            PaletteCommand(id: "answer", title: "Answer today's question", symbol: "book", keywords: "question wonder reply write back thought") { m in
                if !m.isToday { m.goToday() }
                m.insight = .panel
                m.reflection.answerRequested = true
            },
        ]
        #if DOGFOOD
        all.append(PaletteCommand(id: "decisions", title: "Decisions", symbol: "checklist", keywords: "dev log choices") { $0.pane = .decisions })
        #endif
        all += [
            PaletteCommand(id: "knows", title: "What Saro knows", symbol: "point.3.connected.trianglepath.dotted",
                           keywords: "memory memories people graph remember forget", shortcut: "⌥⌘K") { $0.pane = .knows },
            PaletteCommand(id: "memory-pause", title: "Pause memory", symbol: "pause.circle", keywords: "stop learning remember") { m in
                Task { await m.setMemoryPaused(true) }
            },
            PaletteCommand(id: "memory-resume", title: "Resume memory", symbol: "play.circle", keywords: "start learning remember") { m in
                Task { await m.setMemoryPaused(false) }
            },
            PaletteCommand(id: "trash", title: "Trash", symbol: "trash", keywords: "deleted bin restore") { $0.pane = .trash },
            PaletteCommand(id: "settings", title: "Settings…", symbol: "gearshape", keywords: "preferences tone reminder privacy text size say it",
                           shortcut: "⌘,") { _ in WindowActions.openSettings() },
            PaletteCommand(id: "sayit", title: "Change a setting in words…", symbol: "text.bubble", keywords: "say it settings remind bigger text tone") { _ in
                SettingsWindow.askInWords()
            },
            PaletteCommand(id: "profile", title: "Profile…", symbol: "person.crop.circle", keywords: "name called you account") { _ in
                PrefsStore.shared.settingsSection = .you
                WindowActions.openSettings()
            },
            PaletteCommand(id: "export", title: "Export everything", symbol: "square.and.arrow.up", keywords: "backup download save data") { m in
                Task { await m.exportEverything() }
            },
            PaletteCommand(id: "onboarding", title: "Replay onboarding", symbol: "arrow.counterclockwise", keywords: "welcome about you first week setup start again") { m in
                Task { await m.replayOnboarding() }
            },
        ]
        #if DOGFOOD
        all += [
            PaletteCommand(id: "tour", title: "Take the tour", symbol: "map", keywords: "help guide onboarding") { DevMode.shared.startTour($0) },
            PaletteCommand(id: "devnotes", title: "Dev notes", symbol: "doc.text.magnifyingglass", keywords: "dev debug notes", shortcut: "⇧⌘D") {
                $0.devNotesVisible.toggle()
            },
        ]
        #endif
        all.append(PaletteCommand(id: "struggling", title: "If you're struggling", symbol: "heart", keywords: "help crisis support safety talk someone hotline") { _ in
            NotificationCenter.default.post(name: .showSafetyCard, object: nil)
        })
        return all
    }()
    private static let start = ["write", "moment", "voice", "replay"].compactMap { id in commands.first { $0.id == id } }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var words: [String] { trimmed.split(whereSeparator: \.isWhitespace).map(String.init) }
    private var key: String { "\(scope?.rawValue ?? "*")|\(trimmed)" }
    private var loaded: Bool { hitsKey == key }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Tok.shadow.opacity(scheme == .dark ? 0.4 : 0.16)
                    .onTapGesture { if menuHit != nil { actionsOpen = false } else { isPresented = false } }
                panel
                    .frame(width: min(720, geo.size.width - 16), height: max(0, min(472, geo.size.height * 0.84 - 24)))
                    .padding(.top, geo.size.height * 0.16)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            focused = true
            if model.memory.status != .ready { Task { await model.memory.load() } }
            #if DOGFOOD
            if Snapshots.paletteActions { (actionsOpen, action) = (true, 0) }
            #endif
            window = NSApp?.keyWindow
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                MainActor.assumeIsolated { handle(event) } ? nil : event
            }
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
        .onChange(of: query) { _, q in
            selected = nil
            actionsOpen = false
            if scope == nil, q.hasSuffix(" "), let k = Self.scopes.first(where: { $0.aliases.plural.contains(q.trimmingCharacters(in: .whitespaces).lowercased()) }) {
                scope = k
                query = ""
            }
        }
        .onChange(of: scope) {
            selected = nil
            actionsOpen = false
        }
        .task(id: "\(key)|\(attempt)") {
            let (q, k, kind) = (trimmed, key, scope)
            // A hairline under the input says it's working, only once a search is slow enough to notice.
            let slow = Task {
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled { searching = true }
            }
            defer { slow.cancel(); searching = false }
            do {
                let found = try await model.ledger.search(q, kind: kind, limit: q.isEmpty ? (kind == nil ? 5 : 8) : Self.limit)
                guard !Task.isCancelled else { return }
                hits = found
                hitsKey = k
                failed = false
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
        }
    }

    // MARK: Layout

    private var panel: some View {
        VStack(spacing: 0) {
            input
            (searching ? Tok.sage : Tok.border).frame(height: 1)
            list
            Tok.border.frame(height: 1)
            footer
        }
        .background(Tok.surface)
        .clipShape(.rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Tok.border))
        .contentShape(.rect(cornerRadius: 20))
        .compositingGroup()
        .shadow(color: Tok.shadow.opacity(0.24), radius: 40, y: 32)
        .overlay {
            if let menuHit {
                ZStack(alignment: .bottomTrailing) {
                    // Modal like Radix's menu: a click anywhere else only closes it.
                    Color.clear.contentShape(.rect).onTapGesture { actionsOpen = false }
                    // 8 pt above the footer's Actions, right-aligned with it.
                    actionsMenu(menuHit).padding(.trailing, 8).padding(.bottom, 42)
                }
            } else if scopeMenu {
                ZStack(alignment: .topTrailing) {
                    Color.clear.contentShape(.rect).onTapGesture { scopeMenu = false }
                    // 6 pt under the type button, right-aligned with it.
                    scopesMenu.padding(.trailing, 12).padding(.top, 46)
                }
            }
        }
    }

    /// All types, then each type, the current one checked (SearchPalette.tsx's scope menu).
    private var scopesMenu: some View {
        VStack(spacing: 0) {
            ForEach(Array(([nil] + Self.scopes.map(Optional.some)).enumerated()), id: \.offset) { i, k in
                HStack(spacing: 8) {
                    Image(systemName: k?.symbol ?? "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(Tok.ink3).frame(width: 16)
                    Text(k?.plural ?? "All types").font(Typo.ui(13)).tracking(0.13).foregroundStyle(Tok.ink)
                    Spacer(minLength: 16)
                    if k == scope { Image(systemName: "checkmark").font(.system(size: 11, weight: .medium)).foregroundStyle(Tok.ink2) }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(i == scopeRow ? Tok.ink.opacity(0.06) : .clear, in: .rect(cornerRadius: Radius.control))
                .contentShape(.rect)
                .onTapGesture { choose(scope: k) }
                .onContinuousHover { if case .active = $0 { scopeRow = i } }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(k == scope ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { choose(scope: k) }
            }
        }
        .padding(6)
        .frame(width: 220)
        .background(Tok.surfaceAlt, in: .rect(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Tok.line))
        .elevation(.panel)
    }

    private func choose(scope k: EntryKind?) {
        scope = k
        scopeMenu = false
    }

    private func openScopeMenu() {
        scopeRow = scope.flatMap { Self.scopes.firstIndex(of: $0).map { $0 + 1 } } ?? 0
        actionsOpen = false
        scopeMenu = true
    }

    private var input: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(Tok.ink3)
            TextField("Search your journal", text: $query, prompt: Text("Search or type a command…").foregroundStyle(Tok.ink3))
                .textFieldStyle(.plain)
                .font(Typo.ui(18))
                .foregroundStyle(Tok.ink)
                .focused($focused)
            HStack(spacing: 6) {
                if let scope { Image(systemName: scope.symbol).font(.system(size: 11, weight: .medium)) }
                Text(scope?.plural ?? "All types")
                Kbd("⌘P")
            }
            .font(Typo.ui(13))
            .foregroundStyle(scope?.tint ?? Tok.ink2)
            .padding(.leading, 10).padding(.trailing, 4)
            .frame(height: 28)
            .background(scope.map { $0.tint.opacity(0.15) } ?? .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect)
            .onTapGesture { scopeMenu ? (scopeMenu = false) : openScopeMenu() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Search in: \(scope?.plural ?? "All types")")
        }
        .padding(.leading, 16).padding(.trailing, 12)
        .frame(height: 52)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { s in
                        // A section's title scrolls into view with its first row.
                        VStack(alignment: .leading, spacing: 0) {
                            if let title = s.title {
                                HStack {
                                    Text(title.uppercased()).kerning(1.26)
                                    Spacer()
                                    if let count = s.count { Text(count) }
                                }
                                .font(Typo.mono(10.5)).foregroundStyle(Tok.ink3)
                                .padding(.horizontal, 8).padding(.bottom, 6)
                                .frame(height: 28, alignment: .bottom)
                            }
                            if let note = s.note {
                                Text(note).font(Typo.ui(14)).foregroundStyle(Tok.ink3).padding(.horizontal, 8).padding(.vertical, 12)
                            }
                            if let miss = s.miss {
                                VStack(spacing: 4) {
                                    Text("Nothing matches “\(miss)”").font(Typo.serif(17)).foregroundStyle(Tok.ink2)
                                    Text("Typos are fine. Try fewer words.").font(Typo.ui(13)).foregroundStyle(Tok.ink3)
                                }
                                .frame(maxWidth: .infinity).padding(.top, 32).padding(.bottom, 16)
                            }
                            if let first = s.rows.first { row(first) }
                        }
                        .id(s.rows.first?.id ?? s.id)
                        ForEach(s.rows.dropFirst()) { row($0).id($0.id) }
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
            }
            .frame(maxHeight: .infinity)
            .onChange(of: current?.id) { _, id in if let id { proxy.scrollTo(id) } }
        }
    }

    private func row(_ row: Row) -> some View {
        let isCurrent = row.id == current?.id
        let (symbol, tint): (String, Color?) = switch row {
        case .entry(let h): (h.kind.symbol, h.kind.tint)
        case .command(let c): (c.symbol, nil)
        case .day: ("calendar", nil)
        case .scope(let k): (k.symbol, k.tint)
        case .write: (EntryKind.reflection.symbol, EntryKind.reflection.tint)
        case .memory: ("point.3.connected.trianglepath.dotted", Tok.sage)
        case .retry: ("exclamationmark.triangle", Tok.danger)
        case .widen: ("magnifyingglass", nil)
        }
        return HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint ?? Tok.ink2)
                .frame(width: 24, height: 24)
                .background(tint?.opacity(0.15) ?? Tok.ink.opacity(0.06), in: .rect(cornerRadius: 6))
            switch row {
            case .entry(let h):
                // The engine's own matches: stems, prefixes and typo-tolerant words, not just the letters typed.
                Text(h.title.map { Self.marked($0, h.titleHighlights, Typo.ui(14, .semibold)) } ?? AttributedString(h.kind.noun))
                    .font(Typo.ui(14, .medium)).foregroundStyle(Tok.ink)
                    .lineLimit(1).layoutPriority(1)
                Text(Self.marked(h.snippet, h.highlights, Typo.ui(13, .medium), Tok.ink)).font(Typo.ui(13)).foregroundStyle(Tok.ink3).lineLimit(1)
                    .frame(minWidth: h.snippet.isEmpty ? 0 : 160, maxWidth: .infinity, alignment: .leading)
                if let meta = h.meta { Text(meta).font(Typo.mono(11.5)).foregroundStyle(Tok.ink3).monospacedDigit().lineLimit(1).fixedSize() }
                right(Text(when(h).uppercased()))
            case .command(let c):
                title(c.title)
                if let value = c.value?(model) { Text(value).font(Typo.ui(13)).foregroundStyle(Tok.ink2).lineLimit(1).fixedSize() }
                if let s = c.shortcut { Kbd(s).frame(width: 72, alignment: .trailing) }
            case .retry:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Couldn't load your entries").font(Typo.ui(14, .medium)).foregroundStyle(Tok.danger)
                    Text("Try again").font(Typo.ui(12.5)).foregroundStyle(Tok.ink3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .widen:
                title("Search all types")
            case .day(let d):
                Text("Go to \(DayFormat.title(d))").font(Typo.ui(14, .medium)).foregroundStyle(Tok.ink).lineLimit(1).layoutPriority(1)
                Text(dayCount(d)).font(Typo.ui(13)).foregroundStyle(Tok.ink3).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .scope(let k):
                title("Search \(k.plural)")
                Kbd("Tab").frame(width: 72, alignment: .trailing)
            case .write(let text):
                title("New writing starting “\(text)”")
            case .memory(let m):
                Text(marked(m.text, Typo.ui(14, .semibold))).font(Typo.ui(14, .medium)).foregroundStyle(Tok.ink)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(isCurrent ? Tok.ink.opacity(scheme == .dark ? 0.08 : 0.06) : .clear, in: .rect(cornerRadius: 12))
        .contentShape(.rect)
        .background {
            if isCurrent { Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { currentFrame = $0 } }
        }
        .onTapGesture { run(row, from: isCurrent ? currentFrame : nil) }
        // Only a real pointer move selects: rows scrolling under a still pointer must not take the keyboard's place.
        .onContinuousHover { phase in
            guard case .active = phase, NSEvent.mouseLocation != mouse else { return }
            mouse = NSEvent.mouseLocation
            selected = row.id
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { run(row) }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(Typo.ui(14, .medium)).foregroundStyle(Tok.ink).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func right(_ text: Text) -> some View {
        text.font(Typo.mono(11.5)).foregroundStyle(Tok.ink3).lineLimit(1).frame(width: 72, alignment: .trailing)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                Text(context).foregroundStyle(Tok.ink3).opacity(flashOn ? 0 : 1)
                Text(flash).foregroundStyle(Tok.ink2).opacity(flashOn ? 1 : 0)
            }
            .font(Typo.ui(12.5)).lineLimit(1)
            .animation(Motion.easeOut(0.16), value: flashOn)
            Spacer()
            // Each hint does what it says when clicked.
            if let current {
                hint(primary(current), "↵") { run(current) }
                if replays(current) {
                    Tok.border.frame(width: 1, height: 16)
                    hint("Replay", "⌘↵") { replay(current) }
                }
                if case .entry = current {
                    Tok.border.frame(width: 1, height: 16)
                    hint("Actions", "⌘K") { openActions(byKey: false) }
                }
            }
        }
        .padding(.leading, 16).padding(.trailing, 12)
        .frame(height: 40)
    }

    private func hint(_ label: String, _ key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label).font(Typo.ui(12.5)).foregroundStyle(Tok.ink2)
                Kbd(key)
            }
            .padding(.horizontal, 6).frame(height: 28)
            .contentShape(.rect)
        }
        .buttonStyle(PressStyle(hoverFill: true, radius: Radius.control))
    }

    private func actionsMenu(_ h: SearchHit) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(EntryAction.allCases.enumerated()), id: \.offset) { i, a in
                if a == .trash { Tok.line.frame(height: 1).padding(.vertical, 4) }
                HStack(spacing: 8) {
                    Text(a.title).font(Typo.ui(13)).tracking(0.13).foregroundStyle(a == .trash ? Tok.danger : Tok.ink)
                    Spacer(minLength: 16)
                    if let key = a.key { Text(key).font(Typo.mono(11)).foregroundStyle(Tok.ink3) }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(i == action ? Tok.ink.opacity(0.06) : .clear, in: .rect(cornerRadius: Radius.control))
                .contentShape(.rect)
                .onTapGesture { perform(a, on: h) }
                .onContinuousHover { phase in
                    if case .active = phase { action = i } else if action == i { action = nil }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(i == action ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { perform(a, on: h) }
            }
        }
        .padding(6)
        .frame(width: 260)
        .background(Tok.surfaceAlt, in: .rect(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Tok.line))
        .elevation(.panel)
    }

    // MARK: Rows

    /// What the palette lists, in order (palette.ts's buildSections).
    private var sections: [PaletteSection] {
        let q = trimmed
        // A failed read says so in place, with Try again, above whatever still shows.
        var out: [PaletteSection] = failed ? [PaletteSection(id: "error", rows: [.retry])] : []
        if q.isEmpty {
            if let scope {
                return out + [PaletteSection(id: "recent", title: scope.plural, note: loaded && hits.isEmpty ? "No \(scope.plural.lowercased()) yet." : nil,
                                             rows: hits.map(Row.entry))]
            }
            if !hits.isEmpty { out.append(PaletteSection(id: "recent", title: "Recent", rows: hits.map(Row.entry))) }
            else if loaded && !failed { out.append(PaletteSection(id: "recent", note: "Your entries will show up here.")) }
            out.append(PaletteSection(id: "start", title: "Start", rows: Self.start.map(Row.command)))
            return out
        }
        var entries = hits
        if scope == nil {
            // One of Pause memory and Resume memory, whichever would change something.
            let memoryOff = model.profile?.memoryPaused == true ? "memory-pause" : "memory-resume"
            var matched = Self.commands.filter { $0.matches(q) && $0.available(model) && $0.id != memoryOff }
            var top: Row?
            if let day = LocalDay.parse(q) {
                top = .day(day)
            } else if words.count == 1, let k = Self.scope(prefix: q) {
                top = .scope(k)
            } else if q.count >= 2, let c = matched.first {
                top = .command(c)
                matched.removeFirst()
            } else if let h = entries.first {
                top = .entry(h)
                entries.removeFirst()
            }
            if let top { out.append(PaletteSection(id: "top", title: "Top hit", rows: [top])) }
            if !matched.isEmpty { out.append(PaletteSection(id: "commands", title: "Commands", rows: matched.prefix(3).map(Row.command))) }
            // FR-SRC-01: lines of What Saro knows, by their words and the person's own words behind them.
            let memories = model.memory.live.filter { MemoryList.matches($0, q) }
            if !memories.isEmpty { out.append(PaletteSection(id: "memories", title: "Memories", rows: memories.prefix(3).map(Row.memory))) }
        }
        if !entries.isEmpty {
            out.append(PaletteSection(id: "entries", title: scope?.plural ?? "Entries",
                                      count: hits.count >= Self.limit ? "\(Self.limit)+" : "\(entries.count)", rows: entries.map(Row.entry)))
        }
        // Nothing found: offer to start a writing with the words, pre-selected, and to widen a scoped search.
        if out.allSatisfy({ $0.id == "error" }) && loaded {
            out.append(PaletteSection(id: "none", miss: q, rows: [.write(q)] + (scope != nil ? [.widen] : [])))
        }
        return out
    }

    private var rows: [Row] { sections.flatMap(\.rows) }
    private var current: Row? { rows.first { $0.id == selected } ?? rows.first }
    private var menuHit: SearchHit? { if actionsOpen, case .entry(let h) = current { h } else { nil } }

    /// The one type whose aliases start with `word` (two letters at least).
    private static func scope(prefix word: String) -> EntryKind? {
        let w = word.lowercased()
        let found = w.count < 2 ? [] : scopes.filter { k in (k.aliases.singular + k.aliases.plural).contains { $0.hasPrefix(w) } }
        return found.count == 1 ? found[0] : nil
    }

    private var context: String {
        switch current {
        case .entry(let h): "\(h.kind.noun) · \(DayFormat.sidebar(h.localDay))"
        case .command: "Command"
        case .day: "Go to day"
        case .scope: "Narrow the search"
        case .write: "New writing"
        case .memory(let m): "What Saro knows · \(m.group.label)"
        case .retry: "Search"
        case .widen: "Every type"
        case nil: ""
        }
    }

    private func primary(_ row: Row) -> String {
        switch row {
        case .entry: "Open"
        case .day: "Go"
        case .scope, .widen: "Search"
        case .command, .write: "Run"
        case .memory: "Show"
        case .retry: "Try again"
        }
    }

    private func dayCount(_ day: String) -> String {
        let n = model.days.first { $0.day == day }?.count ?? 0
        return n == 0 ? "Nothing captured" : n == 1 ? "1 entry" : "\(n) entries"
    }

    /// As short as it can be: "3:33 PM" today, "Yesterday", "Tue" this week, "12 Oct", "Oct 2025".
    private func when(_ h: SearchHit) -> String {
        let today = LocalDay.today()
        if h.localDay == today { return h.capturedAt.formatted(date: .omitted, time: .shortened) }
        if h.localDay == LocalDay.adding(-1, to: today) { return "Yesterday" }
        guard let d = LocalDay.date(h.localDay) else { return "" }
        if h.localDay > LocalDay.adding(-7, to: today) { return d.formatted(.dateTime.weekday(.abbreviated)) }
        if h.localDay.prefix(4) == today.prefix(4) { return d.formatted(.dateTime.day().month(.abbreviated)) }
        return d.formatted(.dateTime.month(.abbreviated).year())
    }

    /// `text` with the engine's matches (UTF-16 ranges) set in `font` (and `color`).
    private static func marked(_ text: String, _ ranges: [Range<Int>], _ font: Font, _ color: Color? = nil) -> AttributedString {
        var a = AttributedString(text)
        let u = text.utf16
        for r in ranges where r.upperBound <= u.count {
            guard let lo = String.Index(u.index(u.startIndex, offsetBy: r.lowerBound), within: text),
                  let hi = String.Index(u.index(u.startIndex, offsetBy: r.upperBound), within: text),
                  let from = AttributedString.Index(lo, within: a), let to = AttributedString.Index(hi, within: a) else { continue }
            a[from..<to].font = font
            if let color { a[from..<to].foregroundColor = color }
        }
        return a
    }

    /// `text` with each query word set in `font` (and `color`).
    private func marked(_ text: String, _ font: Font, _ color: Color? = nil) -> AttributedString {
        var a = AttributedString(text)
        for w in words {
            var from = a.startIndex
            while let r = a[from...].range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) {
                a[r].font = font
                if let color { a[r].foregroundColor = color }
                from = r.upperBound
            }
        }
        return a
    }

    // MARK: Actions

    private func run(_ row: Row, from: CGRect? = nil) {
        switch row {
        case .entry(let h):
            isPresented = false
            Self.open(h, in: model, from: from.map { $0.offsetBy(dx: -model.dayOrigin.x, dy: -model.dayOrigin.y) })
        case .command(let c) where c.value != nil:
            // A setting cycles in place, and the footer flashes what it is now.
            c.run(model)
            show("\(c.title): \(c.value?(model) ?? "")")
        case .command(let c):
            isPresented = false
            c.run(model)
        case .retry:
            failed = false
            attempt += 1
        case .widen:
            scope = nil
        case .day(let d):
            isPresented = false
            model.go(to: d)
        case .scope(let k):
            scope = k
            query = ""
        case .write(let text):
            isPresented = false
            Self.write(text, in: model)
        case .memory(let m):
            isPresented = false
            model.pane = .knows
            model.memory.reveal = m.key
        }
    }

    /// ⌘↵ replays an entry's day or a day; anything else runs as ↵ would.
    private func replay(_ row: Row) {
        switch row {
        case .entry(let h): model.requestReplay(h.localDay)
        case .day(let d): model.requestReplay(d)
        default: return run(row)
        }
        isPresented = false
    }

    private func replays(_ row: Row) -> Bool {
        switch row {
        case .entry, .day: true
        default: false
        }
    }

    /// Opened by ⌘K its first action is highlighted, by a click none (as Radix does).
    private func openActions(byKey: Bool) {
        guard case .entry = current else { return }
        action = byKey ? 0 : nil
        actionsOpen = true
    }

    private func perform(_ a: EntryAction, on h: SearchHit) {
        actionsOpen = false
        switch a {
        case .open: run(.entry(h))
        case .replay: replay(.entry(h))
        case .day:
            isPresented = false
            model.go(to: h.localDay)
        case .copy: copy(h)
        case .trash:
            isPresented = false
            let flies = !Motion.byKey && !reduceMotion
            Task { await model.trash([h.entryId], undoManager: undoManager, flies: flies) }
        }
    }

    private func copy(_ h: SearchHit) {
        // An entry with no words of its own (a held one shows none of Saro's) leaves the clipboard as it was.
        let text: String
        if h.copyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = "Nothing to copy"
        } else {
            NSPasteboard.general.clearContents()
            text = NSPasteboard.general.setString(h.copyText, forType: .string) ? "Copied" : "Couldn't copy"
        }
        show(text)
    }

    /// In the footer, where the row's context was, for 1.6 s.
    private func show(_ text: String) {
        flash = text
        flashOn = true
        AccessibilityNotification.Announcement(text).post()
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            if !Task.isCancelled { flashOn = false }
        }
    }

    /// The canvas opens an entry only once it is loaded, so another day's entry waits for that day to load. A clicked row
    /// is where the entry's flight into its detail starts (day view coordinates); a key opens it from its card.
    private static func open(_ h: SearchHit, in model: AppModel, from: CGRect? = nil) {
        model.go(to: h.localDay)
        Task {
            if model.entry(h.entryId) == nil { await model.reload() }
            model.reflection.flightSource = from
            model.openEntryID = h.entryId
        }
    }

    private static func write(_ body: String, in model: AppModel) {
        model.pane = .day
        Task { if let e = await model.newWriting(body: body) { model.openEntryID = e.id } }
    }

    private func move(_ by: Int) {
        let all = rows
        guard !all.isEmpty else { return }
        let i = current.flatMap { c in all.firstIndex { $0.id == c.id } } ?? 0
        selected = all[max(0, min(i + by, all.count - 1))].id
    }


    /// Keys while the palette is up, before the text field or the canvas sees them. Returns whether it used the key.
    private func handle(_ e: NSEvent) -> Bool {
        guard e.window === window, (e.window?.firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }
        let mods = e.modifierFlags.intersection([.command, .control, .option, .shift])
        if let menuHit { return handleActions(e, mods, menuHit) }
        if scopeMenu { return handleScopes(e, mods) }
        switch e.keyCode {
        case 125: move(1)
        case 126: move(-1)
        case 36, 76:
            if !e.isARepeat, let current { mods.contains(.command) ? replay(current) : run(current) }
        case 53:
            if !query.isEmpty { query = "" } else if scope != nil { scope = nil } else { isPresented = false }
        case 48:
            if let first = words.first, scope == nil, let k = Self.scope(prefix: first) {
                scope = k
                query = words.dropFirst().joined(separator: " ")
            }
        case 51 where query.isEmpty && scope != nil && mods.isEmpty:
            scope = nil
        default:
            switch (mods, e.charactersIgnoringModifiers?.lowercased()) {
            // On any row, so it never reaches the menu bar's ⌘K and closes the palette.
            case (.command, "k"): openActions(byKey: true)
            case ([.command, .shift], "c"):
                guard case .entry(let h) = current else { return false }
                copy(h)
            case (.command, "p"): openScopeMenu()
            case (.control, "n"): move(1)
            case (.control, "p"): move(-1)
            default: return false
            }
        }
        return true
    }

    /// The type menu: ↑↓, Home/End, ↵ or Space, a first letter, Esc or ⌘P to close.
    private func handleScopes(_ e: NSEvent, _ mods: NSEvent.ModifierFlags) -> Bool {
        let all: [EntryKind?] = [nil] + Self.scopes.map(Optional.some)
        switch e.keyCode {
        case 125: scopeRow = min(scopeRow + 1, all.count - 1)
        case 126: scopeRow = max(scopeRow - 1, 0)
        case 115: scopeRow = 0
        case 119: scopeRow = all.count - 1
        case 36, 76, 49: if !e.isARepeat { choose(scope: all[scopeRow]) }
        case 53: scopeMenu = false
        default:
            let char = e.charactersIgnoringModifiers?.lowercased()
            if mods == .command, char == "p" || char == "k" { scopeMenu = false }
            else if mods.contains(.command) { return false }
            else if let char, let i = all.firstIndex(where: { ($0?.plural ?? "all types").lowercased().hasPrefix(char) }) { scopeRow = i }
        }
        return true
    }

    /// The actions menu has every key but the menu bar's: ↑↓, Home/End, ↵ or Space, a first letter, Esc or ⌘K/⌘P to close.
    private func handleActions(_ e: NSEvent, _ mods: NSEvent.ModifierFlags, _ h: SearchHit) -> Bool {
        let all = EntryAction.allCases
        let char = e.charactersIgnoringModifiers?.lowercased()
        switch e.keyCode {
        case 125: action = min((action ?? -1) + 1, all.count - 1)
        case 126: action = max((action ?? all.count) - 1, 0)
        case 115: action = 0
        case 119: action = all.count - 1
        case 36, 76, 49: if !e.isARepeat, let action { perform(all[action], on: h) }
        case 53: actionsOpen = false
        default:
            if mods == .command, char == "k" || char == "p" {
                actionsOpen = false
            } else if mods.contains(.command) {
                return false
            } else if mods.subtracting(.shift).isEmpty, let char, let i = all.firstIndex(where: { $0.title.lowercased().hasPrefix(char) }) {
                action = i
            }
        }
        return true
    }
}

private extension Daylight.Mode {
    var title: String {
        switch self {
        case .clock: "Follow the day"
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

private struct Kbd: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(Typo.mono(11)).foregroundStyle(Tok.ink2)
            .padding(.horizontal, 4)
            .frame(minWidth: 20, minHeight: 20)
            .background(Tok.ink.opacity(0.06), in: .rect(cornerRadius: 5))
    }
}
