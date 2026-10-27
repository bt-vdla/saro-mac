import Foundation
import FoundationModels

func ms(_ start: ContinuousClock.Instant) -> Int {
    let d = ContinuousClock.now - start
    return Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
}

@Generable
struct DayInsight {
    @Guide(description: "Two or three sentences reflecting the day back in second person, using only what the entries say")
    var narrative: String
    @Guide(description: "Two short phrases copied exactly from the entries", .count(2))
    var quotes: [String]
    @Guide(.anyOf(["heavy", "low", "mixed", "steady", "light", "bright"]))
    var mood: String
    @Guide(description: "One gentle open question about something the writer mentioned")
    var question: String
}

let entries = [
    "Long day at work. Shipped the onboarding flow finally. Had chai with Ravi and we talked about his move to Pune. Feeling tired but good.",
    "It's been a year since Dad died. I keep picking up the phone to call him on Sundays. Today I cried in the car outside the grocery store and couldn't go in.",
    "I was so angry at my manager I wanted to punch the screen. I wrote an email I didn't send.",
    "This deadline is killing me. If I have to sit through one more status meeting I'll die.",
    "Had four drinks again tonight just to fall asleep. I know it's becoming a habit.",
]
let source = entries.joined(separator: "\n")
let norm = { (s: String) in s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }.trimmingCharacters(in: .whitespaces) }
func grounded(_ q: String) -> Bool { let n = norm(q); return !n.isEmpty && norm(source).contains(n) }

let instr = "You are Saro, a private journal. Reflect back only what the person said. Never invent facts, people or history. Never advise or diagnose."
let dayPrompt = "Today's entries:\n" + entries.map { "- " + $0 }.joined(separator: "\n") + "\n\nReflect the day back."
let greedy = GenerationOptions(samplingMode: .greedy)

print("== rung 1: @Generable, default guardrails ==")
var t = ContinuousClock.now
do {
    let r = try await LanguageModelSession(instructions: instr).respond(to: dayPrompt, generating: DayInsight.self, options: greedy)
    print("OK \(ms(t))ms", r.content.mood, r.content.quotes.map(grounded))
} catch { print("FAIL \(ms(t))ms:", error.localizedDescription) }

print("== rung 2: permissive String emitting JSON, decoded into the same @Generable type ==")
t = ContinuousClock.now
do {
    let session = LanguageModelSession(model: SystemLanguageModel(guardrails: .permissiveContentTransformations), instructions: instr)
    let r = try await session.respond(to: dayPrompt + """

    Reply with only a JSON object, no markdown, with keys: "narrative" (2-3 sentences, second person), "quotes" (array of exactly 2 phrases copied exactly from the entries), "mood" (one of heavy, low, mixed, steady, light, bright), "question" (one gentle open question).
    """, options: greedy)
    var raw = r.content.trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.hasPrefix("```") { raw = raw.components(separatedBy: "\n").dropFirst().filter { !$0.hasPrefix("```") }.joined(separator: "\n") }
    let insight = try DayInsight(GeneratedContent(json: raw))
    print("OK \(ms(t))ms mood=\(insight.mood) grounded=\(insight.quotes.map(grounded))")
    print("narrative:", insight.narrative)
    print("quotes:", insight.quotes)
    print("question:", insight.question)
} catch { print("FAIL \(ms(t))ms:", error) }

print("== rung 2b: same, streamed as String (time to first token) ==")
t = ContinuousClock.now
do {
    let session = LanguageModelSession(model: SystemLanguageModel(guardrails: .permissiveContentTransformations), instructions: instr)
    var first = -1
    let stream = session.streamResponse(to: dayPrompt + "\nWrite a short evening letter to the writer, in second person, quoting their words.", options: greedy)
    for try await snap in stream where first < 0 && !snap.content.isEmpty { first = ms(t) }
    let letter = try await stream.collect()
    print("first token \(first)ms, total \(ms(t))ms, \(letter.content.count) chars")
    print(letter.content.prefix(600))
} catch { print("FAIL \(ms(t))ms:", error) }
