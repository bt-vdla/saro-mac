import SaroKit
import Speech
import SwiftUI

/// 05 Comfort (ComfortSection.tsx): text size, captions, Saro's own Reduce motion and Reduce transparency over the
/// device's, sounds, haptics, and the Writing Tools opt-in. Everything takes effect at once, in every window.
struct ComfortSection: View {
    @State private var save = Autosave()
    @State private var locales: [(id: String, name: String, installed: Bool)] = []

    private var prefs: PrefsStore { PrefsStore.shared }

    var body: some View {
        SettingsCard(label: "Comfort", title: "Comfort, in one place", autosave: save) {
            SettingsRow("Text size", caption: "Every screen, on this Mac.") {
                SlidingChoice(label: "Text size", options: Prefs.textScales, selection: binding(\.textScale), spoken: ParseIntent.pct) { scale, on in
                    VStack(spacing: 3) {
                        // Each option shows its own size, fixed, so it doesn't grow with the setting itself.
                        Text("Aa").font(.custom("Newsreader16pt-Regular", fixedSize: 15 * scale)).frame(height: 24)
                        Text(ParseIntent.pct(scale)).font(.system(size: 9.5, design: .monospaced)).monospacedDigit()
                    }
                    .foregroundStyle(on ? Tok.ink : Tok.ink3)
                    .frame(minWidth: 46)
                }
                .fixedSize()
            }
            RowRule()
            // ponytail: drop the second sentence when capture's live captions merge; they read captionsAlways.
            toggle("Captions always on", "In the video and voice recorders, what you said stays on screen when you pause or Saro asks a follow-up. Live captions aren’t in this build yet, so this waits for them.",
                   \.captionsAlways)
            SettingsRow("Caption language", caption: "The language captions and transcripts listen for.") {
                Picker("Caption language", selection: binding(\.captionLocale)) {
                    Text("Follow this Mac").tag(String?.none)
                    ForEach(locales, id: \.id) { l in Text("\(l.name)\(l.installed ? "" : " · downloads when first used")").tag(Optional(l.id)) }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }
            RowRule()
            toggle("Reduce motion", "Things fade instead of moving. Your device: \(prefs.deviceReduceMotion ? "on" : "off").", \.reduceMotion)
            toggle("Reduce transparency", "Solid surfaces instead of frosted glass. Your device: \(prefs.deviceReduceTransparency ? "on" : "off").",
                   \.reduceTransparency)
            RowRule()
            toggle("Sounds", prefs.sounds ? "Saro has no sounds yet; this lets them play when it does." : "Saro has no sounds yet; this keeps them off when it does.",
                   \.sounds)
            toggle("Haptics", prefs.haptics ? "A light tap on the trackpad when a card snaps to a guide." : "No taps on the trackpad.", \.haptics)
            RowRule()
            toggle("Writing Tools", "Lets macOS Writing Tools rewrite text you select. Apple may use Private Cloud Compute, or ChatGPT if you’ve turned it on, for that text. Off by default.",
                   \.writingTools)
        }
        .task {
            let installed = Set(await SpeechTranscriber.installedLocales.map(\.identifier))
            locales = await SpeechTranscriber.supportedLocales
                .map { (id: $0.identifier, name: Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier, installed: installed.contains($0.identifier)) }
                .sorted { $0.name < $1.name }
        }
    }

    private func binding<T>(_ field: WritableKeyPath<Prefs, T>) -> Binding<T> {
        Binding(get: { prefs[dynamicMember: field] }, set: { v in
            prefs[dynamicMember: field] = v
            save.saved()
        })
    }

    private func toggle(_ label: String, _ caption: String, _ field: WritableKeyPath<Prefs, Bool>) -> some View {
        SettingsRow(label, caption: caption) {
            Toggle(label, isOn: binding(field)).toggleStyle(.sage).labelsHidden()
        }
    }
}
