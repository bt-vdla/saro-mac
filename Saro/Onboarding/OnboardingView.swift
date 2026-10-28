import AppKit
import Observation
import SaroKit
import SwiftUI

/// One pass through onboarding (app/page.tsx, useOnboardingState.ts): the step, the furthest step, and About you's
/// answers with the gate's verdict on each. Steps survive a quit or a crash through UserDefaults; a finished pass
/// starts again at Q1 with its answers kept.
@Observable @MainActor
final class OnboardingFlow {
    enum Step: String, CaseIterable, Comparable {
        case welcome, intro, about, firstWeek, findLight

        static func < (a: Step, b: Step) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }

        /// The dock's dots: About you, First week, Light.
        var dot: Int? { [.about: 0, .firstWeek: 1, .findLight: 2][self] }

        var screen: ScreenID {
            switch self {
            case .welcome, .intro: .onboardingWelcome
            case .about: .onboardingAboutYou
            case .firstWeek: .onboardingFirstWeek
            case .findLight: .onboardingFindLight
            }
        }
    }

    enum AboutStep: Hashable {
        case question(Int), prompt

        var key: String { if case .question(let q) = self { "\(q)" } else { "prompt" } }
        init?(key: String?) {
            if key == "prompt" { self = .prompt } else if let q = key.flatMap(Int.init), (1...5).contains(q) { self = .question(q) } else { return nil }
        }
    }

    /// How the last move was made: a pointer gets the rise, a key the quick crossfade.
    enum Nav { case pointer, key }

    /// The first prompt, once every answer has its verdict.
    enum Prompt: Equatable {
        case waiting
        /// A held answer: no personal prompt, the SafetyCard instead.
        case held
        case ready([FirstPrompt.Candidate])
    }

    static let maxName = 30, maxAnswer = 280
    /// A demo journal keeps its own onboarding keys, so trying it never moves the real journal's place.
    static let defaults: UserDefaults = {
        guard PrefsStore.isDemo, let d = UserDefaults(suiteName: "SaroDemo.onboarding") else { return .standard }
        d.removePersistentDomain(forName: "SaroDemo.onboarding")
        return d
    }()

    private(set) var step: Step = .welcome
    private(set) var furthest: Step = .welcome
    private(set) var direction: CGFloat = 1
    private(set) var nav: Nav = .pointer
    private(set) var aboutStep: AboutStep = .question(1)
    /// What the field shows for the question on screen.
    var text = ""
    private(set) var starter = StarterContext(version: 1)
    /// The text each question's verdict was for, and the verdict (nil: the gate deferred, so unchecked).
    private(set) var verdicts: [Int: (text: String, verdict: String?)] = [:]
    /// The name Saro has for them: Q1's, else the profile's, else this Mac's.
    private(set) var knownName = ""
    private(set) var loaded = false
    private(set) var leaving = false
    var speech: Readiness.SpeechState?
    let light = LightCheck()

    // MARK: Loading

    /// Picks up where this pass was, or starts a new pass (a new starter version) seeded with the last one's answers.
    func load(_ model: AppModel) async {
        guard !loaded else { return }
        let d = Self.defaults
        let latest = try? await model.ledger.latestStarter()
        if let latest, latest.id == d.string(forKey: "onboarding.starterID") {
            starter = latest
        } else {
            var fresh = StarterContext(version: (try? await model.ledger.newStarterVersion()) ?? 1)
            fresh.answers = latest?.answers ?? [:]
            fresh.dropped = latest?.dropped ?? []
            starter = fresh
            d.set(fresh.id, forKey: "onboarding.starterID")
        }
        knownName = model.profile?.address
            ?? NSFullUserName().split(whereSeparator: \.isWhitespace).first.map { String($0.prefix(Self.maxName)) } ?? ""
        step = Step(rawValue: d.string(forKey: "onboarding.step") ?? "") ?? .welcome
        furthest = max(step, Step(rawValue: d.string(forKey: "onboarding.furthest") ?? "") ?? step)
        let saved = starter.answers.isEmpty ? nil : AboutStep(key: d.string(forKey: "onboarding.aboutStep"))
        aboutStep = saved ?? (starter.firstPrompt != nil ? .question(1) : (1...5).first { starter.answers[$0] == nil }.map(AboutStep.question) ?? .prompt)
        text = answer(for: aboutStep)
        recompute()
        loaded = true
        model.screen = step.screen
        // Answers from an earlier pass are checked again by this gate.
        for (q, a) in starter.answers { gate(q, a, model) }
    }

    /// Q1 comes back as the name Saro has when its answer gave none ("I'm not sure").
    private func answer(for s: AboutStep) -> String {
        guard case .question(let q) = s else { return "" }
        let a = starter.answers[q] ?? ""
        return q == 1 && Onboarding.extract(answer: a, question: 1).isEmpty ? (knownName.isEmpty ? a : knownName) : a
    }

    var name: String { (Onboarding.name(starter.picks) ?? knownName).trimmingCharacters(in: .whitespaces) }

    private func recompute() {
        starter.picks = Onboarding.picks(answers: starter.answers, dropped: starter.dropped, knownName: name)
        starter.reflectTime = Onboarding.reflectTime(starter.picks)
    }

    // MARK: Steps

    func go(_ to: Step, nav: Nav = .pointer, model: AppModel) {
        guard to != step, !leaving else { return }
        // The step leaving reads the new direction before it goes, so it drifts the right way.
        direction = to > step ? 1 : -1
        self.nav = nav
        let d = Self.defaults
        Task { @MainActor in
            await Task.yield()
            step = to
            furthest = max(furthest, to)
            model.screen = to.screen
            // The intro shows once: a quit during it comes back to About you.
            d.set((to == .intro ? .about : to).rawValue, forKey: "onboarding.step")
            d.set(furthest.rawValue, forKey: "onboarding.furthest")
        }
    }

    /// ⌘[, ⌥⌘← and the dock's chevron: a question back inside About you, else the step before.
    func previous(_ nav: Nav, model: AppModel) {
        if step == .about, aboutStep != .question(1) { return back(nav) }
        if step > .about { go(Step.allCases[Step.allCases.firstIndex(of: step)! - 1], nav: nav, model: model) }
    }

    func next(_ nav: Nav, model: AppModel) {
        guard step >= .about, step < .findLight else { return }
        let to = Step.allCases[Step.allCases.firstIndex(of: step)! + 1]
        if to <= furthest { go(to, nav: nav, model: model) }
    }

    // MARK: About you

    private func move(to s: AboutStep, nav: Nav) {
        self.nav = nav
        aboutStep = s
        text = answer(for: s)
        Self.defaults.set(s.key, forKey: "onboarding.aboutStep")
    }

    var canCommit: Bool {
        guard case .question(let q) = aboutStep else { return false }
        return q > 1 || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Return, →, or Skip (an empty answer): the answer is kept, gated, then saved, and the next question opens.
    func commit(_ answer: String, nav: Nav, model: AppModel) {
        guard case .question(let q) = aboutStep, q > 1 || !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        starter.answers[q] = answer
        if q == 1 { knownName = (Onboarding.extract(answer: answer, question: 1).first?.value ?? knownName).trimmingCharacters(in: .whitespaces) }
        recompute()
        gate(q, answer, model)
        move(to: q == 5 ? .prompt : .question(q + 1), nav: nav)
    }

    /// Back keeps what was typed, so coming forward again restores it.
    func back(_ nav: Nav) {
        switch aboutStep {
        case .question(1): return
        case .question(let q):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { starter.answers[q] = text; recompute() }
            move(to: .question(q - 1), nav: nav)
        case .prompt: move(to: .question(5), nav: nav)
        }
    }

    func toggle(_ pick: Pick, model: AppModel) {
        if starter.dropped.contains(pick.dropKey) { starter.dropped.remove(pick.dropKey) } else { starter.dropped.insert(pick.dropKey) }
        recompute()
        Task { await save(model) }
    }

    /// The gate first (SR-17), then the save; a later answer to the same question replaces this one's verdict.
    private func gate(_ q: Int, _ answer: String, _ model: AppModel) {
        Task {
            let result = await model.pipeline.gate(answer: answer)
            guard starter.answers[q] == answer else { return }
            verdicts[q] = (answer, result?.verdict)
            await save(model, profileFrom: q)
        }
    }

    /// What may be stored: only answers whose verdict is in, with the held ones marked, so nothing is composed or
    /// learned from text the gate hasn't seen.
    private var gated: StarterContext {
        var s = starter
        s.answers = starter.answers.filter { verdicts[$0.key]?.text == $0.value }
        s.held = Set(s.answers.keys.filter { verdicts[$0]?.verdict == "safety_hold" })
        s.picks = Onboarding.picks(answers: s.answers, dropped: s.dropped, knownName: name)
        s.reflectTime = Onboarding.reflectTime(s.picks)
        return s
    }

    private func save(_ model: AppModel, profileFrom q: Int? = nil) async {
        let s = gated
        await model.saveStarter(s)
        guard let q, !s.held.contains(q) else { return }
        let picks = s.storable.picks
        switch q {
        case 1:
            guard let n = Onboarding.name(picks) else { return }
            await model.saveProfile { $0.name = n; $0.called = n }
        case 4:
            let focus = Onboarding.focusAreas(picks)
            if !focus.isEmpty { await model.saveProfile { $0.focusAreas = focus } }
        case 5:
            let tone = Onboarding.tone(picks) ?? .neutral
            await model.saveProfile { $0.tone = tone }
        default: break
        }
    }

    var tone: Tone { Onboarding.tone(keptPicks) ?? .neutral }

    /// The picks that may be used past About you: gated, not held, not left out.
    var keptPicks: [Pick] { gated.storable.picks }

    var prompt: Prompt {
        let answered = starter.answers.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if answered.contains(where: { verdicts[$0.key]?.text != $0.value }) { return .waiting }
        let s = gated
        if !s.held.isEmpty { return .held }
        // An answer the gate couldn't check gets the tone's line, never a prompt made from it.
        let unchecked = s.answers.keys.contains { q in
            let v = verdicts[q]?.verdict ?? nil
            return v != "clear" && v != "unavailable_clear"
        }
        if unchecked { return .ready([FirstPrompt.Candidate(text: tone.previewLine(name: name))]) }
        return .ready(FirstPrompt.compose(starter: s, name: name, tone: tone))
    }

    /// 'Answer it' (or Continue past the SafetyCard): the prompt is kept unless an answer was held, then First week.
    func accept(_ text: String?, model: AppModel) {
        starter.firstPrompt = text
        Task { await save(model) }
        go(.firstWeek, nav: nav, model: model)
    }

    // MARK: Finishing

    /// Completes onboarding and hands the first reflection to the day canvas: nil is 'Later'. The camera check is off
    /// before the recorder asks for the camera.
    func finish(_ mode: AppModel.FirstMode?, model: AppModel) async {
        guard !leaving else { return }
        leaving = true
        await light.release()
        let d = Self.defaults
        d.set(Step.about.rawValue, forKey: "onboarding.step")
        d.set(Step.about.rawValue, forKey: "onboarding.furthest")
        d.set("1", forKey: "onboarding.aboutStep")
        d.removeObject(forKey: "onboarding.starterID")
        await model.completeOnboarding()
        if let mode { await model.startFirstReflection(mode) }
    }

    /// Speech downloads during About you, so it's ready by the first recording. Never blocks anything.
    func prepareSpeech() {
        guard speech == nil else { return }
        speech = .downloading(nil)
        Task {
            let now = await Readiness.speech()
            guard case .needsDownload = now else { speech = now; return }
            speech = await Readiness.downloadSpeech { p in Task { @MainActor in if case .downloading = self.speech { self.speech = .downloading(p) } } }
        }
    }

    #if DOGFOOD
    /// Snapshots: a flow at a given place, without the ledger.
    static func preview(step: Step, about: AboutStep = .question(1), answers: [Int: String] = [:], text: String? = nil,
                        held: Set<Int> = [], name: String = "Bharat") -> OnboardingFlow {
        let f = OnboardingFlow()
        f.step = step
        f.furthest = step
        f.knownName = name
        f.starter.answers = answers
        f.aboutStep = about
        f.recompute()
        for (q, a) in answers { f.verdicts[q] = (a, held.contains(q) ? "safety_hold" : "clear") }
        f.text = text ?? f.answer(for: about)
        f.loaded = true
        return f
    }
    #endif
}

/// The onboarding window: the lit ground, one step at a time, and the dock. Full window, no title bar.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var flow = OnboardingFlow()

    var body: some View {
        ZStack {
            if flow.step != .firstWeek { LitGround().ignoresSafeArea() }
            if flow.loaded {
                content
                    .id(flow.step)
                    .transition(reduceMotion ? AnyTransition.opacity.animation(Motion.fade) : StepMotion.transition(flow.direction))
            }
        }
        .animation(reduceMotion ? Motion.fade : .interactiveSpring(duration: 0.45), value: flow.step)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if flow.step >= .about {
                ProgressDock(flow: flow)
                    .opacity(flow.furthest >= .firstWeek ? 1 : 0)
                    .allowsHitTesting(flow.furthest >= .firstWeek)
                    .animation(Motion.easeOut(0.9), value: flow.furthest >= .firstWeek)
            }
        }
        .background { shortcuts }
        .background(Tok.bg)
        .environment(flow)
        .task { await flow.load(model) }
    }

    @ViewBuilder private var content: some View {
        switch flow.step {
        case .welcome: WelcomeDoor()
        case .intro: IntroBeat { flow.go(.about, model: model) }
        case .about: AboutYouView()
        case .firstWeek: FirstWeekView()
        case .findLight: FindLightView()
        }
    }

    /// ⌘[ and ⌘] (or ⌥⌘← and ⌥⌘→) move between steps; inside About you ⌘[ goes back a question.
    private var shortcuts: some View {
        Group {
            Button("Previous Step") { flow.previous(.key, model: model) }.keyboardShortcut("[", modifiers: .command)
            Button("Previous Step") { flow.previous(.key, model: model) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Next Step") { flow.next(.key, model: model) }.keyboardShortcut("]", modifiers: .command)
            Button("Next Step") { flow.next(.key, model: model) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .disabled(flow.step < .about || flow.leaving)
    }
}

/// The step change: the old step leaves in 200 ms, drifting up 6 pt with a 4 pt blur; the new one comes in over
/// 450 ms from 18 pt below with a 7 pt blur clearing. Going back, both run the other way.
struct StepMotion: ViewModifier {
    var y: CGFloat
    var blur: CGFloat
    var opacity: Double

    func body(content: Content) -> some View { content.offset(y: y).blur(radius: blur).opacity(opacity) }

    static func transition(_ direction: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(active: StepMotion(y: 18 * direction, blur: 7, opacity: 0), identity: StepMotion(y: 0, blur: 0, opacity: 1))
                .animation(.interactiveSpring(duration: 0.45)),
            removal: .modifier(active: StepMotion(y: -6 * direction, blur: 4, opacity: 0), identity: StepMotion(y: 0, blur: 0, opacity: 1))
                .animation(Motion.easeOut(0.2)))
    }
}

/// The step's small 'saro' over its content, and its mono eyebrow (StepLayout.tsx).
struct StepMark: View {
    var body: some View {
        Text("saro").font(Typo.serif(20, italic: true)).foregroundStyle(Tok.ink.opacity(0.28)).accessibilityHidden(true)
    }
}

extension View {
    /// The web's `rise`: in from `y` below, fading, after `delay`. Under Reduce Motion only the fade remains.
    func rise(_ shown: Bool, y: CGFloat = 8, delay: Double, duration: Double = 0.5, reduce: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown || reduce ? 0 : y)
            .animation(reduce ? Motion.fade.delay(delay) : .timingCurve(0.33, 1, 0.68, 1, duration: duration).delay(delay), value: shown)
    }

    /// Posts `text` to VoiceOver whenever it changes and isn't empty.
    func announces(_ text: String) -> some View {
        onChange(of: text) { _, t in if !t.isEmpty { AccessibilityNotification.Announcement(t).post() } }
    }
}

/// Whether the click that's running was a key press (Return, Space) rather than a pointer.
@MainActor func pressedByKey() -> Bool { NSApp.currentEvent?.type == .keyDown }
