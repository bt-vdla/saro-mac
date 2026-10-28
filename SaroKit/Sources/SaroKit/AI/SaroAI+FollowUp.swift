import Foundation
import FoundationModels

@Generable
struct FollowUpOut {
    @Guide(description: "One short sentence in second person that only states something the person said, or null")
    var observation: String?
    @Guide(description: "One gentle open follow-up question about something the person said")
    var question: String
}

/// reflect_deeper (a checkpoint in the recorder, verb "said") and reflect_further (under a written page, verb "wrote"):
/// the ladder, raced against the heuristic twin. Callers pass only text the SafetyGate cleared. Whatever the model says
/// must pass the output gate and the drift check against the person's words; a late model call is cancelled and the twin
/// answers. The returned ai_run is content-free.
extension SaroAI {
    static let followUpPromptVersion = "follow-up-1"
    /// BRD FR-REF-06: the question comes within about 2.5 s, or the twin's does.
    public static let followUpBudget: Duration = .milliseconds(2500)

    public func followUp(text: String, verb: String, exclude: [String], excludeObservations: [String] = [], seed: Int,
                         phraseFrom: String? = nil, localDay: String?, budget: Duration = followUpBudget) async -> (FollowUp, AIRun) {
        let start = ContinuousClock.now
        let feature = verb == "said" ? "reflect_deeper" : "reflect_further"
        let twin = FollowUps.twin(text, verb: verb, exclude: exclude, excludeObservations: excludeObservations, seed: seed, phraseFrom: phraseFrom)
        func finish(_ f: FollowUp, _ rung: Rung, calls: Int, status: String) -> (FollowUp, AIRun) {
            var run = AIRun(feature: feature, executor: rung == .heuristic ? "heuristic" : "on_device", status: status)
            run.ladderRung = rung.rawValue
            run.guardrails = rung == .permissiveJSON ? "permissive" : rung == .guided ? "default" : nil
            run.variant = variant
            run.osBuild = Self.osBuild
            run.contextSize = contextSize
            run.sampling = rung == .heuristic ? nil : "greedy"
            run.promptVersion = Self.followUpPromptVersion + personalTag
            run.modelCalls = calls
            run.latencyMs = Int((ContinuousClock.now - start) / .milliseconds(1))
            run.localDay = localDay
            var out = f
            out.runId = run.id
            return (out, run)
        }
        guard status == .available else { return finish(twin, .heuristic, calls: 0, status: "unavailable") }

        let grounds = ([text] + known).joined(separator: "\n")
        let instructions = Self.voice + personalization
        let (base, permissive, stub, name) = (self.base, SystemLanguageModel(guardrails: .permissiveContentTransformations), self.stub, self.name)
        let task = { @Sendable (json: Bool, retry: Bool) in Self.followUpTask(text, verb: verb, exclude: exclude, json: json, retry: retry) }
        let walked = try? await Self.withTimeout(budget) {
            await Ladder.walk(
                permissive: { attempt in try await Self.ask(permissive, instructions, task(true, attempt > 0), Self.options, stub) },
                decode: { try Self.followUp(Ladder.decode(FollowUpOut.self, from: $0)) },
                guided: { attempt in
                    try await Self.followUp(Self.ask(FollowUpOut.self, base, instructions, task(false, attempt > 0), Self.options, stub))
                },
                prose: { [$0.observation, $0.question].compactMap { $0 }.joined(separator: "\n") },
                validate: { Self.acceptable($0, grounds: grounds, exclude: exclude, excludeObservations: excludeObservations, name: name) },
                fallback: twin)
        }
        guard let walked else { return finish(twin, .heuristic, calls: 1, status: "timeout") }
        return finish(walked.value, walked.rung, calls: walked.calls, status: walked.stop ?? "ok")
    }

    static func followUp(_ out: FollowUpOut) -> FollowUp {
        let observation = out.observation.map(trimmed).flatMap { $0.isEmpty ? nil : $0 }
        return FollowUp(observation: observation, question: trimmed(out.question), generator: "on_device")
    }

    static func followUpTask(_ text: String, verb: String, exclude: [String], json: Bool, retry: Bool) -> String {
        var parts = [verb == "said" ? "What the person just said, recording a video journal:\n\(text)" : "What the person wrote in their journal:\n\(text)"]
        if json {
            parts.append("""
            Reply with only a JSON object, no markdown, with exactly these keys:
            "observation": one short sentence in second person that only states something they \(verb), or null
            "question": one gentle open follow-up question about something they \(verb), under 20 words
            """)
        }
        if !exclude.isEmpty { parts.append("Ask a question that is not one of these:\n" + exclude.map { "- \($0)" }.joined(separator: "\n")) }
        if retry { parts.append(correction) }
        return parts.joined(separator: "\n\n")
    }

    /// One question, asked fresh, in the person's own nouns, and an observation that states and never asks.
    static func acceptable(_ out: FollowUp, grounds: String, exclude: [String], excludeObservations: [String], name: String?) -> Bool {
        let q = out.question
        guard q.hasSuffix("?"), q.count <= 200, q.filter({ $0 == "?" }).count == 1,
              !exclude.contains(where: { $0.caseInsensitiveCompare(q) == .orderedSame }),
              Heuristics.driftOK(generated: q, source: grounds), !Pipeline.quotesName(q, name) else { return false }
        guard let o = out.observation else { return true }
        return !o.contains("?") && o.count <= 160 && !excludeObservations.contains(o) && Heuristics.driftOK(generated: o, source: grounds)
            && !Pipeline.quotesName(o, name)
    }

    private static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\""))) }
}
