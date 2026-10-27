import Foundation
import Testing
@testable import SaroKit

private let neutralEntry = "Long day at work. Shipped the onboarding flow finally. Had chai with Ravi and we talked about his move to Pune. Feeling tired but good."
let hinglishEntry = "Aaj bahut thak gayi hoon. Office mein sab kuch galat ho raha hai, mann nahi lag raha kisi cheez mein."

// MARK: - ai.test.ts ports

@Test func compressTitleCases() {
    #expect(Heuristics.compressTitle("Honestly, the launch is taking up all the space. More later.") == "Launch is taking up all the space")
    #expect(Heuristics.compressTitle("Just got back from a run, only three kilometres.") == "Got back from a run")
    #expect(Heuristics.compressTitle("Slept badly again, maybe four hours.") == "Slept badly again")
    #expect(Heuristics.compressTitle("Probably Maya laughing at dinner tonight when she knocked the salt over.") == "Maya laughing at dinner tonight")
    #expect(Heuristics.compressTitle("I want to carry the calm from this week into the next one.") == "I want to carry the calm")
    #expect(Heuristics.compressTitle("um, okay.") == "Um okay")
    #expect(Heuristics.compressTitle("") == "")
    for t in ["Third night in a row I was awake at 3am running through the launch checklist.", "a b c d e f g h i j"] {
        #expect(Heuristics.compressTitle(t).split(separator: " ").count <= 7, "\(t)")
    }
}

@Test func firstSentenceCases() {
    #expect(Heuristics.firstSentence("We launched this morning. Nothing broke.") == "We launched this morning.")
    let s = Heuristics.firstSentence(String(repeating: "word ", count: 60) + "end.")
    #expect(s.utf16.count <= 160)
    #expect(s.hasSuffix("…"))
    #expect(Heuristics.firstSentence("no punctuation at all") == "no punctuation at all")
}

@Test func extractPhraseIsShortVerbatimAndNearFocus() throws {
    let text = "Third night in a row I was awake at 3am running through the launch checklist in my head. I know none of it can be fixed at that hour."
    let phrase = try #require(Heuristics.extractPhrase(text, focus: Heuristics.analyzeText(text).focus))
    #expect(text.contains(phrase))
    #expect(phrase.split(separator: " ").count <= 8)
    #expect(["awake", "3am", "launch"].contains { phrase.contains($0) })
    #expect(Heuristics.extractPhrase("") == nil)
    #expect(Heuristics.extractPhrase("Hi.") == nil)
}

@Test func extractPhraseIsAlwaysASubstring() {
    let texts = [neutralEntry, hinglishEntry, "Honestly, I think, you know, it was fine — mostly.\n\nThen “Maya” said it’s okay; we’ll see 🙂 tomorrow.",
                 "मैं आज बहुत थक गई हूँ, पर शाम अच्छी थी।", String(repeating: "and so we kept walking along the river ", count: 6)]
    for text in texts {
        if let p = Heuristics.extractPhrase(text, focus: Heuristics.analyzeText(text).focus) { #expect(text.contains(p), "\(p)") }
    }
}

@Test func analyzeTextThemesMoodsNegationNames() {
    let s = Heuristics.analyzeText("My sister Maya called. I slept badly and felt anxious about the launch, but the run left me calm and calm again.")
    #expect(s.themes.first == .family)
    #expect([.sleep, .work, .health].allSatisfy(s.themes.contains))
    #expect(s.moods.prefix(2) == [.calm, .anxious])
    #expect(s.names == ["Maya"])
    #expect(Heuristics.analyzeText("I wasn't anxious at all.").moods.isEmpty)
    #expect(Heuristics.analyzeText("Totally burnt out and fed up.").moods.first == .overwhelmed)
    #expect(Heuristics.analyzeText("").moods.isEmpty)
}

@Test func entryMood() {
    #expect(Heuristics.entryMoodFor("The run left me calm.") == .calm)
    #expect(Heuristics.entryMoodFor("Felt calm, but I want to die.") == nil)
    #expect(Heuristics.entryMoodFor("  ") == nil)
    #expect(Heuristics.entryMoodFor("Bought groceries.") == nil)
}

// MARK: - Candidates and readings

@Test func candidatesAreVerbatimWithRoundTrippingSpans() {
    let text = "Honestly, it was a strange day 🙂. Had “chai” with Ravi—he’s moving to Pune!\n\nमैं आज बहुत थक गई हूँ, पर शाम अच्छी थी। " +
        String(repeating: "We walked, we talked, we laughed at nothing. ", count: 10)
    let cs = Heuristics.candidates(entryId: "e1", field: "body", text: text, firstIndex: 5)
    #expect(!cs.isEmpty && cs.count <= Heuristics.maxCandidates)
    #expect(cs.map(\.index) == Array(5..<5 + cs.count))
    for c in cs {
        let utf16 = Array(text.utf16)
        #expect(String(decoding: utf16[c.utf16From..<c.utf16To], as: UTF16.self) == c.text)
        #expect((text as NSString).substring(with: NSRange(location: c.utf16From, length: c.utf16To - c.utf16From)) == c.text)
        #expect((c.entryId, c.field) == ("e1", "body"))
    }
    #expect(cs.contains { $0.text == "Honestly, it was a strange day 🙂." })
    #expect(cs.contains { $0.text.contains("थक") })
    #expect(cs == Heuristics.candidates(entryId: "e1", field: "body", text: text, firstIndex: 5))
    #expect(Heuristics.candidates(entryId: "e", field: "body", text: "").isEmpty)
}

@Test func heuristicEntryReading() throws {
    let cs = Heuristics.candidates(entryId: "e1", field: "body", text: neutralEntry)
    let r = Heuristics.heuristicReading(text: neutralEntry, candidates: cs)
    #expect(r.title == "Long day at work")
    #expect(r.summary == "Long day at work.")
    #expect(r.mood == .neutral)
    #expect(cs.map(\.text).contains("Long day at work") && !cs.map(\.text).contains("Long day at work."))
    let q = try #require(r.quoteIndex)
    #expect(cs.contains { $0.index == q })
    #expect(Heuristics.heuristicReading(text: "The run left me calm and happy, calm again.", candidates: []).mood == .calm)
}

@Test func heuristicDayReading() throws {
    let a = "Slept badly and felt anxious about the launch.", b = "Walked by the river after work and felt calm.", c = "Calm evening."
    let cs = Heuristics.candidates(entryId: "a", field: "body", text: a)
        + Heuristics.candidates(entryId: "b", field: "body", text: b, firstIndex: 50)
        + Heuristics.candidates(entryId: "c", field: "body", text: c, firstIndex: 100)
    let digests = [EntryDigest(entryId: "a", kind: "reflection", time: "08:00", title: "Slept badly", summary: a, mood: .anxious),
                   EntryDigest(entryId: "b", kind: "reflection", time: "18:00", title: "Walked by the river", summary: b, mood: .calm),
                   EntryDigest(entryId: "c", kind: "reflection", time: "21:00", title: "Calm evening", summary: c, mood: .calm)]
    let day = Heuristics.heuristicDayReading(digests: digests, candidates: cs)
    #expect(day.mood == .calm)
    #expect((1...2).contains(day.quoteIndexes.count))
    let picked = day.quoteIndexes.map { i in cs.first { $0.index == i }! }
    #expect(Set(picked.map(\.entryId)).count == picked.count)
    #expect(day.narrative == nil)
    let question = try #require(day.question)
    #expect(Lexicon.questions.values.contains { $0.contains(question) })
    #expect(day == Heuristics.heuristicDayReading(digests: digests, candidates: cs))
    #expect(Heuristics.heuristicDayReading(digests: [], candidates: []).mood == .neutral)
    let long = "Third night in a row I was awake at 3am running through the launch checklist in my head. I know none of it can be fixed."
    let longCs = Heuristics.candidates(entryId: "l", field: "body", text: long)
    let first = try #require(Heuristics.heuristicDayReading(digests: [], candidates: longCs).quoteIndexes.first)
    #expect(longCs[first].text == "awake at 3am running through the launch checklist")
}

// MARK: - Drift

@Test func driftRejectsInventedNounsAndHinglish() {
    #expect(!Heuristics.driftOK(generated: "the end of a long shift", source: neutralEntry))
    #expect(!Heuristics.driftOK(generated: "Thakawat aur asuvidha", source: hinglishEntry))
    #expect(!Heuristics.driftOK(generated: "You had chai with Priya.", source: neutralEntry))
    #expect(!Heuristics.driftOK(generated: "You walked 5 km after work.", source: neutralEntry))
    #expect(!Heuristics.driftOK(generated: "Your mom called about the move.", source: neutralEntry))
    #expect(!Heuristics.driftOK(generated: "You've been tired lately.", source: neutralEntry))
    #expect(!Heuristics.driftOK(generated: "Remember to rest after work.", source: neutralEntry))
    #expect(!Heuristics.driftOK(generated: "A long day at the hospital.", source: neutralEntry))
}

@Test func driftAcceptsGroundedProse() {
    #expect(Heuristics.driftOK(generated: "You shipped the onboarding flow and had chai with Ravi.", source: neutralEntry))
    #expect(Heuristics.driftOK(generated: "You pushed through chai with Ravi.", source: neutralEntry))
    #expect(Heuristics.driftOK(generated: "A long day at work, tired but good, with a quiet sense of relief.", source: neutralEntry))
    #expect(Heuristics.driftOK(generated: "Ravi's move to Pune", source: neutralEntry))
    #expect(Heuristics.driftOK(generated: "You finally shipped the onboarding flow, then caught up with Ravi over chai about his move to Pune.",
                               source: neutralEntry))
    #expect(Heuristics.driftOK(generated: "What did it feel like to finally ship the onboarding flow?", source: neutralEntry))
    #expect(Heuristics.driftOK(generated: "Thak gayi hoon", source: hinglishEntry))
    #expect(Heuristics.driftOK(generated: "Slept badly again", source: "Slept badly again, maybe four hours."))
}

// MARK: - Letter

func quote(_ index: Int, _ text: String) -> Candidate {
    Candidate(index: index, entryId: "r1", field: "body", text: text, utf16From: 0, utf16To: text.utf16.count)
}

@Test func letterFromNarrativeOrTemplate() throws {
    let cs = [quote(0, "awake at 3am"), quote(1, "the run left me calm")]
    let withNarrative = try #require(Letter(reading: DayReading(mood: .calm, quoteIndexes: [1], question: " What helped? ",
                                                                narrative: " You wrote \"the run left me calm\". "), candidates: cs))
    #expect(withNarrative.paragraphs == ["You wrote \"the run left me calm\"."])
    #expect(withNarrative.quotes == [cs[1]])
    #expect((withNarrative.mood.rawValue, withNarrative.mood.summary) == ("Calm", "Settled and present, without the noise."))
    #expect(withNarrative.question == "What helped?")
    #expect(withNarrative.signOff == "— Saro")

    let templated = try #require(Letter(reading: DayReading(mood: .tender, quoteIndexes: [0, 1], question: ""), candidates: cs))
    #expect(templated.paragraphs == ["In your words today: \"awake at 3am\" and \"the run left me calm\"."])
    #expect(templated.question == nil)
    #expect(Letter(reading: DayReading(mood: .calm, quoteIndexes: [0]), candidates: [quote(0, "We launched.")])?.paragraphs
        == ["In your words today: \"We launched.\""])
    #expect(Letter(reading: DayReading(mood: .calm, quoteIndexes: []), candidates: cs) == nil)
    #expect(Letter(reading: DayReading(mood: .calm, quoteIndexes: [9], narrative: "  "), candidates: cs) == nil)
}

@Test func letterSegmentsAndTypeset() {
    let q = quote(0, "awake at 3am")
    #expect(Letter.segments("You wrote \"awake at 3am\". Then \"other\".", quotes: [q]) == [
        Letter.Segment(text: "You wrote "), Letter.Segment(text: "\"awake at 3am\"", quote: q), Letter.Segment(text: ". Then \"other\"."),
    ])
    let a = quote(1, "first one"), b = quote(2, "second")
    #expect(Letter.segments("“second” then \"first one\"", quotes: [a, b]).map(\.quote?.text) == ["second", nil, "first one"])
    #expect(Letter.segments("No quotes here.", quotes: [q]) == [Letter.Segment(text: "No quotes here.")])
    #expect(Letter.typeset("You said \"it's fine\".") == "You said “it’s fine”.")
    #expect(Letter.typeset("\"Quote\" opens (\"here\")") == "“Quote” opens (“here”)")
}
