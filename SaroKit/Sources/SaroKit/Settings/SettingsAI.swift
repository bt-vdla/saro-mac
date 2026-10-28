import Foundation
import FoundationModels

/// What the model may answer for Say it: one key of the closed list, or none, and its value.
@Generable
struct SettingOut {
    @Guide(.anyOf(ParseIntent.Key.allCases.map(\.rawValue) + ["none"]))
    var key: String
    @Guide(description: "HH:MM (24-hour) for reminder or letterTime, on or off, a percentage for textScale, a tone (gentle, neutral, direct, contemplative), auto, light or dark for theme, or comma-separated focus areas")
    var value: String
}

/// Settings' two optional on-device touchpoints. Neither writes anything: the tone preview is display text, and a
/// parsed setting is a proposal the person still has to Apply. The tone preview is one permissive call on gate-cleared
/// text; Say it is one guided call on words the whole gate cleared. Each is checked as strictly as the rules it stands
/// in for, and logged as a content-free ai_run.
extension SaroAI {
    static let tonePromptVersion = "tone-preview-1"
    static let settingsPromptVersion = "settings-parse-2"

    /// The sentence in all four tones, in one call (tone-preview). Every line that fails the output gate or the drift
    /// check, or doesn't come back, is the rules' version instead.
    public func tonePreview(_ sentence: String, localDay: String?) async -> (tones: [Tone: String], run: AIRun) {
        let start = ContinuousClock.now
        guard status == .available else { return (TonePreview.ruled(sentence), run("tone-preview", start, calls: 0, status: "unavailable", localDay)) }
        let prompt = """
        Rewrite this sentence four ways, keeping its meaning and every fact, adding nothing:
        "\(sentence)"

        Reply with only a JSON object, no markdown, with exactly these keys:
        "gentle": softer, ending with a short reassurance
        "neutral": plain and even
        "direct": no hedges, the main point first
        "contemplative": ending with an open question
        """
        do {
            let reply = try await Self.ask(SystemLanguageModel(guardrails: .permissiveContentTransformations), Self.voice, prompt, Self.options, nil)
            let tones = TonePreview.accept(reply, sentence: sentence)
            return (tones, run("tone-preview", start, calls: 1, status: SafetyGate.phraseHit(reply) ? "output_gate" : "ok", localDay))
        } catch {
            return (TonePreview.ruled(sentence), run("tone-preview", start, calls: 1, status: Ladder.reason(error), localDay))
        }
    }

    /// When the rules match nothing (settings-parse): the person's words about settings mapped to one key of the same
    /// closed list, on the default guardrails. Callers gate the words first (`Pipeline.parseSetting`); words that trip
    /// the phrase gate are never sent.
    public func parseSetting(_ text: String, current: SettingsValues) async -> (result: ParseIntent.Result, run: AIRun?) {
        let start = ContinuousClock.now
        guard status == .available, !SafetyGate.phraseHit(text) else { return (.none, nil) }
        let prompt = """
        Someone typed this in a journal app's settings: "\(text)"
        Which one setting do they want to change, and to what? The key is none if it isn't a setting.
        Focus areas are \(FocusArea.allCases.map(\.rawValue).joined(separator: ", ")).
        """
        do {
            let out = try await Self.ask(SettingOut.self, base, Self.voice, prompt, Self.options, stub)
            let held = SafetyGate.phraseHit("\(out.key) \(out.value)")
            let result = held ? .none : ParseIntent.fromModel(key: out.key, value: out.value, current: current)
            return (result, run("settings-parse", start, calls: 1, status: held ? "output_gate" : "ok", nil))
        } catch {
            return (.none, run("settings-parse", start, calls: 1, status: Ladder.reason(error), nil))
        }
    }

    private func run(_ feature: String, _ start: ContinuousClock.Instant, calls: Int, status: String, _ localDay: String?) -> AIRun {
        var r = AIRun(feature: feature, executor: calls == 0 ? "heuristic" : "on_device", status: status)
        let rung: Rung = calls == 0 ? .heuristic : feature == "settings-parse" ? .guided : .permissiveJSON
        r.ladderRung = rung.rawValue
        r.guardrails = rung == .heuristic ? nil : rung == .guided ? "default" : "permissive"
        r.variant = variant
        r.osBuild = Self.osBuild
        r.contextSize = contextSize
        r.promptVersion = feature == "tone-preview" ? Self.tonePromptVersion : Self.settingsPromptVersion
        r.modelCalls = calls
        r.latencyMs = Int((ContinuousClock.now - start) / .milliseconds(1))
        r.localDay = localDay
        return r
    }
}

extension TonePreview {
    /// The rules' four versions: the floor under the model.
    public static func ruled(_ sentence: String) -> [Tone: String] {
        Dictionary(uniqueKeysWithValues: Tone.allCases.map { ($0, rewrite(sentence, tone: $0)) })
    }

    /// A model reply's four tones, each kept only when it's there, passes the output gate and the drift check against
    /// the sentence, actually changes it (but neutral), and (contemplative) ends on a question; otherwise the rules'.
    static func accept(_ reply: String, sentence: String) -> [Tone: String] {
        var out = ruled(sentence)
        guard !SafetyGate.phraseHit(reply), let json = Ladder.jsonObject(in: reply),
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return out }
        func letters(_ s: String) -> String { s.lowercased().filter(\.isLetter) }
        for tone in Tone.allCases {
            guard let line = (object[tone.rawValue] as? String)?.jsTrim, !line.isEmpty, line.count <= 240,
                  tone == .neutral || letters(line) != letters(sentence),
                  Heuristics.driftOK(generated: line, source: sentence), tone != .contemplative || line.hasSuffix("?") else { continue }
            out[tone] = line
        }
        return out
    }
}

extension ParseIntent {
    /// A model's {key, value}, validated against the same specs as the rules; anything else matches nothing.
    static func fromModel(_ reply: String, current: SettingsValues) -> Result {
        guard let json = Ladder.jsonObject(in: reply),
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let key = object["key"] as? String, let value = object["value"] as? String
        else { return .none }
        return fromModel(key: key, value: value, current: current)
    }

    static func fromModel(key: String, value: String, current: SettingsValues) -> Result {
        guard let key = Key(rawValue: key) else { return .none }
        let value = value.lowercased().jsTrim
        var next = current
        let on = ["on", "true", "yes"].contains(value), off = ["off", "false", "no"].contains(value)
        func minutes(_ s: String) -> Int? {
            guard let m = s.jsMatch(#"^([01]?\d|2[0-3]):([0-5]\d)$"#), let h = Int(m[1] ?? ""), let mm = Int(m[2] ?? "") else { return nil }
            return h * 60 + mm
        }
        switch key {
        case .reminder:
            if off { next.reminderOn = false } else if let m = minutes(value) { (next.reminderOn, next.reminderMinutes) = (true, m) } else { return .none }
        case .letterTime:
            guard let m = minutes(value) else { return .none }
            next.letterMinutes = m
        case .tone:
            guard current.tone != nil, let t = Tone(rawValue: value) else { return .none }
            next.tone = t
        case .theme:
            guard let t: SettingsValues.Appearance = value == "auto" ? .clock : value == "light" ? .light : value == "dark" ? .dark : nil else { return .none }
            next.theme = t
        case .textScale:
            guard let p = Double(value.replacingOccurrences(of: "%", with: "")), Prefs.textScales.contains(p / 100) else { return .none }
            next.textScale = p / 100
        case .focus:
            guard current.focus != nil else { return .none }
            let areas = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let picks = areas.compactMap(FocusArea.init)
            guard picks.count == areas.count else { return .none }
            next.focus = FocusArea.allCases.filter(picks.contains)
        case .captionsAlways, .reduceMotion, .reduceTransparency, .sounds, .haptics, .memoryPaused:
            guard on || off else { return .none }
            switch key {
            case .captionsAlways: next.captionsAlways = on
            case .reduceMotion: next.reduceMotion = on
            case .reduceTransparency: next.reduceTransparency = on
            case .sounds: next.sounds = on
            case .haptics: next.haptics = on
            default: next.memoryPaused = on
            }
        }
        guard valid(next), let from = format(key, current), let to = format(key, next) else { return .none }
        if same(key, current, next) { return .alreadySet(already(key, next)) }
        return .changes([Change(key: key, label: label(key), why: "Read by the on-device model; check it before you apply", from: from, to: to)],
                        note: nil, proposed: next)
    }
}

extension Pipeline {
    /// Say it's words when the rules match nothing: they pass the whole SafetyGate first (SR-01), and only words it clears
    /// reach the model. `held` when the gate held them, so the bar offers the SafetyCard instead of a setting.
    public func parseSetting(_ text: String, current: SettingsValues) async -> (result: ParseIntent.Result, held: Bool) {
        guard let verdict = await check(text)?.verdict else { return (.none, false) }
        guard verdict == "clear" else { return (.none, verdict == "safety_hold") }
        let (result, run) = await ai.parseSetting(text, current: current)
        if let run { try? await ledger.insertRun(run) }
        return (result, false)
    }
}
