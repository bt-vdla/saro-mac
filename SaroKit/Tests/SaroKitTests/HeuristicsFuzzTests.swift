import Foundation
import Testing
@testable import SaroKit

/// SplitMix64, so every run fuzzes the same texts.
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Synthetic pieces (SR-28): English, Hinglish, Devanagari, CJK, emoji sequences, keycaps, combining marks, CRLF.
private let pieces = [
    "I", "think", "the", "launch", "felt", "calm", "anxious", "work", "sister", "Maya", "Ravi", "chai", "slept", "badly", "again",
    "3am", "5k", "not", "honestly", "you know", "bahut", "thak", "gayi", "मैं", "थक", "हूँ", "शाम", "क्षि", "我今天很累", "开心",
    "🙂", "👨‍👩‍👧", "👍🏽", "🇮🇳", "#️⃣", "1️⃣", "café", "e\u{301}te\u{301}", "it’s", "don't", "well-being",
    "—", "–", ",", ".", "!", "?", ";", ":", "(", ")", "\"", "“", "”", "'", "…", "।", "\r\n", "\n\n", "\n", "\t", " ", " ", " ",
]

private let edges = [
    "", " \n\t ", ".", "?!...", "—", "\"\"", "🙂", "Hello", "Hello.", "one word", "#️⃣ is a keycap and so is 1️⃣",
    "Tired.\r\nVery tired.\r\n", String(repeating: "🙂", count: 200), String(repeating: "क्षि", count: 100), String(repeating: "!", count: 200),
    String(repeating: "x", count: 158) + "🙂🙂🙂 end", String(repeating: "word ", count: 100), String(repeating: "我", count: 400),
    String(repeating: "We walked, we talked. ", count: 40),
]

private let texts: [String] = edges + {
    var rng = SplitMix(state: 28)
    return (0..<400).map { _ in
        let n = Int.random(in: 0...90, using: &rng), glue = Bool.random(using: &rng) ? " " : ""
        return (0..<n).map { _ in pieces.randomElement(using: &rng)! }.joined(separator: glue)
    }
}()

/// True when a UTF-16 offset falls between two whole characters of `text`.
private func onCharacter(_ text: String, _ utf16: Int) -> Bool {
    String.Index(utf16Offset: utf16, in: text).samePosition(in: text) != nil
}

// MARK: - Fuzz

@Test func fuzzedCandidatesAreWholeCharacterSpans() {
    for text in texts {
        let cs = Heuristics.candidates(entryId: "e", field: "body", text: text, firstIndex: 3)
        let utf16 = Array(text.utf16)
        #expect(cs.count <= Heuristics.maxCandidates)
        #expect(cs.map(\.index) == Array(3..<3 + cs.count))
        #expect(cs == Heuristics.candidates(entryId: "e", field: "body", text: text, firstIndex: 3))
        for c in cs {
            guard 0 <= c.utf16From, c.utf16From < c.utf16To, c.utf16To <= utf16.count else {
                Issue.record("span out of bounds: \(c) in \(text.debugDescription)")
                continue
            }
            #expect(String(decoding: utf16[c.utf16From..<c.utf16To], as: UTF16.self) == c.text)
            #expect(onCharacter(text, c.utf16From) && onCharacter(text, c.utf16To), "\(c.text.debugDescription) in \(text.debugDescription)")
            #expect(c.text.first?.isWhitespace == false && c.text.last?.isWhitespace == false)
        }
    }
    #expect(Heuristics.candidates(entryId: "e", field: "body", text: String(repeating: "We walked, we talked. ", count: 40)).count
        == Heuristics.maxCandidates)
}

@Test func fuzzedEntryReadingsOnlyUseTheEntrysWords() {
    for text in texts {
        let words = Set(Heuristics.tokenize(text).map { $0.text.lowercased() })
        let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let cs = Heuristics.candidates(entryId: "e", field: "body", text: text)
        let r = Heuristics.heuristicReading(text: text, candidates: cs)
        let title = Heuristics.tokenize(r.title)
        #expect(title.count <= 7)
        #expect(title.allSatisfy { words.contains($0.text.lowercased()) }, "\(r.title.debugDescription) from \(text.debugDescription)")
        #expect(r.summary.utf16.count <= 160)
        #expect(clean.hasPrefix(r.summary) || r.summary.hasSuffix("…") && clean.hasPrefix(r.summary.dropLast()),
                "\(r.summary.debugDescription) from \(text.debugDescription)")
        #expect(r.quoteIndex.map { i in cs.contains { $0.index == i } } ?? cs.isEmpty)
        #expect(r == Heuristics.heuristicReading(text: text, candidates: cs))
        if let p = Heuristics.extractPhrase(text, focus: Heuristics.analyzeText(text).focus) {
            #expect(text.contains(p), "\(p.debugDescription) from \(text.debugDescription)")
            #expect((2...10).contains(Heuristics.tokenize(p).count))
        }
    }
}

@Test func fuzzedDayReadingsAndLettersKeepTheirQuotes() {
    let questions = Set(Lexicon.questions.values.joined())
    for i in stride(from: 0, to: texts.count - 2, by: 3) {
        var cs: [Candidate] = [], digests: [EntryDigest] = []
        for (j, text) in texts[i..<i + 3].enumerated() {
            let entry = Heuristics.candidates(entryId: "e\(j)", field: "body", text: text, firstIndex: cs.count)
            let r = Heuristics.heuristicReading(text: text, candidates: entry)
            cs += entry
            digests.append(EntryDigest(entryId: "e\(j)", kind: "reflection", time: "09:00", title: r.title, summary: r.summary, mood: r.mood))
        }
        let day = Heuristics.heuristicDayReading(digests: digests, candidates: cs)
        let picked = day.quoteIndexes.compactMap { q in cs.first { $0.index == q } }
        #expect(picked.count == day.quoteIndexes.count && picked.count <= 2 && Set(picked).count == picked.count)
        #expect(picked.isEmpty == cs.isEmpty)
        if picked.count == 2, picked[0].entryId == picked[1].entryId {
            #expect(picked[0].utf16To <= picked[1].utf16From || picked[1].utf16To <= picked[0].utf16From)
        }
        #expect(day.narrative == nil && day.moodBasis == nil)
        #expect(day.question.map(questions.contains) == true)
        #expect(digests.contains { $0.mood == day.mood })
        #expect(day == Heuristics.heuristicDayReading(digests: digests, candidates: cs))

        guard let letter = Letter(reading: day, candidates: cs) else {
            #expect(picked.isEmpty)
            continue
        }
        let typed = Letter.typeset(letter.paragraphs[0])
        let segments = Letter.segments(typed, quotes: letter.quotes)
        #expect(segments.map(\.text).joined() == typed)
        #expect(Set(segments.compactMap(\.quote)) == Set(letter.quotes), "\(typed)")
        for q in letter.quotes {
            #expect(Letter.segments(Letter.typeset("“\(q.text)”"), quotes: [q]).contains { $0.quote == q }, "\(q.text)")
        }
    }
}

// MARK: - Edge cases

@Test func firstSentenceNeverSplitsACharacter() {
    #expect(Heuristics.firstSentence("") == "")
    #expect(Heuristics.firstSentence(" \n\t ") == "")
    #expect(Heuristics.firstSentence("Hello") == "Hello")
    #expect(Heuristics.firstSentence("?!...") == "?!...")
    #expect(Heuristics.firstSentence("Line one\r\nLine two.\r\nLine three.") == "Line one Line two.")
    #expect(Heuristics.firstSentence(String(repeating: "x", count: 158) + "🙂🙂🙂 end") == String(repeating: "x", count: 158) + "…")
    #expect(Heuristics.firstSentence(String(repeating: "🙂", count: 200)) == String(repeating: "🙂", count: 79) + "…")
    let devanagari = String(repeating: "क्षि", count: 100), cut = Heuristics.firstSentence(devanagari)
    #expect(cut.hasSuffix("…") && cut.utf16.count <= 160 && devanagari.hasPrefix(cut.dropLast()))
}

@Test func keycapsAndDandasDontBreakWords() throws {
    #expect(Heuristics.tokenize("#️⃣ is 1️⃣").map(\.text) == ["is", "1️⃣"])
    #expect(Heuristics.compressTitle("#️⃣ is a keycap") == "Is a keycap")
    #expect(Heuristics.extractPhrase("#️⃣ is a keycap") == "is a keycap")
    #expect(Heuristics.candidates(entryId: "k", field: "body", text: "#️⃣ is a keycap").map(\.text) == ["#️⃣ is a keycap", "is a keycap"])

    let hindi = "पहला वाक्य यहाँ है। दूसरा वाक्य थोड़ा लंबा है।"
    #expect(Heuristics.firstSentence(hindi) == "पहला वाक्य यहाँ है।")
    #expect(Heuristics.compressTitle(hindi) == "पहला वाक्य यहाँ है")
    #expect(!Heuristics.candidates(entryId: "h", field: "body", text: hindi).contains { $0.text.contains("। ") })
    let letter = try #require(Letter(reading: DayReading(mood: .calm, quoteIndexes: [0]), candidates: [quote(0, "शाम अच्छी थी।")]))
    #expect(letter.paragraphs == ["In your words today: \"शाम अच्छी थी।\""])
}

@Test func titlesAndPhrasesFromTinyOrHugeTexts() {
    for t in ["", "?!...", "🙂🙂", "—"] {
        #expect(Heuristics.compressTitle(t) == "")
        #expect(Heuristics.extractPhrase(t) == nil)
    }
    #expect(Heuristics.compressTitle("Hello") == "Hello")
    #expect(Heuristics.extractPhrase("Hello") == nil)
    let long = String(repeating: "word ", count: 100)
    #expect(Heuristics.compressTitle(long).split(separator: " ").count == 7)
    #expect(Heuristics.extractPhrase(long)?.split(separator: " ").count == 8)
}

@Test func typesetQuotesStillLinkToTheirEntry() throws {
    let q = quote(0, "it's fine, I'm \"done\"")
    let letter = try #require(Letter(reading: DayReading(mood: .calm, quoteIndexes: [0]), candidates: [q]))
    #expect(Letter.segments(Letter.typeset(letter.paragraphs[0]), quotes: [q]).map(\.quote) == [nil, q, nil])
    #expect(Letter.segments(Letter.typeset("“\(q.text)”"), quotes: [q]).map(\.quote) == [q])
}

// MARK: - Drift tables (§11.6)

private let workday = "Long day at work. Shipped the onboarding flow finally. Had chai with Ravi and we talked about his move to Pune. Feeling tired but good."

@Test(arguments: [
    "What would rest look like after a long day at work?", "You can't always rest after a long day at work.",
    "You won't forget shipping the onboarding flow.", "Can't stop thinking about Ravi's move.", "You couldn’t rest after work.",
    "How did it feel to finally ship the onboarding flow?", "What did talking with Ravi about his move bring up?",
    "Which moment with Ravi stayed with you?", "How are you feeling about Ravi’s move to Pune?", "Work was long, and chai with Ravi helped.",
    "You felt tired but good.",
])
func driftAcceptsGroundedProse(_ generated: String) {
    #expect(Heuristics.driftOK(generated: generated, source: workday))
}

@Test(arguments: [
    // Proper nouns
    "You and Ravi went to Mumbai.", "Ravi and Priya talked about Pune.",
    // Numbers
    "You worked ten hours.", "You drank three cups of chai.", "You talked twice.", "You shipped it a fourth time.",
    "The onboarding flow launched to 500 users.", "You shipped it at 3am.",
    // Relationship words
    "You had chai with Ravi's sister.", "Ravi's wife came too.", "You talked with your friend Ravi.",
    // History words
    "Ravi moved to Pune last week.", "You and Ravi have been close lately.", "You were tired again.",
    // Banned phrases
    "Remember to rest.", "You should rest.", "It's okay to rest after work.", "it's ok to rest after work.", "It is okay to rest.",
    "Self-care matters.",
    // Invented nouns
    "You had coffee with Ravi.", "You had chai at the cafe.", "You took the train home.", "Long day at the gym.",
    "You shipped the payments flow.", "You shipped the onboarding flow on Friday.",
])
func driftRejectsUngroundedProse(_ generated: String) {
    #expect(!Heuristics.driftOK(generated: generated, source: workday))
}

@Test func driftHinglishTable() {
    for g in ["Office mein sab galat", "Bahut thak gayi aaj", "Mann nahi lag raha", "You felt tired at the office."] {
        #expect(Heuristics.driftOK(generated: g, source: hinglishEntry), "\(g)")
    }
    for g in ["Kaam bahut tha", "Yaar, bahut thak gayi", "Wo thak gaya."] {
        #expect(!Heuristics.driftOK(generated: g, source: hinglishEntry), "\(g)")
    }
}
