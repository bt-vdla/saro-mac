import Foundation

/// Saro's follow-up at a checkpoint or under a page, and the observation line over it.
public struct FollowUp: Sendable, Hashable {
    /// One line that only states what was said ("You mentioned Maya."); nil when there's nothing new to state.
    public var observation: String?
    public var question: String
    /// `on_device` or `heuristic`.
    public var generator: String
    /// The content-free ai_run behind it.
    public var runId: String?

    public init(observation: String?, question: String, generator: String, runId: String? = nil) {
        self.observation = observation
        self.question = question
        self.generator = generator
        self.runId = runId
    }
}

/// The heuristic twin of reflect_deeper and reflect_further (ai.ts FOLLOW_UPS, PHRASELESS_FOLLOW_UPS, followUp,
/// observations): templates around a verbatim phrase of the person's own, and lines that only count and name what they
/// said. Deterministic: the same words and seed always give the same question, so it never invents anything.
public enum FollowUps {
    /// `{p}` is a verbatim phrase, `{verb}` said or wrote.
    static let templates: [Theme?: [String]] = [
        .work: ["You {verb} “{p}”. What part of that is yours to carry, and what isn’t?", "Thinking about “{p}”, what would ‘enough’ look like here?"],
        .family: ["You {verb} “{p}”. What do you wish they knew about how you feel?", "Thinking about “{p}”, what would you like more of with them?"],
        .sleep: ["You mentioned “{p}”. What tends to keep your mind busy at night?", "Thinking about “{p}”, what would make tonight a little easier?"],
        .health: ["You {verb} “{p}”. How does your body feel as you think about it?", "Thinking about “{p}”, what is your body asking for right now?"],
        .creativity: ["You {verb} “{p}”. What would it take to follow that a little further?", "Thinking about “{p}”, what would you make if no one had to see it?"],
        .relationships: ["You {verb} “{p}”. What would you like more of in that relationship?", "Thinking about “{p}”, what do you need from them right now?"],
        .money: ["You {verb} “{p}”. What would feeling a little safer look like here?", "Thinking about “{p}”, which part of this is in your hands?"],
        .purpose: ["You {verb} “{p}”. What does that tell you about what matters to you?", "Thinking about “{p}”, where does that want to take you?"],
        .nature: ["You mentioned “{p}”. What did that place give you?", "Thinking about “{p}”, when could you get more of that?"],
        .learning: ["You {verb} “{p}”. What are you curious to understand next?", "Thinking about “{p}”, what would you like to get better at?"],
        nil: ["You {verb} “{p}”. What’s underneath that?", "Thinking about “{p}”, what would it look like to give that more room?",
              "You {verb} “{p}”. What are you hoping for there?", "You {verb} “{p}”. What else is true about that?"],
    ]

    /// When no phrase of theirs can be held up, an open question that quotes nothing.
    public static let phraseless = [
        "What else comes up when you stay with that?",
        "What would you like to remember about this?",
        "Is there anything you haven’t said yet?",
    ]

    /// A question around a phrase of `text` (or of `phraseFrom`, the newest answer under a page), from the first theme pool
    /// with one not in `exclude`, then the general pool; with no phrase, an open one. Repeating beats inventing one.
    public static func followUp(_ text: String, verb: String, exclude: [String], seed: Int, phraseFrom: String? = nil) -> String {
        let signals = Heuristics.analyzeText(text)
        guard let phrase = Heuristics.extractPhrase(phraseFrom ?? text, focus: signals.focus), !SafetyGate.phraseHit(phrase) else {
            return pick([phraseless], seed: seed, exclude: exclude) ?? phraseless[seed % phraseless.count]
        }
        let fill = { (t: String) in t.replacingOccurrences(of: "{p}", with: phrase).replacingOccurrences(of: "{verb}", with: verb) }
        let pools = (signals.themes.compactMap { templates[$0] } + [templates[nil]!]).map { $0.map(fill) }
        return pick(pools, seed: seed, exclude: exclude) ?? pools[pools.count - 1][seed % pools[pools.count - 1].count]
    }

    /// Lines that only state what was said: the theme they came back to, the people they named, a feeling word they
    /// used, and how many words it was.
    public static func observations(_ text: String) -> [String] {
        let signals = Heuristics.analyzeText(text)
        let tokens = Heuristics.tokenize(text)
        var out: [String] = []
        if let top = signals.themes.first {
            let n = signals.themeCounts[top] ?? 0
            out.append(n > 1 ? "You came back to \(top.rawValue) \(n == 2 ? "twice" : "\(n) times") there." : "You touched on \(top.rawValue).")
        }
        out += signals.names.prefix(2).map { "You mentioned \($0)." }
        if let word = feelingWord(tokens) { out.append("You used the word “\(word)”.") }
        out.append("That was \(tokens.count) \(tokens.count == 1 ? "word" : "words").")
        return out
    }

    /// The twin's whole answer: the question, and the first observation not shown earlier this session.
    public static func twin(_ text: String, verb: String, exclude: [String], excludeObservations: [String], seed: Int,
                            phraseFrom: String? = nil) -> FollowUp {
        let lines = observations(text)
        return FollowUp(observation: pick([lines], seed: seed, exclude: excludeObservations),
                        question: followUp(text, verb: verb, exclude: exclude, seed: seed, phraseFrom: phraseFrom), generator: "heuristic")
    }

    public static func seed(_ s: String) -> Int { Heuristics.seed(s) }

    static func pick(_ pools: [[String]], seed: Int, exclude: [String]) -> String? {
        for pool in pools {
            let open = pool.filter { !exclude.contains($0) }
            if !open.isEmpty { return open[seed % open.count] }
        }
        return nil
    }

    /// The first feeling word that isn't negated, as said (a two-word one too: "too much").
    private static func feelingWord(_ tokens: [Token]) -> String? {
        for (i, t) in tokens.enumerated() {
            let bigram = i + 1 < tokens.count ? "\(t.lower) \(tokens[i + 1].lower)" : ""
            let surface = Lexicon.emotionIndex[bigram] != nil ? bigram : Lexicon.emotionIndex[t.lower] != nil ? t.lower : nil
            guard let surface, !tokens[max(0, i - 3)..<i].contains(where: { Lexicon.negators.contains($0.lower) }) else { continue }
            return surface
        }
        return nil
    }
}
