import SwiftUI

/// The bottom dock (OnboardingProgress.tsx): three dots and chevrons. The active dot is a 16 pt sage pill whose
/// leading and trailing edges travel on different springs, so it stretches toward the next dot and then settles.
/// Its height is reserved under the step, so it never covers what the step shows.
struct ProgressDock: View {
    let flow: OnboardingFlow
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let titles = ["About you", "First week", "Light"]
    private static let slot: CGFloat = 22

    var body: some View {
        let active = flow.step.dot ?? 0
        let reached = flow.furthest.dot ?? 0
        HStack(spacing: 0) {
            chevron("Previous step", symbol: "chevron.left", disabled: active <= 0) { flow.previous(nav, model: model) }
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Self.titles.indices, id: \.self) { i in dot(i, active: active, reached: reached) }
                }
                Pill(index: active, slot: Self.slot, reduceMotion: reduceMotion)
            }
            chevron("Next step", symbol: "chevron.right", disabled: active >= Self.titles.count - 1 || active + 1 > reached) {
                flow.next(nav, model: model)
            }
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Onboarding steps")
    }

    private var nav: OnboardingFlow.Nav { pressedByKey() ? .key : .pointer }

    private func dot(_ i: Int, active: Int, reached: Int) -> some View {
        let label = "Step \(i + 1) of \(Self.titles.count): \(Self.titles[i])"
        let fill = i == active ? Color.clear : i < active ? Tok.sage.opacity(0.4) : i <= reached ? Tok.ink4.opacity(0.7) : Tok.ink4.opacity(0.35)
        return Button {
            flow.go([.about, .firstWeek, .findLight][i], nav: nav, model: model)
        } label: {
            DotMark(fill: fill, grows: i != active && i <= reached)
                .frame(width: Self.slot, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(i == active || i > reached)
        .accessibilityLabel(label)
        .accessibilityAddTraits(i == active ? .isSelected : [])
    }

    private func chevron(_ label: String, symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ChevronMark(symbol: symbol, leading: symbol == "chevron.left")
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.2 : 1)
        .animation(Motion.easeOut(0.4), value: disabled)
        .accessibilityLabel(label)
    }
}

private struct DotMark: View {
    let fill: Color
    let grows: Bool
    @State private var hover = false

    var body: some View {
        Capsule().fill(fill).frame(width: 4, height: 4)
            .scaleEffect(grows && hover ? 1.7 : 1)
            .animation(Motion.small, value: hover)
            .onHover { hover = $0 }
    }
}

private struct ChevronMark: View {
    let symbol: String
    let leading: Bool
    @State private var hover = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(hover ? Tok.ink : Tok.ink3)
            .offset(x: hover ? (leading ? -3 : 3) : 0)
            .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.35), value: hover)
            .onHover { hover = $0 }
    }
}

/// The active pill. Moving right, its trailing edge leads on a quick spring and its leading edge follows on a slower
/// one with a little overshoot; moving left, the other way round.
private struct Pill: View {
    let index: Int
    let slot: CGFloat
    let reduceMotion: Bool
    @State private var lead: CGFloat?
    @State private var trail: CGFloat?

    var body: some View {
        let l = lead ?? x(index), t = trail ?? x(index) + 16
        Capsule().fill(Tok.sage)
            .frame(width: max(4, t - l), height: 4)
            .offset(x: l)
            .accessibilityHidden(true)
            .onChange(of: index) { old, new in
                let fast = Animation.spring(response: 0.28, dampingFraction: 0.9)
                let slow = Animation.spring(response: 0.5, dampingFraction: 0.62)
                guard !reduceMotion else {
                    withAnimation(Motion.fade) { (lead, trail) = (x(new), x(new) + 16) }
                    return
                }
                withAnimation(new > old ? fast : slow) { trail = x(new) + 16 }
                withAnimation(new > old ? slow : fast) { lead = x(new) }
            }
    }

    private func x(_ i: Int) -> CGFloat { CGFloat(i) * slot + (slot - 16) / 2 }
}
