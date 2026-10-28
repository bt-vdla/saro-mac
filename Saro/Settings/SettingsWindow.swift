import AppKit
import SaroKit
import SwiftUI

extension SettingsSection: Identifiable {
    var id: Self { self }
    var number: String { String(format: "%02d", (Self.allCases.firstIndex(of: self) ?? 0) + 1) }

    var name: String {
        switch self {
        case .you: "You"
        case .talk: "How Saro talks"
        case .rhythm: "Rhythm"
        case .appearance: "Appearance"
        case .comfort: "Comfort"
        case .knows: "What Saro knows"
        case .intelligence: "Intelligence"
        case .data: "Your data"
        }
    }
}

/// Settings (⌘,): one scrolling page on the lit ground, a numbered rail that follows the scroll, and Say it at the
/// top (PersonalizationSheet.tsx + SettingsNav.tsx). ⌘1–⌘8 jump to a section; `saro://settings/<section>` opens on one.
struct SettingsWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active = SettingsSection.you
    @State private var tops = Tops()
    @State private var viewport: CGFloat = 720
    @State private var width: CGFloat = 920
    @State private var previewHour: Double?
    @State private var previousScreen = ScreenID.canvas
    @State private var window: NSWindow?
    @State private var keys: Any?
    @FocusState private var sayIt: Bool
    @AccessibilityFocusState private var heading: SettingsSection?
    @Namespace private var rail

    /// ⌘K → Change a setting in words: Settings, with the cursor in Say it once its window is key, however cold.
    @MainActor @Observable
    final class SayItRequest {
        static let shared = SayItRequest()
        var pending = false
    }

    static func askInWords() {
        SayItRequest.shared.pending = true
        WindowActions.openSettings()
    }

    /// Where a jump lands a section's top, below the window's top edge.
    private static let mark: CGFloat = 24
    private var wide: Bool { width >= 780 }

    /// Section tops in the scroll view, updated every scroll frame without re-rendering the page.
    final class Tops {
        var y: [SettingsSection: CGFloat] = [:]
        var holdUntil = Date.distantPast
        /// A deep link's section, held at the mark while the sections above it finish loading and change height.
        var pinned: SettingsSection?
    }

    var body: some View {
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                if wide { railView(proxy).frame(width: 212).padding(.top, 92) }
                page(proxy)
            }
            .background { shortcuts(proxy) }
            .toolbar {
                if !wide {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ForEach(SettingsSection.allCases) { s in Button("\(s.number)  \(s.name)") { jump(to: s, proxy, instant: false) } }
                        } label: {
                            Label(active.name, systemImage: "list.bullet")
                        }
                        .accessibilityLabel("Sections")
                    }
                }
            }
            .onAppear {
                previousScreen = model.screen
                model.screen = .settings
                openLinkedSection(proxy)
            }
            .onChange(of: PrefsStore.shared.settingsSection) { openLinkedSection(proxy) }
            // A link that came before the window was up is followed once it is.
            .onChange(of: window) {
                openLinkedSection(proxy)
                answerSayIt()
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .frame(minWidth: 640, idealWidth: 920, minHeight: 480, idealHeight: 720)
        .background { LitGround(hour: previewHour).ignoresSafeArea() }
        .background(Tok.bg)
        .tint(Tok.sage)
        .background(WindowReader(window: $window))
        .onExitCommand { window?.performClose(nil) }
        .onAppear(perform: watchSlash)
        .onChange(of: SayItRequest.shared.pending) { answerSayIt() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { n in
            if n.object as? NSWindow === window { answerSayIt() }
        }
        .onDisappear {
            if let keys { NSEvent.removeMonitor(keys) }
            keys = nil
            previewHour = nil
            Daylight.shared.replayHour = nil
            // Unless the main window moved on meanwhile, its screen is current again once Settings closes.
            if model.screen == .settings { model.screen = previousScreen }
        }
    }

    private func page(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                SayItBar(focused: $sayIt) { section, instant in jump(to: section, proxy, instant: instant) }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(SettingsSection.allCases) { s in
                        section(s)
                            .accessibilityFocused($heading, equals: s)
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("settings")).minY } action: {
                                tops.y[s] = $0
                                if tops.pinned == s, Date.now < tops.holdUntil, abs($0 - Self.mark) > 2 { proxy.scrollTo(s, anchor: .top) }
                                spy()
                            }
                            // The last section is tall enough to scroll up to the mark, as every other one can.
                            .frame(minHeight: s == .data ? max(0, viewport - Self.mark - 72) : nil, alignment: .top)
                            // The jump target includes the gap above the card, so a jump lands the card at the mark.
                            .padding(.top, Self.mark)
                            .id(s)
                    }
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 72)
            .frame(maxWidth: .infinity)
        }
        .coordinateSpace(.named("settings"))
        .scrollContentBackground(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings").monoCaps(11, tracking: 0.12).foregroundStyle(Tok.ink3)
            Text("Settings").font(Typo.serif(34)).foregroundStyle(Tok.ink).accessibilityAddTraits(.isHeader)
            Text("Changes save as you make them. Anything you ask for in words waits for your yes.")
                .font(Typo.ui(14)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func section(_ s: SettingsSection) -> some View {
        switch s {
        case .you: YouSection()
        case .talk: TalkSection()
        case .rhythm: RhythmSection()
        case .appearance: AppearanceSection(previewHour: $previewHour)
        case .comfort: ComfortSection()
        case .knows: WhatSaroKnowsView(embedded: true)
        case .intelligence: IntelligenceSection()
        case .data: DataSection()
        }
    }

    // MARK: Rail

    private func railView(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { s in
                let on = s == active
                Button {
                    jump(to: s, proxy, instant: NSApp.currentEvent?.type == .keyDown)
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            if on { Capsule().fill(Tok.sage).matchedGeometryEffect(id: "bar", in: rail) }
                        }
                        .frame(width: 2, height: 16)
                        Text(s.number).font(Typo.mono(11)).monospacedDigit().foregroundStyle(on ? Tok.sageTeal : Tok.ink3)
                        Text(s.name).font(Typo.ui(13, on ? .medium : .regular)).foregroundStyle(on ? Tok.ink : Tok.ink2)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6).padding(.leading, 20)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(s.number), \(s.name)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(Motion.pick(Motion.small, reduce: reduceMotion), value: active)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { step(-1, proxy) }
        .onKeyPress(.downArrow) { step(1, proxy) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }

    /// ⌘1–⌘8, whether the rail shows or has folded into the toolbar menu.
    private func shortcuts(_ proxy: ScrollViewProxy) -> some View {
        ZStack {
            ForEach(Array(SettingsSection.allCases.enumerated()), id: \.offset) { i, s in
                Button(s.name) { jump(to: s, proxy, instant: true) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func step(_ by: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        let all = SettingsSection.allCases
        guard let i = all.firstIndex(of: active), all.indices.contains(i + by) else { return .ignored }
        jump(to: all[i + by], proxy, instant: true)
        return .handled
    }

    // MARK: Jumping and scroll-spy

    /// Smooth after a pointer, instant after a key or with Reduce Motion. The rail holds the section while its own
    /// scroll runs, and VoiceOver lands on the section.
    private func jump(to s: SettingsSection, _ proxy: ScrollViewProxy, instant: Bool) {
        tops.pinned = nil
        tops.holdUntil = .now.addingTimeInterval(instant || reduceMotion ? 0.1 : 0.7)
        active = s
        if instant || reduceMotion {
            proxy.scrollTo(s, anchor: .top)
        } else {
            withAnimation(.smooth(duration: 0.45)) { proxy.scrollTo(s, anchor: .top) }
        }
        heading = s
    }

    /// The last section whose top has reached the mark, so the one just jumped to is marked, however short.
    private func spy() {
        guard Date.now > tops.holdUntil else { return }
        let reached = SettingsSection.allCases.last { (tops.y[$0] ?? .infinity) <= Self.mark + 2 } ?? .you
        if reached != active { active = reached }
    }

    private func answerSayIt() {
        guard SayItRequest.shared.pending, window?.isKeyWindow == true else { return }
        SayItRequest.shared.pending = false
        sayIt = true
    }

    /// Only a page that's in a window takes the link, so one being replaced can't swallow it.
    private func openLinkedSection(_ proxy: ScrollViewProxy) {
        guard window != nil, let s = PrefsStore.shared.settingsSection else { return }
        PrefsStore.shared.settingsSection = nil
        // After the first layout, so the section has a place to scroll to.
        Task { @MainActor in
            jump(to: s, proxy, instant: true)
            tops.pinned = s
            tops.holdUntil = .now.addingTimeInterval(1.5)
            // A first layout that wasn't ready to scroll gets a second try.
            try? await Task.sleep(for: .milliseconds(250))
            if tops.pinned == s, abs((tops.y[s] ?? .infinity) - Self.mark) > 2 { proxy.scrollTo(s, anchor: .top) }
        }
    }

    /// "/" reaches Say it from anywhere in the window, unless you're typing somewhere else.
    private func watchSlash() {
        guard keys == nil else { return }
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] e in
            guard e.charactersIgnoringModifiers == "/", e.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let window, e.window === window, !(window.firstResponder is NSText) else { return e }
            sayIt = true
            return nil
        }
    }
}

/// The NSWindow a view is in, for Escape, the "/" key and links; nil again once the view leaves it.
struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView { Probe { window = $0 } }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Probe: NSView {
        let moved: (NSWindow?) -> Void

        init(_ moved: @escaping (NSWindow?) -> Void) {
            self.moved = moved
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        // After this update, not during it.
        override func viewDidMoveToWindow() {
            let window = window
            Task { @MainActor in moved(window) }
        }
    }
}
