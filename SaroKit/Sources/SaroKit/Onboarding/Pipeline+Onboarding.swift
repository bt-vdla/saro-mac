extension Pipeline {
    /// An About you answer through the same SafetyGate as an entry (SR-01, SR-17), before anything is saved or composed
    /// from it. Nil means no verdict yet (the classifier deferred), which the caller treats as unchecked.
    public func gate(answer: String) async -> GateResult? {
        guard !answer.allSatisfy(\.isWhitespace) else { return GateResult(verdict: "clear", layer: 0, reasonCode: "clear") }
        return await gate.gate(text: answer, transcriptConfidence: nil)
    }
}
