import AppKit
import SaroKit
import SwiftUI

/// "Say it, and it's set" (SayItBar.tsx): ask for a change in words, see exactly what would change, and nothing moves
/// until Apply. ↵ proposes, ⌘↵ applies, Esc clears the proposal and then the text; Undo stays for 8 s and on ⌘Z.
struct SayItBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var focused: FocusState<Bool>.Binding
    /// Opens a section: Your data for delete and export, What Saro knows for forget. True when from a key.
    let openSection: (SettingsSection, Bool) -> Void

    enum Result: Equatable {
        case changes([ParseIntent.Change], note: String?, proposed: SettingsValues, checked: Set<ParseIntent.Key>)
        case none
        /// The on-device model is reading words the rules didn't match.
        case reading
        case needsYou(SettingsSection)
        case already(String)
        case failed
        case applied(keys: [ParseIntent.Key], before: SettingsValues)
    }

    struct Shown: Equatable {
        var result: Result
        /// A new id for every result, so a new answer replaces the last rather than morphing it.
        var id: Int
        var instant: Bool
        /// The words it answers; typing anything else drops it.
        var words = ""
    }

    #if DOGFOOD
    /// Snapshots only: words to propose as the bar appears.
    static var propose: String?
    #endif

    @State private var text = ""
    @State private var shown: Shown?
    @State private var busy = false
    @State private var seq = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            ZStack(alignment: .topLeading) {
                if let shown {
                    card(shown.result)
                        .id(shown.id)
                        .transition(shown.instant ? .identity : reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                }
            }
            .animation(shown?.instant == true ? nil : Motion.pick(Motion.small, reduce: reduceMotion), value: shown)
        }
        .onKeyPress(.escape) {
            if shown != nil { cancel(); return .handled }
            if !text.isEmpty { text = ""; return .handled }
            return .ignored
        }
        #if DOGFOOD
        .onAppear {
            guard let q = Self.propose else { return }
            Self.propose = nil
            text = q
            run(q, instant: true)
        }
        #endif
        .onChange(of: text) {
            // A proposal belongs to the words that made it; Undo stays until it times out.
            guard let s = shown, s.words != text else { return }
            if case .applied = s.result { return }
            shown = nil
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.bubble").font(.system(size: 13)).foregroundStyle(Tok.ink3).accessibilityHidden(true)
            TextField("Change a setting in your own words", text: $text, prompt: Text("Tell Saro what to change, like “remind me later”").foregroundStyle(Tok.ink3))
                .textFieldStyle(.plain)
                .font(Typo.ui(15))
                .foregroundStyle(Tok.ink)
                .focused(focused)
                .autocorrectionDisabled()
                .onSubmit { if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { run(text, instant: true) } }
            Text("↵").font(Typo.mono(12)).foregroundStyle(Tok.ink3).accessibilityHidden(true)
            Text("/").font(Typo.mono(10.5)).foregroundStyle(Tok.ink4)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Tok.border))
                .help("Press / to type here")
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16).frame(height: 48)
        .background(Tok.surfaceAlt, in: .rect(cornerRadius: Radius.field, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(focused.wrappedValue ? Tok.sage : Tok.border, lineWidth: 1))
        .animation(Motion.fade, value: focused.wrappedValue)
    }

    // MARK: Results

    @ViewBuilder
    private func card(_ r: Result) -> some View {
        switch r {
        case .changes(let changes, let note, _, let checked):
            proposal(changes, note: note, checked: checked)
        case .none:
            VStack(alignment: .leading, spacing: 10) {
                Text("I couldn’t match that to a setting.").font(Typo.ui(14)).foregroundStyle(Tok.ink2)
                HStack(spacing: 8) {
                    ForEach(ParseIntent.examples, id: \.self) { example in
                        Button(example) {
                            text = example
                            run(example, instant: NSApp.currentEvent?.type == .keyDown)
                            focused.wrappedValue = true
                        }
                        .buttonStyle(Chip())
                    }
                }
            }
            .padding(.top, 12)
        case .needsYou(let section):
            HStack(spacing: 4) {
                Text("That one needs you.")
                Button("\(section.name) →") { openSection(section, NSApp.currentEvent?.type == .keyDown) }.buttonStyle(.settingsLink)
            }
            .font(Typo.ui(14)).foregroundStyle(Tok.ink2).padding(.top, 12)
        case .already(let message):
            Text(message).font(Typo.ui(14)).foregroundStyle(Tok.ink2).padding(.top, 12).fixedSize(horizontal: false, vertical: true)
        case .reading:
            Text("Reading that on this Mac…").font(Typo.ui(14)).foregroundStyle(Tok.ink3).padding(.top, 12)
        case .failed:
            Text("Something didn’t change. Try again.").font(Typo.ui(14)).foregroundStyle(Tok.danger).padding(.top, 12)
        case .applied(let keys, let before):
            HStack(spacing: 4) {
                Text("Changed \(plural(keys.count, "setting", "settings")) ·")
                Button("Undo") { Task { await undo(keys, before) } }.buttonStyle(.settingsLink)
            }
            .font(Typo.ui(14)).foregroundStyle(Tok.ink2).padding(.top, 12)
            .task(id: shown?.id) {
                try? await Task.sleep(for: .seconds(8))
                if case .applied = shown?.result { shown = nil }
            }
        }
    }

    private func proposal(_ changes: [ParseIntent.Change], note: String?, checked: Set<ParseIntent.Key>) -> some View {
        let count = changes.filter { checked.contains($0.key) }.count
        return VStack(alignment: .leading, spacing: 0) {
            Text("Saro will change \(plural(changes.count, "thing", "things"))").font(Typo.serif(20)).foregroundStyle(Tok.ink)
                .accessibilityAddTraits(.isHeader)
            if let note { Text(note).font(Typo.ui(12)).foregroundStyle(Tok.ink3).padding(.top, 4).fixedSize(horizontal: false, vertical: true) }
            VStack(spacing: 0) {
                ForEach(Array(changes.enumerated()), id: \.element.key) { i, change in
                    if i > 0 { RowRule() }
                    row(change, on: checked.contains(change.key))
                }
            }
            .padding(.top, 8)
            HStack(spacing: 8) {
                Button("Apply \(count)") { Task { await apply(instant: NSApp.currentEvent?.type == .keyDown) } }
                    .buttonStyle(.settingsPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(count == 0 || busy)
                    .accessibilityLabel("Apply \(plural(count, "change", "changes"))")
                Button("Cancel") { cancel() }.buttonStyle(.settingsQuiet)
                Spacer()
                Text("⌘↵ apply · esc cancel").font(Typo.mono(11)).foregroundStyle(Tok.ink3).accessibilityHidden(true)
            }
            .padding(.top, 14)
        }
        .padding(20)
        .background(Tok.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Tok.borderStrong))
        .elevation(.card)
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Proposed changes")
    }

    private func row(_ change: ParseIntent.Change, on: Bool) -> some View {
        Toggle(isOn: Binding(get: { on }, set: { toggle(change.key, $0) })) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.label).font(Typo.ui(13, .semibold)).foregroundStyle(Tok.ink)
                    Text(change.why).font(Typo.ui(12)).foregroundStyle(Tok.ink3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    Text(change.from).strikethrough(color: Tok.ink3.opacity(0.6)).foregroundStyle(Tok.ink3)
                    Text(" → ").foregroundStyle(Tok.ink3)
                    Text(change.to).foregroundStyle(Tok.ink)
                }
                .font(Typo.mono(11.5)).monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 10)
        .opacity(on ? 1 : 0.55)
        .animation(Motion.fade, value: on)
        .accessibilityLabel("\(change.label), from \(change.from) to \(change.to). \(change.why)")
    }

    // MARK: Actions

    private func show(_ result: Result?, instant: Bool) {
        seq += 1
        shown = result.map { Shown(result: $0, id: seq, instant: instant, words: text) }
        if let result { AccessibilityNotification.Announcement(spoken(result)).post() }
    }

    private func run(_ value: String, instant: Bool) {
        let rules = ParseIntent.parse(value, current: model.settingsValues)
        guard rules == .none, Readiness.model().isReady else { return present(rules, value, instant: instant) }
        // The rules matched nothing: the on-device model maps it to the same closed list, and it's still only a proposal.
        show(.reading, instant: instant)
        Task {
            let (result, run) = await model.ai.parseSetting(value, current: model.settingsValues)
            if let run { try? await model.ledger.insertRun(run) }
            guard case .reading? = shown?.result else { return }
            present(result, value, instant: instant)
        }
    }

    private func present(_ result: ParseIntent.Result, _ value: String, instant: Bool) {
        switch result {
        case .changes(let changes, let note, let proposed):
            show(.changes(changes, note: note, proposed: proposed, checked: Set(changes.map(\.key))), instant: instant)
        case .none: show(Result.none, instant: instant)
        case .needsYou: show(.needsYou(value.lowercased().contains("forget") ? .knows : .data), instant: instant)
        case .alreadySet(let message): show(.already(message), instant: instant)
        }
    }

    private func toggle(_ key: ParseIntent.Key, _ on: Bool) {
        guard var s = shown, case .changes(let c, let n, let p, var checked) = s.result else { return }
        if on { checked.insert(key) } else { checked.remove(key) }
        s.result = .changes(c, note: n, proposed: p, checked: checked)
        s.instant = true
        shown = s
    }

    private func cancel() {
        show(nil, instant: true)
        focused.wrappedValue = true
    }

    /// Applies the checked changes in order; a step that fails rolls back every step already applied.
    private func apply(instant: Bool) async {
        guard !busy, case .changes(let changes, _, let proposed, let checked)? = shown?.result else { return }
        let keys = changes.map(\.key).filter(checked.contains)
        guard !keys.isEmpty else { return }
        busy = true
        defer { busy = false; focused.wrappedValue = true }
        let before = model.settingsValues
        var done: [ParseIntent.Key] = []
        do {
            for key in keys {
                try await model.write(key, from: proposed)
                done.append(key)
            }
        } catch {
            for key in done.reversed() { try? await model.write(key, from: before) }
            return show(.failed, instant: instant)
        }
        text = ""
        show(.applied(keys: done, before: before), instant: instant)
        let id = seq
        undoManager?.registerUndo(withTarget: model) { [done, before] model in
            Task { @MainActor in
                for key in done.reversed() { try? await model.write(key, from: before) }
                // ⌘Z did what the banner's Undo would, so the banner goes too.
                if shown?.id == id { shown = nil }
            }
        }
        undoManager?.setActionName("Change \(plural(done.count, "Setting", "Settings"))")
    }

    private func undo(_ keys: [ParseIntent.Key], _ before: SettingsValues) async {
        for key in keys.reversed() { try? await model.write(key, from: before) }
        undoManager?.removeAllActions(withTarget: model)
        show(nil, instant: true)
        focused.wrappedValue = true
    }

    private func spoken(_ r: Result) -> String {
        switch r {
        case .changes(let changes, _, _, _):
            "Saro will change \(plural(changes.count, "thing", "things")): \(changes.map { "\($0.label), \($0.from) to \($0.to)" }.joined(separator: "; "))."
        case .none: "I couldn’t match that to a setting."
        case .needsYou(let s): "That one needs you, in \(s.name)."
        case .already(let m): m
        case .reading: "Reading that on this Mac."
        case .failed: "Something didn’t change. Try again."
        case .applied(let keys, _): "Changed \(plural(keys.count, "setting", "settings")). Undo is there for 8 seconds."
        }
    }

    private func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
}

/// A rounded example chip.
struct Chip: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.ui(13)).foregroundStyle(hovering ? Tok.ink : Tok.ink2)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Tok.surfaceAlt, in: .capsule)
            .overlay(Capsule().strokeBorder(hovering ? Tok.borderStrong : Tok.border))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}
