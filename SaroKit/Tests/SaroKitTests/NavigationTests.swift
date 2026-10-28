import Foundation
import Testing
@testable import SaroKit

// MARK: Search (ports of the web's lib/search tests; synthetic text only, SR-28)

private func at(_ iso: String) -> Date { (try? Date(iso, strategy: .iso8601)) ?? .distantPast }

private func fixtureDoc(_ id: String, _ kind: EntryKind, _ day: String, _ time: String, title: String? = nil, summary: String? = nil,
                        body: String? = nil, transcript: String? = nil, tags: [String] = [], extra: String? = nil) -> SearchDoc {
    SearchDoc(id: id, kind: kind, day: day, capturedAt: at("\(day)T\(time):00Z"), title: title, summary: summary, body: body,
              transcript: transcript, tags: tags, extra: extra)
}

/// The web's journalFixture; its commitments are writings here, and its HTML body is plain text.
private let journal: [SearchDoc] = [
    fixtureDoc("v1", .moment, "2025-01-05", "19:12", title: "Sunday call with Maya",
               summary: "Caught up with my sister Maya about her new job in Lisbon and how Mum is doing.",
               transcript: "So I called Maya tonight. My sister always knows when something's off. We talked about her new job in Lisbon, about Mum's knee, and she made me promise to actually take a day off after the launch.",
               tags: ["family", "sister", "gratitude"]),
    fixtureDoc("e1", .voice, "2025-01-09", "02:14", title: "Two in the morning again",
               transcript: "It's 2am and I can't sleep. The launch is Thursday and my brain keeps running through the checklist. I tried the breathing thing Maya taught me. Didn't help much. Going to try reading instead.",
               tags: ["sleep", "anxiety", "work"]),
    fixtureDoc("r1", .reflection, "2025-01-10", "21:40", title: "Launch day",
               body: "We shipped it. The work launch went live at 9:03 and nothing caught fire. I felt proud of the team & weirdly calm. Celebrated with tacos.",
               tags: ["work", "launch", "milestone"]),
    fixtureDoc("s1", .still, "2025-01-12", "09:05", title: "Morning at Café Lumière", tags: ["café", "morning", "coffee"],
               extra: "Flat white and a croissant by the window at Café Lumière."),
    fixtureDoc("m1", .music, "2025-01-13", "22:30", title: "Weightless", summary: "The track I put on when I need help falling asleep.",
               tags: ["sleep", "calm"], extra: "Marconi Union · Weightless (Ambient Transmissions Vol. 2)"),
    fixtureDoc("c1", .reflection, "2025-01-14", "07:00", title: "Run three mornings a week",
               summary: "Commit to running on Monday, Wednesday and Friday before work, even when it is cold.", tags: ["running", "health"]),
    fixtureDoc("r2", .reflection, "2025-01-18", "10:20", title: "First 5k in months",
               body: "Ran my first 5k since the knee injury. Legs felt heavy for the first two kilometres, then something clicked and the running felt easy. Maya sent a string of emoji when I told her.",
               tags: ["running", "5k"]),
    fixtureDoc("e2", .voice, "2025-01-20", "06:45", title: "Stillness",
               transcript: "Ten minutes of stillness on the balcony before anyone else was awake. Meditation is getting easier. I noticed the pigeons, the kettle, my own breath. No phone.",
               tags: ["meditation", "calm", "morning"]),
    fixtureDoc("v2", .moment, "2025-01-08", "18:30", title: "Pre-launch jitters",
               summary: "Nervous about the launch; walked around the block twice to calm down.",
               transcript: "Tomorrow we launch the new onboarding. I walked around the block twice, called nobody, and wrote the rollback plan three times. It is fine. It is going to be fine.",
               tags: ["work", "anxiety"]),
    fixtureDoc("r3", .reflection, "2025-01-25", "20:00", title: "Memories of Grandma's kitchen",
               body: "Maya and I spent the evening swapping memories of Grandma's kitchen: the radio, the burnt toast, the way she hummed. I want to write more of these down before they fade.",
               tags: ["family", "memory", "sister"]),
    fixtureDoc("s2", .still, "2025-01-26", "16:10", title: "Rainy walk", tags: ["walk", "rain"], extra: "The park path after the rain, puddles everywhere."),
    fixtureDoc("r4", .reflection, "2025-01-28", "23:05", title: "Didn’t sleep well",
               body: "I didn’t sleep well. Too much coffee at the café after 4pm, and then I scrolled until midnight. Tomorrow: no caffeine after lunch.",
               tags: ["sleep", "coffee"]),
    fixtureDoc("c2", .reflection, "2025-02-01", "08:00", title: "No screens after 10pm",
               summary: "Protect my sleep: phone charges in the kitchen, book in bed.", tags: ["sleep", "habits"]),
    fixtureDoc("e3", .voice, "2025-02-03", "13:15", title: "Walking meeting",
               transcript: "Did the product sync as a walking meeting along the canal. Much better than a conference room. We talked through the launch retro and what we would do differently next time.",
               tags: ["work", "walking"]),
    fixtureDoc("v3", .moment, "2025-02-07", "19:45", title: "Maya's birthday", summary: "We surprised Maya with a cake at her favourite café.",
               transcript: "Today we surprised my sister at her favourite café with a lemon cake. She cried a little, then laughed at herself for crying. Best evening in weeks. I'm so glad she's back from Lisbon for a bit.",
               tags: ["family", "birthday", "celebration"]),
    fixtureDoc("r5", .reflection, "2025-02-09", "07:30", title: "Morning run by the river",
               body: "Running along the river at sunrise. Cold hands, clear head. I kept thinking about how much better I sleep on the days I run.",
               tags: ["running", "sleep", "morning"]),
]

private let index = SearchIndex(journal)
private func find(_ q: String, in i: SearchIndex = index, kinds: Set<EntryKind>? = nil) -> [String] { i.search(q, kinds: kinds).map(\.doc.id) }
private func slice(_ s: String, _ r: Range<Int>) -> String { String(decoding: Array(s.utf16)[r], as: UTF16.self) }

private func doc(_ id: String? = nil, title: String? = nil, body: String, time: String = "2025-03-01T12:00:00Z") -> SearchDoc {
    SearchDoc(id: id ?? UUID().uuidString, kind: .reflection, day: "2025-03-01", capturedAt: at(time), title: title, body: body)
}

@Test func searchFoldsDiacriticsCaseAndApostrophes() {
    for q in ["cafe", "Café", "CAFÉ"] { #expect(find(q).sorted() == ["r4", "s1", "v3"]) }
    #expect(index.search("Café")[0].matchedTerms == ["cafe"])
    for q in ["didn't", "didn’t", "didnt"] { #expect(find(q).sorted() == ["e1", "r4"]) }
    #expect(find("5k") == ["r2"])
    #expect(find("2am") == ["e1"])
    #expect(find("pre-launch").first == "v2")
}

@Test func searchStemsAndDropsStopwords() {
    #expect(find("walked").first == "v2")
    #expect(find("walked").sorted() == ["e3", "s2", "v2"])
    #expect(find("walking").contains("s2"))
    #expect(find("memory") == ["r3"])
    for id in ["c1", "r2", "r5", "e1"] { #expect(find("run").contains(id)) }
    #expect(find("the launch") == find("launch"))
    #expect(index.search("the launch")[0].matchedTerms == ["launch"])
    // A stopword-only query still searches, literally.
    let the = index.search("the")
    #expect(the.count > 5 && the.allSatisfy { $0.matchedTerms == ["the"] })
}

@Test func searchToleratesTyposWithinItsBudget() {
    #expect(find("stilness") == ["e2"])
    #expect(find("sistr").sorted() == ["r3", "v1", "v3"])
    #expect(find("wlak") == ["s2"])
    #expect(find("meditatoin") == ["e2"])
    let small = SearchIndex([doc("w", body: "walk"), doc("s", body: "stillness")])
    #expect(find("wak", in: small).isEmpty)
    #expect(find("wakl", in: small) == ["w"])
    #expect(find("wlka", in: small).isEmpty)
    #expect(find("stilnesss", in: small) == ["s"])
    #expect(find("stlnesses", in: small).isEmpty)
    // A real word keeps its common neighbours out but still catches a rare typo.
    var docs = [doc("mood", body: "my mood today")]
    for i in 0..<5 { docs += [doc(body: "a good day \(i)"), doc(body: "a walk \(i)")] }
    docs.append(doc("typo", body: "a wlak"))
    let typos = SearchIndex(docs)
    #expect(find("mood", in: typos) == ["mood"])
    #expect(find("walk", in: typos).count == 6 && find("walk", in: typos).last == "typo")
}

@Test func searchPrefixesOnlyTheWordBeingTyped() {
    let r = index.search("medit")[0]
    #expect(r.doc.id == "e2")
    #expect(r.highlights.map { slice(r.snippet, $0) } == ["Meditation"])
    #expect(find("maya slee") == ["e1"])
    #expect(index.search("medit calm").allSatisfy { $0.matchedTerms == ["calm"] })
}

@Test func searchRanksByTierFieldRarityAndPhrase() {
    let tiers = SearchIndex([doc("exact", body: "evening walk river", time: "2025-01-01T00:00:00Z"),
                             doc("stem", body: "evening walked river", time: "2025-02-01T00:00:00Z"),
                             doc("prefix", body: "evening walkway river", time: "2025-03-01T00:00:00Z"),
                             doc("fuzzy", body: "evening wlak river", time: "2025-04-01T00:00:00Z")])
    #expect(find("walk", in: tiers) == ["exact", "stem", "prefix", "fuzzy"])
    let fields = SearchIndex([doc("body", title: "Notes", body: "maya from today"), doc("title", title: "Maya", body: "notes from today")])
    #expect(find("maya", in: fields) == ["title", "body"])
    #expect(fields.search("maya").map(\.field) == [.title, .body])
    var rare = [doc("rare", body: "lumiere")]
    for _ in 0..<6 { rare.append(doc(body: "coffee")) }
    #expect(find("coffee lumiere", in: SearchIndex(rare)).first == "rare")
    let phrase = SearchIndex([doc("apart", body: "work went well launch today ok"), doc("reversed", body: "launch work went well today ok"),
                              doc("phrase", body: "work launch went well today ok")])
    #expect(find("work launch", in: phrase).first == "phrase")
    let same = SearchIndex([doc("old", body: "lemon cake", time: "2024-01-01T00:00:00Z"), doc("new", body: "lemon cake", time: "2025-01-01T00:00:00Z")])
    #expect(find("lemon", in: same) == ["new", "old"])
    #expect(find("maya").first == "v1")
    #expect(find("work launch").first == "r1")
    #expect(find("sleep coffee").first == "r4")
}

@Test func searchWantsEveryWordThenTheMost() {
    #expect(find("maya launch").sorted() == ["e1", "v1"])
    #expect(find("maya zebra").sorted() == ["e1", "r2", "r3", "v1", "v3"])
    let counts = index.search("maya coffee running").map(\.matchedTerms.count)
    #expect(counts == counts.sorted(by: >))
    #expect(find("sleep").count == 5)
    #expect(find("sleep", kinds: [.music]) == ["m1"])
    #expect(find("maya launch", kinds: [.reflection]).allSatisfy { id in journal.first { $0.id == id }?.kind == .reflection })
}

@Test func searchSnippetsCentreOnTheMatchesInWholeWords() {
    let filler = (0..<40).map { "word\($0)" }.joined(separator: " ")
    let body = "\(filler) and then Maya called \(filler)"
    let r = SearchIndex([doc(body: body)]).search("maya")[0]
    #expect(r.snippet.hasPrefix("…") && r.snippet.hasSuffix("…") && r.snippet.utf16.count <= 162)
    #expect(slice(r.snippet, r.highlights[0]) == "Maya")
    #expect(body.contains(r.snippet.dropFirst().dropLast()))
    let cluster = SearchIndex([doc(body: "Maya \(filler) the launch party where Maya gave a toast \(filler)")]).search("maya launch")[0]
    #expect(cluster.highlights.map { slice(cluster.snippet, $0) } == ["launch", "Maya"])
    #expect(SearchText.snippet("walk in the park", [.init(start: 0, end: 4, mask: 1)]).snippet == "walk in the park")
    // Title highlights index into the title; a title-only match leads with the summary.
    let maya = Dictionary(uniqueKeysWithValues: index.search("maya").map { ($0.doc.id, $0) })
    #expect(maya["v3"].map { r in r.titleHighlights.map { slice(r.doc.title ?? "", $0) } } == ["Maya's"])
    let jitters = index.search("jitters")[0]
    #expect(jitters.field == .title && jitters.snippet == journal.first { $0.id == "v2" }?.summary && jitters.highlights.isEmpty)
    #expect(index.search("lisbon")[0].field == .summary)
    // Only a term's best tier lights up: "café", never its fuzzy neighbour "cake".
    let cafe = index.search("cafe", kinds: [.moment])[0]
    #expect(cafe.highlights.map { slice(cafe.snippet, $0) } == ["café"])
}

@Test func searchStemmerAndDistance() {
    #expect(SearchText.stem("memories") == SearchText.stem("memory"))
    #expect(SearchText.stem("running") == "run" && SearchText.stem("walked") == "walk" && SearchText.stem("goes") == "go")
    #expect(SearchText.editDistance("wlak", "walk", max: 1) == 1)
    #expect(SearchText.editDistance("kitten", "sitting", max: 2) == 3)
    #expect(SearchText.bigrams("walk") == ["^w", "wa", "al", "lk", "k$"])
    #expect(SearchText.tokenize("Café, didn’t!").map(\.term) == ["cafe", "didnt"])
}

@Test func searchPenalisesEditsAndFavoursShortFieldsAndInOrderPhrases() {
    #expect(find("stillness", in: SearchIndex([doc("two", body: "evening stilnes river"), doc("one", body: "evening stilness river")])) == ["one", "two"])
    let lengths = SearchIndex([doc("long", body: "sleep " + String(repeating: "filler words here ", count: 10)), doc("short", body: "sleep well")])
    #expect(find("sleep", in: lengths) == ["short", "long"])
    let phrase = SearchIndex([doc("apart", body: "work went well launch today ok"), doc("reversed", body: "launch work went well today ok"),
                              doc("phrase", body: "work launch went well today ok")]).search("work launch")
    #expect(phrase.count == 3 && phrase[1].score == phrase[2].score)
    // The phrase skips stopwords: "walk in the park" is adjacent, "walk by big park" isn't.
    #expect(find("walk park", in: SearchIndex([doc("big", body: "walk by big park"), doc("in", body: "walk in the park")])) == ["in", "big"])
    // Recency only breaks ties: an older title match still beats a newer body match.
    let better = SearchIndex([doc("old", title: "Lemon", body: "cake", time: "2020-01-01T00:00:00Z"),
                              doc("new", title: "Cake", body: "lemon", time: "2025-01-01T00:00:00Z")])
    #expect(find("lemon", in: better) == ["old", "new"])
}

@Test func searchMatchesEveryWordThenTheMostInsideTheKinds() {
    #expect(index.search("maya launch").allSatisfy { $0.matchedTerms == ["maya", "launch"] })
    #expect(index.search("maya zebra").allSatisfy { $0.matchedTerms == ["maya"] })
    #expect(Array(index.search("maya coffee running").map(\.matchedTerms.count).prefix(2)) == [2, 2])
    #expect(find("sleep", kinds: [.music, .voice]).sorted() == ["e1", "m1"])
    #expect(index.search("maya launch", kinds: [.reflection]).allSatisfy { $0.doc.kind == .reflection && $0.matchedTerms.count == 1 })
    let many = SearchIndex((0..<30).map { doc(body: "walk \($0)") })
    #expect(many.search("walk").count == 20)
    #expect(many.search("walk", limit: 5).count == 5 && many.search("walk", limit: 50).count == 30 && many.search("walk", limit: 0).isEmpty)
}

@Test func searchHighlightsAreWholeWordsInEveryFixtureResult() {
    for q in ["maya", "sleep", "walked", "sistr", "medit", "the launch", "didn't", "the", "cafe"] {
        for r in index.search(q) {
            for h in r.highlights {
                let s = slice(r.snippet, h)
                #expect(!s.isEmpty && s.trimmingCharacters(in: .whitespaces) == s && SearchText.tokenize(s).count == 1, "\(q): \(s)")
            }
            for h in r.titleHighlights { #expect(SearchText.tokenize(slice(r.doc.title ?? "", h)).count == 1, "\(q)") }
        }
    }
    let maya = Dictionary(uniqueKeysWithValues: index.search("maya").map { ($0.doc.id, $0) })
    #expect(maya["v1"].map { r in r.titleHighlights.map { slice(r.doc.title ?? "", $0) } } == ["Maya"])
    #expect(maya["e1"]?.titleHighlights.isEmpty == true)
    let memory = index.search("memory")[0]
    #expect(memory.field == .title && memory.snippet.contains("memories"))
}

@Test func searchSnippetsAreCentredAndCutBetweenWords() throws {
    let filler = (0..<40).map { "word\($0)" }.joined(separator: " ")
    let body = "\(filler) and then Maya called \(filler)"
    let r = SearchIndex([doc(body: body)]).search("maya")[0]
    let core = String(r.snippet.dropFirst().dropLast())
    let at = try #require(body.range(of: core))
    #expect(body[body.index(before: at.lowerBound)] == " " && body[at.upperBound] == " ")
    let maya = try #require(r.highlights.first)
    #expect(abs(Double(maya.lowerBound) - Double(r.snippet.utf16.count) / 2) < 30)
}

@Test func searchSurvivesOddQueriesAndIgnoresInsertionOrder() {
    for q in ["", "   ", "\n\t ", "…", "—"] { #expect(index.search(q).isEmpty, "\(q)") }
    for q in ["*?()[]", "(", ")", "[", "\\", ".*", "$^", "+?", "(?<x>", "|||", "a**b", "💥", "\u{0}",
              String(repeating: "x", count: 100_000), String(repeating: "maya ", count: 5_000)] { _ = index.search(q) }
    // Long queries keep their first 12 terms.
    let words = (0..<40).map { "term\(Character(Unicode.Scalar(97 + $0 % 26)!))\($0)" }
    let capped = SearchIndex([doc("thirteenth", body: words[12]), doc("first", body: words[0])]).search(words.joined(separator: " "))
    #expect(capped.map(\.doc.id) == ["first"] && capped.allSatisfy { $0.matchedTerms.count <= 12 })
    let reversed = SearchIndex(journal.reversed())
    for q in ["maya", "sleep", "the", "walk", "cafe coffee", "sistr", "medit"] {
        let key = { (r: SearchIndex.Result) in "\(r.doc.id) \((r.score * 1e9).rounded()) \(r.snippet) \(r.highlights)" }
        #expect(reversed.search(q).map(key) == index.search(q).map(key), "\(q)")
    }
}

// MARK: Normalising and fuzzy matching (ports of normalize.test.ts and fuzzy.test.ts; the web's stripHtml has no native
// counterpart, since native writings are plain text)

private func terms(_ s: String) -> [String] { SearchText.tokenize(s).map(\.term) }

@Test func tokenizeLowercasesFoldsAndSplits() {
    #expect(terms("Hello, WORLD! self-care; x/y (ok)") == ["hello", "world", "self", "care", "x", "y", "ok"])
    #expect(terms("Café Lumière ÅNGSTRÖM naïve") == ["cafe", "lumiere", "angstrom", "naive"])
    #expect(terms("ﬁne Ｆｕｌｌ ①") == ["fine", "full", "1"])
    #expect(terms("cafe\u{301}") == ["cafe"])
}

@Test func tokenizeJoinsApostrophesKeepsNumbersAndSplitsOnEmoji() {
    #expect(terms("didn't didn’t Maya's 'quoted' rock 'n' roll") == ["didnt", "didnt", "mayas", "quoted", "rock", "n", "roll"])
    #expect(terms("5k at 7:30, 2024 and 10pm") == ["5k", "at", "7", "30", "2024", "and", "10pm"])
    #expect(terms("run🏃‍♀️fast ❤️ 🎉done") == ["run", "fast", "done"])
}

@Test func tokenOffsetsPointBackIntoTheText() {
    let text = "  Didn’t sleep at Café Lumière — ﬁne!"
    let tokens = SearchText.tokenize(text)
    for t in tokens { #expect(terms(slice(text, t.start..<t.end)) == [t.term]) }
    #expect(slice(text, tokens[0].start..<tokens[0].end) == "Didn’t")
    #expect(SearchText.tokenize(String(repeating: "a", count: 500))[0].term.count == 64)
    #expect(SearchText.tokenize("").isEmpty && SearchText.tokenize(" \n\t *?()[] ").isEmpty)
}

@Test func stemConflatesInflectionsWithoutOverStemming() {
    let groups = [["walk", "walks", "walking", "walked"], ["memory", "memories"], ["run", "runs", "running"], ["try", "tries", "tried", "trying"],
                  ["hope", "hopes", "hoped", "hoping"], ["launch", "launches", "launched", "launching"],
                  ["meditate", "meditates", "meditated", "meditating"], ["sister", "sisters"], ["family", "families"], ["cafe", "cafes"],
                  ["coffee", "coffees"], ["smile", "smiled", "smiling"], ["agree", "agreed"]]
    for g in groups { #expect(Set(g.map(SearchText.stem)).count == 1, "\(g)") }
    for w in ["bus", "gas", "yes", "was", "has", "this", "is", "us", "news", "sing", "thing", "bed", "stillness", "5ks", "2024", "straße"] {
        #expect(SearchText.stem(w) == w, "\(w)")
    }
    #expect(SearchText.stem("hope") != SearchText.stem("hop"))
    #expect(SearchText.stem("hoping") != SearchText.stem("hopping"))
    #expect(SearchText.stem("meditation") != SearchText.stem("meditate"))
}

@Test func stopwordsKeepContractionsThatMeanSomething() {
    #expect(SearchText.stopwords.contains("the") && SearchText.stopwords.contains("im"))
    #expect(!SearchText.stopwords.contains("didnt") && !SearchText.stopwords.contains("ill") && !SearchText.stopwords.contains("maya"))
}

@Test func editDistanceIsABoundedDamerauLevenshtein() {
    let d = { (a: String, b: String, bound: Int) -> Int in SearchText.editDistance(a, b, max: bound) }
    let exact: [Int] = [d("walk", "walk", 2), d("wlak", "walk", 2), d("sistr", "sister", 2), d("stilness", "stillness", 2),
                        d("meditatoin", "meditation", 2), d("ab", "ba", 2), d("kitten", "sitting", 5), d("", "ab", 2)]
    #expect(exact == [0, 1, 1, 1, 1, 1, 3, 2])
    // Anything over the bound comes back as bound + 1.
    let bounded: [Int] = [d("kitten", "sitting", 2), d("walk", "running", 1), d("a", "abcdef", 2),
                          d(String(repeating: "x", count: 200), String(repeating: "y", count: 200), 2)]
    #expect(bounded == [3, 2, 3, 3])
    #expect([1, 2, 3, 4, 7, 8, 12].map(SearchText.maxEdits) == [0, 0, 0, 1, 1, 2, 2])
    #expect(SearchText.bigrams("walk") == ["^w", "wa", "al", "lk", "k$"])
    #expect(SearchText.bigrams("aaa") == ["^a", "aa", "a$"] && SearchText.bigrams("a") == ["^a", "a$"])
}

// MARK: The palette's pure parts (ports of palette.test.ts's matchCommand and parseDay; its sections are the view's own)

@Test func commandsMatchByWordPrefixKeywordOrInitials() {
    let m = { (q: String, title: String, keywords: String) in CommandMatch.matches(q, title: title, keywords: keywords) }
    #expect(m("new ref", "New reflection", "write") && m("rec voice", "Record voice note", "audio") && m("theme", "Appearance", "theme dark"))
    #expect(!m("record", "New reflection", "write") && !m("", "New reflection", "write"))
    #expect(m("nr", "New reflection", "") && m("RAM", "Record a moment", "video") && !m("rn", "New reflection", ""))
}

@Test func typedDaysReadAsThePaletteReadsThem() throws {
    // Tuesday 22 September 2026, 3:33 PM.
    let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 15, minute: 33)))
    let cases: [(String, String?)] = [
        ("today", "2026-09-22"), (" Yesterday ", "2026-09-21"), ("3 days ago", "2026-09-19"), ("1 day ago", "2026-09-21"),
        ("tue", "2026-09-22"), ("tuesday", "2026-09-22"), ("last tue", "2026-09-15"), ("monday", "2026-09-21"), ("wed", "2026-09-16"),
        ("last wed", "2026-09-16"), ("12 sep", "2026-09-12"), ("sep 12", "2026-09-12"), ("September 12", "2026-09-12"),
        ("22 sep", "2026-09-22"), ("23 sep", "2025-09-23"), ("12 oct", "2025-10-12"),
        ("12/9", nil), ("coffee", nil), ("31 feb", nil), ("last", nil), ("mo", nil), ("12 se", nil), ("", nil),
    ]
    for (text, day) in cases { #expect(LocalDay.parse(text, now: now) == day, "\(text)") }
}

@Test func searchStaysFastAt300Entries() {
    var seed: UInt64 = 42
    func next() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 11) / Double(1 << 53)
    }
    let words = "maya sister sleep slept tired morning evening coffee cafe walk walked run running launch work meeting team stillness meditation breath calm anxious grateful journal memory kitchen family friend dinner rain park river phone book music cake quiet happy proud nervous jitters".split(separator: " ").map(String.init)
    let stop = ["the", "and", "i", "to", "a", "of", "my", "it"]
    let text = { (n: Int) in (0..<n).map { _ in next() < 0.3 ? stop[Int(next() * 8)] : words[Int(Double(words.count) * pow(next(), 2.5))] }.joined(separator: " ") }
    let docs = (0..<300).map { i in
        SearchDoc(id: "doc-\(i)", kind: EntryKind.allCases[i % 5], day: "2026-01-01", capturedAt: Date(timeIntervalSince1970: Double(i) * 17_280),
                  title: text(5), summary: text(14), body: text(56), tags: [words[i % words.count]])
    }
    let clock = ContinuousClock()
    var built: SearchIndex?
    let build = (0..<3).map { _ in clock.measure { built = SearchIndex(docs) } }.min() ?? .zero
    guard let index = built else { return }
    for q in ["stilness", "sistr", "medit", "maya slep", "coffe at the cafe", "meditatoin breathng", "the", "m"] {
        // The best of five, so a busy machine running the rest of the suite in parallel can't fail it: ~5 ms a keystroke
        // in release, debug test builds several times slower.
        let t = (0..<5).map { _ in clock.measure { _ = index.search(q, limit: 50) } }.min() ?? .zero
        #expect(t < .milliseconds(60), "\(q): \(t)")
    }
    #expect(build < .milliseconds(1500), "\(build)")
}

@Test func ledgerSearchShowsSaroTextOnlyForClearEntriesOnDaysNotHeld() async throws {
    let l = try tempLedger()
    let day = "2026-10-20", held = "2026-10-21"
    let clear = Entry(kind: .voice, capturedAt: at("\(day)T09:00:00Z"), localDay: day)
    let unchecked = Entry(kind: .voice, capturedAt: at("\(day)T10:00:00Z"), localDay: day)
    let onHeldDay = Entry(kind: .voice, capturedAt: at("\(held)T09:00:00Z"), localDay: held)
    let holder = Entry(kind: .reflection, body: "A synthetic held page.", capturedAt: at("\(held)T10:00:00Z"), localDay: held)
    for e in [clear, unchecked, onHeldDay, holder] { try await l.insertEntry(e) }
    for e in [clear, unchecked, onHeldDay] {
        var run = AIRun(feature: "entry_reading", executor: "heuristic", status: "ok")
        run.inputHash = "h-\(e.id)"
        try await l.insertRun(run)
        var a = EntryAnnotation(entryId: e.id, aiRunId: run.id, generator: "heuristic")
        (a.title, a.summary) = ("Lantern walk", "A quiet lantern walk by the canal.")
        try await l.insertAnnotation(a)
    }
    for e in [clear, onHeldDay] {
        try await l.insertVerdict(SafetyVerdictRow(entryId: e.id, textSha256: "h-\(e.id)", safetyVersion: SafetyGate.version, layer: 2, verdict: "clear", reasonCode: "t"))
    }
    try await l.insertVerdict(SafetyVerdictRow(entryId: holder.id, textSha256: sha256(holder.body ?? ""), safetyVersion: SafetyGate.version,
                                               layer: 2, verdict: "safety_hold", reasonCode: "t"))
    let found = try await l.search("lantern")
    #expect(found.map(\.entryId) == [clear.id])
    #expect(found.first?.title == "Lantern walk")
    // Unchecked and held-day entries show no generated title either.
    let recent = try await l.search("")
    #expect(recent.first { $0.entryId == unchecked.id }?.title == nil)
    #expect(recent.first { $0.entryId == onHeldDay.id }?.title == nil)
    // The person's own words are always theirs to find.
    #expect(try await l.search("synthetic held").map(\.entryId) == [holder.id])
}

// MARK: Time lens (ports of lensLayout.test.ts)

private let lens = LensCalendar(from: "2025-10-01", through: "2026-09-26")
private let lensVP = LensMath.Viewport(width: 1440, height: 900, top: 88, bottom: 72)
private let geo = LensMath.measure(lens, lensVP)
private let todayIndex = lens.days.count - 1
private func lensAt(_ z: CGFloat, focus: Int = todayIndex, pan: CGFloat = 0) -> [LensMath.Transform] {
    LensMath.transforms(lens, geo, focus: focus, z: z, pan: pan).blocks
}
private func near(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 0.01) -> Bool { abs(a - b) < eps }
private func key(_ i: Int) -> String { lens.days[i].key }

@Test func lensCalendarLaysMonthsOutAsBlocksEndingToday() {
    #expect(lens.blocks.count == 12 && lens.days.count == 361)
    let sep = lens.blocks[11]
    #expect(sep.offset == 2 && sep.rows == 4) // 1 September 2026 is a Tuesday
    let last = lens.days[todayIndex]
    #expect(last.key == "2026-09-26" && last.col == 6 && last.row == 3)
    #expect(Calendar(identifier: .gregorian).component(.hour, from: last.date) == 12)
    // Weeks follow the Mac's first weekday.
    #expect(LensCalendar(from: "2026-09-01", through: "2026-09-26", weekStart: 1).blocks[0].offset == 1)
    #expect(lens.unit(todayIndex, .week).map(key) == ["2026-09-20", "2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24", "2026-09-25", "2026-09-26"])
    #expect(lens.index(of: "2024-01-01") == nil && lens.index(of: "2026-09-26") == todayIndex)
}

@Test func lensMeasurePicksTheBiggestYearGridAndCapsWeekTiles() {
    #expect(geo.cols == 4)
    #expect(geo.weekScale > geo.monthScale && geo.monthScale > geo.yearScale && geo.weekScale <= 196)
    #expect(geo.gridW * geo.yearScale <= lensVP.width)
}

@Test func lensLevelsFrameTheirUnitAroundTheFocus() {
    let p = LensMath.pitch, sep = lens.blocks[11]
    let week = lensAt(0)[11]
    #expect(near(week.y + (3 * p + 0.5) * week.scale, geo.cy) && near(week.x + LensMath.blockW / 2 * week.scale, geo.cx))
    let month = lensAt(1)[11]
    #expect(near(month.y + (CGFloat(sep.rows) * p - 0.1) * month.scale / 2, geo.cy))
    #expect((6 * p - 0.1) * month.scale / 2 + LensMath.labelH * month.scale * 0.62 <= geo.cy - lensVP.top)
    let year = lensAt(2)
    #expect(near(year[0].x, geo.cx - geo.gridW / 2 * geo.yearScale))
    let top = year.map(\.y).min() ?? 0
    let bottom = zip(lens.blocks, year).map { $1.y + $0.height * $1.scale }.max() ?? 0
    #expect(near((top + bottom) / 2, geo.cy))
    #expect(top - LensMath.labelH * geo.yearScale >= lensVP.top - 0.01 && bottom <= lensVP.height - lensVP.bottom + 0.01)
}

@Test func lensZoomIsContinuousAcrossTheReflow() {
    for z: CGFloat in [1, 2] {
        let (a, b) = (lensAt(z - 1e-6), lensAt(z + 1e-6))
        var checked = 0
        for m in 0..<12 where a[m].y + lens.blocks[m].height * a[m].scale > 0 && a[m].y < lensVP.height {
            checked += 1
            #expect(near(a[m].x, b[m].x, 0.05) && near(a[m].y, b[m].y, 0.05) && near(a[m].scale, b[m].scale, 0.05) && near(a[m].emphasis, b[m].emphasis, 0.05))
        }
        #expect(checked >= 2)
    }
}

@Test func lensTileAtFindsTilesAndNotGutters() throws {
    for z: CGFloat in [0, 1, 1.5, 2] {
        let t = lensAt(z)
        let r = try #require(LensMath.tileRect(lens, t, todayIndex - 9))
        #expect(LensMath.tileAt(lens, t, CGPoint(x: r.midX, y: r.midY)) == todayIndex - 9)
    }
    let t = lensAt(1), r = try #require(LensMath.tileRect(lens, t, todayIndex))
    #expect(LensMath.tileAt(lens, t, CGPoint(x: r.minX + r.width * 1.05, y: r.midY)) == nil)
    #expect(LensMath.tileAt(lens, t, CGPoint(x: r.minX + r.width * 1.05, y: r.midY), slack: r.width * 0.1) == todayIndex)
}

@Test func lensKeysMoveByDayWeekAndMonth() throws {
    #expect(LensMath.move(lens, todayIndex, .right) == todayIndex)
    #expect(LensMath.move(lens, todayIndex, .up) == todayIndex - 7)
    #expect(key(LensMath.move(lens, todayIndex, .pageUp)) == "2026-08-26")
    #expect(key(LensMath.move(lens, 0, .pageUp)) == "2025-10-01")
    #expect(key(LensMath.move(lens, todayIndex, .home)) == "2026-09-20")
    let aug31 = try #require(lens.index(of: "2026-08-31"))
    #expect(key(LensMath.move(lens, aug31, .end)) == "2026-08-31")
    #expect(key(LensMath.move(lens, aug31, .pageDown)) == "2026-09-26")
}

@Test func lensPanSnapsToRowsAndMonths() {
    let up = LensMath.framingY(lens, todayIndex, .week) - LensMath.pitch * 1.3
    #expect(key(LensMath.snapFocus(lens, todayIndex, .week, worldY: up)) == "2026-09-19")
    let aug = LensMath.framingY(lens, todayIndex - 40, .month)
    #expect(key(LensMath.snapFocus(lens, todayIndex, .month, worldY: aug + 0.5)) == "2026-08-26")
    #expect(LensMath.snapFocus(lens, todayIndex, .month, worldY: LensMath.framingY(lens, todayIndex, .month) + 2) == todayIndex)
}

@Test func lensPhysics() {
    #expect(near(LensMath.project(1000), 499))
    #expect(LensMath.rubberband(10, 100) < 10 && LensMath.rubberband(1e6, 100) < 100 && LensMath.rubberband(-10, 100) == -LensMath.rubberband(10, 100))
    #expect(LensMath.rubberband(20, 100) > LensMath.rubberband(10, 100))
    #expect(near(LensMath.unrubberband(LensMath.rubberband(37, 100), 100), 37))
    #expect(near(LensMath.unrubberband(LensMath.rubberband(-0.8, 1.2, 0.7), 1.2, 0.7), -0.8))
    var s = LensMath.Spring(0)
    var settled = false
    for _ in 0..<120 where !settled { settled = s.step(to: 1, dt: 1 / 60) }
    #expect(settled && s.x == 1)
    #expect(LensMath.settle(z: 0.3, velocity: 0, from: 0) == 1) // a clear move steps even with no velocity
    #expect(LensMath.settle(z: 0.1, velocity: 0, from: 0) == 0)
    #expect(LensMath.settle(z: 1.2, velocity: 12, from: 1) == 2)
    #expect(LensMath.settle(z: 2.3, velocity: 0, from: 2) == 2)
    #expect(LensMath.settle(z: -0.3, velocity: -3, from: 0) == nil)
    #expect(LensMath.settle(z: -0.2, velocity: 0, from: 0) == 0)
}

@Test func lensZoomIsTheLogOfTileSize() throws {
    #expect(near(LensMath.zOfLog(geo, log(geo.weekScale)), 0) && near(LensMath.zOfLog(geo, log(geo.monthScale)), 1))
    #expect(near(LensMath.zOfLog(geo, log(geo.yearScale)), 2))
    for z: CGFloat in [-0.6, 0, 0.3, 1, 1.7, 2, 2.4] { #expect(near(LensMath.zOfLog(geo, LensMath.logOfZ(geo, z)), z, 1e-9)) }
    #expect(near(lensAt(0.4)[11].scale, exp(LensMath.logOfZ(geo, 0.4)), 1e-3))
    // The flight zooms about the tile until it covers the window.
    var t = lensAt(0)
    let f = try #require(LensMath.applyFlight(lens, &t, f: 1, index: todayIndex, width: 1440, height: 900))
    let r = try #require(LensMath.tileRect(lens, t, todayIndex))
    #expect(near(r.midX, 720, 0.5) && near(r.midY, 450, 0.5) && near(r.width, 1440, 0.5) && f.cover > 1)
}

// MARK: Day summaries

@Test func daySummariesCountStacksOnceAndPickTheNewestPicture() async throws {
    let l = try tempLedger()
    let day = "2026-10-20"
    let still = MediaAsset(fileName: "s.heic", kind: .image, origin: "picked", state: "ready")
    let clip = MediaAsset(fileName: "p1.mov", kind: .video, origin: "recorded", state: "ready")
    let broken = MediaAsset(fileName: "p2.mov", kind: .video, origin: "recorded", state: "failed")
    for m in [still, clip, broken] { try await l.insertMedia(m) }
    let entries = [
        Entry(kind: .moment, sessionId: "s1", turnNumber: 1, capturedAt: at("\(day)T09:00:00Z"), localDay: day, mediaId: clip.id),
        Entry(kind: .moment, sessionId: "s1", turnNumber: 2, capturedAt: at("\(day)T09:01:00Z"), localDay: day, mediaId: broken.id),
        Entry(kind: .still, capturedAt: at("\(day)T12:00:00Z"), localDay: day, mediaId: still.id),
        Entry(kind: .reflection, body: "A synthetic page.", capturedAt: at("\(day)T13:00:00Z"), localDay: day),
        Entry(kind: .voice, capturedAt: at("2026-10-22T08:00:00Z"), localDay: "2026-10-22"),
        Entry(kind: .voice, capturedAt: at("2026-11-02T08:00:00Z"), localDay: "2026-11-02"),
    ]
    for e in entries { try await l.insertEntry(e) }
    let s = try await l.daySummaries(from: "2026-10-01", to: "2026-10-31")
    #expect(s.map(\.day) == [day, "2026-10-22"])
    #expect(s[0].counts == [.moment: 1, .still: 1, .reflection: 1] && s[0].total == 3)
    // A moment's ready file wins over a newer still; a failed part never shows.
    #expect(s[0].keyMediaId == clip.id)
    #expect(s[1].total == 1 && s[1].keyMediaId == nil && s[1].mood == nil)
    try await l.setPoster(mediaId: clip.id, file: "\(day)/\(clip.id).poster.jpg")
    #expect(try await l.poster(mediaId: clip.id) == "\(day)/\(clip.id).poster.jpg")
}

@Test func lensEntriesCarryMoodsOnlyWhereSaroMayShowThem() async throws {
    let l = try tempLedger()
    let (day, held) = ("2026-10-20", "2026-10-21")
    let mine = Entry(kind: .voice, capturedAt: at("\(day)T09:00:00Z"), localDay: day)
    let unchecked = Entry(kind: .voice, capturedAt: at("\(day)T10:00:00Z"), localDay: day)
    let onHeld = Entry(kind: .voice, capturedAt: at("\(held)T09:00:00Z"), localDay: held)
    let holder = Entry(kind: .reflection, body: "A synthetic held page.", capturedAt: at("\(held)T10:00:00Z"), localDay: held)
    for e in [mine, unchecked, onHeld, holder] { try await l.insertEntry(e) }
    for e in [mine, unchecked, onHeld] {
        var run = AIRun(feature: "entry_reading", executor: "heuristic", status: "ok")
        run.inputHash = "h-\(e.id)"
        try await l.insertRun(run)
        var a = EntryAnnotation(entryId: e.id, aiRunId: run.id, generator: "heuristic")
        a.moodLabel = Mood.calm.rawValue
        try await l.insertAnnotation(a)
    }
    for e in [mine, onHeld] {
        try await l.insertVerdict(SafetyVerdictRow(entryId: e.id, textSha256: "h-\(e.id)", safetyVersion: SafetyGate.version, layer: 2, verdict: "clear", reasonCode: "t"))
    }
    try await l.insertVerdict(SafetyVerdictRow(entryId: holder.id, textSha256: sha256(holder.body ?? ""), safetyVersion: SafetyGate.version,
                                               layer: 2, verdict: "safety_hold", reasonCode: "t"))
    let week = try await l.lensEntries(from: day, to: held)
    #expect(week.map(\.day) == [day, day, held, held])
    #expect(week.map(\.mood) == [.calm, nil, nil, nil])
}

// MARK: Key frames (ports of keyframes.test.ts)

private func frame(_ rgb: (UInt8, UInt8, UInt8), pixels: Int = 16) -> [UInt8] { (0..<pixels).flatMap { _ in [rgb.0, rgb.1, rgb.2, 255] } }

@Test func keyframesFitTheShortSideWithoutUpscalingOrDistorting() {
    #expect(Keyframe.fit(width: 1920, height: 1080) == (455, 256))
    #expect(Keyframe.fit(width: 720, height: 540) == (341, 256))
    #expect(Keyframe.fit(width: 1080, height: 1920) == (256, 455))
    #expect(Keyframe.fit(width: 200, height: 120) == (200, 120))
    #expect(Keyframe.fit(width: 4000, height: 500) == (512, 64))
    #expect(Keyframe.fit(width: 0, height: 0) == (256, 256))
}

@Test func keyframeLumaWeighsChannelsByPerceivedBrightness() {
    #expect(Keyframe.luma(frame((0, 0, 0))).mean == 0)
    #expect(Keyframe.luma(frame((255, 255, 255))).mean.rounded() == 255)
    #expect(Keyframe.luma(frame((0, 255, 0))).mean > Keyframe.luma(frame((255, 0, 0))).mean)
    #expect(Keyframe.luma([]) == (0, 0))
}

@Test func keyframesSkipWarmUpBlackButKeepDimRealFrames() {
    #expect(Keyframe.isBlack(frame((0, 0, 0))) && Keyframe.isBlack(frame((12, 12, 14))))
    #expect(!Keyframe.isBlack(frame((40, 34, 30))))
    var mostlyDark = frame((0, 0, 0), pixels: 100)
    mostlyDark.replaceSubrange(0..<12, with: [200, 180, 160, 255, 200, 180, 160, 255, 200, 180, 160, 255])
    #expect(!Keyframe.isBlack(mostlyDark))
}

@Test func keyframesProbeTheOpeningSecondsInsideTheClip() {
    #expect(Keyframe.seekTimes(nil) == [0.05, 0.4, 1, 2, 3.5])
    #expect(Keyframe.seekTimes(.infinity) == [0.05, 0.4, 1, 2, 3.5] && Keyframe.seekTimes(.nan) == [0.05, 0.4, 1, 2, 3.5])
    #expect(Keyframe.seekTimes(3) == [0.05, 0.4, 1, 2])
    #expect(Keyframe.seekTimes(1.5) == [0.05, 0.4, 1])
    #expect(Keyframe.seekTimes(0.04) == [0.02])
}

/// The web's isFresh: a poster is reused only for the same version of the file, so its name carries the file's stamp.
@Test func keyframesAreNamedByMediaAndFileVersion() {
    let m = MediaAsset(id: "m1", fileName: "2026-10-27/s1/part-1.mov", kind: .video, origin: "recorded")
    #expect(Keyframe.file(for: m, stamp: 42) == "2026-10-27/posters/m1-42.jpg")
    #expect(Keyframe.file(for: m, stamp: 42) != Keyframe.file(for: m, stamp: 43))
}

// MARK: Day layout (ports of dayLayout.test.ts)

private let layoutSizes: [EntryKind: CGSize] = [.reflection: CGSize(width: 360, height: 200), .still: CGSize(width: 260, height: 300),
                                                .moment: CGSize(width: 420, height: 280), .voice: CGSize(width: 380, height: 160),
                                                .music: CGSize(width: 280, height: 88)]
private func layoutDay(_ mix: [(EntryKind, Int)]) -> [DayLayout.Item] {
    mix.flatMap { k, n in (0..<n).map { DayLayout.Item(id: "\(k)-\($0)", kind: k, size: layoutSizes[k]!) } }
}
private let layoutView = CGSize(width: 1288, height: 684)
private func extent(_ items: [DayLayout.Item], _ at: [String: CGPoint]) -> CGRect {
    items.map { CGRect(x: at[$0.id]!.x - $0.size.width / 2, y: at[$0.id]!.y - $0.size.height / 2, width: $0.size.width, height: $0.size.height) }
        .reduce(CGRect.null) { $0.union($1) }
}

@Test func dayLayoutGrowsWideNotTallAndFitsASmallDay() {
    let busy = layoutDay([(.reflection, 40), (.still, 30), (.moment, 30), (.voice, 30), (.music, 30)])
    let at = DayLayout.layoutDay(busy, center: .zero, visible: layoutView)
    #expect(at.count == 160)
    let box = extent(busy, at)
    #expect(box.width > box.height && min(layoutView.width / box.width, layoutView.height / box.height) >= 0.08)
    let small = layoutDay([(.reflection, 2), (.still, 2), (.moment, 1)])
    #expect(extent(small, DayLayout.layoutDay(small, center: .zero, visible: layoutView)).width <= layoutView.width + 10)
}

@Test func freeSpotAndPackBurstNeverOverlap() throws {
    let visible = CGRect(x: -644, y: -342, width: 1288, height: 684)
    let order: [EntryKind] = [.reflection, .reflection, .reflection, .reflection, .still, .still, .still, .music, .music, .music]
    var taken: [CGRect] = []
    let cardByCard = order.map { k -> CGPoint? in
        let spot = DayLayout.freeSpot(layoutSizes[k]!, in: visible, avoiding: taken)
        if let spot { taken.append(CGRect(origin: spot, size: layoutSizes[k]!)) }
        return spot
    }
    // Card by card, the third still finds no room; the block fits them all.
    #expect(cardByCard[6] == nil)
    for (i, a) in taken.enumerated() { for b in taken.dropFirst(i + 1) { #expect(!a.intersects(b)) } }
    let sizes = order.map { layoutSizes[$0]! }
    let spots = try #require(DayLayout.packBurst(sizes, in: visible, avoiding: []))
    let rects = zip(spots, sizes).map { CGRect(origin: $0, size: $1) }
    for r in rects { #expect(visible.contains(r)) }
    for (i, a) in rects.enumerated() { for b in rects.dropFirst(i + 1) { #expect(!a.insetBy(dx: -12, dy: -12).intersects(b.insetBy(dx: -11.9, dy: -11.9))) } }
    #expect(DayLayout.packBurst(sizes, in: visible, avoiding: [CGRect(x: -50, y: -50, width: 100, height: 100)]) == nil)
    #expect(DayLayout.packBurst(sizes + sizes, in: visible, avoiding: []) == nil)
    // Zoomed far out over a full middle, a new card finds the room at the side.
    let wide = CGRect(x: -5000, y: -1000, width: 10_000, height: 2000)
    let side = try #require(DayLayout.freeSpot(layoutSizes[.reflection]!, in: wide, avoiding: [CGRect(x: -4000, y: -1000, width: 8000, height: 2000)]))
    #expect(side.x >= 4024 || side.x + 360 <= -4024)
    #expect(DayLayout.dropGrid(count: 4, at: .zero).count == 4 && DayLayout.dropGrid(count: 1, at: CGPoint(x: 5, y: 6)) == [CGPoint(x: 5, y: 6)])
}

@Test func arrowsMoveToTheNearestCardThatWay() {
    let cards: [(id: String, center: CGPoint)] = [("a", CGPoint(x: 0, y: 0)), ("right", CGPoint(x: 400, y: 20)), ("far", CGPoint(x: 900, y: 0)),
                                                  ("below", CGPoint(x: 30, y: 300)), ("diagonal", CGPoint(x: 300, y: 260))]
    let from = CGPoint.zero
    #expect(DayLayout.neighbour(of: from, toward: CGVector(dx: 1, dy: 0), among: cards) == "right")
    #expect(DayLayout.neighbour(of: from, toward: CGVector(dx: 0, dy: 1), among: cards) == "below")
    #expect(DayLayout.neighbour(of: from, toward: CGVector(dx: -1, dy: 0), among: cards) == nil)
    #expect(DayLayout.neighbour(of: from, toward: CGVector(dx: 0, dy: -1), among: cards) == nil)
}

@Test func weekLapsePlaysBusyDaysLonger() {
    let lapse = Replay.weekLapse([2, 0, 1, 0, 0, 0, 3])
    #expect(abs(lapse.length - (3 * 1.6 + 4 * 0.4)) < 1e-9)
    #expect(abs(lapse.hour(at: 1.6) - 24) < 1e-9 && abs(lapse.hour(at: 2.0) - 48) < 1e-9)
    #expect(abs(lapse.time(at: 48) - 2.0) < 1e-9)
}
