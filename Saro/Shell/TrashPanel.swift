import AppKit
import SaroKit
import SwiftUI

/// Trash (TrashModal.tsx, DR-15): what you deleted, each with its days left, to restore or delete for good, and Restore
/// all or a two-step Empty trash with its progress. A glass popover above the bar from the account menu, or the pane.
struct TrashPanel: View {
    enum Style { case popover, pane }
    let style: Style

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var items: [Entry] = []
    @State private var loaded = false
    @State private var confirming: String?
    @State private var confirmEmpty = false
    @State private var armedAt = Date.distantPast
    @State private var busy: (restore: Bool, of: Int)?
    @State private var rows: [String: CGRect] = [:]
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case keep(String), delete(String), keepAll, empty }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Tok.line.opacity(0.7)).frame(height: 1)
            if items.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(spacing: 4) { ForEach(items) { row($0) } }.padding(8)
                }
                .frame(maxHeight: style == .popover ? 400 : 640)
                .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(Tok.line.opacity(0.7)).frame(height: 1)
                footer
            }
        }
        .frame(width: style == .popover ? 400 : nil)
        .frame(maxWidth: style == .pane ? 560 : nil)
        .modifier(TrashSurface(style: style))
        .task(id: model.entries.map(\.id)) { await load() }
        .onAppear { if style == .pane { model.screen = .trash } }
        .onExitCommand { if style == .popover { ShellPanels.shared.panel = nil } }
        // Keys here must not reach the canvas under it, where ⌫ trashes the selection.
        .onDeleteCommand {}
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trash")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Trash").font(Typo.ui(20, .semibold)).foregroundStyle(Tok.ink)
            if !items.isEmpty { Text("\(items.count)").font(Typo.mono(12, .regular)).foregroundStyle(Tok.ink3) }
            Spacer()
            if style == .popover {
                Button { ShellPanels.shared.panel = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .medium)).frame(width: 36, height: 36)
                }
                .buttonStyle(PressStyle(hoverFill: true, radius: 18))
                .foregroundStyle(Tok.ink2)
                .accessibilityLabel("Close trash")
            }
        }
        .padding(.leading, 20).padding(.trailing, style == .popover ? 12 : 20).padding(.vertical, style == .popover ? 8 : 16)
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Image(systemName: "trash").font(.system(size: 34, weight: .light)).foregroundStyle(Tok.ink3.opacity(0.5)).padding(.bottom, 10)
            Text("Nothing in the trash").font(Typo.ui(13, .medium)).foregroundStyle(Tok.ink)
            Text("Deleted items wait here for 30 days.").font(Typo.ui(12)).foregroundStyle(Tok.ink2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 48)
        .opacity(loaded ? 1 : 0)
        .accessibilityElement(children: .combine)
    }

    private func row(_ e: Entry) -> some View {
        let asking = confirming == e.id
        let title = Self.title(e)
        return HStack(spacing: 12) {
            Image(systemName: e.kind.symbol).font(.system(size: 14)).foregroundStyle(e.kind.inkTint).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.ui(13, .medium)).foregroundStyle(Tok.ink).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).naturalAlignment(for: title)
                Text(asking ? "Delete forever? This can't be undone." : TrashClock.left(until: Ledger.expiry(trashedAt: e.trashedAt ?? .now)))
                    .font(Typo.ui(12)).foregroundStyle(asking ? Tok.danger : Tok.ink2)
            }
            if asking {
                HStack(spacing: 4) {
                    Button("Keep") {
                        confirming = nil
                        focus = nil
                    }
                    .buttonStyle(TrashTextButton(kind: .quiet))
                    .focused($focus, equals: .keep(e.id))
                    Button("Delete") {
                        guard decided() else { return }
                        confirming = nil
                        Task { await deleteForever([e]) }
                    }
                    .buttonStyle(TrashTextButton(kind: .danger))
                    .focused($focus, equals: .delete(e.id))
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 2) {
                    iconButton("arrow.uturn.backward", "Restore \(title)", hover: Tok.sage) {
                        guard !doubleClick else { return }
                        Task { await restore([e]) }
                    }
                    .help("Restore")
                    iconButton("trash", "Delete \(title) forever", hover: Tok.danger) {
                        guard !doubleClick else { return }
                        armedAt = .now
                        confirming = e.id
                        // Keep is focused, so a held Return can't confirm (TrashModal.tsx).
                        focus = .keep(e.id)
                    }
                    .help("Delete forever")
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minHeight: 56)
        .background(asking ? Tok.dangerBg : .clear, in: .rect(cornerRadius: Radius.field))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rows[e.id] = $0 }
        .animation(Motion.fade, value: asking)
        .accessibilityElement(children: .contain)
    }

    private var footer: some View {
        let n = items.count
        let status = busy.map { "\($0.restore ? "Restoring" : "Deleting") \(max(0, $0.of - n)) of \($0.of)…" }
            ?? (confirmEmpty ? "Delete \(n == 1 ? "this item" : "all \(n)") forever?" : "Deleted for good after 30 days.")
        return HStack(spacing: 4) {
            Text(status).font(Typo.ui(12)).foregroundStyle(confirmEmpty ? Tok.danger : Tok.ink2).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
                .accessibilityAddTraits(.updatesFrequently)
            if confirmEmpty {
                Button("Keep") {
                    confirmEmpty = false
                    focus = .empty
                }
                .buttonStyle(TrashTextButton(kind: .quiet))
                .focused($focus, equals: .keepAll)
            } else {
                Button("Restore all") {
                    guard !doubleClick else { return }
                    Task { await restore(items, all: true) }
                }
                .buttonStyle(TrashTextButton(kind: .sage))
                .disabled(busy != nil)
            }
            Button(confirmEmpty ? "Empty trash" : "Empty trash…") {
                if !confirmEmpty {
                    guard !doubleClick else { return }
                    armedAt = .now
                    confirmEmpty = true
                    focus = .keepAll
                    return
                }
                guard decided() else { return }
                confirmEmpty = false
                Task { await deleteForever(items, all: true) }
            }
            .buttonStyle(TrashTextButton(kind: confirmEmpty ? .danger : .dangerQuiet))
            .focused($focus, equals: .empty)
            .disabled(busy != nil)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .onChange(of: status) { _, s in if busy != nil || confirmEmpty { AccessibilityNotification.Announcement(s).post() } }
    }

    private func iconButton(_ symbol: String, _ label: String, hover: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 36, height: 36).contentShape(.circle)
        }
        .buttonStyle(TrashIconButton(hover: hover))
        .accessibilityLabel(label)
    }

    // MARK: Guards (TrashModal.tsx)

    /// A double-click's second click, which landed on what took the first one's place.
    private var doubleClick: Bool { (NSApp.currentEvent?.type == .leftMouseUp || NSApp.currentEvent?.type == .leftMouseDown) && (NSApp.currentEvent?.clickCount ?? 1) > 1 }

    /// The second step of a confirm is a decision: not the same gesture's second click, not within 500 ms, not a held Return.
    private func decided() -> Bool {
        !doubleClick && Date.now.timeIntervalSince(armedAt) >= 0.5 && NSApp.currentEvent.map { $0.type != .keyDown || !$0.isARepeat } ?? true
    }

    // MARK: Actions

    private func load() async {
        items = (try? await model.ledger.trashed()) ?? items
        loaded = true
    }

    /// Six at a time, so the footer counts up and what failed stays.
    private func restore(_ entries: [Entry], all: Bool = false) async {
        if all { busy = (true, entries.count) }
        let flies = style == .popover && !all && !Motion.byKey && !reduceMotion
        var done = 0
        for chunk in stride(from: 0, to: entries.count, by: 6).map({ Array(entries[$0..<min($0 + 6, entries.count)]) }) {
            guard await model.restore(ids: chunk.map(\.id)) else { break }
            done += chunk.count
            items.removeAll { e in chunk.contains { $0.id == e.id } }
        }
        busy = nil
        if all, done > 0 { model.show(Toast(done == 1 ? "Restored 1 item" : "Restored \(done) items")) }
        // One restored: it flies back to its card when that's on screen, and otherwise says where it went.
        if !all, done == 1, let e = entries.first, !(flies && flyBack(e)) {
            model.show(Toast("Restored to \(DayFormat.sidebar(e.localDay))"))
        }
        await load()
    }

    private func deleteForever(_ entries: [Entry], all: Bool = false) async {
        if all { busy = (false, entries.count) }
        var done = 0
        for chunk in stride(from: 0, to: entries.count, by: 6).map({ Array(entries[$0..<min($0 + 6, entries.count)]) }) {
            guard await model.deleteForever(chunk.map(\.id)) else { break }
            done += chunk.count
            items.removeAll { e in chunk.contains { $0.id == e.id } }
        }
        busy = nil
        if all, done > 0 { model.show(Toast(done == 1 ? "Deleted 1 item for good" : "Deleted \(done) items for good")) }
        await load()
    }

    /// The restored card flies from its row back to its place on the canvas, through the trash flight Undo uses. False
    /// when its card isn't on screen.
    private func flyBack(_ e: Entry) -> Bool {
        guard let row = rows[e.id], let origin = ShellPanels.shared.toastOrigin,
              let card = model.stageCards.first(where: { $0.ids.contains(e.id) }) else { return false }
        let frame = row.offsetBy(dx: -origin.x, dy: -origin.y)
        model.trashFlight = TrashFlight(cards: [card], back: (Toast(title: Self.title(e)), frame))
        return true
    }

    /// The person's own words only: a trashed entry's generated title is never read here.
    static func title(_ e: Entry) -> String {
        if let t = e.titleUser?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        let own = e.kind == .still ? e.captionUser : e.kind == .reflection || e.kind == .music ? e.body : nil
        if let line = own?.split(separator: "\n").first?.trimmingCharacters(in: .whitespaces), !line.isEmpty { return String(line.prefix(80)) }
        return e.kind.noun
    }
}

private struct TrashSurface: ViewModifier {
    let style: TrashPanel.Style

    func body(content: Content) -> some View {
        switch style {
        case .popover:
            content
                .background(Tok.paper.opacity(0.95), in: .rect(cornerRadius: Radius.panel))
                .background(.frosted(solid: Tok.paper), in: .rect(cornerRadius: Radius.panel))
                .clipShape(.rect(cornerRadius: Radius.panel))
                .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Tok.rim.opacity(0.6)))
                .elevation(.float)
                .background { DismissCatcher { ShellPanels.shared.panel = nil } }
        case .pane:
            content
                .glassPanel()
                .padding(.vertical, 40).padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background { LitGround().ignoresSafeArea() }
                .background(Tok.bg)
        }
    }
}

/// TrashModal.tsx's text buttons: 36 pt, radius 8.
private struct TrashTextButton: ButtonStyle {
    enum Kind { case quiet, sage, danger, dangerQuiet }
    let kind: Kind
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        let (ink, fill): (Color, Color) = switch kind {
        case .quiet: (hover ? Tok.ink : Tok.ink2, Tok.ink.opacity(hover ? 0.05 : 0))
        case .sage: (Tok.sageDark, Tok.sage.opacity(hover ? 0.1 : 0))
        case .danger: (Tok.onPrimary, Tok.danger.opacity(hover ? 0.9 : 1))
        case .dangerQuiet: (Tok.danger, hover ? Tok.dangerBg : .clear)
        }
        configuration.label
            .font(Typo.ui(13, .medium))
            .foregroundStyle(ink)
            .padding(.horizontal, 12).frame(minHeight: 36)
            .background(fill, in: .rect(cornerRadius: Radius.control))
            .contentShape(.rect(cornerRadius: Radius.control))
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .focusRing(radius: Radius.control)
            .onHover { hover = $0 }
    }
}

private struct TrashIconButton: ButtonStyle {
    let hover: Color
    @State private var on = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(on ? (hover == Tok.danger ? Tok.danger : Tok.sageDark) : Tok.ink2)
            .background(on ? (hover == Tok.danger ? Tok.dangerBg : Tok.sage.opacity(0.1)) : .clear, in: .circle)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .focusRing(radius: 18)
            .onHover { on = $0 }
    }
}

extension EntryKind {
    /// The type's text-safe ink (TrashModal.tsx TYPE).
    var inkTint: Color {
        switch self {
        case .moment: Tok.momentInk
        case .voice: Tok.echoInk
        case .still: Tok.stillInk
        case .reflection: Tok.reflectionInk
        case .music: Tok.music
        }
    }
}
