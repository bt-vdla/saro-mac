import AppKit
import SaroKit
import SwiftUI

/// 01 You (ProfileSheet.tsx, without the account): the name Saro knows you by, where the journal lives, and the
/// way back into the welcome.
struct YouSection: View {
    @Environment(AppModel.self) private var model
    @State private var save = Autosave()
    @State private var name = ""
    @State private var called = ""
    @State private var calledMissing = false
    @State private var weight: Int64?
    @FocusState private var field: Field?

    enum Field { case name, called }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // The web's Profile page, as this section's opening.
            VStack(alignment: .leading, spacing: 4) {
                Text("Profile").monoCaps(10.5, tracking: 0.12).foregroundStyle(Tok.ink3)
                Text("Who you are.").font(Typo.serif(26)).foregroundStyle(Tok.ink).accessibilityAddTraits(.isHeader)
                Text("Your name and your corner of Saro.").font(Typo.ui(14)).foregroundStyle(Tok.ink2)
            }
            .padding(.leading, 4)
            card
        }
    }

    private var card: some View {
        SettingsCard(label: "Identity", title: "The self you carry in.", autosave: save) {
            HStack(spacing: 20) {
                Text(Names.initials(name.isEmpty ? called : name))
                    .font(Typo.serif(28)).foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(Tok.sage, in: .circle)
                    .overlay(Circle().strokeBorder(Tok.line, lineWidth: 2))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(shownName).font(Typo.serif(24)).foregroundStyle(Tok.ink).lineLimit(1)
                    if let since { Text("With Saro since \(since)").font(Typo.ui(12)).foregroundStyle(Tok.ink3) }
                }
            }
            .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 18) {
                labelled("Name") {
                    input("Your name, as you like it", text: $name, field: .name, invalid: false)
                }
                labelled("What Saro calls you", hint: calledMissing ? nil : "First name or nickname is perfect.",
                         error: calledMissing ? "Saro needs something to call you." : nil) {
                    input("A first name or nickname", text: $called, field: .called, invalid: calledMissing)
                }
            }
            .padding(.bottom, 18)

            RowRule()
            SettingsRow("Where your journal lives", caption: "No account. No sign-in. No way online.") {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(model.isDemo ? "Demo (temporary)" : (model.ledger.rootURL.path as NSString).abbreviatingWithTildeInPath)
                        .font(Typo.mono(11)).foregroundStyle(Tok.ink2).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Text(weight.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Adding up…")
                        .font(Typo.mono(11)).monospacedDigit().foregroundStyle(Tok.ink3)
                }
                .frame(maxWidth: 260, alignment: .trailing)
            }
            HStack(spacing: 8) {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.ledger.rootURL]) }
                Button("Export…") { Task { await model.exportEverything() } }
            }
            .buttonStyle(.settingsQuiet)
            .padding(.bottom, 12)

            RowRule()
            SettingsRow("Replay onboarding", caption: "Walk through the welcome again. Your journal stays exactly as it is.") {
                Button("Replay Onboarding…") {
                    Task {
                        await model.replayOnboarding()
                        WindowActions.openMain()
                    }
                }
                .buttonStyle(.settingsQuiet)
            }
            RowRule()
            SettingsRow("About Saro", caption: "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · built for this Mac, on-device only.") {
                Button("About Saro") { WindowActions.openWindow("about") }.buttonStyle(.settingsQuiet)
            }
            #if DOGFOOD
            RowRule()
            SettingsRow("The tour", caption: "Dogfood builds only.") {
                Button("Take the Tour Again") {
                    WindowActions.openMain()
                    DevMode.shared.startTour(model)
                }
                .buttonStyle(.settingsQuiet)
            }
            #endif
        }
        .task {
            sync()
            if let s = try? await model.ledger.storageSummary() { weight = s.totalBytes + s.databaseBytes + s.backupsBytes }
        }
        .onChange(of: model.profile) { if field == nil { sync() } }
        .onChange(of: field) { old, _ in if let old { commit(old) } }
    }

    private var shownName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? (called.isEmpty ? "Your name" : called) : n
    }

    /// The month of the first entry, else of the journal itself.
    private var since: String? {
        let first = model.days.last.flatMap { LocalDay.date($0.day) } ?? model.profile?.createdAt
        return first?.formatted(Date.VerbatimFormatStyle(format: "\(month: .wide) \(year: .defaultDigits)", locale: Locale(identifier: "en_US_POSIX"),
                                                         timeZone: .current, calendar: Calendar(identifier: .gregorian)))
    }

    private func sync() {
        name = model.profile?.name ?? ""
        called = model.profile?.called ?? ""
    }

    /// Return or leaving the field saves it, capped at 60 characters; an empty called name goes back to what it was.
    private func commit(_ f: Field) {
        guard let profile = model.profile else { return }
        switch f {
        case .name:
            let next = Names.cap(name)
            name = next
            guard next != (profile.name ?? "") else { return }
            save.run { try await model.updateProfile { $0.name = next.isEmpty ? nil : next } }
        case .called:
            let next = Names.cap(called)
            guard !next.isEmpty else {
                calledMissing = true
                called = profile.called ?? ""
                return
            }
            calledMissing = false
            called = next
            guard next != (profile.called ?? "") else { return }
            save.run { try await model.updateProfile { $0.called = next } }
        }
    }

    private func labelled<Content: View>(_ label: String, hint: String? = nil, error: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(Typo.ui(12, .medium)).foregroundStyle(Tok.ink2)
            content()
            if let error {
                Text(error).font(Typo.ui(12)).foregroundStyle(Tok.danger)
            } else if let hint {
                Text(hint).font(Typo.ui(12)).foregroundStyle(Tok.ink3)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func input(_ prompt: String, text: Binding<String>, field f: Field, invalid: Bool) -> some View {
        TextField(prompt, text: text, prompt: Text(prompt).italic().foregroundStyle(Tok.ink3))
            .textFieldStyle(.plain)
            .font(Typo.ui(14))
            .foregroundStyle(Tok.ink)
            .focused($field, equals: f)
            .onSubmit { commit(f) }
            .onChange(of: text.wrappedValue) { if f == .called, calledMissing, !text.wrappedValue.isEmpty { calledMissing = false } }
            .padding(.horizontal, 14).frame(height: 38)
            .background(Tok.surfaceAlt, in: .rect(cornerRadius: Radius.field, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                .strokeBorder(invalid ? Tok.danger : field == f ? Tok.sage : Tok.border, lineWidth: 1))
            .animation(Motion.fade, value: field)
            .accessibilityLabel(f == .name ? "Name" : "What Saro calls you")
    }
}
