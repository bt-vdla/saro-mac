import Foundation
import FoundationModels

@Generable
struct PersonPick {
    @Guide(description: "A person's name exactly as the writer wrote it")
    var name: String
    @Guide(description: "The number of a phrase that names them")
    var phrase: Int
}

@Generable
struct ThemePick {
    @Guide(.anyOf(Theme.allCases.map(\.rawValue)))
    var theme: String
    @Guide(description: "The number of a phrase that shows it")
    var phrase: Int
}

@Generable
struct MemoryOut {
    @Guide(description: "People the writer mentions by name; never a company, app, place or pet", .count(0...6))
    var people: [PersonPick]
    @Guide(description: "What the entry is about", .count(0...4))
    var themes: [ThemePick]
    @Guide(description: "Numbers of the phrases where the writer says what they mean to do", .count(0...4))
    var intentions: [Int]
}

/// One thing the model picked out of an entry, tied to a numbered phrase so its quote stays verbatim (DR-09).
public struct ExtractedObservation: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case person(String), theme(Theme), intention }

    public let kind: Kind
    public let candidate: Candidate
}

extension SaroAI {
    public static let memoryPromptVersion = "memory-1"
    static let memoryInstructions = voice + " You list who and what one journal entry mentions, using only the writer's own words."

    /// The model rung of memory extraction: a guided call (default guardrails; never the permissive rung, so a heavy
    /// entry ends on a guardrail and the heuristic twin reads it instead) that picks people, themes and intentions by
    /// phrase number. A name that isn't in the phrase it cites, or isn't a name, rejects the whole reply. Nil means
    /// fall back to the heuristic twin; the provenance says why.
    public func extractMemory(text: String, candidates: [Candidate]) async -> ([ExtractedObservation]?, Provenance) {
        let start = ContinuousClock.now
        func provenance(_ rung: Rung, _ calls: Int, _ status: String) -> Provenance {
            Provenance(executor: rung == .heuristic ? "heuristic" : "on_device", rung: rung, guardrails: rung == .guided ? "default" : nil,
                       variant: variant, osBuild: Self.osBuild, contextSize: contextSize, promptVersion: Self.memoryPromptVersion,
                       tokensIn: nil, modelCalls: calls, latencyMs: Int((ContinuousClock.now - start) / .milliseconds(1)), status: status)
        }
        guard status == .available, !candidates.isEmpty else { return (nil, provenance(.heuristic, 0, "ok")) }
        // ponytail: a fixed 6,000-character cut (~1,500 tokens) instead of fit(); journal entries rarely come close.
        let prompt = Self.memoryTask(Ladder.truncated(text, maxChars: 6000), candidates)
        let (base, stub, source) = (self.base, self.stub, text)
        let result = await Ladder.walk(
            permissive: nil,
            decode: { _ in nil as [ExtractedObservation]? },
            guided: { attempt in
                Self.picks(try await Self.ask(MemoryOut.self, base, Self.memoryInstructions,
                                              attempt > 0 ? prompt + "\n\n" + Self.correction : prompt, stub),
                           candidates: candidates, source: source)
            },
            prose: { picks in (picks ?? []).map { if case .person(let n) = $0.kind { n } else { $0.candidate.text } }.joined(separator: "\n") },
            validate: { $0 != nil },
            fallback: nil)
        return (result.value, provenance(result.rung, result.calls, result.stop ?? "ok"))
    }

    static func memoryTask(_ text: String, _ candidates: [Candidate]) -> String {
        """
        Numbered phrases from the entry:
        \(Ladder.numbered(candidates))

        Entry:
        \(text)

        List the people the writer names, what the entry is about, and the phrases where the writer says what they mean \
        to do. Use only numbers from the list.
        """
    }

    /// The reply checked against the phrases it cites; nil when any part of it isn't grounded.
    static func picks(_ out: MemoryOut, candidates: [Candidate], source: String) -> [ExtractedObservation]? {
        let byIndex = Dictionary(candidates.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
        var out2: [ExtractedObservation] = []
        for p in out.people {
            let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let c = byIndex[p.phrase], isName(name, in: c.text), source.contains(c.text) else { return nil }
            out2.append(ExtractedObservation(kind: .person(name), candidate: c))
        }
        for t in out.themes {
            guard let theme = Theme(rawValue: t.theme.lowercased()), let c = byIndex[t.phrase] else { return nil }
            out2.append(ExtractedObservation(kind: .theme(theme), candidate: c))
        }
        for i in out.intentions {
            guard let c = byIndex[i] else { return nil }
            // Only a phrase that says what they mean to do in so many words is an intention; the rest of the reply stands.
            if MemoryRules.intention(in: c.text) != nil { out2.append(ExtractedObservation(kind: .intention, candidate: c)) }
        }
        return out2
    }

    /// A capitalised word or two the phrase spells exactly, and not a brand, a relation or a word like "Someone".
    static func isName(_ name: String, in phrase: String) -> Bool {
        let parts = name.split(separator: " ").map(String.init)
        guard (1...3).contains(parts.count), parts.allSatisfy({ $0.first?.isUppercase == true }),
              !parts.contains(where: { MemoryRules.brands.contains($0.lowercased()) || MemoryRules.notNames.contains($0.lowercased())
                  || MemoryRules.isRelation($0) }) else { return false }
        return Heuristics.tokenize(phrase).map(\.text).joined(separator: " ").range(of: "\\b\(NSRegularExpression.escapedPattern(for: name))\\b",
                                                                                   options: .regularExpression) != nil
    }
}
