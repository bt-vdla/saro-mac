import SaroKit
import SwiftUI

/// About you (AboutYouScreen.tsx): five short questions, one at a time, with what Saro picks up marked in the answer
/// as it's typed, then the first question, written from what they said.
struct AboutYouView: View {
    @Environment(AppModel.self) private var model
    @Environment(OnboardingFlow.self) private var flow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    Group {
                        if case .question(let q) = flow.aboutStep { QuestionView(q: q) } else { FirstQuestionView() }
                    }
                    .id(flow.aboutStep)
                    .transition(.asymmetric(insertion: .identity, removal: removal))
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, max(96, geo.size.height * 0.22))
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
        }
        .overlay(alignment: .top) { header }
        .onAppear { flow.prepareSpeech() }
    }

    /// With a pointer the old question drifts up 16 pt and fades in 180 ms; by keyboard, a 120 ms crossfade.
    private var removal: AnyTransition {
        if reduceMotion { return .opacity.animation(.easeOut(duration: 0.15)) }
        if flow.nav == .key { return .opacity.animation(Motion.easeOut(0.12)) }
        return .modifier(active: StepMotion(y: -16, blur: 0, opacity: 0), identity: StepMotion(y: 0, blur: 0, opacity: 1)).animation(Motion.easeOut(0.18))
    }

    /// ← Back (not on Q1), a faint 'saro', and Skip (Q2–Q5). Full ink: the ground's vignette darkens the corners.
    private var header: some View {
        HStack {
            if flow.aboutStep != .question(1) {
                Button { withAnimation(animation) { flow.back(pressedByKey() ? .key : .pointer) } } label: {
                    Text("← Back").font(Typo.ui(14)).foregroundStyle(Tok.ink).frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                }
                .buttonStyle(PressStyle(scale: 0.97))
                .accessibilityLabel("Back")
            }
            Spacer()
            if case .question(let q) = flow.aboutStep, q > 1 {
                Button { withAnimation(animation) { flow.commit("", nav: pressedByKey() ? .key : .pointer, model: model) } } label: {
                    Text("Skip").font(Typo.ui(14)).foregroundStyle(Tok.ink).frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                }
                .buttonStyle(PressStyle(scale: 0.97))
            }
        }
        .overlay { StepMark() }
        .padding(.horizontal, 28)
        .padding(.top, 34)
    }

    private var animation: Animation { reduceMotion ? .easeOut(duration: 0.15) : flow.nav == .key ? Motion.easeOut(0.12) : Motion.surface }
}

private struct Copy {
    let lead: String, em: String, placeholder: String

    static let all: [Int: Copy] = [
        1: Copy(lead: "What should I call ", em: "you?", placeholder: "your name"),
        2: Copy(lead: "What’s taking up the most room in your head ", em: "lately?", placeholder: "The launch. My sister. Sleep…"),
        3: Copy(lead: "When does your day finally go ", em: "quiet?", placeholder: "Late, usually. After the kids are down…"),
        4: Copy(lead: "What do you want more of, and less ", em: "of?", placeholder: "More sleep, less rehearsing conversations…"),
        5: Copy(lead: "How should I talk to ", em: "you?", placeholder: "Gently. Or straight to it."),
    ]
}

/// The question's serif heading, its last word in italic sage.
private func questionText(_ lead: String, _ em: String) -> Text {
    Text("\(lead)\(Text(em).font(Typo.serif(56, italic: true)).foregroundStyle(Tok.sage))").font(Typo.serif(56))
}

/// One question: its heading rises on the surface spring, and its field and what Saro heard follow 60 ms later.
private struct QuestionView: View {
    let q: Int
    @Environment(AppModel.self) private var model
    @Environment(OnboardingFlow.self) private var flow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var caret: Int?
    @State private var composeFrom: Int?
    @State private var frozen: [Pick] = []
    @State private var settle: Task<Void, Never>?
    @State private var idle = false
    @State private var announced = 0

    private var copy: Copy { Copy.all[q]! }

    /// What to mark while someone types: a pick touching the caret waits for 400 ms of idle (so "Ma" doesn't light up
    /// on the way to "Maya"), and nothing re-extracts during composition.
    private func shown() -> [Pick] {
        if let composeFrom { return frozen.filter { $0.end <= composeFrom } }
        let all = Onboarding.extract(answer: flow.text, question: q, knownName: q == 1 ? "" : flow.name)
        guard let caret else { return all }
        return all.filter { caret < $0.start || caret > $0.end }
    }

    var body: some View {
        let shown = shown()
        let marks = shown.filter { !flow.starter.dropped.contains($0.dropKey) }
        let empty = flow.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(q) / 5").monoCaps(11, tracking: 0.12).foregroundStyle(Tok.ink2).padding(.bottom, 16)
                if q == 2, !flow.name.isEmpty {
                    Text("Good to meet you, \(flow.name).").font(Typo.serif(20, italic: true)).foregroundStyle(Tok.ink2).padding(.bottom, 12)
                }
                questionText(copy.lead, copy.em)
                    .foregroundStyle(Tok.ink)
                    .tracking(-1.6)
                    .lineSpacing(-4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 40)
            }
            .appear(appeared, y: 20, animation: Motion.surface, nav: flow.nav, reduce: reduceMotion)

            VStack(alignment: .leading, spacing: 0) {
                field(marks: marks, empty: empty)
                Text(q == 1 ? "Return to continue" : "Return to continue · Shift-Return new line")
                    .monoCaps(10.5)
                    .foregroundStyle(Tok.ink2)
                    .padding(.top, 16)
                    .accessibilityHidden(true)
                if !shown.isEmpty { SaroHeard(picks: shown, dropped: flow.starter.dropped) { flow.toggle($0, model: model) }.padding(.top, 20) }
                if q == 5, idle, !marks.contains(where: { $0.kind == .tone }) {
                    ToneChips { word in
                        let t = flow.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? word : "\(flow.text.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)) \(word.lowercased())"
                        flow.text = String(t.utf16.count <= OnboardingFlow.maxAnswer ? t : String(t.prefix(OnboardingFlow.maxAnswer)))
                    }
                    .padding(.top, 20)
                    .transition(.opacity.animation(Motion.easeOut(0.2)))
                }
            }
            .appear(appeared, y: 20, animation: Motion.small.delay(0.06), nav: flow.nav, reduce: reduceMotion)
        }
        .onAppear { appeared = true }
        // Q5: if nothing has set a tone after 1.5 s idle, offer four.
        .task(id: flow.text) {
            idle = false
            guard q == 5 else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { withAnimation(Motion.easeOut(0.2)) { idle = true } }
        }
        // "Saro picked up 3 things", once typing pauses for a second and only when the count changed.
        .task(id: "\(flow.text)|\(marks.count)") {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, marks.count != announced else { return }
            announced = marks.count
            if !marks.isEmpty { AccessibilityNotification.Announcement("Saro picked up \(marks.count) thing\(marks.count == 1 ? "" : "s")").post() }
        }
    }

    private func field(marks: [Pick], empty: Bool) -> some View {
        @Bindable var flow = flow
        return ZStack(alignment: .bottomTrailing) {
            AnswerField(text: $flow.text, marks: marks, maxLength: q == 1 ? OnboardingFlow.maxName : OnboardingFlow.maxAnswer, singleLine: q == 1,
                        label: copy.lead + copy.em,
                        onCommit: { commit(.key) }, onBack: { if q > 1 { withAnimation(Motion.easeOut(0.12)) { flow.back(.key) } } },
                        onEdit: noteInput, onComposing: composing)
                .padding(.trailing, 52)
                .padding(.bottom, 10)
                .overlay(alignment: .topLeading) {
                    if empty, composeFrom == nil {
                        Text(copy.placeholder).font(Typo.ui(28)).tracking(-0.28).foregroundStyle(Tok.ink3).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            Button { commit(pressedByKey() ? .key : .pointer) } label: {
                ArrowMark().frame(width: 44, height: 44, alignment: .trailing).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(q == 1 && empty)
            .opacity(empty ? 0.4 : 1)
            .animation(Motion.easeOut(0.4), value: empty)
            .accessibilityLabel(empty && q > 1 ? "Skip this question" : "Continue")
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Tok.borderStrong).frame(height: 1).accessibilityHidden(true) }
    }

    private func commit(_ nav: OnboardingFlow.Nav) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : nav == .key ? Motion.easeOut(0.12) : Motion.surface) {
            flow.commit(flow.text, nav: nav, model: model)
        }
    }

    private func noteInput(_ at: Int) {
        caret = at
        settle?.cancel()
        settle = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { caret = nil }
        }
    }

    private func composing(_ from: Int?) {
        if from != nil, composeFrom == nil { frozen = shown() }
        composeFrom = from
    }
}

private struct ArrowMark: View {
    @State private var hover = false

    var body: some View {
        Text("→").font(.system(size: 20)).foregroundStyle(Tok.sage)
            .offset(x: hover ? 4 : 0)
            .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.35), value: hover)
            .onHover { hover = $0 }
    }
}

/// 'Saro heard': each pick as a toggle. A pick left out loses its underline in the answer.
private struct SaroHeard: View {
    let picks: [Pick]
    let dropped: Set<String>
    let toggle: (Pick) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saro heard").monoCaps(11, tracking: 0.12).foregroundStyle(Tok.ink2)
            Flow(spacing: 16, lineSpacing: 0) {
                ForEach(picks, id: \.self) { p in
                    let off = dropped.contains(p.dropKey)
                    let word = Onboarding.word(p.kind)
                    Button { toggle(p) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(chipText(p, off: off)).font(Typo.ui(15)).foregroundStyle(off ? Tok.ink2 : Tok.ink)
                            Text(word).font(Typo.mono(11, .regular)).foregroundStyle(Tok.ink2)
                        }
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(PressStyle(scale: 0.97))
                    .accessibilityLabel(off ? "\(p.text), \(word), left out. Press to keep." : "\(p.text), \(word). Press to leave out.")
                    .accessibilityAddTraits(.isToggle)
                    .accessibilityValue(off ? "Left out" : "Kept")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What Saro picked up")
    }

    private func chipText(_ p: Pick, off: Bool) -> AttributedString {
        var s = AttributedString(p.text)
        if off { s.strikethroughStyle = Text.LineStyle(pattern: .solid, color: Tok.ink3) } else { PickStyle(p.kind).apply(to: &s[s.startIndex..<s.endIndex], wash: false) }
        return s
    }
}

/// Q5's four tones, offered after a pause with no tone said.
private struct ToneChips: View {
    let add: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(["Gently", "Plainly", "Straight", "Slowly"], id: \.self) { word in
                Button { add(word) } label: { ToneChip(word: word) }.buttonStyle(PressStyle(radius: 999, scale: 0.97))
            }
        }
    }
}

private struct ToneChip: View {
    let word: String
    @State private var hover = false

    var body: some View {
        Text(word).font(Typo.ui(15)).foregroundStyle(hover ? Tok.ink : Tok.ink2)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(hover ? Tok.voice : Tok.line))
            .contentShape(.rect(cornerRadius: 22))
            .onHover { hover = $0 }
            .animation(Motion.fade, value: hover)
    }
}

/// 'Your first question': the first reflection question, written from what they said, with their own words set in
/// sans with their underline. A held answer gets no personal prompt: the SafetyCard instead.
private struct FirstQuestionView: View {
    @Environment(AppModel.self) private var model
    @Environment(OnboardingFlow.self) private var flow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index: Int?
    @State private var appeared = false
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if flow.prompt != .held {
                Text("Your first question").monoCaps(11, tracking: 0.12).foregroundStyle(Tok.ink2).padding(.bottom, 16)
                    .appear(appeared, y: 20, animation: Motion.surface, nav: flow.nav, reduce: reduceMotion)
            }
            switch flow.prompt {
            case .waiting:
                HStack(spacing: 10) {
                    BreathingDot()
                    Text("Checking your answers here on this Mac…").font(Typo.ui(15)).foregroundStyle(Tok.ink2)
                }
                .frame(minHeight: 120, alignment: .topLeading)
                .accessibilityElement(children: .combine)
            case .held:
                held
            case .ready(let candidates):
                ready(candidates)
            }
        }
        .background {
            Button("Back to the last question") { withAnimation(Motion.easeOut(0.12)) { flow.back(.key) } }
                .keyboardShortcut(.leftArrow, modifiers: .option)
                .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
        .onAppear { appeared = true }
        .animation(Motion.fade, value: flow.prompt)
    }

    private var held: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("You don’t have to carry this alone.")
                .font(Typo.serif(40)).foregroundStyle(Tok.ink).tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
            Text("These lines are free and confidential, and someone will listen.")
                .font(Typo.ui(15)).foregroundStyle(Tok.ink2).padding(.top, 12).padding(.bottom, 20)
            SafetyCardView(compact: true).frame(maxWidth: 440)
            Button {
                guard !heldKey() else { return }
                flow.accept(nil, model: model)
            } label: { Text("Continue").font(Typo.ui(14, .semibold)).frame(height: 44) }
                .buttonStyle(PrimaryStyle())
                .returnPresses()
                .padding(.top, 24)
        }
        .appear(appeared, y: 20, animation: Motion.small.delay(0.06), nav: flow.nav, reduce: reduceMotion)
        .onAppear { headingFocused = true }
    }

    private func ready(_ candidates: [FirstPrompt.Candidate]) -> some View {
        let i = (index ?? candidates.firstIndex { $0.text == flow.starter.firstPrompt } ?? 0) % candidates.count
        let current = candidates[i]
        return VStack(alignment: .leading, spacing: 0) {
            Text(attributed(current))
                .foregroundStyle(Tok.ink)
                .tracking(-1.6)
                .lineSpacing(-4)
                .fixedSize(horizontal: false, vertical: true)
                .id(i)
                .transition(.opacity.animation(reduceMotion ? nil : Motion.easeOut(0.16)))
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
                .padding(.bottom, 40)
                .appear(appeared, y: 20, animation: Motion.surface, nav: flow.nav, reduce: reduceMotion)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 24) {
                    Button {
                        guard !heldKey() else { return }
                        flow.accept(current.text, model: model)
                    } label: {
                        HStack(spacing: 8) {
                            Text("Answer it")
                            Text("→").accessibilityHidden(true)
                        }
                        .font(Typo.ui(14, .semibold))
                        .frame(height: 44)
                    }
                    .buttonStyle(PrimaryStyle())
                    .returnPresses()
                    if candidates.count > 1 {
                        Button("Ask me something else") { withAnimation(reduceMotion ? nil : Motion.easeOut(0.16)) { index = i + 1 } }
                            .buttonStyle(LinkStyle())
                    }
                    // A caution hit with Apple Intelligence off: the question doesn't read it, and someone can listen.
                    if flow.caution {
                        Button("Talk to someone") { model.safetyCardRequested = true }.buttonStyle(LinkStyle())
                    }
                }
                Text("Return to answer it").monoCaps(10.5).foregroundStyle(Tok.ink2).accessibilityHidden(true)
            }
            .appear(appeared, y: 20, animation: Motion.small.delay(0.06), nav: flow.nav, reduce: reduceMotion)
        }
        .onAppear { headingFocused = true }
        .announces(index == nil ? "" : current.text)
    }

    private func attributed(_ c: FirstPrompt.Candidate) -> AttributedString {
        var s = AttributedString(c.text)
        s.font = Typo.serif(56)
        if let slot = c.slot, let r = Range(NSRange(location: slot.start, length: slot.end - slot.start), in: c.text),
           let lower = AttributedString.Index(r.lowerBound, within: s), let upper = AttributedString.Index(r.upperBound, within: s) {
            s[lower..<upper].font = Typo.ui(50)
            PickStyle(slot.kind).apply(to: &s[lower..<upper])
        }
        return s
    }
}

private struct BreathingDot: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle().fill(Tok.sage).frame(width: 8, height: 8)
            .opacity(on ? 0.5 : 1).scaleEffect(on && !reduceMotion ? 0.8 : 1)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
            .accessibilityHidden(true)
    }
}

extension View {
    /// A question's arrival: by pointer it rises `y` on `animation`; by keyboard a 120 ms crossfade; Reduce Motion fades.
    func appear(_ shown: Bool, y: CGFloat, animation: Animation, nav: OnboardingFlow.Nav, reduce: Bool) -> some View {
        let pointer = nav == .pointer && !reduce
        return opacity(shown ? 1 : 0)
            .offset(y: shown || !pointer ? 0 : y)
            .animation(pointer ? animation : .easeOut(duration: reduce ? 0.15 : 0.12), value: shown)
    }
}

/// Lays children in rows, wrapping at the proposed width.
struct Flow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        rows(proposal.width ?? .infinity, subviews).reduce(CGSize.zero) { size, row in
            CGSize(width: max(size.width, row.width), height: size.height + row.height + (size.height > 0 ? lineSpacing : 0))
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func rows(_ width: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var out: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if let last = out.last, last.width + spacing + size.width <= width {
                out[out.count - 1] = (last.items + [i], last.width + spacing + size.width, max(last.height, size.height))
            } else {
                out.append(([i], min(size.width, width), size.height))
            }
        }
        return out
    }
}
