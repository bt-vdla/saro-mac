import Foundation

/// The newest `still_caption` run for a still and the description it left, if it was cleared and kept.
public struct StillCaption: Sendable, Hashable {
    /// Run statuses besides `ok` and the model's own stop reasons (`guardrail`, `refusal`, `unreadable`).
    public static let held = "safety_hold", caution = "caution"

    public var runId: String
    /// `ok` until a later check of the description's own text holds it or leaves it waiting (a re-gate, SR-17/18, or a
    /// day reading's layer 3): then `held` or `caution`, as if its first check had said so.
    public var status: String
    public var executor: String
    public var rung: String?
    public var variant: String?
    public var modelCalls: Int
    public var latencyMs: Int?
    /// Nil unless the gate cleared it and nothing has held the still since (a hold deletes it, SR-15).
    public var caption: String?
    public var tags: [String]

    public var gatedText: String? { caption.map { StillVision.gatedText($0, tags) } }
    /// Held or waiting for a check: that verdict stands for the still until a new description clears it.
    public var standsHeld: Bool { status == Self.held || status == Self.caution }
}

extension Ledger {
    public func stillCaption(entryId: String) throws -> StillCaption? {
        try db.run("""
            SELECT r.id, r.status, r.executor, r.ladder_rung, r.variant, r.model_calls, r.latency_ms, a.caption, a.tags,
              (SELECT v.verdict FROM safety_verdict v WHERE v.entry_id = i.entry_id AND v.text_sha256 = r.input_hash
               ORDER BY v.rowid DESC LIMIT 1) AS verdict
            FROM ai_run r JOIN ai_run_input i ON i.ai_run_id = r.id
            LEFT JOIN entry_annotation a ON a.rowid = (SELECT MAX(rowid) FROM entry_annotation WHERE ai_run_id = r.id)
            WHERE i.entry_id = ? AND r.feature = 'still_caption' ORDER BY r.rowid DESC LIMIT 1
            """, [.text(entryId)]).first.map { r in
            var status = r.str("status") ?? ""
            if status == "ok", let v = r.str("verdict") {
                switch EntryState(verdict: v) {
                case .safetyHold: status = StillCaption.held
                case .awaitingCheck: status = StillCaption.caution
                default: break
                }
            }
            return StillCaption(runId: r.str("id") ?? "", status: status, executor: r.str("executor") ?? "",
                                rung: r.str("ladder_rung"), variant: r.str("variant"), modelCalls: r.int("model_calls") ?? 0,
                                latencyMs: r.int("latency_ms"), caption: r.str("caption"), tags: Self.decode([String].self, r.str("tags")) ?? [])
        }
    }

    /// A cleared description: its run, the image it read, and the annotation that is the still's reading. With
    /// `keepingReading` (the still has a caption of the user's), a reading of that caption stays the newest annotation,
    /// so the unchanged caption isn't read again. ponytail: separate writes; a crash between them leaves a run with no
    /// caption, which the detail offers to describe again, or the description newest, which reads the caption once more.
    func insertStillCaption(_ run: AIRun, input: AIRunInput, annotation a: EntryAnnotation, tags: [String], keepingReading: Bool) throws {
        let newest = keepingReading ? try db.run("""
            SELECT a.ai_run_id, r.feature FROM entry_annotation a JOIN ai_run r ON r.id = a.ai_run_id
            WHERE a.entry_id = ? ORDER BY a.rowid DESC LIMIT 1
            """, [.text(a.entryId)]).first : nil
        try insertRun(run, inputs: [input])
        try db.run("""
            INSERT INTO entry_annotation (id, entry_id, ai_run_id, generator, title, summary, caption, tags, created_at)
            VALUES (?,?,?,?,?,?,?,?,?)
            """, [.text(a.id), .text(a.entryId), .text(a.aiRunId), .text(a.generator), a.title.sql, a.summary.sql, a.caption.sql,
                  .text(Self.json(tags)), .text(a.createdAt.iso)])
        if let newest, newest.str("feature") != "still_caption", let id = newest.str("ai_run_id") { try restoreAnnotation(runId: id) }
    }

    /// Makes a run's annotation the entry's newest again (DR-05: newest is current): the description after a reading of a
    /// caption the user has since cleared, or the caption's reading after a new description.
    func restoreAnnotation(runId: String) throws {
        try db.run("""
            INSERT INTO entry_annotation (id, entry_id, ai_run_id, generator, title, summary, caption, mood_label, mood_basis, quote,
              quote_field, quote_from, quote_to, quote_sha256, tags, created_at)
            SELECT ?, entry_id, ai_run_id, generator, title, summary, caption, mood_label, mood_basis, quote,
              quote_field, quote_from, quote_to, quote_sha256, tags, ? FROM entry_annotation
            WHERE ai_run_id = ? ORDER BY rowid DESC LIMIT 1
            """, [.text(UUID().uuidString), .text(Date.now.iso), .text(runId)])
    }
}
