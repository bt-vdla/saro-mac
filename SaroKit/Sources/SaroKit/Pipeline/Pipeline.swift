import Foundation

/// What a day reading snapshot stores: the reading plus the verbatim quotes it picked, so the letter and
/// "What Saro noticed" never re-derive text.
public struct DayPayload: Codable, Sendable, Hashable {
    public var reading: DayReading
    public var quotes: [Candidate]
    public var entryIds: [String]
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
            return (entry.captionUser ?? "", "caption_user", nil)
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
        guard let entry = try? await ledger.entry(entryId), entry.trashedAt == nil else { return }
        func status(_ s: String) async {
            try? await ledger.setProcessingStatus(id: entryId, s)
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
        }
        guard let v = verdict?.verdict, v == "clear" || v == "unavailable_clear" else {
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
        switch SafetyGate.dayGate(states) {
        case .safetyHeld: return .held
        case .awaitingCheck: return .awaitingCheck
        case .allowed: return states.contains(.clear) || states.contains(.modelUnavailable) ? .ready : .empty
        }
    }

    /// The day reading behind "What Saro noticed" and the letter. Map-reduce: the model sees only stored per-entry
    /// annotations plus numbered verbatim candidates, never raw history. Skipped when the inputs haven't changed.
    @discardableResult
    public func readDay(_ day: String) async -> DayPayload? {
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
            candidates += Heuristics.candidates(entryId: e.id, field: src.field, text: src.text, firstIndex: candidates.count)
                .prefix(Self.candidatesPerEntryInDay)
            inputs.append(AIRunInput(entryId: e.id, field: src.field, text: src.text))
            sources.append(src.text)
        }
        guard !digests.isEmpty else { return nil }
        // The model's mark keeps a reading made without the model from standing in once the model can run.
        let inputHash = sha256(digests.map { "\($0.entryId)|\($0.title)|\($0.summary)|\($0.mood?.rawValue ?? "")" }.joined(separator: "\n")
                               + candidates.map(\.text).joined(separator: "\n") + (modelOK ? "\nmodel" : ""))
        if let last = try? await ledger.latestSnapshot(kind: "day_reading", day: day), last.inputHash == inputHash,
           let payload = try? JSONDecoder().decode(DayPayload.self, from: Data(last.payload.utf8)) {
            return payload
        }

        let source = sources.joined(separator: "\n")
        let fallback = Heuristics.heuristicDayReading(digests: digests, candidates: candidates)
        let reading: DayReading
        let prov: Provenance
        if modelOK {
            // §11.3: an entry the model refused is never re-sent to the permissive rung, so its day starts on guided.
            let refused = (try? await ledger.refusedEntryIDs(day: day)) ?? []
            // §11.6: the drift check covers all the prose the day shows, the question and mood basis included.
            (reading, prov) = await ai.readDay(day: day, digests: digests, candidates: candidates, fallback: fallback,
                                               permissiveOK: refused.isDisjoint(with: digests.map(\.entryId))) { r in
                [r.narrative, r.question, r.moodBasis].allSatisfy { $0.map { Heuristics.driftOK(generated: $0, source: source) } ?? true }
            }
        } else {
            (reading, prov) = (fallback, Provenance(executor: "heuristic", rung: .heuristic, guardrails: nil, variant: nil, osBuild: SaroAI.osBuild,
                                                    contextSize: nil, promptVersion: SaroAI.dayPromptVersion, tokensIn: nil, modelCalls: 0, latencyMs: 0))
        }
        if prov.status == "rate_limited" { return nil } // deferred (§11.7): the next readDay asks again
        // Layer 3 (SR-08): a hit holds every entry the reading drew on, so the whole day is held and nothing is stored.
        if prov.status == "output_gate" || SafetyGate.phraseHit(reading.prose) {
            for d in digests {
                guard let row = verdicts[d.entryId] else { continue }
                try? await ledger.insertVerdict(SafetyVerdictRow(entryId: d.entryId, textSha256: row.textSha256, safetyVersion: SafetyGate.version,
                                                                layer: 3, verdict: "safety_hold", reasonCode: "output_gate"))
            }
            return nil
        }

        let picked = reading.quoteIndexes.compactMap { i in candidates.first { $0.index == i } }
        let payload = DayPayload(reading: reading, quotes: picked, entryIds: digests.map(\.entryId))
        var run = AIRun(feature: "day_reading", executor: prov.executor, status: prov.status)
        run.guardrails = prov.guardrails
        run.ladderRung = prov.rung.rawValue
        run.osBuild = prov.osBuild
        run.variant = prov.variant
        run.contextSize = prov.contextSize
        run.sampling = "greedy"
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
              let p = try? JSONDecoder().decode(DayPayload.self, from: Data(s.payload.utf8)) else { return nil }
        return (p, s.generator, s.aiRunId)
    }
}
