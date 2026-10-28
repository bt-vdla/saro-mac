import AppKit
import Observation
import SaroKit
import SwiftUI

/// Which of the avatar's glass panels is up above the bar: its menu or Trash.
@Observable @MainActor
final class ShellPanels {
    // ponytail: one per process like DevMode, so the bar, the palette and the Entry menu share it without wiring.
    static let shared = ShellPanels()
    enum Panel { case account, trash }
    var panel: Panel?
    /// It opened from a key, so it shows and goes at once (the frequency rule).
    var byKey = false

    enum Sheet: Identifiable, Hashable {
        case edit(String), duplicate(String)
        var id: Self { self }
    }
    var sheet: Sheet?
    /// Where the toasts' layer sits in its window, so a card can fly from a Trash row through it.
    @ObservationIgnored var toastOrigin: CGPoint?

    func open(_ p: Panel) {
        byKey = Motion.byKey
        panel = p
    }
}

/// The bar's first control (BottomLeftStatus.tsx): your initials on sage with the save status as a 10 pt dot, and "Not
/// saved" beside it while a write has failed. A click grows the account menu out of it.
struct AvatarButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var panels: ShellPanels { .shared }

    var body: some View {
        let saves = model.saves
        Button {
            if panels.panel == nil { panels.open(.account) } else { panels.panel = nil }
        } label: {
            HStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Initials(profile: model.profile, size: 36)
                    Circle()
                        .fill(saves.pending ? Tok.reflection : saves.notSaved ? Tok.danger : Tok.moment)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Tok.paper, lineWidth: 2).padding(-2))
                        .breathing(saves.pending && !reduceMotion)
                        .opacity(saves.pending || saves.notSaved || saves.justSaved ? 1 : 0)
                        .animation(Motion.easeOut(0.4), value: saves.justSaved)
                        .offset(x: 1, y: 1)
                }
                if saves.notSaved {
                    Text("Not saved").font(Typo.ui(12, .medium)).foregroundStyle(Tok.danger).fixedSize()
                }
            }
            .padding(.horizontal, saves.notSaved ? 4 : 0).padding(.trailing, saves.notSaved ? 4 : 0)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.capsule)
        }
        .buttonStyle(PressStyle(hoverFill: true, radius: 22))
        .help(saves.notSaved ? "Something didn't save. Open this menu to try again." : "Your journal")
        .accessibilityLabel("Account menu")
        .accessibilityValue(saves.tally.label)
        .onAppear { CardMenuKeys.install(model) }
        // Another day closes what was open over the bar.
        .onChange(of: model.day) { panels.panel = nil }
    }
}

/// The account menu or Trash, 8 pt above the whole bar from its left edge, over everything on it. It grows out of the
/// avatar on Motion.small, and comes and goes at once when a key opened it.
struct ShellPanelLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var panels: ShellPanels { .shared }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            switch panels.panel {
            case .account: AccountMenu().transition(transition)
            case .trash: TrashPanel(style: .popover).transition(transition)
            case nil: EmptyView()
            }
        }
        .fixedSize()
        // ponytail: the bar's height (64, its 52 pt captures in 6 pt of padding) as a constant, as ToastHost does.
        .padding(.bottom, 72)
        .animation(panels.byKey ? nil : Motion.pick(Motion.small, reduce: reduceMotion), value: panels.panel)
    }

    private var transition: AnyTransition {
        panels.byKey ? .identity : reduceMotion ? .opacity : .scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity)
    }
}

/// The sage disc with white initials in Newsreader (ProfileAvatar.tsx); decorative beside the name it stands for.
struct Initials: View {
    let profile: Profile?
    let size: CGFloat

    var body: some View {
        let called = profile?.called?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let letters = ShellText.initials(called.isEmpty ? profile?.name ?? "" : called)
        Text(letters.isEmpty ? "—" : letters)
            .font(Typo.serif(size * 0.42))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Tok.sage, in: .circle)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .accessibilityHidden(true)
    }
}

/// The account menu (ProfileMenuPanel.tsx), grown out of the avatar: who keeps this journal, Profile and Settings, the
/// day as an image, Trash, the lock, Retry when something didn't save, and the Developer items in dogfood builds.
private struct AccountMenu: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focus: Int?
    private var panels: ShellPanels { .shared }

    var body: some View {
        let saves = model.saves
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Initials(profile: model.profile, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    let name = [model.profile?.name, model.profile?.called].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
                    Text(name ?? "Your journal").font(Typo.ui(13, .medium)).foregroundStyle(Tok.ink).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading).naturalAlignment(for: name ?? "")
                    Text(model.isDemo ? "Demo journal · temporary" : "Journal on this Mac").font(Typo.ui(12)).foregroundStyle(Tok.ink3)
                }
            }
            .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 8)
            .accessibilityElement(children: .combine)
            if saves.notSaved {
                MenuRow("Not saved · Retry", symbol: "exclamationmark.arrow.circlepath", tint: Tok.danger, index: 0, focus: $focus) {
                    Task { await saves.retryAll() }
                }
                .help("Something didn't save. Saro tries it again on this Mac.")
            }
            MenuDivider()
            MenuRow("Profile…", symbol: "person", index: 1, focus: $focus) {
                PrefsStore.shared.settingsSection = .you
                WindowActions.openSettings()
            }
            MenuRow("Settings…", symbol: "slider.horizontal.3", keys: "⌘,", index: 2, focus: $focus) { WindowActions.openSettings() }
            MenuDivider()
            MenuRow("Export Day as Image…", symbol: "square.and.arrow.down", index: 3, focus: $focus) {
                Task { await model.exportDayImage() }
            }
            MenuRow("Trash", symbol: "trash", index: 4, focus: $focus, closes: false) { panels.open(.trash) }
            if PrefsStore.shared.lockEnabled {
                MenuRow("Lock Saro", symbol: "lock", keys: "⌃⌘L", index: 5, focus: $focus) { Locker.shared.lock() }
            }
            #if DOGFOOD
            DeveloperItems(focus: $focus)
            #endif
        }
        .padding(8)
        .frame(width: 288)
        .background(Tok.paper.opacity(0.95), in: .rect(cornerRadius: Radius.panel))
        .background(.frosted(solid: Tok.paper), in: .rect(cornerRadius: Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Tok.rim.opacity(0.6)))
        .elevation(.float)
        .background { DismissCatcher { panels.panel = nil } }
        .onAppear { if panels.byKey { focus = model.saves.notSaved ? 0 : 1 } }
        .onExitCommand { panels.panel = nil }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Account menu")
        .accessibilityAddTraits(.isModal)
    }

    /// The rows ↑ and ↓ step through, in order.
    private var order: [Int] {
        var o = (model.saves.notSaved ? [0] : []) + [1, 2, 3, 4] + (PrefsStore.shared.lockEnabled ? [5] : [])
        #if DOGFOOD
        o += DeveloperItems.rows
        #endif
        return o
    }

    private func move(_ by: Int) -> KeyPress.Result {
        let o = order
        let i = focus.flatMap(o.firstIndex) ?? (by > 0 ? -1 : 0)
        focus = o[(i + by + o.count) % o.count]
        return .handled
    }
}

/// A click anywhere outside a panel closes it, and goes no further (as a menu's does).
struct DismissCatcher: View {
    let close: () -> Void

    var body: some View {
        Color.clear.frame(width: 12_000, height: 12_000).contentShape(.rect).onTapGesture(perform: close)
            .accessibilityHidden(true)
    }
}

struct MenuDivider: View {
    var body: some View { Rectangle().fill(Tok.line.opacity(0.7)).frame(height: 1).padding(.vertical, 4) }
}

/// A row of a glass menu: a sage-dark glyph, the label, its keys, 40 pt tall and ink/5 on hover.
struct MenuRow: View {
    let title: String
    let symbol: String
    var tint = Tok.sageDark
    var keys: String?
    let index: Int
    var focus: FocusState<Int?>.Binding
    var closes = true
    let action: () -> Void
    @State private var hover = false

    init(_ title: String, symbol: String, tint: Color = Tok.sageDark, keys: String? = nil, index: Int, focus: FocusState<Int?>.Binding,
         closes: Bool = true, action: @escaping () -> Void) {
        (self.title, self.symbol, self.tint, self.keys, self.index, self.focus, self.closes, self.action) =
            (title, symbol, tint, keys, index, focus, closes, action)
    }

    var body: some View {
        Button(action: run) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(tint).frame(width: 18)
                Text(title).font(Typo.ui(13)).foregroundStyle(tint == Tok.sageDark ? Tok.ink : tint)
                Spacer(minLength: 8)
                if let keys { Text(keys).font(Typo.mono(10.5)).foregroundStyle(Tok.ink3) }
            }
            .padding(.horizontal, 12).frame(minHeight: 40)
            .background(Tok.ink.opacity(hover || focus.wrappedValue == index ? 0.05 : 0), in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .focused(focus, equals: index)
        .onKeyPress(.return) {
            run()
            return .handled
        }
        .onHover { hover = $0 }
        .accessibilityLabel(title)
    }

    private func run() {
        if closes { ShellPanels.shared.panel = nil }
        action()
    }
}
