import AppKit
import SaroKit
import SwiftUI

/// 07 Intelligence (FR-ONB-05): whether Apple Intelligence and speech can run here, each with one honest line, and
/// what Saro does without them. The model's details sit under a disclosure.
struct IntelligenceSection: View {
    @Environment(AppModel.self) private var model
    @State private var speech: [(name: String, state: Readiness.SpeechState)] = []
    @State private var details = false

    var body: some View {
        let state = Readiness.model()
        SettingsCard(label: "Intelligence", title: "Reading, here on this Mac") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(state.isReady ? Tok.sageTeal : Tok.warning).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(state.line).font(Typo.ui(14)).foregroundStyle(Tok.ink).fixedSize(horizontal: false, vertical: true)
            }
            if let url = state.settingsURL {
                Button("Open Apple Intelligence Settings") { NSWorkspace.shared.open(url) }.buttonStyle(.settingsQuiet).padding(.top, 10)
            }
            Text("Without the model, Saro uses your own words: In your words.")
                .font(Typo.serif(16, italic: true)).foregroundStyle(Tok.ink2).padding(.top, 12).padding(.bottom, 14)
            RowRule()
            VStack(alignment: .leading, spacing: 10) {
                Text("Speech").font(Typo.ui(14.5, .medium)).foregroundStyle(Tok.ink)
                if speech.isEmpty {
                    Text("Checking speech on this Mac…").font(Typo.ui(12)).foregroundStyle(Tok.ink3)
                }
                ForEach(speech, id: \.name) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).monoCaps(10.5).foregroundStyle(Tok.ink3)
                        Text(s.state.line).font(Typo.ui(13)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 14)
            RowRule()
            DisclosureGroup(isExpanded: $details) {
                VStack(alignment: .leading, spacing: 6) {
                    detail("Model", model.ai.variant)
                    detail("Context", "\(model.ai.contextSize) tokens")
                    detail("macOS build", SaroAI.osBuild)
                    detail("Routes", "On-device only. Nothing leaves this Mac.")
                }
                .padding(.top, 8)
            } label: {
                Text("Details").font(Typo.ui(13, .medium)).foregroundStyle(Tok.ink2)
            }
            .padding(.top, 12)
        }
        .task(id: PrefsStore.shared.captionLocale) {
            var out: [(String, Readiness.SpeechState)] = [("This Mac’s language", await Readiness.speech())]
            if let id = PrefsStore.shared.captionLocale {
                out.append((Locale.current.localizedString(forIdentifier: id) ?? id, await Readiness.speech(locale: Locale(identifier: id))))
            }
            speech = out
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Typo.ui(12)).foregroundStyle(Tok.ink3).frame(width: 96, alignment: .leading)
            Text(value).font(Typo.mono(11.5)).foregroundStyle(Tok.ink2).textSelection(.enabled)
        }
    }
}
