import CryptoKit
import Foundation

/// P-STILLS (FR-CAP-08, SR-11): Saro describes a still on import, through the same one-job queue, and again when asked.
/// The description is gated (layers 3 and 2) before anything is stored. Cleared, it is the still's reading and its text of
/// record until the user writes a caption (DR-04); held, the hold stands for the still until a new description clears it.
extension Pipeline {
    /// Saro's words about a still: a digest title and summary, never a quote candidate and never read again.
    public static let aiCaptionField = "ai_caption"

    /// The user's caption, else the cleared description. Nil while a description is held or waits for a check, so that
    /// verdict is read as it stands whatever caption is written (the day stays held, SR-13).
    func stillText(_ e: Entry) async throws -> (text: String, field: String, confidence: Double?)? {
        let last = try await ledger.stillCaption(entryId: e.id)
        if last?.standsHeld == true { return nil }
        if let c = e.captionUser, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (c, "caption_user", nil) }
        if let gated = last?.gatedText { return (gated, Self.aiCaptionField, nil) }
        return ("", "caption_user", nil)
    }

    /// Describe again: the next pass for this still describes it afresh (not while it is held).
    public func describeAgain(_ entryId: String) { stillsToDescribe.insert(entryId) }

    /// Describes a still with no description yet, one asked for again, or one that can now be told better: described
    /// without ever asking the model once the model can see, waiting for Apple Intelligence once it can run (SR-17), or
    /// held by an older gate (SR-18). False when deferred by a rate limit (§11.7), which ends this pass.
    func describeStillIfDue(_ entry: Entry, onStatus: @Sendable () async -> Void) async -> Bool {
        guard entry.kind == .still, let mid = entry.mediaId, let media = try? await ledger.media(mid), media.state == "ready" else { return true }
        let newest = (try? await ledger.verdicts(day: entry.localDay))?[entry.id]
        let asked = stillsToDescribe.remove(entry.id) != nil && newest?.verdict != "safety_hold"
        let last = try? await ledger.stillCaption(entryId: entry.id)
        let due = asked || last == nil
            || last?.status == "ok" && last?.executor == "heuristic" && last?.modelCalls == 0 && ai.canSee
            || last?.status == StillCaption.caution && ai.status == .available
            || last?.status == StillCaption.held && newest.map { $0.safetyVersion != SafetyGate.version } ?? true
        guard due else { return true }

        func status(_ s: String) async {
            try? await ledger.setProcessingStatus(s, startedFrom: entry)
            await onStatus()
        }
        await status(ProcessingStatus.reading)
        let url = ledger.url(for: media)
        guard let d = await ai.describeStill(at: url) else {
            await status(ProcessingStatus.pending)
            return false
        }
        var run = AIRun(feature: "still_caption", executor: d.provenance.executor, status: d.provenance.status)
        run.guardrails = d.provenance.guardrails
        run.ladderRung = d.provenance.rung.rawValue
        run.osBuild = d.provenance.osBuild
        run.variant = d.provenance.variant
        run.contextSize = d.provenance.contextSize
        run.sampling = d.provenance.rung == .guided ? "greedy" : nil
        run.promptVersion = d.provenance.promptVersion
        run.modelCalls = d.provenance.modelCalls
        run.latencyMs = d.provenance.latencyMs
        run.localDay = entry.localDay
        let input = Self.imageInput(entryId: entry.id, url: url)
        // A guardrail, a refusal or an unreadable image: no caption, labelled, and nothing to gate (SR-11).
        guard let caption = d.caption else {
            try? await ledger.insertRun(run, inputs: [input])
            return true
        }

        // Layer 3 over what was generated, then layer 2 (SR-08, SR-11).
        let text = StillVision.gatedText(caption, d.tags)
        let hash = sha256(text)
        run.inputHash = hash
        let result = SafetyGate.phraseHit(text) ? GateResult(verdict: "safety_hold", layer: 3, reasonCode: "output_gate")
            : await gate.gate(text: text, transcriptConfidence: nil)
        guard let result else {
            await status(ProcessingStatus.pending)
            return false
        }
        let verdict = SafetyVerdictRow(entryId: entry.id, textSha256: hash, safetyVersion: SafetyGate.version, layer: result.layer,
                                       verdict: result.verdict, reasonCode: result.reasonCode)
        if result.verdict == "clear" || result.verdict == "unavailable_clear" {
            var a = EntryAnnotation(entryId: entry.id, aiRunId: run.id, generator: run.executor)
            (a.title, a.summary, a.caption) = (caption, caption, caption)
            try? await ledger.insertStillCaption(run, input: input, annotation: a, tags: d.tags)
            try? await ledger.insertVerdict(verdict)
        } else {
            // Nothing generated is stored for a held still (SR-15): the verdict first, so a crash re-describes it.
            run.status = result.verdict == "unavailable_caution" ? StillCaption.caution : StillCaption.held
            try? await ledger.insertVerdict(verdict)
            try? await ledger.insertRun(run, inputs: [input])
        }
        return true
    }

    /// The description is the still's reading again if a reading of a since-cleared caption came after it.
    func keepStillCaptionCurrent(_ entryId: String, hash: String) async {
        guard (try? await ledger.hasAnnotation(entryId: entryId, inputHash: hash)) != true,
              let last = try? await ledger.stillCaption(entryId: entryId), last.caption != nil else { return }
        try? await ledger.restoreStillCaption(runId: last.runId)
    }

    /// The image a run read, by its file's hash: ai_run_input stores no content.
    static func imageInput(entryId: String, url: URL) -> AIRunInput {
        var input = AIRunInput(entryId: entryId, field: "image", text: "")
        if let data = try? Data(contentsOf: url) { input.textSha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        return input
    }
}
