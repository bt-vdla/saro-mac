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
    /// Survives closing the panel, so a half-written note is never lost to Esc.
    var draft = ""
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

    var body: some View {
        @Bindable var panel = CapturePanelController.shared
        VStack(spacing: 12) {
            Picker("Capture", selection: $panel.tab) {
                Text("Video").tag(CaptureTab.video)
                Text("Voice").tag(CaptureTab.voice)
                Text("Write").tag(CaptureTab.write)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(CaptureController.shared.hasSession(.panel))

            if panel.saved {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 30)).foregroundStyle(Tok.sage)
                    Text("Saved to Today").font(Typo.ui(14, .medium)).foregroundStyle(Tok.ink)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            } else if panel.tab == .write {
                writer
            } else {
                RecorderView(kind: panel.tab == .voice ? .voice : .moment, surface: .panel,
                             onSaved: { panel.confirmSaved() }, onClose: { panel.close() })
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(width: 400, height: 404, alignment: .top)
        .background(Tok.surface)
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
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tok.border))
            HStack {
                Text("⌘↵ SAVES TO TODAY").font(Typo.mono(10)).foregroundStyle(Tok.ink3)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .tint(Tok.sage)
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
