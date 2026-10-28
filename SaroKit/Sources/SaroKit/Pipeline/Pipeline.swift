import Foundation

/// What a day reading snapshot stores: the reading plus the verbatim quotes it picked, so the letter and
/// "What Saro noticed" never re-derive text.
public struct DayPayload: Codable, Sendable, Hashable {
    public var reading: DayReading
    public var quotes: [Candidate]
    public var entryIds: [String]
    /// The counted, quoted narrative and last-inferred line; nil in readings stored before it existed.
    public var narrative: Narrative?
    /// Who chose the question when it isn't the reading's own: 'curated' once Refresh question picked it from Saro's list.
    public var questionGenerator: String?
}

/// Where a day stands for its reading (§13.2 whole-day rules).
public enum DayStatus: Sendable, Hashable {
    case empty
    /// Some entries are still being transcribed, checked or read.
    case working
    /// A safety hold anywhere that day: no reading, letter or quotes (SR-13).
    case held
    /// An entry with a caution hit or no verdict: nothing until it is checked (SR-14).
    case awaitingCheck
    case ready
}

/// Takes one saved entry through transcription → SafetyGate → per-entry reading, and reads a day from the stored
/// annotations. The caller runs one job at a time (§11.7: one model call at a time).
public actor Pipeline {
    public static let candidatesPerEntryInDay = 6
    let ledger: Ledger
    let ai: SaroAI
    let gate: SafetyGate
    var stillsToDescribe: Set<String> = []

    public init(ledger: Ledger, ai: SaroAI) {
        self.ledger = ledger
        self.ai = ai
        // Always wired: SaroAI.classify answers `.unavailable` itself while the model can't run, so a model that
        // becomes ready mid-session is used without a relaunch.
        gate = SafetyGate(classify: { @Sendable text in
            await ai.classify(text, instructions: SafetyGate.classifierInstructions, prompt: SafetyGate.classifierPrompt(for: "{text}"))
        })
    }

    /// The text an entry offers the gate and the model, the field it came from, and transcript confidence.
    func text(for entry: Entry) async throws -> (text: String, field: String, confidence: Double?)? {
        switch entry.kind {
        case .reflection, .music:
            return (entry.body ?? "", "body", nil)
        case .still:
            return try await stillText(entry)
        case .moment, .voice:
            guard let id = entry.mediaId else { return nil }
            let words = try await ledger.transcript(mediaId: id)
            guard !words.isEmpty else { return nil }
            let conf = words.compactMap(\.confidence)
            return (Self.join(words), "transcript", conf.isEmpty ? nil : conf.reduce(0, +) / Double(conf.count))
        }
    }

    static func join(_ words: [TranscriptWord]) -> String {
        words.map(\.text).joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Runs every step that hasn't run for this entry yet. `onStatus` is called after each status change.
    public func process(entryId: String, onStatus: @Sendable () async -> Void) async {
        // A song is a link the person kept, read offline from its URL: nothing gates or reads it, so no part of a link is
        // ever quoted back (a restore from Trash queues it like any entry).
        guard let entry = try? await ledger.entry(entryId), entry.trashedAt == nil, entry.kind != .music else { return }
        func status(_ s: String) async {
            try? await ledger.setProcessingStatus(s, startedFrom: entry)
            await onStatus()
        }

        // 1. Transcript of record (moments and voice notes).
        if entry.kind == .moment || entry.kind == .voice {
            guard let mid = entry.mediaId, let media = try? await ledger.media(mid) else { return }
            if media.state == "recording" { return }
            guard media.state == "ready" else {
                // A file that went missing or failed can't be transcribed; don't leave the day waiting on it.
                await status(ProcessingStatus.failed)
                return
            }
            if (try? await ledger.transcript(mediaId: mid))?.isEmpty ?? true {
                await status(ProcessingStatus.transcribing)
                do {
                    let r = try await Transcriber.transcribe(url: ledger.url(for: media))
                    try await ledger.setTranscript(mediaId: mid, words: r.words, extractorVersion: r.extractorVersion)
                } catch {
                    await status(ProcessingStatus.transcriptUnavailable)
                    return
                }
            }
        }
        // 1b. Saro's description of a still (Pipeline+Stills).
        guard await describeStillIfDue(entry, onStatus: onStatus) else { return }

        guard let source = try? await text(for: entry), !source.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await status(ProcessingStatus.done)
            return
        }

        // 2. SafetyGate, cached by text hash and gate version (SR-17, SR-18).
        let hash = sha256(source.text)
        var verdict = try? await ledger.cachedVerdict(entryId: entryId, textSha256: hash, safetyVersion: SafetyGate.version)
        // A verdict made while the model couldn't run is re-gated once it can (SR-17).
        if let v = verdict?.verdict, v.hasPrefix("unavailable"), ai.status == .available { verdict = nil }
        if verdict == nil {
            await status(ProcessingStatus.gating)
            guard let r = await gate.gate(text: source.text, transcriptConfidence: source.confidence) else {
                // Rate-limited (§11.7): no verdict yet. Pending, so the next pass or the launch sweep checks it.
                await status(ProcessingStatus.pending)
                return
            }
            let row = SafetyVerdictRow(entryId: entryId, textSha256: hash, safetyVersion: SafetyGate.version, layer: r.layer,
                                       verdict: r.verdict, reasonCode: r.reasonCode)
            try? await ledger.insertVerdict(row)
            verdict = row
        } else if let cached = verdict, (try? await ledger.verdicts(day: entry.localDay))?[entryId]?.id != cached.id {
            // An edit back to text gated before: its verdict is restated as the newest, which the day and the canvas read.
            let row = SafetyVerdictRow(entryId: entryId, textSha256: hash, safetyVersion: SafetyGate.version, layer: cached.layer,
                                       verdict: cached.verdict, reasonCode: cached.reasonCode)
            try? await ledger.insertVerdict(row)
            verdict = row
        }
        guard let v = verdict?.verdict, v == "clear" || v == "unavailable_clear" else {
            await status(ProcessingStatus.done)
            return
        }
        if source.field == Self.aiCaptionField {
            await keepStillCaptionCurrent(entryId, hash: hash)
            await status(ProcessingStatus.done)
            return
        }

        // 3. Per-entry reading on the ladder; "In your words" when the model can't run. Skipped if this text was read,
        //    unless only the heuristic read it and the model now can (a re-gate after Apple Intelligence came back).
        if (try? await ledger.hasAnnotation(entryId: entryId, inputHash: hash, needsModel: v == "clear" && ai.status == .available)) == true {
            await status(ProcessingStatus.done)
            return
        }
        await status(ProcessingStatus.reading)
        let candidates = Heuristics.candidates(entryId: entryId, field: source.field, text: source.text)
        let fallback = Heuristics.heuristicReading(text: source.text, candidates: candidates)
        let text = source.text
        let reading: EntryReading
        let prov: Provenance
        if v == "clear" {
            (reading, prov) = await ai.readEntry(entryId: entryId, text: text, candidates: candidates, fallback: fallback) { r in
                Heuristics.driftOK(generated: "\(r.title). \(r.summary)", source: text)
            }
        } else {
            (reading, prov) = (fallback, Provenance(executor: "heuristic", rung: .heuristic, guardrails: nil, variant: nil,
                                                    osBuild: SaroAI.osBuild, contextSize: nil, promptVersion: SaroAI.entryPromptVersion,
                                                    tokensIn: nil, modelCalls: 0, latencyMs: 0))
        }
        if prov.status == "rate_limited" {
            // Deferred, not failed (§11.7): nothing stored, so a later pass reads it.
            await status(ProcessingStatus.pending)
            return
        }

        // Layer 3 over whatever was generated, heuristic included (SR-08): the ladder stops on a hit in any reply, and
        // the result is checked again here. A hit stores nothing but a verdict.
        if prov.status == "output_gate" || SafetyGate.phraseHit(reading.prose) {
            try? await ledger.insertVerdict(SafetyVerdictRow(entryId: entryId, textSha256: hash, safetyVersion: SafetyGate.version,
                                                            layer: 3, verdict: "safety_hold", reasonCode: "output_gate"))
            await status(ProcessingStatus.done)
            return
        }

        // A guardrail or refusal is recorded, so the day reading never re-sends this entry to the permissive rung.
        var run = AIRun(feature: "entry_reading", executor: prov.executor, status: prov.status)
        run.guardrails = prov.guardrails
        run.ladderRung = prov.rung.rawValue
        run.osBuild = prov.osBuild
        run.variant = prov.variant
        run.contextSize = prov.contextSize
        run.sampling = "greedy"
        run.promptVersion = prov.promptVersion
        run.inputHash = hash
        run.tokensIn = prov.tokensIn
        run.modelCalls = prov.modelCalls
        run.latencyMs = prov.latencyMs
        run.localDay = entry.localDay
        var a = EntryAnnotation(entryId: entryId, aiRunId: run.id, generator: prov.executor)
        a.title = reading.title
        a.summary = reading.summary
        a.moodLabel = reading.mood.rawValue
        a.moodBasis = reading.moodBasis
        if let i = reading.quoteIndex, let c = candidates.first(where: { $0.index == i }) {
            a.quote = c.text
            a.quoteField = c.field
            a.quoteFrom = c.utf16From
            a.quoteTo = c.utf16To
        }
        do {
            try await ledger.insertRun(run, inputs: [AIRunInput(entryId: entryId, field: source.field, text: text)])
            try await ledger.insertAnnotation(a)
            await status(ProcessingStatus.done)
        } catch {
            await status(ProcessingStatus.failed)
        }
    }

    // MARK: Day

    public func dayStatus(_ day: String) async -> DayStatus {
        guard let entries = try? await ledger.entries(day: day), !entries.isEmpty else { return .empty }
        let verdicts = (try? await ledger.verdicts(day: day)) ?? [:]
        var states: [EntryState] = []
        for e in entries {
            let src = try? await text(for: e)
            // Emptied text has nothing left to read, whatever was gated before (a cleared page or still caption).
            if let src, src.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if let v = verdicts[e.id] {
                // A verdict only counts for the text it was given: edited text is unchecked until it is gated again.
                if let src, sha256(src.text) != v.textSha256 { return .working }
                states.append(EntryState(verdict: v.verdict))
                continue
            }
            switch e.processingStatus {
            case ProcessingStatus.done, ProcessingStatus.failed: continue // nothing to read (a silent recording, a bare still)
            case ProcessingStatus.transcriptUnavailable: states.append(.awaitingCheck)
            default: return .working
            }
        }
        // The person's answers and mood note are their words too: a hold on one holds the day (SR-13). Only entries
        // make it ready, though: an answer alone leaves nothing to read.
        let readable = states.contains(.clear) || states.contains(.modelUnavailable)
        switch SafetyGate.dayGate(states + (await reflectionVerdicts(day)).map(EntryState.init(verdict:))) {
        case .safetyHeld: return .held
        case .awaitingCheck: return .awaitingCheck
        case .allowed: return readable ? .ready : .empty
        }
    }

    /// The day reading behind "What Saro noticed" and the letter. Map-reduce: the model sees only stored per-entry
    /// annotations plus numbered verbatim candidates, never raw history. Skipped when the inputs haven't changed, unless
    /// `force`d (Refresh, which samples with `seed` and rotates past the `avoid` title). An answered question stays.
    @discardableResult
    public func readDay(_ day: String, force: Bool = false, avoid: String? = nil, seed: UInt64? = nil) async -> DayPayload? {
        guard await dayStatus(day) == .ready, let entries = try? await ledger.entries(day: day) else { return nil }
        let verdicts = (try? await ledger.verdicts(day: day)) ?? [:]
        let annotations = (try? await ledger.annotations(day: day)) ?? [:]
        var digests: [EntryDigest] = []
        var candidates: [Candidate] = []
        var inputs: [AIRunInput] = []
        var sources: [String] = []
        let modelOK = ai.status == .available && entries.allSatisfy { verdicts[$0.id].map { $0.verdict != "unavailable_clear" } ?? true }
        for e in entries {
            // Only a reading of exactly the current text: one deferred by a rate limit leaves the older reading newest.
            guard let row = verdicts[e.id], row.verdict == "clear" || row.verdict == "unavailable_clear",
                  let a = annotations[e.id], let src = try? await text(for: e), sha256(src.text) == row.textSha256,
                  (try? await ledger.hasAnnotation(entryId: e.id, inputHash: row.textSha256)) == true else { continue }
            digests.append(EntryDigest(entryId: e.id, kind: e.kind.rawValue, time: e.capturedAt.formatted(date: .omitted, time: .shortened),
                                       title: a.title ?? e.kind.rawValue, summary: a.summary ?? "", mood: a.moodLabel.flatMap(Mood.init(rawValue:))))
            // Only the user's own words are quoted: a still's description is its digest, never a candidate.
            if src.field != Self.aiCaptionField {
                candidates += Heuristics.candidates(entryId: e.id, field: src.field, text: src.text, firstIndex: candidates.count)
                    .prefix(Self.candidatesPerEntryInDay)
            }
            inputs.append(AIRunInput(entryId: e.id, field: src.field, text: src.text))
            sources.append(src.text)
        }
        guard !digests.isEmpty else { return nil }
        let told = await narrativeEntries(day)
        // The model's mark is one-way: a reading made without the model gives way once it can run, but the model's own
        // reading still stands while it briefly can't.
        let key = digests.map { "\($0.entryId)|\($0.title)|\($0.summary)|\($0.mood?.rawValue ?? "")" }.joined(separator: "\n")
            + candidates.map(\.text).joined(separator: "\n") + told.map { "\n\($0.kind.rawValue)|\($0.id)" }.joined()
        let (marked, unmarked) = (sha256(key + "\nmodel"), sha256(key))
        let last = try? await ledger.latestSnapshot(kind: "day_reading", day: day)
        let previous = last.flatMap { try? JSONDecoder().decode(DayPayload.self, from: Data($0.payload.utf8)) }
        if !force, let last, last.inputHash == marked || !modelOK && last.inputHash == unmarked, let previous, previous.narrative != nil {
            return previous
        }

        let source = sources.joined(separator: "\n")
        let exclude = (try? await ledger.recentQuestions(day: day, includingDay: false)) ?? []
        let (tone, known, name) = await (ai.tone, ai.known, ai.name)
        let fallback = Heuristics.heuristicDayReading(digests: digests, candidates: candidates, exclude: exclude, tone: tone)
        var reading: DayReading
        let prov: Provenance
        if modelOK {
            // §11.3: an entry the model refused is never re-sent to the permissive rung, so its day starts on guided.
            let refused = (try? await ledger.refusedEntryIDs(day: day)) ?? []
            // §11.6: the drift check covers all the prose the day shows, the question and mood basis included. The person's
            // name is known, not invented, but is never quoted as their words.
            let grounds = ([source] + known).joined(separator: "\n")
            (reading, prov) = await ai.readDay(day: day, digests: digests, candidates: candidates, fallback: fallback,
                                               permissiveOK: refused.isDisjoint(with: digests.map(\.entryId)), seed: seed,
                                               avoid: force ? previous?.reading.narrative : nil, exclude: exclude) { r in
                [r.narrative, r.question, r.moodBasis].allSatisfy { $0.map { Heuristics.driftOK(generated: $0, source: grounds) } ?? true }
                    && !Self.quotesName(r.narrative ?? "", name)
            }
        } else {
            (reading, prov) = (fallback, Provenance(executor: "heuristic", rung: .heuristic, guardrails: nil, variant: nil, osBuild: SaroAI.osBuild,
                                                    contextSize: nil, promptVersion: SaroAI.dayPromptVersion, tokensIn: nil, modelCalls: 0, latencyMs: 0))
        }
        if prov.status == "rate_limited" { return nil } // deferred (§11.7): the next readDay asks again
        let locked = await answeredQuestion(day)
        if let locked { reading.question = locked.question }
        let narrative = DayNarrative.draft(day: day, entries: told, recent: await recentNarrativeEntries(before: day), avoidTitle: avoid)
        // Layer 3 (SR-08): a hit holds every entry the reading drew on, so the whole day is held and nothing is stored.
        if prov.status == "output_gate" || SafetyGate.phraseHit(reading.prose + "\n" + (narrative?.prose ?? "")) {
            for d in digests {
                guard let row = verdicts[d.entryId] else { continue }
                try? await ledger.insertVerdict(SafetyVerdictRow(entryId: d.entryId, textSha256: row.textSha256, safetyVersion: SafetyGate.version,
                                                                layer: 3, verdict: "safety_hold", reasonCode: "output_gate"))
            }
            return nil
        }

        // Stored unmarked when the model's assets went missing mid-ladder: the model never read this day.
        let inputHash = modelOK && prov.status != "assetsUnavailable" ? marked : unmarked
        let picked = reading.quoteIndexes.compactMap { i in candidates.first { $0.index == i } }
        let payload = DayPayload(reading: reading, quotes: picked, entryIds: digests.map(\.entryId), narrative: narrative,
                                 questionGenerator: locked.flatMap { $0.generator == "curated" ? "curated" : nil })
        var run = AIRun(feature: "day_reading", executor: prov.executor, status: prov.status)
        run.guardrails = prov.guardrails
        run.ladderRung = prov.rung.rawValue
        run.osBuild = prov.osBuild
        run.variant = prov.variant
        run.contextSize = prov.contextSize
        // The heuristic twin samples nothing, a refresh included.
        run.sampling = prov.executor == "heuristic" ? nil : seed.map { "random:\($0)" } ?? "greedy"
        run.promptVersion = prov.promptVersion
        run.inputHash = inputHash
        run.tokensIn = prov.tokensIn
        run.modelCalls = prov.modelCalls
        run.latencyMs = prov.latencyMs
        run.localDay = day
        guard let json = try? JSONEncoder().encode(payload), let text = String(data: json, encoding: .utf8) else { return nil }
        do {
            try await ledger.insertRun(run, inputs: inputs)
            try await ledger.insertSnapshot(InsightSnapshot(kind: "day_reading", day: day, aiRunId: run.id, generator: prov.executor,
                                                            inputHash: inputHash, payload: text))
            return payload
        } catch {
            return nil
        }
    }

    public func latestDayReading(_ day: String) async -> (payload: DayPayload, generator: String, runId: String?)? {
        guard let s = try? await ledger.latestSnapshot(kind: "day_reading", day: day),
              var p = try? JSONDecoder().decode(DayPayload.self, from: Data(s.payload.utf8)) else { return nil }
        // A reading older than an edit (its successor deferred) keeps only the quotes still verbatim in the text (§11.6);
        // a narrative that quotes words no longer there waits for the next reading.
        var kept: [Candidate] = []
        for q in p.quotes { if await verbatim(q) { kept.append(q) } }
        p.quotes = kept
        for q in p.narrative?.quotes ?? [] { if await !verbatim(q) { p.narrative = nil } }
        return (p, s.generator, s.aiRunId)
    }

    func verbatim(_ q: Candidate) async -> Bool {
        guard let e = try? await ledger.entry(q.entryId), e.trashedAt == nil, let src = try? await text(for: e), src.field == q.field
        else { return false }
        let ns = src.text as NSString
        return q.utf16From >= 0 && q.utf16From <= q.utf16To && q.utf16To <= ns.length
            && ns.substring(with: NSRange(location: q.utf16From, length: q.utf16To - q.utf16From)) == q.text
    }
}
