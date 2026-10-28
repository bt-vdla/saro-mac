import Foundation

extension Pipeline {
    /// The SafetyGate over the person's own words stored outside an entry (an answer, a mood note). nil when the classifier
    /// was rate-limited: there is no verdict yet, so nothing is stored.
    public func check(_ text: String) async -> GateResult? {
        await gate.gate(text: text, transcriptConfidence: nil)
    }

    /// The gate's verdicts on the day's answers, archived ones too, and its mood note.
    func reflectionVerdicts(_ day: String) async -> [String] {
        let turns = (try? await ledger.turns(day: day, includeArchived: true)) ?? []
        return turns.compactMap(\.answerVerdict) + [try? await ledger.dayState(day).moodNoteVerdict].compactMap { $0 ?? nil }
    }

    /// An answered daily question is the person's, so it stays through every re-read (CONTRACT §4), with who chose it.
    func answeredQuestion(_ day: String) async -> ReflectionTurn? {
        try? await ledger.turns(day: day, kind: .dailyQuestion).last { $0.answer != nil }
    }

    /// The day's entries as the narrative reads them, oldest first: those the gate cleared for their current text, with
    /// their stored quote, and those with no words to read (a bare still, a silent recording), counted but never quoted.
    func narrativeEntries(_ day: String) async -> [NarrativeEntry] {
        guard let entries = try? await ledger.entries(day: day) else { return [] }
        let verdicts = (try? await ledger.verdicts(day: day)) ?? [:]
        let annotations = (try? await ledger.annotations(day: day)) ?? [:]
        var out: [NarrativeEntry] = []
        for e in entries {
            guard let src = try? await text(for: e), !src.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                out.append(NarrativeEntry(id: e.id, kind: e.kind, day: day))
                continue
            }
            guard let v = verdicts[e.id], v.verdict == "clear" || v.verdict == "unavailable_clear", sha256(src.text) == v.textSha256 else { continue }
            let current = (try? await ledger.hasAnnotation(entryId: e.id, inputHash: v.textSha256)) == true
            let quote = current ? annotations[e.id].flatMap { a in
                a.quote.map { Candidate(index: 0, entryId: e.id, field: a.quoteField ?? src.field, text: $0, utf16From: a.quoteFrom ?? 0,
                                        utf16To: a.quoteTo ?? 0) }
            } : nil
            switch e.kind {
            case .still: out.append(NarrativeEntry(id: e.id, kind: e.kind, day: day, label: src.text))
            case .music: out.append(NarrativeEntry(id: e.id, kind: e.kind, day: day, label: e.titleUser))
            case .reflection, .moment, .voice:
                out.append(NarrativeEntry(id: e.id, kind: e.kind, day: day, text: src.text, field: src.field, quote: quote))
            }
        }
        return out
    }

    /// The 13 days before `day`, oldest first, for the narrative's recurrence line. Only days whose reading may show.
    // ponytail: read again with every day reading (13 small queries); keep a per-day theme index if journals grow long.
    func recentNarrativeEntries(before day: String) async -> [NarrativeEntry] {
        var out: [NarrativeEntry] = []
        for i in (1...13).reversed() {
            let d = LocalDay.adding(-i, to: day)
            if await dayStatus(d) == .ready { out += await narrativeEntries(d) }
        }
        return out
    }

    /// Whether the model's prose puts the person's name inside quote marks, as though they had said it.
    static func quotesName(_ text: String, _ name: String?) -> Bool {
        guard let name, !name.isEmpty else { return false }
        return text.matches(of: /["“]([^"“”]+)["”]/).contains { $0.1.localizedCaseInsensitiveContains(name) }
    }

    /// Refresh question (ai.ts demoRefreshQuestion): an answered pair is archived, and a curated question asked neither
    /// today nor in the last 7 days takes its place, in a new snapshot of the same reading marked as curated, so the
    /// panel never shows Saro's list under the model's name.
    public func refreshQuestion(_ day: String) async -> DayPayload? {
        guard await dayStatus(day) == .ready, let last = try? await ledger.latestSnapshot(kind: "day_reading", day: day),
              var payload = try? JSONDecoder().decode(DayPayload.self, from: Data(last.payload.utf8)) else { return nil }
        for t in (try? await ledger.turns(day: day, kind: .dailyQuestion)) ?? [] { try? await ledger.archiveTurn(id: t.id) }
        var exclude = (try? await ledger.recentQuestions(day: day, includingDay: true)) ?? []
        if let q = payload.reading.question { exclude.append(q) }
        let corpus = await narrativeEntries(day).map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
        payload.reading.question = Heuristics.pickQuestion(themes: Heuristics.analyzeText(corpus).themes,
                                                           seed: Heuristics.seed("\(day)\n\(corpus)\n\(exclude.count)"),
                                                           exclude: exclude, tone: await ai.tone)
        payload.questionGenerator = "curated"
        guard let json = try? JSONEncoder().encode(payload), let text = String(data: json, encoding: .utf8) else { return nil }
        do {
            try await ledger.insertSnapshot(InsightSnapshot(kind: "day_reading", day: day, aiRunId: last.aiRunId, generator: last.generator,
                                                            inputHash: last.inputHash, payload: text))
            return payload
        } catch {
            return nil
        }
    }

    /// The day's mood for the ribbon and the letter: the person's own when they set one, else the reading's; none unless the
    /// day's reading may show (§13.2).
    public func dayMood(_ day: String) async -> Mood? {
        guard await dayStatus(day) == .ready else { return nil }
        if let mood = try? await ledger.dayState(day).lockedMood { return mood }
        return await latestDayReading(day)?.payload.reading.mood
    }

    /// The first week's moments from `start` (FR-REF-10): only entries the gate cleared for their current text, from
    /// days whose reading may show (a day held, awaiting a check or still being read gives none, SR-13, SR-14), as their
    /// stored quotes, readings and moods.
    public func weekEntries(from start: String, days: Int = 7) async -> [WeekEntry] {
        var out: [WeekEntry] = []
        for i in 0..<days {
            let d = LocalDay.adding(i, to: start)
            guard await dayStatus(d) == .ready, let entries = try? await ledger.entries(day: d) else { continue }
            let verdicts = (try? await ledger.verdicts(day: d)) ?? [:]
            let annotations = (try? await ledger.annotations(day: d)) ?? [:]
            for e in entries {
                guard let v = verdicts[e.id], v.verdict == "clear" || v.verdict == "unavailable_clear", let a = annotations[e.id],
                      let src = try? await text(for: e), sha256(src.text) == v.textSha256,
                      (try? await ledger.hasAnnotation(entryId: e.id, inputHash: v.textSha256)) == true else { continue }
                out.append(WeekEntry(id: e.id, at: e.capturedAt, words: [a.quote, a.title, a.summary].compactMap { $0 }.joined(separator: "\n"),
                                     quote: a.quote, mood: a.moodLabel.flatMap(Mood.init(rawValue:))))
            }
        }
        return out
    }

    /// Whether a stored first-week note may still show, by the days its moments are on (SR-13, SR-14, SR-15): `.held`
    /// when one of those days was since held or a moment is gone, so the note is dropped; `.ready` when every one may
    /// show; any other status hides it until those days are read.
    public func weekNoteStatus(_ note: WeekNote) async -> DayStatus {
        var days: Set<String> = []
        for id in note.sources {
            guard let e = try? await ledger.entry(id), e.trashedAt == nil else { return .held }
            days.insert(e.localDay)
        }
        var status = DayStatus.ready
        for d in days {
            switch await dayStatus(d) {
            case .held: return .held
            case .ready: continue
            case let other: status = other
            }
        }
        return status
    }

    /// Answers and mood notes checked while the model couldn't run are checked again once it can (SR-17).
    public func regateReflections(_ day: String) async {
        guard ai.status == .available else { return }
        for t in (try? await ledger.turns(day: day, includeArchived: true)) ?? [] where t.answerVerdict?.hasPrefix("unavailable") == true {
            guard let answer = t.answer, let r = await check(answer) else { continue }
            try? await ledger.setTurnAnswer(id: t.id, answer: answer, verdict: r.verdict)
        }
        if let s = try? await ledger.dayState(day), s.moodNoteVerdict?.hasPrefix("unavailable") == true, let note = s.moodNote,
           let mood = s.moodUser, let r = await check(note) {
            try? await ledger.setUserMood(day: day, label: mood, note: note, verdict: r.verdict)
        }
    }
}
