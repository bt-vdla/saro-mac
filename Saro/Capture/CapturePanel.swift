import AppKit
import SaroKit
import SwiftUI

enum CaptureTab: String, CaseIterable {
    case video, voice, write
}

/// The floating capture panel (⌃⌘J and the menu bar): a moment, a voice note or a quick note, always into today.
@Observable @MainActor
final class CapturePanelController {
    static let shared = CapturePanelController()

    var tab: CaptureTab = .video
    /// Survives Esc, a quit and a crash, so a half-written note is never lost. Saving clears it.
    var draft = UserDefaults.standard.string(forKey: "captureDraft") ?? "" {
        didSet { UserDefaults.standard.set(draft, forKey: "captureDraft") }
    }
    private(set) var saved = false
    @ObservationIgnored private var panel: CapturePanel?
    @ObservationIgnored private var model: AppModel?

    private init() {}

    /// Call once at launch: keeps the model for the panel and registers ⌃⌘J.
    func install(_ model: AppModel) {
        self.model = model
        HotKey.register { CapturePanelController.shared.hotKeyPressed() }
    }

    func show(tab: CaptureTab) {
        guard let model else { return }
        let panel = panel ?? makePanel()
        if !panel.isVisible {
            saved = false
            let host = NSHostingView(rootView: CapturePanelView().environment(model))
            host.safeAreaRegions = []
            panel.contentView = host
        }
        if !CaptureController.shared.hasSession(.panel) { self.tab = tab }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        CaptureController.shared.finish(.panel)
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    /// Esc, or ⌃⌘J while the panel is key: close, unless a recording is under way.
    func dismiss() {
        if !CaptureController.shared.hasSession(.panel) { close() }
    }

    func confirmSaved() {
        saved = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if saved { close() }
        }
    }

    private func hotKeyPressed() {
        if panel?.isKeyWindow == true { dismiss() } else { show(tab: tab) }
    }

    private func makePanel() -> CapturePanel {
        let p = CapturePanel()
        p.center()
        p.setFrameAutosaveName("SaroCapturePanel")
        panel = p
        return p
    }
}

/// Non-activating, so capturing doesn't pull you out of the app you're in; it still becomes key for typing.
final class CapturePanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 404),
                   styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: true)
        title = "Capture to Today"
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }

    /// Esc closes from anywhere in the panel, including the text editor (which would otherwise offer completions).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            CapturePanelController.shared.dismiss()
        } else {
            super.sendEvent(event)
        }
    }
}

struct CapturePanelView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var writing: Bool
    @Namespace private var tabs

    var body: some View {
        @Bindable var panel = CapturePanelController.shared
        VStack(spacing: 12) {
            tabBar
            if panel.saved {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Tok.onPrimary)
                        .frame(width: 28, height: 28)
                        .background(Tok.sage, in: .circle)
                    Text("Saved to today.").font(Typo.serif(17)).foregroundStyle(Tok.ink)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if panel.tab == .write {
                writer
            } else {
                RecorderView(kind: panel.tab == .voice ? .voice : .moment, surface: .panel,
                             onSaved: { panel.confirmSaved() }, onClose: { panel.close() })
            }
        }
        .animation(CaptureMotion.small, value: panel.saved)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(width: 400, height: 404, alignment: .top)
        .background(Tok.surface)
    }

    /// Moment, Voice, Write: a capsule track whose selected chip slides on the small spring.
    private var tabBar: some View {
        let panel = CapturePanelController.shared
        let locked = CaptureController.shared.hasSession(.panel)
        return HStack(spacing: 2) {
            ForEach(CaptureTab.allCases, id: \.self) { tab in
                let on = panel.tab == tab
                Button { withAnimation(CaptureMotion.small) { panel.tab = tab } } label: {
                    Label(tab.title, systemImage: tab.icon)
                        .font(Typo.ui(13, .medium))
                        .foregroundStyle(on ? Tok.ink : Tok.ink2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background {
                            if on {
                                Capsule().fill(Tok.surfaceAlt)
                                    .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "tab", in: tabs)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Tok.bg, in: .capsule)
        .overlay(Capsule().strokeBorder(Tok.border))
        .disabled(locked)
        .opacity(locked ? 0.5 : 1)
    }

    private var writer: some View {
        @Bindable var panel = CapturePanelController.shared
        let empty = panel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $panel.draft)
                .font(Typo.ui(14))
                .foregroundStyle(Tok.ink)
                .scrollContentBackground(.hidden)
                .writingToolsBehavior(.disabled)
                .focused($writing)
                .padding(10)
                .background(Tok.surfaceAlt, in: .rect(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if panel.draft.isEmpty {
                        Text("Write anything. It goes to Today.")
                            .font(Typo.ui(14))
                            .foregroundStyle(Tok.ink3)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(writing ? Tok.sageSoft : Tok.border))
                .animation(CaptureMotion.out(0.16), value: writing)
            HStack {
                Text("⌘↵ SAVES TO TODAY").font(Typo.mono(10.5)).tracking(1.15).foregroundStyle(Tok.ink3)
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(CaptureButtonStyle.primary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(empty)
            }
        }
        .onAppear { writing = true }
    }

    private func save() {
        let body = CapturePanelController.shared.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        Task {
            guard let entry = await model.newWriting(body: body, day: LocalDay.today()) else { return }
            model.process(entry.id)
            CapturePanelController.shared.draft = ""
            CapturePanelController.shared.confirmSaved()
        }
    }
}

private extension CaptureTab {
    var title: String {
        switch self {
        case .video: "Moment"
        case .voice: "Voice"
        case .write: "Write"
        }
    }

    var icon: String {
        switch self {
        case .video: "video.fill"
        case .voice: "waveform"
        case .write: "square.and.pencil"
        }
    }
}
