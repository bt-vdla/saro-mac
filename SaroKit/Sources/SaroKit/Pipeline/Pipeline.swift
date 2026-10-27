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
        let classify: (@Sendable (String) async -> ClassifierOutcome)? = ai.status == .available
            ? { @Sendable text in await ai.classify(text, instructions: SafetyGate.classifierInstructions, prompt: SafetyGate.classifierPrompt(for: "{text}")) }
            : nil
        gate = SafetyGate(classify: classify)
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
            guard let mid = entry.mediaId, let media = try? await ledger.media(mid), media.state == "ready" else { return }
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
        if verdict == nil {
            await status(ProcessingStatus.gating)
            let r = await gate.gate(text: source.text, transcriptConfidence: source.confidence)
            let row = SafetyVerdictRow(entryId: entryId, textSha256: hash, safetyVersion: SafetyGate.version, layer: r.layer,
                                       verdict: r.verdict, reasonCode: r.reasonCode)
            try? await ledger.insertVerdict(row)
            verdict = row
        }
        guard let v = verdict?.verdict, v == "clear" || v == "unavailable_clear" else {
            await status(ProcessingStatus.done)
            return
        }

        // 3. Per-entry reading on the ladder; "In your words" when the model can't run.
        await status(ProcessingStatus.reading)
        let candidates = Heuristics.candidates(entryId: entryId, field: source.field, text: source.text)
        let fallback = Heuristics.heuristicReading(text: source.text, candidates: candidates)
        let text = source.text
        let reading: EntryReading
        let prov: Provenance
        if v == "clear" {
            (reading, prov) = await ai.readEntry(entryId: entryId, text: text, candidates: candidates, fallback: fallback) { r in
                Heuristics.driftOK(generated: "\(r.title). \(r.summary)", source: text)
                    && !SafetyGate.phraseHit("\(r.title) \(r.summary) \(r.moodBasis ?? "")")
            }
        } else {
            (reading, prov) = (fallback, Provenance(executor: "heuristic", rung: .heuristic, guardrails: nil, variant: nil,
                                                    osBuild: SaroAI.osBuild, contextSize: nil, promptVersion: SaroAI.entryPromptVersion,
                                                    tokensIn: nil, modelCalls: 0, latencyMs: 0))
        }

        // Layer 3 over whatever was generated, heuristic included (SR-08). A hit stores nothing but a verdict.
        if SafetyGate.phraseHit("\(reading.title) \(reading.summary) \(reading.moodBasis ?? "")") {
            try? await ledger.insertVerdict(SafetyVerdictRow(entryId: entryId, textSha256: hash, safetyVersion: SafetyGate.version,
                                                            layer: 3, verdict: "safety_hold", reasonCode: "output_gate"))
            await status(ProcessingStatus.done)
            return
        }

        var run = AIRun(feature: "entry_reading", executor: prov.executor, status: "ok")
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
            if let v = verdicts[e.id] { states.append(EntryState(verdict: v.verdict)); continue }
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
            guard let v = verdicts[e.id]?.verdict, v == "clear" || v == "unavailable_clear",
                  let a = annotations[e.id], let src = try? await text(for: e) else { continue }
            digests.append(EntryDigest(entryId: e.id, kind: e.kind.rawValue, time: e.capturedAt.formatted(date: .omitted, time: .shortened),
                                       title: a.title ?? e.kind.rawValue, summary: a.summary ?? "", mood: a.moodLabel.flatMap(Mood.init(rawValue:))))
            candidates += Heuristics.candidates(entryId: e.id, field: src.field, text: src.text, firstIndex: candidates.count)
                .prefix(Self.candidatesPerEntryInDay)
            inputs.append(AIRunInput(entryId: e.id, field: src.field, text: src.text))
            sources.append(src.text)
        }
        guard !digests.isEmpty else { return nil }
        let inputHash = sha256(digests.map { "\($0.entryId)|\($0.title)|\($0.summary)|\($0.mood?.rawValue ?? "")" }.joined(separator: "\n")
                               + candidates.map(\.text).joined(separator: "\n"))
        if let last = try? await ledger.latestSnapshot(kind: "day_reading", day: day), last.inputHash == inputHash,
           let payload = try? JSONDecoder().decode(DayPayload.self, from: Data(last.payload.utf8)) {
            return payload
        }

        let source = sources.joined(separator: "\n")
        let fallback = Heuristics.heuristicDayReading(digests: digests, candidates: candidates)
        let reading: DayReading
        let prov: Provenance
        if modelOK {
            (reading, prov) = await ai.readDay(day: day, digests: digests, candidates: candidates, fallback: fallback) { r in
                (r.narrative.map { Heuristics.driftOK(generated: $0, source: source) } ?? true)
                    && !SafetyGate.phraseHit([r.narrative, r.question, r.moodBasis].compactMap { $0 }.joined(separator: " "))
            }
        } else {
            (reading, prov) = (fallback, Provenance(executor: "heuristic", rung: .heuristic, guardrails: nil, variant: nil, osBuild: SaroAI.osBuild,
                                                    contextSize: nil, promptVersion: SaroAI.dayPromptVersion, tokensIn: nil, modelCalls: 0, latencyMs: 0))
        }
        guard !SafetyGate.phraseHit([reading.narrative, reading.question, reading.moodBasis].compactMap { $0 }.joined(separator: " ")) else { return nil }

        let picked = reading.quoteIndexes.compactMap { i in candidates.first { $0.index == i } }
        let payload = DayPayload(reading: reading, quotes: picked, entryIds: digests.map(\.entryId))
        var run = AIRun(feature: "day_reading", executor: prov.executor, status: "ok")
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
