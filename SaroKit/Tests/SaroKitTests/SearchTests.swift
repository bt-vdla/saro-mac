import Foundation
import Testing
@testable import SaroKit

/// A reading and verdicts for the entry's current text (or `text`), as the pipeline writes them.
private func annotate(_ l: Ledger, _ e: Entry, title: String, summary: String? = nil, verdicts: [String], text: String? = nil) async throws {
    let sha = sha256(text ?? (e.kind == .still ? e.captionUser : e.body) ?? "")
    var run = AIRun(feature: "entry", executor: "heuristic", status: "ok")
    run.inputHash = sha
    try await l.insertRun(run)
    var a = EntryAnnotation(entryId: e.id, aiRunId: run.id, generator: "on_device")
    a.title = title
    a.summary = summary
    try await l.insertAnnotation(a)
    for v in verdicts {
        try await l.insertVerdict(SafetyVerdictRow(entryId: e.id, textSha256: sha, safetyVersion: "1", layer: 1, verdict: v, reasonCode: v))
    }
}

@Test func matchesIgnoringCaseAndDiacriticsAcrossWords() async throws {
    let l = try tempLedger()
    let e = Entry(kind: .reflection, body: "Chai at the Café with Ravi, then the long walk home.")
    try await l.insertEntry(e)
    try await l.insertEntry(Entry(kind: .reflection, body: "Nothing to see here."))
    #expect(try await l.search("cafe").map(\.entryId) == [e.id])
    #expect(try await l.search("RAVI  chai").map(\.entryId) == [e.id])
    #expect(try await l.search("ravi tokyo").isEmpty)
}

@Test func titleOutranksSummaryOutranksBodyThenNewestFirst() async throws {
    let l = try tempLedger()
    let base = Date(timeIntervalSince1970: 1_790_000_000)
    let body = Entry(kind: .reflection, body: "A note about tea.", capturedAt: base.addingTimeInterval(300))
    let older = Entry(kind: .reflection, body: "More about tea.", capturedAt: base)
    let titled = Entry(kind: .reflection, titleUser: "Tea with Ravi", body: "Long day.", capturedAt: base.addingTimeInterval(100))
    let summarised = Entry(kind: .reflection, body: "Long day.", capturedAt: base.addingTimeInterval(200))
    for e in [body, older, titled, summarised] { try await l.insertEntry(e) }
    try await annotate(l, summarised, title: "A long day", summary: "Mostly tea.", verdicts: ["clear"])
    #expect(try await l.search("tea").map(\.entryId) == [titled.id, summarised.id, body.id, older.id])
}

@Test func transcriptsAreJoinedFromTheNewestExtractor() async throws {
    let l = try tempLedger()
    let m = MediaAsset(fileName: "v.mov", kind: .audio, origin: "recorded", state: "ready")
    try await l.insertMedia(m)
    let e = Entry(kind: .voice, mediaId: m.id)
    try await l.insertEntry(e)
    let words = { (s: String) in s.split(separator: " ").enumerated().map { TranscriptWord(text: String($1), startMs: $0 * 300, durMs: 300, confidence: 0.9) } }
    try await l.setTranscript(mediaId: m.id, words: words("old words only"), extractorVersion: "v1")
    try await l.setTranscript(mediaId: m.id, words: words("walked home the long way and the sky was pink"), extractorVersion: "v2")
    let hits = try await l.search("sky was pink")
    #expect(hits.map(\.entryId) == [e.id])
    #expect(hits.first?.snippet == "…the long way and the sky was pink")
    #expect(hits.first?.title == nil)
    #expect(try await l.search("old words").isEmpty)
}

@Test func heldEntriesAreNeverFoundOrTitledByGeneratedText() async throws {
    let l = try tempLedger()
    // Held entries on a day of their own: a hold covers its whole day (SR-13).
    let heldDay = LocalDay.adding(-1, to: LocalDay.today())
    let held = Entry(kind: .reflection, body: "Words of my own.", localDay: heldDay)
    let cleared = Entry(kind: .reflection, body: "Words of my own.")
    let flipped = Entry(kind: .reflection, body: "Words of my own.", localDay: heldDay)
    let unchecked = Entry(kind: .reflection, body: "Words of my own.")
    let unavailable = Entry(kind: .reflection, body: "Words of my own.")
    for e in [held, cleared, flipped, unchecked, unavailable] { try await l.insertEntry(e) }
    try await annotate(l, held, title: "Grief", summary: "A hard anniversary.", verdicts: ["safety_hold"])
    try await annotate(l, cleared, title: "Grief", summary: "A hard anniversary.", verdicts: ["clear"])
    try await annotate(l, flipped, title: "Grief", summary: "A hard anniversary.", verdicts: ["clear", "safety_hold"])
    try await annotate(l, unchecked, title: "Grief", summary: "A hard anniversary.", verdicts: [])
    try await annotate(l, unavailable, title: "Grief", summary: "A hard anniversary.", verdicts: ["unavailable_clear"])
    #expect(Set(try await l.search("grief").map(\.entryId)) == [cleared.id, unavailable.id])
    #expect(Set(try await l.search("anniversary").map(\.entryId)) == [cleared.id, unavailable.id])
    let all = try await l.search("words")
    #expect(all.count == 5)
    for h in all where ![cleared.id, unavailable.id].contains(h.entryId) {
        #expect(h.title == nil)
        #expect(!h.snippet.contains("anniversary"))
    }
}

@Test func copyTextIsTheUsersWordsFirstAndNeverAHeldEntrysGeneratedText() async throws {
    let l = try tempLedger()
    let m = MediaAsset(fileName: "v.mov", kind: .audio, origin: "recorded", state: "ready")
    try await l.insertMedia(m)
    let voice = Entry(kind: .voice, mediaId: m.id)
    let page = Entry(kind: .reflection, titleUser: "Tuesday", body: "Tea with Ravi.")
    let still = Entry(kind: .still, captionUser: "The pink sky")
    let untranscribed = Entry(kind: .voice)
    // On another day: a hold holds its whole day, which aHeldDayShowsNoGeneratedTextForAnyOfItsEntries covers.
    let held = Entry(kind: .voice, localDay: LocalDay.adding(-1, to: LocalDay.today()))
    for e in [voice, page, still, untranscribed, held] { try await l.insertEntry(e) }
    try await l.setTranscript(mediaId: m.id, words: [TranscriptWord(text: "walked", startMs: 0, durMs: 300, confidence: 0.9),
                                                     TranscriptWord(text: "home", startMs: 300, durMs: 300, confidence: 0.9)],
                              extractorVersion: "v1")
    try await annotate(l, voice, title: "A walk", summary: "A walk home.", verdicts: ["clear"])
    try await annotate(l, untranscribed, title: "A walk", summary: "A walk home.", verdicts: ["clear"])
    try await annotate(l, held, title: "Grief", summary: "A hard anniversary.", verdicts: ["safety_hold"])
    let copied = Dictionary(uniqueKeysWithValues: try await l.search("").map { ($0.entryId, $0.copyText) })
    #expect(copied[voice.id] == "walked home")
    #expect(copied[page.id] == "Tea with Ravi.")
    #expect(copied[still.id] == "The pink sky")
    #expect(copied[untranscribed.id] == "A walk home.")
    #expect(copied[held.id] == "")
}

@Test func aHeldDayShowsNoGeneratedTextForAnyOfItsEntries() async throws {
    let l = try tempLedger()
    let days = (1...3).map { LocalDay.adding(-$0, to: LocalDay.today()) }
    let pages = days.map { Entry(kind: .reflection, body: "Words of my own.", localDay: $0) }
    for e in pages { try await l.insertEntry(e) }
    for e in pages { try await annotate(l, e, title: "Grief", summary: "A hard anniversary.", verdicts: ["clear"]) }
    // Held by another page, by an answer, and by the mood note.
    let other = Entry(kind: .reflection, body: "Other words.", localDay: days[0])
    try await l.insertEntry(other)
    try await annotate(l, other, title: "Other", verdicts: ["safety_hold"])
    let turn = ReflectionTurn(kind: .dailyQuestion, question: "What stood out?", generator: "heuristic", localDay: days[1])
    try await l.insertTurn(turn)
    try await l.setTurnAnswer(id: turn.id, answer: "Synthetic answer.", verdict: "safety_hold")
    try await l.setUserMood(day: days[2], label: .anxious, note: "Synthetic note.", verdict: "safety_hold")
    #expect(try await l.search("grief").isEmpty)
    #expect(try await l.search("anniversary").isEmpty)
    for h in try await l.search("") {
        #expect(h.title == nil)
        #expect(!h.snippet.contains("anniversary"))
    }
}

@Test func anEditedEntryShowsNoReadingOfItsOldText() async throws {
    let l = try tempLedger()
    let e = Entry(kind: .reflection, body: "Words of my own.")
    try await l.insertEntry(e)
    try await annotate(l, e, title: "Grief", summary: "A hard anniversary.", verdicts: ["clear"])
    #expect(try await l.search("grief").map(\.entryId) == [e.id])
    try await l.updateEntryText(id: e.id, body: "New words, not yet checked.", titleUser: nil, captionUser: nil)
    #expect(try await l.search("grief").isEmpty)
    #expect(try await l.search("").first?.title == nil)
}

@Test func aStillIsTitledByThePersonsCaptionAndHidesSarosOnAHeldDay() async throws {
    let l = try tempLedger()
    let captioned = Entry(kind: .still, captionUser: "Our walk")
    try await l.insertEntry(captioned)
    try await annotate(l, captioned, title: "A path through a green park.", summary: "A path through a green park.", verdicts: ["clear"])
    #expect(try await l.search("").first?.title == "Our walk")
    let heldDay = LocalDay.adding(-1, to: LocalDay.today())
    let described = Entry(kind: .still, localDay: heldDay)
    let page = Entry(kind: .reflection, body: "Other words.", localDay: heldDay)
    for e in [described, page] { try await l.insertEntry(e) }
    try await annotate(l, described, title: "A path through a green park.", summary: "A path through a green park.",
                       verdicts: ["clear"], text: "A path through a green park.")
    try await annotate(l, page, title: "Other", verdicts: ["safety_hold"])
    #expect(try await l.search("park").map(\.entryId) == [captioned.id])
    #expect(try await l.search("").first { $0.entryId == described.id }?.title == nil)
}

@Test func emptyQueryListsNewestLiveEntriesOfAKind() async throws {
    let l = try tempLedger()
    let base = Date(timeIntervalSince1970: 1_790_000_000)
    let entries = (0..<5).map { Entry(kind: $0 % 2 == 0 ? .reflection : .still, body: "n\($0)", capturedAt: base.addingTimeInterval(Double($0) * 60)) }
    for e in entries { try await l.insertEntry(e) }
    try await l.trash([entries[4].id])
    #expect(try await l.search("", limit: 3).map(\.entryId) == [entries[3].id, entries[2].id, entries[1].id])
    #expect(try await l.search("", kind: .still, limit: 6).map(\.entryId) == [entries[3].id, entries[1].id])
    #expect(try await l.search("n4").isEmpty)
}

@Test func snippetsStartNearTheMatchAndSkipTheTitle() async throws {
    let l = try tempLedger()
    let e = Entry(kind: .reflection, body: "Monday notes\nShipped the onboarding flow finally, and then had chai with Ravi in the evening.")
    try await l.insertEntry(e)
    let hit = try #require(try await l.search("ravi").first)
    #expect(hit.title == "Monday notes")
    #expect(hit.snippet == "…and then had chai with Ravi in the evening.")
    #expect(try await l.search("onboarding").first?.snippet == "Shipped the onboarding flow finally, and then had chai with Ravi in the evening.")
}

@Test func typedDates() throws {
    let now = try #require(LocalDay.date("2026-10-27"))  // a Tuesday
    let cases: [(String, String?)] = [
        ("today", "2026-10-27"), ("Yesterday", "2026-10-26"), ("3 days ago", "2026-10-24"),
        ("tue", "2026-10-27"), ("last tue", "2026-10-20"), ("friday", "2026-10-23"), ("last friday", "2026-10-23"),
        ("mon", "2026-10-26"), ("sun", "2026-10-25"),
        ("12 oct", "2026-10-12"), ("oct 12", "2026-10-12"), ("October 12th", "2026-10-12"), ("12 dec", "2025-12-12"),
        ("2026-10-12", "2026-10-12"), ("2026-02-30", nil), ("30 feb", nil),
        ("tea", nil), ("may", nil), ("fr", nil), ("12/10", nil),
    ]
    for (text, day) in cases { #expect(LocalDay.parse(text, now: now) == day, "\(text)") }
}
