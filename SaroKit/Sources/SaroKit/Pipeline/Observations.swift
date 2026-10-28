import Foundation

extension Pipeline {
    /// Learns what one entry's current text says about the person (FR-MEM-01/02, DR-14, DR-17), after the pipeline has
    /// gated and read it. Only cleared text is read. Nothing is learned while memory is paused, from text written or
    /// edited inside a pause, from before forget-everything, or from a still's own description; such text gets a
    /// content-free run, so the backfill doesn't ask again. An edit retracts the rows of the old text (`source_edited`)
    /// and learns again. Forgotten keys are never written. Returns whether anything changed.
    @discardableResult
    public func learn(entryId: String) async -> Bool {
        guard let entry = try? await ledger.entry(entryId), entry.trashedAt == nil else { return false }
        let src = try? await text(for: entry)
        let text = src?.text ?? ""
        let hash = sha256(text)
        let standing = (try? await ledger.standingObservations(entryId: entryId)) ?? []
        // A still's own description is Saro's words, never the person's (P-STILLS): it teaches memory nothing, and
        // whatever it taught goes.
        let saros = src?.field == Self.aiCaptionField
        let stale = standing.filter { saros || $0.textSha256 != hash }
        func retractStale() async -> Bool {
            guard !stale.isEmpty else { return false }
            try? await ledger.retract(stale.map(\.id), reason: "source_edited")
            return true
        }

        guard let src, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let v = (try? await ledger.verdicts(day: entry.localDay))?[entryId], v.textSha256 == hash,
              v.verdict == "clear" || v.verdict == "unavailable_clear" else { return await retractStale() }
        let version = MemoryRules.extractorVersion
        let learned = (try? await ledger.memoryLearned(entryId: entryId, textSha256: hash, extractor: version)) == true
        // Learned, unless its rows were retracted since (an edit and back again): then it is read afresh.
        if learned {
            let ever = (try? await ledger.observedEver(entryId: entryId, textSha256: hash)) == true
            if saros || standing.contains(where: { $0.textSha256 == hash }) || !ever { return await retractStale() }
        }
        guard let profile = try? await ledger.profile(), !profile.memoryPaused else { return await retractStale() }

        var run = AIRun(feature: Ledger.memoryFeature, executor: "heuristic", status: "ok")
        run.ladderRung = Rung.heuristic.rawValue
        run.osBuild = SaroAI.osBuild
        run.extractorVersion = version
        run.promptVersion = SaroAI.memoryPromptVersion
        run.inputHash = hash
        run.modelCalls = 0
        run.latencyMs = 0
        run.localDay = entry.localDay
        let inputs = [AIRunInput(entryId: entryId, field: src.field, text: text)]

        let pauses = (try? await ledger.pauses()) ?? []
        let edited = (try? await ledger.firstVerdictAt(entryId: entryId, textSha256: hash)) ?? entry.capturedAt
        let cutoff = try? await ledger.forgotAllAt()
        let paused = pauses.contains { $0.contains(entry.capturedAt) || $0.contains(edited) }
        if saros || paused || cutoff.map({ entry.capturedAt <= $0 }) == true {
            run.status = saros ? "not_their_words" : paused ? "paused" : "forgotten"
            try? await ledger.insertObservations([], run: run, inputs: inputs, retracting: stale)
            return !stale.isEmpty
        }

        // The entry reading's mood and quote, when the reading is of this text: one lineage per entry (DR-13).
        let annotation = (try? await ledger.annotations(day: entry.localDay))?[entryId]
        let reading = (try? await ledger.hasAnnotation(entryId: entryId, inputHash: hash)) == true ? annotation : nil
        let moodQuote = reading.flatMap { a -> Candidate? in
            guard let q = a.quote, let from = a.quoteFrom, let to = a.quoteTo, a.quoteField == src.field else { return nil }
            return Candidate(index: 0, entryId: entryId, field: src.field, text: q, utf16From: from, utf16To: to)
        }
        var rows = MemoryRules.observe(entryId: entryId, field: src.field, text: text, localDay: entry.localDay,
                                       mood: reading?.moodLabel.flatMap(Mood.init(rawValue:)), moodQuote: moodQuote)

        if v.verdict == "clear", ai.status == .available {
            let candidates = Heuristics.candidates(entryId: entryId, field: src.field, text: text)
            let (picks, prov) = await ai.extractMemory(text: text, candidates: candidates)
            switch prov.status {
            case "rate_limited":
                return await retractStale() // deferred (§11.7): no run, so the next pass or the backfill reads it
            case "output_gate":
                // Layer 3 (SR-08): a hit in the reply holds the entry, as the entry reading does; the hold drops its rows.
                try? await ledger.insertVerdict(SafetyVerdictRow(entryId: entryId, textSha256: hash, safetyVersion: SafetyGate.version,
                                                                layer: 3, verdict: "safety_hold", reasonCode: "output_gate"))
                return true
            default: break
            }
            run.executor = prov.executor
            run.ladderRung = prov.rung.rawValue
            run.guardrails = prov.guardrails
            run.variant = prov.variant
            run.contextSize = prov.contextSize
            run.sampling = "greedy"
            run.modelCalls = prov.modelCalls
            run.latencyMs = prov.latencyMs
            run.status = prov.status
            if let picks {
                // The model's people, themes and intentions replace the heuristic's; places and the feeling stay NLTagger's
                // and the reading's.
                rows = rows.filter { [.place, .org, .emotion].contains($0.kind) }
                    + picks.map { Self.observation($0, text: text, hash: hash, day: entry.localDay) }
            }
        }

        let tombstones = (try? await ledger.tombstoneHashes()) ?? []
        // A feeling's lineage is the reading it came from (DR-13). Without a reading mood it is the heuristic's, which a
        // model run mustn't claim, so it is left out then.
        let readingMood = reading?.moodLabel != nil
        rows = MemoryRules.dedupe(rows).filter { o in
            !tombstones.contains(sha256(o.key)) && (o.kind != .emotion || readingMood || run.executor == "heuristic")
        }.map { o in
            var o = o
            if o.kind == .emotion, readingMood { o.aiRunId = reading?.aiRunId }
            return o
        }
        do {
            try await ledger.insertObservations(rows, run: run, inputs: inputs, retracting: stale)
            return true
        } catch {
            return await retractStale()
        }
    }

    /// Where a quote at UTF-16 `offset` of a transcript (as `join` spells it) starts playing: its word's start.
    public static func startMs(atUTF16 offset: Int, in words: [TranscriptWord]) -> Int? {
        var at = 0
        for w in words {
            for part in w.text.split(whereSeparator: \.isWhitespace) {
                at += part.utf16.count
                if offset < at { return w.startMs }
                at += 1
            }
        }
        return words.last?.startMs
    }

    static func observation(_ p: ExtractedObservation, text: String, hash: String, day: String) -> MemoryObservation {
        let c = p.candidate
        let (kind, key, label): (MemoryObservation.Kind, String, String) = switch p.kind {
        case .person(let name):
            (.person, "person:\(name.replacingOccurrences(of: #"['’]s$"#, with: "", options: .regularExpression).lowercased())", name)
        case .theme(let t): (.theme, "theme:\(t.rawValue)", t.rawValue)
        case .intention:
            MemoryRules.intention(in: c.text).map { (.intention, "intent:\($0.label.lowercased())", $0.label) }
                ?? (.intention, "intent:\(c.text.lowercased())", c.text) // picks already passed MemoryRules.intention
        }
        return MemoryObservation(entryId: c.entryId, kind: kind, key: key, label: label, quote: c.text, field: c.field, spanStart: c.utf16From,
                           spanEnd: c.utf16To, textSha256: hash, localDay: day)
    }
}
