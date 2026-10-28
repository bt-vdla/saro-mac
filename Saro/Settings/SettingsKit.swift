import SwiftUI

/// A card's saves, in order (PersonalizationSheet.tsx useAutosave): the ✓ Saved tick shows only once the latest write
/// has returned, and leaves after 2.2 s; Couldn't save · Retry shows only when a write throws.
@MainActor @Observable
final class Autosave {
    enum State { case idle, saved, failed }

    private(set) var state = State.idle
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var last: (@MainActor () async throws -> Void)?

    func run(_ write: @escaping @MainActor () async throws -> Void) {
        seq += 1
        let id = seq
        state = .idle
        last = write
        let previous = queue
        queue = Task {
            await previous?.value
            do {
                try await write()
                guard id == seq else { return }
                state = .saved
                try? await Task.sleep(for: .seconds(2.2))
                if id == seq, state == .saved { state = .idle }
            } catch {
                if id == seq { state = .failed }
            }
        }
    }

    /// A write that can't fail (UserDefaults), so the tick still says it landed.
    func saved() { run {} }

    func retry() { if let last { run(last) } }
}

/// One section's card: a mono-caps label over a serif title, lifting a little on hover.
struct SettingsCard<Content: View, Aside: View>: View {
    let label: String
    let title: String
    var autosave: Autosave?
    @ViewBuilder var aside: Aside
    @ViewBuilder var content: Content
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(label: String, title: String, autosave: Autosave? = nil, @ViewBuilder aside: () -> Aside = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.label = label
        self.title = title
        self.autosave = autosave
        self.aside = aside()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).monoCaps(10.5).foregroundStyle(Tok.ink3).padding(.bottom, 6)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).font(Typo.serif(21)).foregroundStyle(Tok.ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                aside
            }
            .padding(.bottom, 18)
            content
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tok.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(hovering ? Tok.borderStrong : Tok.border, lineWidth: 1))
        .overlay(alignment: .topTrailing) { if let autosave { SaveIndicator(autosave: autosave).padding(.top, 26).padding(.trailing, 28) } }
        .elevation(hovering ? .card : .lift)
        .offset(y: hovering && !reduceMotion ? -1 : 0)
        .animation(Motion.pick(Motion.small, reduce: reduceMotion), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// One setting inside a card: a label and caption, and its control at the end of the row.
struct SettingsRow<Control: View>: View {
    let label: String
    var caption: String?
    @ViewBuilder var control: Control

    init(_ label: String, caption: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.caption = caption
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(Typo.ui(14.5, .medium)).foregroundStyle(Tok.ink)
                if let caption {
                    Text(caption).font(Typo.ui(12)).foregroundStyle(Tok.ink3).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .frame(minHeight: 56)
        .padding(.vertical, 6)
    }
}

/// The hairline between rows.
struct RowRule: View {
    var body: some View { Tok.line.frame(height: 1).accessibilityHidden(true) }
}

/// "✓ Saved" (opacity and y −3 over 0.2 s), or "Couldn't save · Retry".
struct SaveIndicator: View {
    let autosave: Autosave
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .trailing) {
            switch autosave.state {
            case .saved:
                Label("Saved", systemImage: "checkmark")
                    .labelStyle(TightLabel())
                    .font(Typo.ui(12, .medium)).foregroundStyle(Tok.sageDark)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: reduceMotion ? 0 : -3)), removal: .opacity))
            case .failed:
                HStack(spacing: 4) {
                    Text("Couldn’t save ·")
                    Button("Retry") { autosave.retry() }.buttonStyle(.settingsLink(Tok.danger))
                }
                .font(Typo.ui(12, .medium)).foregroundStyle(Tok.danger)
                .transition(.opacity)
            case .idle:
                EmptyView()
            }
        }
        .animation(Motion.easeOut(0.2), value: autosave.state)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 10.5, weight: .bold))
            configuration.title
        }
    }
}

/// A 36×20 switch: sage when on, an ink-4 outline when off. Its row shows the label, so the switch draws none, and
/// VoiceOver still hears a switch with that label. Tab reaches it and Space flips it, as a native switch.
struct SageToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { SageSwitch(configuration: configuration) }
}

private struct SageSwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let on = configuration.isOn
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? Tok.sage : .clear)
            Capsule().strokeBorder(on ? Tok.sage : Tok.ink4, lineWidth: 1)
            Circle().fill(on ? Tok.onPrimary : Tok.ink4).frame(width: 14, height: 14).padding(3)
        }
        .frame(width: 36, height: 20)
        .contentShape(.interaction, .rect.inset(by: -10))
        .contentShape(.focusEffect, .capsule)
        .onTapGesture { configuration.isOn.toggle() }
        .focusable(enabled)
        .onKeyPress(.space) {
            configuration.isOn.toggle()
            return .handled
        }
        .animation(Motion.pick(Motion.small, reduce: reduceMotion), value: on)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

extension ToggleStyle where Self == SageToggleStyle {
    static var sage: SageToggleStyle { .init() }
}

/// The quiet bordered button, the sage primary, the danger outline, and an underlined inline link.
struct SettingsButtonStyle: ButtonStyle {
    enum Kind { case quiet, primary, danger }
    let kind: Kind
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.ui(13, kind == .primary ? .semibold : .medium))
            .foregroundStyle(kind == .primary ? Tok.onPrimary : kind == .danger ? (hovering ? Tok.onPrimary : Tok.danger) : (hovering ? Tok.ink : Tok.ink2))
            .padding(.horizontal, 14).frame(minHeight: 32)
            .background {
                let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                switch kind {
                case .quiet: shape.fill(Tok.surfaceAlt).overlay(shape.strokeBorder(hovering ? Tok.borderStrong : Tok.border))
                case .primary: shape.fill(hovering ? Tok.sageDark : Tok.sage)
                case .danger: shape.fill(hovering ? Tok.danger : .clear).overlay(shape.strokeBorder(Tok.danger))
                }
            }
            .contentShape(.rect)
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(Motion.fade, value: hovering)
            .onHover { hovering = $0 && enabled }
    }
}

struct SettingsLinkStyle: ButtonStyle {
    var color = Tok.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .underline(true, color: color.opacity(configuration.isPressed ? 0.8 : 0.3))
            .contentShape(.rect.inset(by: -4))
    }
}

extension ButtonStyle where Self == SettingsButtonStyle {
    static var settingsQuiet: SettingsButtonStyle { .init(kind: .quiet) }
    static var settingsPrimary: SettingsButtonStyle { .init(kind: .primary) }
    static var settingsDanger: SettingsButtonStyle { .init(kind: .danger) }
}

extension ButtonStyle where Self == SettingsLinkStyle {
    static var settingsLink: SettingsLinkStyle { .init() }
    static func settingsLink(_ color: Color) -> SettingsLinkStyle { .init(color: color) }
}

/// A segmented choice with a sliding thumb (the web's radiogroup): arrow keys move the pick; VoiceOver reads a picker.
struct SlidingChoice<Value: Hashable, Option: View>: View {
    let label: String
    let options: [Value]
    @Binding var selection: Value
    var spoken: (Value) -> String
    @ViewBuilder var option: (Value, Bool) -> Option
    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { value in
                let on = value == selection
                option(value, on)
                    .frame(maxWidth: .infinity).padding(.vertical, 6).padding(.horizontal, 8)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Tok.surfaceAlt)
                                .elevation(.lift)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(.rect)
                    .onTapGesture { withAnimation(Motion.pick(Motion.small, reduce: reduceMotion)) { selection = value } }
            }
        }
        .padding(3)
        .background(Tok.ink.opacity(0.06), in: .rect(cornerRadius: 11, style: .continuous))
        .focusable()
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .accessibilityRepresentation {
            Picker(label, selection: $selection) { ForEach(options, id: \.self) { Text(spoken($0)).tag($0) } }
        }
    }

    /// From the keyboard, so it moves without animating (the frequency rule).
    private func step(_ by: Int) -> KeyPress.Result {
        guard let i = options.firstIndex(of: selection) else { return .ignored }
        selection = options[min(options.count - 1, max(0, i + by))]
        return .handled
    }
}
