import SaroKit
import SwiftUI

/// The lit door (LoginScreen.tsx): the local clock and the hour's greeting, 'Start here.', the three privacy lines
/// word for word (NFR-02) and one Begin. No account, so no sign-in: the promise lines open their proof in place.
struct WelcomeDoor: View {
    @Environment(AppModel.self) private var model
    @Environment(OnboardingFlow.self) private var flow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    @State private var page: PrivacyCopy.Promise?
    @State private var instant = false
    @FocusState private var focus: String?

    var body: some View {
        ZStack {
            if let page {
                ScrollView {
                    PromisePage(promise: page, onClose: close, onOpen: open)
                        .frame(width: 520)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 56)
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.never)
                    .transition(instant || reduceMotion ? .opacity.animation(nil) : .opacity.combined(with: .offset(y: 8)).animation(Motion.surface))
            } else {
                door.transition(.opacity.animation(instant ? nil : .easeOut(duration: 0.1)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { entered = true }
    }

    private var door: some View {
        VStack(spacing: 0) {
            Wordmark().padding(.bottom, 28).rise(entered, y: 10, delay: 0, duration: 0.4, reduce: reduceMotion)
            TimelineView(.everyMinute) { context in
                let hour = Sky.localHour(context.date)
                VStack(spacing: 0) {
                    Text("\(context.date.formatted(.dateTime.hour().minute())) · \(Greeting.eyebrow(hour: hour))")
                        .monoCaps(11, tracking: 0.12)
                        .monospacedDigit()
                        .foregroundStyle(Tok.ink2)
                        .padding(.bottom, 14)
                        .rise(entered, y: 10, delay: 0.05, duration: 0.4, reduce: reduceMotion)
                    VStack(spacing: 2) {
                        Text(Greeting.line(hour: hour)).contentTransition(.opacity)
                        Text("Start here.").font(Typo.serif(56, italic: true)).foregroundStyle(Tok.sage)
                    }
                    .font(Typo.serif(56))
                    .foregroundStyle(Tok.ink)
                    .tracking(-1.1)
                    .multilineTextAlignment(.center)
                    .animation(Motion.fade, value: Greeting.band(hour: hour))
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 10)
                    .rise(entered, y: 10, delay: 0.12, duration: 0.4, reduce: reduceMotion)
                }
            }
            Text("A few questions, then your first reflection.")
                .font(Typo.ui(15))
                .foregroundStyle(Tok.ink2)
                .padding(.bottom, 34)
                .rise(entered, y: 10, delay: 0.19, duration: 0.4, reduce: reduceMotion)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(PrivacyCopy.nfr02, id: \.self) { line in
                    Text(line).font(Typo.ui(14)).foregroundStyle(Tok.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 400, alignment: .leading)
            .padding(.bottom, 26)
            .rise(entered, y: 10, delay: 0.26, duration: 0.4, reduce: reduceMotion)
            Button { flow.go(.intro, nav: pressedByKey() ? .key : .pointer, model: model) } label: {
                Text("Begin").font(Typo.ui(14, .semibold)).frame(maxWidth: .infinity).frame(height: 46)
            }
            .buttonStyle(PrimaryStyle())
            .keyboardShortcut(.defaultAction)
            .frame(width: 400)
            .rise(entered, y: 10, delay: 0.36, duration: 0.4, reduce: reduceMotion)
            PromiseLines(focus: $focus, onOpen: open)
                .padding(.top, 18)
                .rise(entered, y: 10, delay: 0.42, duration: 0.4, reduce: reduceMotion)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
    }

    /// A keyboard open is instant, a click rises in on the surface spring; every close is instant.
    private func open(_ p: PrivacyCopy.Promise) {
        instant = pressedByKey()
        withAnimation(instant ? nil : Motion.surface) { page = p }
    }

    private func close() {
        let id = page?.id
        instant = true
        withAnimation(nil) { page = nil }
        Task {
            await Task.yield()
            focus = id
        }
    }
}

/// The logo and 'Saro' in Newsreader (Wordmark.tsx).
struct Wordmark: View {
    var body: some View {
        HStack(spacing: 9) {
            Image("Logo").resizable().scaledToFit().frame(width: 22, height: 22)
            Text("Saro").font(Typo.serif(20)).tracking(-0.2).foregroundStyle(Tok.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Saro")
    }
}

/// The three promise lines (PrivacyPromise.tsx PromiseLines): each opens its page in place.
private struct PromiseLines: View {
    var focus: FocusState<String?>.Binding
    var exclude: String?
    var leading = false
    let onOpen: (PrivacyCopy.Promise) -> Void

    var body: some View {
        VStack(alignment: leading ? .leading : .center, spacing: 0) {
            ForEach(PrivacyCopy.promises.filter { $0.id != exclude }) { p in
                Button { onOpen(p) } label: { PromiseLine(title: p.title) }
                    .buttonStyle(.plain)
                    .focused(focus, equals: p.id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(exclude == nil ? "Privacy" : "More privacy")
    }
}

private struct PromiseLine: View {
    let title: String
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title).underline(hover, color: Tok.ink3)
            Text("→").foregroundStyle(Tok.ink3).offset(x: hover ? 2 : 0).accessibilityHidden(true)
        }
        .font(Typo.ui(13))
        .foregroundStyle(hover ? Tok.ink : Tok.ink2)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .onHover { hover = $0 }
        .animation(Motion.fade, value: hover)
    }
}

/// A short page that proves one promise; Back or Esc returns to the line that opened it.
private struct PromisePage: View {
    let promise: PrivacyCopy.Promise
    let onClose: () -> Void
    let onOpen: (PrivacyCopy.Promise) -> Void
    @AccessibilityFocusState private var headingFocused: Bool
    @FocusState private var focus: String?

    var body: some View {
        let index = PrivacyCopy.promises.firstIndex(of: promise) ?? 0
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Text("←").accessibilityHidden(true)
                    Text("Back")
                }
                .font(Typo.ui(14))
                .foregroundStyle(Tok.ink2)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(.bottom, 28)
            Text("Privacy · \(index + 1) of \(PrivacyCopy.promises.count)").monoCaps(11, tracking: 0.12).foregroundStyle(Tok.ink2).padding(.bottom, 12)
            Text(promise.title)
                .font(Typo.serif(30))
                .foregroundStyle(Tok.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(promise.body, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
            }
            .font(Typo.ui(15))
            .lineSpacing(3)
            .foregroundStyle(Tok.ink2)
            .padding(.top, 16)
            Text("In the code: " + promise.proofs.joined(separator: " · "))
                .font(Typo.mono(11, .regular))
                .foregroundStyle(Tok.ink2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)
            Text("Where: \(promise.where)").font(Typo.ui(13)).foregroundStyle(Tok.ink2).padding(.top, 14)
            Divider().overlay(Tok.line).padding(.top, 30).padding(.bottom, 8)
            PromiseLines(focus: $focus, exclude: promise.id, leading: true, onOpen: onOpen)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { headingFocused = true }
    }
}

/// 'You're in.' between Begin and the first question: it settles in word by word from a blur, holds 2.5 s, and moves
/// on sooner with a click, Return, an arrow or any printable key. Blur and fade only, so Reduce Motion keeps it.
struct IntroBeat: View {
    let onNext: () -> Void
    @State private var shown = false
    @State private var done = false
    @FocusState private var focused: Bool
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        let words = ["You’re", "in."]
        HStack(spacing: 0) {
            ForEach(words.indices, id: \.self) { i in
                Text(words[i] + (i < words.count - 1 ? " " : ""))
                    .opacity(shown ? 1 : 0)
                    .blur(radius: shown ? 0 : 5)
                    .animation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.9).delay(0.2 + Double(i) * 0.12), value: shown)
            }
        }
        .font(Typo.serif(44))
        .foregroundStyle(Tok.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You’re in.")
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($headingFocused)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture(perform: advance)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.isDisjoint(with: [.command, .control, .option]),
                  [.return, .leftArrow, .rightArrow, .upArrow, .downArrow].contains(press.key) || press.characters.unicodeScalars.contains(where: { !CharacterSet.controlCharacters.contains($0) })
            else { return .ignored }
            advance()
            return .handled
        }
        .task {
            shown = true
            focused = true
            headingFocused = true
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { advance() }
        }
    }

    private func advance() {
        guard !done else { return }
        done = true
        onNext()
    }
}

/// Saro's primary button: sage, a lift and a deeper sage on hover, a press scale.
struct PrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Tok.onPrimary)
            .padding(.horizontal, 20)
            .background(hover && enabled ? Tok.sageDark : Tok.sage, in: .rect(cornerRadius: Radius.control))
            .shadow(color: Tok.sage.opacity(hover && enabled ? 0.22 : 0), radius: 10, y: 4)
            .offset(y: hover && enabled && !configuration.isPressed ? -1 : 0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(enabled ? 1 : 0.4)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(Motion.fade, value: hover)
            .onHover { hover = $0 }
    }
}

/// A quiet bordered button (Allow this reminder, Try again).
struct QuietStyle: ButtonStyle {
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.ui(13, .semibold))
            .foregroundStyle(Tok.ink)
            .padding(.horizontal, 18)
            .frame(minHeight: 40)
            .background(Tok.surfaceAlt.opacity(hover ? 0.6 : 0), in: .rect(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(hover ? Tok.ink3 : Tok.borderStrong))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(Motion.fade, value: hover)
            .onHover { hover = $0 }
    }
}

/// An underlined text link (Ask me something else, Voice only, Turn off).
struct LinkStyle: ButtonStyle {
    var size: CGFloat = 13
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.ui(size, .medium))
            .foregroundStyle(hover ? Tok.ink : Tok.ink2)
            .underline(color: hover ? Tok.ink3 : Tok.borderStrong)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Motion.fade, value: hover)
            .onHover { hover = $0 }
    }
}
