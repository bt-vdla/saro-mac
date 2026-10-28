extension Pipeline {
    /// An About you answer through the same SafetyGate as an entry (SR-01, SR-17), before anything is saved or composed
    /// from it. Nil means no verdict yet (the classifier deferred), which the caller treats as unchecked.
    public func gate(answer: String) async -> GateResult? {
        guard !answer.allSatisfy(\.isWhitespace) else { return GateResult(verdict: "clear", layer: 0, reasonCode: "clear") }
        return await gate.gate(text: answer, transcriptConfidence: nil)
    }

    /// A stored starter's answers through this gate again (SR-17, SR-18), kept as `gated` allows: picks and the reflect
    /// time made again from the answers it clears, a held one marked, and no first prompt once any isn't clear. Nil when
    /// an answer got no verdict yet.
    public func regate(starter: StarterContext, knownName: String) async -> StarterContext? {
        var verdicts: [Int: AnswerVerdict] = [:]
        for (q, a) in starter.answers {
            guard let r = await gate(answer: a) else { return nil }
            verdicts[q] = AnswerVerdict(text: a, verdict: r.verdict)
        }
        var s = starter.gated(verdicts, knownName: Onboarding.name(starter.picks) ?? knownName)
        if verdicts.values.contains(where: { !$0.checked }) { s.firstPrompt = nil }
        return s
    }
}

extension Profile {
    /// The name, focus and tone onboarding set from About you follow its picks once they're gated again, where they still
    /// hold what the old picks gave them (one changed since in Settings stays).
    public mutating func follow(picks old: [Pick], to new: [Pick]) {
        if let n = Onboarding.name(old), name == n {
            name = Onboarding.name(new)
            if called == n { called = name }
        }
        if focusAreas == Onboarding.focusAreas(old) { focusAreas = Onboarding.focusAreas(new) }
        if tone == Onboarding.tone(old) ?? .neutral { tone = Onboarding.tone(new) ?? .neutral }
    }
}
