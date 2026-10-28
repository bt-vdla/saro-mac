import SaroKit
import SwiftUI

/// 02 How Saro talks (ToneSection.tsx + the focus picker): your own sentence said four ways, and what the lens is
/// aimed at. Both save as you pick.
struct TalkSection: View {
    @Environment(AppModel.self) private var model
    @State private var save = Autosave()
    @State private var source: ToneSource?
    @State private var lines: [Tone: String]?
    @State private var loadFailed = false
    /// Sentences this opening has asked for: a failed one waits for the next opening, not the next status change.
    @State private var asked: Set<String> = []
    /// One on-device rewrite per sentence, for the session.
    private static var rewrites: [String: [Tone: String]] = [:]

    var body: some View {
        SettingsCard(label: "How Saro talks", title: "How should I speak to you?", autosave: save) {
            if let profile = model.profile {
                TonePicker(tone: profile.tone, source: source, lines: lines) { pick in
                    save.run { try await model.updateProfile { $0.tone = pick } }
                }
                RowRule().padding(.vertical, 18)
                FocusPicker(focus: profile.focusAreas) { next in
                    save.run { try await model.updateProfile { $0.focusAreas = next } }
                }
            } else if loadFailed {
                LoadError { Task { await load() } }
            } else {
                Skeleton()
            }
        }
        .task { await load() }
        // A day held by an answer or a mood note changes no count, only its status: either picks the sentence again (SR-13).
        .task(id: "\(model.days.first.map { "\($0.day)-\($0.count)" } ?? "")-\(model.day)-\(model.dayStatus)") {
            let next = await ToneSource.latest(model)
            source = next
            lines = Self.rewrites[next.sentence]
            guard lines == nil, !asked.contains(next.sentence), Readiness.model().isReady else { return }
            asked.insert(next.sentence)
            // The rules show at once; the model's lines replace them once they pass the output gate and drift check.
            let reply = await model.exclusive { () -> (tones: [Tone: String], run: AIRun)? in
                // Openings that queued the same sentence meanwhile have nothing to ask once one has its rewrite.
                guard Self.rewrites[next.sentence] == nil else { return nil }
                return await model.ai.tonePreview(next.sentence, localDay: next.day)
            }
            guard let reply else {
                if source == next { lines = Self.rewrites[next.sentence] }
                return
            }
            let (tones, run) = reply
            try? await model.ledger.insertRun(run, inputs: next.inputs)
            // A busy or failed model is tried again next time, not kept as the rules' lines for the session.
            if run.status == "ok" { Self.rewrites[next.sentence] = tones }
            if source == next { withAnimation(Motion.fade) { lines = tones } }
        }
    }

    private func load() async {
        loadFailed = false
        if model.profile == nil { await model.loadProfile() }
        loadFailed = model.profile == nil
    }
}

/// The sentence the tone picker says four ways: the latest clear day's narrative, else the latest clear writing in the
/// second person, else the sample. A held day or an unchecked entry is never used (SR-13).
struct ToneSource: Equatable {
    var sentence: String
    var caption: String
    var day: String?
    /// What the sentence came from, for the tone-preview run's content-free log.
    var inputs: [AIRunInput] = []

    static let sample = ToneSource(sentence: TonePreview.sample, caption: "Sample · write something and this uses your words")

    private static func short(_ day: String) -> String {
        LocalDay.date(day)?.formatted(Date.VerbatimFormatStyle(format: "\(month: .abbreviated) \(day: .defaultDigits)", locale: Locale(identifier: "en_US_POSIX"),
                                                               timeZone: .current, calendar: Calendar(identifier: .gregorian))) ?? day
    }

    /// ponytail: looks back over the last 30 days with entries; older journals fall back to the sample.
    @MainActor static func latest(_ model: AppModel) async -> ToneSource {
        let days = model.days.prefix(30).map(\.day)
        var clear: [String] = []
        for day in days where await model.pipeline.dayStatus(day) == .ready {
            clear.append(day)
            if let reading = await model.pipeline.latestDayReading(day), let n = reading.payload.reading.narrative, !n.isEmpty {
                let sentence = TonePreview.previewSentence(n)
                return ToneSource(sentence: sentence, caption: day == LocalDay.today() ? "From today’s insight" : "From your insight on \(short(day))",
                                  day: day, inputs: reading.payload.entryIds.prefix(1).map { AIRunInput(entryId: $0, field: "day_reading", text: sentence) })
            }
        }
        for day in clear {
            guard let entries = try? await model.ledger.entries(day: day), let verdicts = try? await model.ledger.verdicts(day: day) else { continue }
            for e in entries.reversed() where e.kind == .reflection {
                guard let body = e.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let v = verdicts[e.id],
                      v.verdict == "clear" || v.verdict == "unavailable_clear", v.textSha256 == sha256(body) else { continue }
                return ToneSource(sentence: TonePreview.previewSentence(TonePreview.toSecondPerson(body)), caption: "From your reflection on \(short(day))",
                                  day: day, inputs: [AIRunInput(entryId: e.id, field: "body", text: body)])
            }
        }
        return sample
    }
}

/// Four tones, each the same sentence said that way. Arrow keys move the pick.
struct TonePicker: View {
    let tone: Tone
    let source: ToneSource?
    /// The on-device rewrite once it has passed its checks; else the rules' lines.
    var lines: [Tone: String]?
    let pick: (Tone) -> Void
    @State private var hovered: Tone?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(source?.caption ?? " ").font(Typo.ui(12)).foregroundStyle(Tok.ink3)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Tone.allCases, id: \.self) { t in
                    let on = t == tone
                    Button { pick(t) } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Capsule()
                                .fill(on ? Tok.voice : hovered == t ? Tok.borderStrong : .clear)
                                .frame(width: 2)
                                .padding(.vertical, 6)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.label).monoCaps(11, tracking: 0.12).foregroundStyle(on ? Tok.ink : Tok.ink3)
                                // A reserved line while the sentence loads, so the list doesn't jump.
                                Text(line(t) ?? " ")
                                    .font(Typo.serif(17)).foregroundStyle(on ? Tok.ink : hovered == t ? Tok.ink2 : Tok.ink3)
                                    .frame(minHeight: 24, alignment: .topLeading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 8)
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 ? t : hovered == t ? nil : hovered }
                }
            }
            .animation(Motion.pick(Motion.small, reduce: reduceMotion), value: tone)
            .animation(Motion.fade, value: hovered)
            .focusable()
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                let all = Tone.allCases
                let step = press.key == .upArrow || press.key == .leftArrow ? -1 : 1
                let i = all.firstIndex(of: tone) ?? 0
                pick(all[(i + step + all.count) % all.count])
                return .handled
            }
            .accessibilityRepresentation {
                Picker("How Saro talks", selection: Binding(get: { tone }, set: { pick($0) })) {
                    ForEach(Tone.allCases, id: \.self) { t in Text("\(t.label): \(line(t) ?? "")").tag(t) }
                }
                .pickerStyle(.radioGroup)
            }
            .accessibilityHint(source?.caption ?? "")
        }
    }

    private func line(_ t: Tone) -> String? { lines?[t] ?? source.map { TonePreview.rewrite($0.sentence, tone: t) } }
}

/// "Aim the lens at—": up to three of eight focus areas, each in its own colour (focus-data.ts).
struct FocusPicker: View {
    let focus: [FocusArea]
    let change: ([FocusArea]) -> Void
    @State private var shakes = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let picked = FocusArea.allCases.filter(focus.contains)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Aim the lens at—").font(Typo.ui(14.5, .medium)).foregroundStyle(Tok.ink)
                    Text("What Saro looks for in your entries, up to three.").font(Typo.ui(12)).foregroundStyle(Tok.ink3)
                }
                Spacer()
                Text("\(focus.count) / \(ParseIntent.maxFocus)")
                    .font(Typo.mono(12)).monospacedDigit().foregroundStyle(focus.isEmpty ? Tok.ink3 : Tok.ink2)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .accessibilityLabel("\(focus.count) of \(ParseIntent.maxFocus) chosen")
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                ForEach(FocusArea.allCases, id: \.self) { area in
                    Button { toggle(area) } label: { FocusChipLabel(area: area) }
                        .buttonStyle(FocusChip(area: area, on: focus.contains(area)))
                        .accessibilityAddTraits(focus.contains(area) ? .isSelected : [])
                }
            }
            .keyframeAnimator(initialValue: 0.0, trigger: shakes) { grid, x in grid.offset(x: x) } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(-3, duration: 0.06)
                    LinearKeyframe(3, duration: 0.06)
                    LinearKeyframe(-3, duration: 0.06)
                    LinearKeyframe(0, duration: 0.06)
                }
            }
            if let line = FocusCopy.preview(picked) {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(LinearGradient(colors: picked.map(\.tint), startPoint: .top, endPoint: .bottom))
                        .frame(width: 3)
                    Text(line).font(Typo.serif(17, italic: true)).foregroundStyle(Tok.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(line)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
                }
                .frame(minHeight: 28)
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .animation(Motion.easeOut(0.2), value: focus)
    }

    private func toggle(_ area: FocusArea) {
        if focus.contains(area) { return change(focus.filter { $0 != area }) }
        guard focus.count < ParseIntent.maxFocus else {
            if !reduceMotion { shakes += 1 }
            AccessibilityNotification.Announcement(FocusCopy.limit).post()
            return
        }
        change(focus + [area])
    }
}

private struct FocusChipLabel: View {
    let area: FocusArea
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: area.symbol).font(.system(size: 12, weight: .medium)).accessibilityHidden(true)
            Text(area.label).lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

/// A picked chip takes its own colour for border and text over a 5% tint; hover lifts it a point.
private struct FocusChip: ButtonStyle {
    let area: FocusArea
    let on: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.ui(13, .medium))
            .foregroundStyle(on ? area.tint : hovering ? Tok.ink : Tok.ink2)
            .padding(.horizontal, 14).frame(height: 44)
            .background(on ? area.tint.opacity(0.05) : .clear, in: .rect(cornerRadius: 9, style: .continuous))
            .background(Tok.surfaceAlt, in: .rect(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(on ? area.tint : hovering ? Tok.borderStrong : Tok.border, lineWidth: 1.5))
            .shadow(color: Tok.shadow.opacity(hovering && !configuration.isPressed ? 0.07 : 0), radius: 5, y: 2)
            .offset(y: hovering && !configuration.isPressed && !reduceMotion ? -1 : 0)
            .animation(Motion.pick(Motion.small, reduce: reduceMotion), value: hovering)
            .animation(Motion.press, value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

/// "Loading your settings…": only the profile can be slow to read.
struct Skeleton: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(Tok.ink.opacity(0.07)).frame(width: 200, height: 14)
            RoundedRectangle(cornerRadius: Radius.field).fill(Tok.ink.opacity(0.05)).frame(height: 96)
        }
        .opacity(pulse ? 0.5 : 1)
        .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 1.2).repeatForever()) { pulse = true } } }
        .accessibilityElement()
        .accessibilityLabel("Loading your settings…")
    }
}

struct LoadError: View {
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Couldn’t load your settings right now.").font(Typo.ui(14, .medium)).foregroundStyle(Tok.ink)
            Button("Retry", action: retry).buttonStyle(.settingsDanger)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tok.dangerBg, in: .rect(cornerRadius: Radius.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(Tok.dangerBorder))
    }
}
