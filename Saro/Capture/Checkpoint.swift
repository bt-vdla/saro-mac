import Observation
import SaroKit
import SwiftUI

/// Pause & reflect (VideoReflectionScreen.tsx handleCheckpoint, BRD FR-REF-06): the part ends and is kept back, the
/// SafetyGate reads what was said live, and Saro asks one follow-up about it, or holds and shows the resources instead.
/// Keep going keeps the part and starts the next one with the question as its prompt. Live words are never stored.
@Observable @MainActor
final class Checkpoint {
    enum Phase: Equatable {
        case none
        /// "Reflecting…": the 1 s breath while the gate and Saro read the part.
        case reflecting
        /// Saro's question is up.
        case asked
        /// The part's words were held: the SafetyCard, and no question.
        case held
        /// Nothing was heard live: Keep going only.
        case quiet
    }

    private(set) var phase: Phase = .none
    private(set) var followUp: FollowUp?
    /// Started from the keyboard: the question shows at once (the frequency rule).
    private(set) var instant = false
    /// The orb talks for 2.4 s as the question arrives.
    private(set) var talking = false
    /// Keep going is waiting on the file for more than 150 ms.
    private(set) var saving = false
    /// The held state's card, until Continue.
    var safetyShown = false
    /// "Click Pause & reflect…", once a session.
    private(set) var hint = false
    @ObservationIgnored private var asked: [String] = []
    @ObservationIgnored private var observed: [String] = []
    @ObservationIgnored private var count = 0
    @ObservationIgnored private var hinted = false

    var isUp: Bool { phase != .none }
    var canKeepGoing: Bool { [.asked, .held, .quiet].contains(phase) }

    func reflect(_ model: AppModel) async {
        let capture = CaptureController.shared
        guard phase == .none, [.recording, .paused].contains(capture.state) else { return }
        instant = Motion.byKey
        hint = false
        hinted = true
        phase = .reflecting
        count += 1
        let breath = ContinuousClock.now + .seconds(1)
        let source = capture.take
        let text = await capture.endPart().trimmingCharacters(in: .whitespacesAndNewlines)
        var next = Phase.quiet
        var result: FollowUp?
        if !text.isEmpty {
            switch await model.pipeline.check(text)?.state {
            case .clear?, .modelUnavailable?:
                let day = source.flatMap { model.entry($0.entryId)?.localDay } ?? model.day
                let (f, run) = await model.ai.followUp(text: text, verb: "said", exclude: asked + [capture.prompt], excludeObservations: observed,
                                                       seed: FollowUps.seed("\(text)\n\(count)"), localDay: day)
                // Layer 3 over what was generated, the twin's included (SR-08): a hit asks nothing.
                if SafetyGate.phraseHit([f.observation ?? "", f.question].joined(separator: "\n")) {
                    next = .held
                } else {
                    (result, next) = (f, .asked)
                }
                // Linked to the part it was asked from, by id only, so a hold on that part takes the question (SR-15).
                try? await model.ledger.insertRun(run, inputs: source.map { [AIRunInput(entryId: $0.entryId, field: "live_caption", text: "")] } ?? [])
            case .safetyHold?, .awaitingCheck?:
                next = .held
            default:
                next = .quiet
            }
        }
        try? await Task.sleep(until: breath)
        guard phase == .reflecting else { return }
        withAnimation(instant ? nil : CaptureMotion.out(0.3)) {
            followUp = result
            phase = next
            safetyShown = next == .held
        }
        if let result {
            asked.append(result.question)
            if let o = result.observation { observed.append(o) }
            talking = true
            Task {
                try? await Task.sleep(for: .seconds(2.4))
                talking = false
            }
        }
    }

    func keepGoing() async {
        guard canKeepGoing else { return }
        let key = Motion.byKey
        let slow = Task {
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled { saving = true }
        }
        await CaptureController.shared.keepGoing(prompt: followUp?.question, generator: followUp?.generator ?? "heuristic", runId: followUp?.runId)
        slow.cancel()
        withAnimation(key ? nil : CaptureMotion.out(0.25)) {
            saving = false
            phase = .none
            followUp = nil
            safetyShown = false
        }
    }

    /// Once a session, 20 s into the first part with no checkpoint yet; it fades after 8 s.
    func hintIfDue() async {
        guard !hinted else { return }
        try? await Task.sleep(for: .seconds(20))
        guard !Task.isCancelled, !hinted, phase == .none, CaptureController.shared.turn == 1 else { return }
        hinted = true
        hint = true
        try? await Task.sleep(for: .seconds(8))
        hint = false
    }

    func dismiss() {
        phase = .none
        followUp = nil
        safetyShown = false
    }
}

/// The checkpoint's glass notice above the captions.
struct GlassNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typo.ui(12))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: 480)
            .fixedSize(horizontal: false, vertical: true)
            .background(.black.opacity(0.3), in: .rect(cornerRadius: 16))
            .background(.frosted(solid: Night.surface), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.2)))
            .accessibilityAddTraits(.isStaticText)
    }
}

/// The held checkpoint: the SafetyCard in the night tone, rising 12 pt into the centre of the frame, with Continue.
struct NightSafetyCard: View {
    let onContinue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saro is here with you").font(Typo.serif(20, .medium)).foregroundStyle(Night.ink)
            Text("You don’t have to carry this alone. These people will listen, any time.")
                .font(Typo.ui(13)).foregroundStyle(Night.ink2).fixedSize(horizontal: false, vertical: true)
            SafetyCardView(compact: true)
            HStack {
                Spacer()
                Button("Continue", action: onContinue)
                    .buttonStyle(CaptureButtonStyle(fill: Night.sage, hover: Night.sageDark, ink: Night.bg, padding: 18, size: 13))
            }
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(Night.surface.opacity(0.96), in: .rect(cornerRadius: Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(.white.opacity(0.1)))
        .elevation(.overlay)
        .environment(\.colorScheme, .dark)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
        .accessibilityElement(children: .contain)
    }
}
