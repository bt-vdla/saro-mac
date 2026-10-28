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
    let run: @MainActor (AppModel) -> Void

    /// Every query word starts a word of the title or keywords, or the query is the title's initials ("wsn").
    func matches(_ query: String) -> Bool {
        let words = Self.words(query)
        let title = Self.words(self.title)
        guard !words.isEmpty else { return false }
        if words.allSatisfy({ w in (title + Self.words(keywords)).contains { $0.hasPrefix(w) } }) { return true }
        return words.count == 1 && words[0].count >= 2 && String(title.compactMap(\.first)) == words[0]
    }

    private static func words(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

private enum Row: Identifiable {
    case entry(SearchHit)
    case command(PaletteCommand)
    case day(String)
    case scope(EntryKind)
    case write(String)

    var id: String {
        switch self {
        case .entry(let h): "e:\(h.entryId)"
        case .command(let c): "c:\(c.id)"
        case .day(let d): "d:\(d)"
        case .scope(let k): "s:\(k.rawValue)"
        case .write: "w"
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

/// ⌘K: search every entry and run commands. Keyboard all the way: ↑↓ move, ↵ runs, ⌘↵ goes to the row's day,
/// ⌘P (or "moments ", or a type and Tab) scopes, Esc steps back through the query and scope, then closes.
struct SearchPalette: View {
    @Binding var isPresented: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool
    @State private var query = ""
    @State private var scope: EntryKind?
    @State private var hits: [SearchHit] = []
    /// The query and scope `hits` belong to; until it matches, the last results stay up instead of flashing empty.
    @State private var hitsKey: String?
    @State private var selected: String?
    @State private var window: NSWindow?
    @State private var monitor: Any?
    @State private var mouse: CGPoint?

    private static let limit = 50
    private static let scopes: [EntryKind] = [.moment, .voice, .reflection, .still]
    private static let commands: [PaletteCommand] = {
        var all = [
            PaletteCommand(id: "today", title: "Today", symbol: "sun.max", keywords: "go now day home", shortcut: "⌘T") { $0.goToday() },
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
            PaletteCommand(id: "noticed", title: "What Saro noticed", symbol: "sparkles", keywords: "insight inspector patterns mood",
                           shortcut: "⌥⌘I") {
                $0.pane = .day
                $0.showNoticed = true
            },
            PaletteCommand(id: "letter", title: "Evening letter", symbol: "envelope.open", keywords: "letter night reading") {
                $0.pane = .day
                $0.showLetter = true
            },
        ]
        #if DOGFOOD
        all.append(PaletteCommand(id: "decisions", title: "Decisions", symbol: "checklist", keywords: "dev log choices") { $0.pane = .decisions })
        #endif
        all += [
            PaletteCommand(id: "trash", title: "Trash", symbol: "trash", keywords: "deleted bin restore") { $0.pane = .trash },
            PaletteCommand(id: "export", title: "Export everything", symbol: "square.and.arrow.up", keywords: "backup download save data") { m in
                Task { await m.exportEverything() }
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
    private static let start = ["write", "moment", "voice", "today"].compactMap { id in commands.first { $0.id == id } }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var words: [String] { trimmed.split(whereSeparator: \.isWhitespace).map(String.init) }
    private var key: String { "\(scope?.rawValue ?? "*")|\(trimmed)" }
    private var loaded: Bool { hitsKey == key }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Tok.shadow.opacity(scheme == .dark ? 0.4 : 0.16)
                    .onTapGesture { isPresented = false }
                panel
                    .frame(width: min(720, geo.size.width - 16), height: max(0, min(472, geo.size.height * 0.84 - 24)))
                    .padding(.top, geo.size.height * 0.16)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            focused = true
            window = NSApp?.keyWindow
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                MainActor.assumeIsolated { handle(event) } ? nil : event
            }
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
        .onChange(of: query) { _, q in
            selected = nil
            if scope == nil, q.hasSuffix(" "), let k = Self.scopes.first(where: { $0.aliases.plural.contains(q.trimmingCharacters(in: .whitespaces).lowercased()) }) {
                scope = k
                query = ""
            }
        }
        .onChange(of: scope) { selected = nil }
        .task(id: key) {
            let (q, k, kind) = (trimmed, key, scope)
            do {
                let found = try await model.ledger.search(q, kind: kind, limit: q.isEmpty ? (kind == nil ? 6 : 8) : Self.limit)
                guard !Task.isCancelled else { return }
                hits = found
                hitsKey = k
            } catch {
                model.show(Toast("Couldn't search: \(error.localizedDescription)", style: .error))
            }
        }
    }

    // MARK: Layout

    private var panel: some View {
        VStack(spacing: 0) {
            input
            Tok.border.frame(height: 1)
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
            .onTapGesture { cycleScope() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Search in: \(scope?.plural ?? "All types")")
            Kbd("⌘K")
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
                                    Text("Try fewer words, or another spelling.").font(Typo.ui(13)).foregroundStyle(Tok.ink3)
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
        }
        return HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint ?? Tok.ink2)
                .frame(width: 24, height: 24)
                .background(tint?.opacity(0.15) ?? Tok.ink.opacity(0.06), in: .rect(cornerRadius: 6))
            switch row {
            case .entry(let h):
                Text(marked(h.title ?? h.kind.noun, Typo.ui(14, .semibold))).font(Typo.ui(14, .medium)).foregroundStyle(Tok.ink)
                    .lineLimit(1).layoutPriority(1)
                Text(marked(h.snippet, Typo.ui(13, .medium), Tok.ink)).font(Typo.ui(13)).foregroundStyle(Tok.ink3).lineLimit(1)
                    .frame(minWidth: h.snippet.isEmpty ? 0 : 160, maxWidth: .infinity, alignment: .leading)
                right(Text(when(h).uppercased()))
            case .command(let c):
                title(c.title)
                if let s = c.shortcut { Kbd(s).frame(width: 72, alignment: .trailing) }
            case .day(let d):
                Text("Go to \(DayFormat.title(d))").font(Typo.ui(14, .medium)).foregroundStyle(Tok.ink).lineLimit(1).layoutPriority(1)
                Text(dayCount(d)).font(Typo.ui(13)).foregroundStyle(Tok.ink3).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .scope(let k):
                title("Search \(k.plural)")
                Kbd("Tab").frame(width: 72, alignment: .trailing)
            case .write(let text):
                title("Write “\(text)”")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(isCurrent ? Tok.ink.opacity(scheme == .dark ? 0.08 : 0.06) : .clear, in: .rect(cornerRadius: 12))
        .contentShape(.rect)
        .onTapGesture { run(row) }
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
            Text(context).font(Typo.ui(12.5)).foregroundStyle(Tok.ink3).lineLimit(1)
            Spacer()
            if let current {
                hint(primary(current), "↵")
                if case .entry = current {
                    Tok.border.frame(width: 1, height: 16)
                    hint("Go to day", "⌘↵")
                }
            }
        }
        .padding(.leading, 16).padding(.trailing, 12)
        .frame(height: 40)
    }

    private func hint(_ label: String, _ key: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(Typo.ui(12.5)).foregroundStyle(Tok.ink2)
            Kbd(key)
        }
    }

    // MARK: Rows

    private var sections: [PaletteSection] {
        let q = trimmed
        if q.isEmpty {
            if let scope {
                return [PaletteSection(id: "recent", title: scope.plural, note: loaded && hits.isEmpty ? "No \(scope.plural.lowercased()) yet." : nil,
                                       rows: hits.map(Row.entry))]
            }
            var out: [PaletteSection] = []
            if !hits.isEmpty { out.append(PaletteSection(id: "recent", title: "Recent", rows: hits.map(Row.entry))) }
            out.append(PaletteSection(id: "start", title: "Start", rows: Self.start.map(Row.command)))
            return out
        }
        var out: [PaletteSection] = []
        var entries = hits
        if scope == nil {
            var matched = Self.commands.filter { $0.matches(q) }
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
        }
        if !entries.isEmpty {
            out.append(PaletteSection(id: "entries", title: scope?.plural ?? "Entries",
                                      count: hits.count >= Self.limit ? "\(Self.limit)+" : "\(entries.count)", rows: entries.map(Row.entry)))
        }
        if out.isEmpty && loaded { out.append(PaletteSection(id: "none", miss: q, rows: [.write(q)])) }
        return out
    }

    private var rows: [Row] { sections.flatMap(\.rows) }
    private var current: Row? { rows.first { $0.id == selected } ?? rows.first }

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
        case nil: ""
        }
    }

    private func primary(_ row: Row) -> String {
        switch row {
        case .entry: "Open"
        case .day: "Go"
        case .scope: "Search"
        case .command, .write: "Run"
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

    private func run(_ row: Row) {
        switch row {
        case .entry(let h):
            isPresented = false
            Self.open(h, in: model)
        case .command(let c):
            isPresented = false
            c.run(model)
        case .day(let d):
            isPresented = false
            model.go(to: d)
        case .scope(let k):
            scope = k
            query = ""
        case .write(let text):
            isPresented = false
            Self.write(text, in: model)
        }
    }

    /// ⌘↵: an entry's day, or what ↵ does for anything else.
    private func goToDay(_ row: Row) {
        guard case .entry(let h) = row else { return run(row) }
        isPresented = false
        model.go(to: h.localDay)
    }

    /// The canvas opens an entry only once it is loaded, so another day's entry waits for that day to load.
    private static func open(_ h: SearchHit, in model: AppModel) {
        model.go(to: h.localDay)
        Task {
            if model.entry(h.entryId) == nil { await model.reload() }
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

    private func cycleScope() {
        let i = scope.flatMap { Self.scopes.firstIndex(of: $0) } ?? -1
        scope = i + 1 < Self.scopes.count ? Self.scopes[i + 1] : nil
    }

    /// Keys while the palette is up, before the text field or the canvas sees them. Returns whether it used the key.
    private func handle(_ e: NSEvent) -> Bool {
        guard e.window === window, (e.window?.firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }
        let mods = e.modifierFlags.intersection([.command, .control, .option, .shift])
        switch e.keyCode {
        case 125: move(1)
        case 126: move(-1)
        case 36, 76:
            if !e.isARepeat, let current { mods.contains(.command) ? goToDay(current) : run(current) }
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
            case (.command, "p"): cycleScope()
            case (.control, "n"): move(1)
            case (.control, "p"): move(-1)
            default: return false
            }
        }
        return true
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
