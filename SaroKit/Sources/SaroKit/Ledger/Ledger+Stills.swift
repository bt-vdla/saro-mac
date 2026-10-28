import Foundation

/// The newest `still_caption` run for a still and the description it left, if it was cleared and kept.
public struct StillCaption: Sendable, Hashable {
    /// Run statuses besides `ok` and the model's own stop reasons (`guardrail`, `refusal`, `unreadable`).
    public static let held = "safety_hold", caution = "caution"

    public var runId: String
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
            SELECT r.id, r.status, r.executor, r.ladder_rung, r.variant, r.model_calls, r.latency_ms, a.caption, a.tags
            FROM ai_run r JOIN ai_run_input i ON i.ai_run_id = r.id
            LEFT JOIN entry_annotation a ON a.rowid = (SELECT MAX(rowid) FROM entry_annotation WHERE ai_run_id = r.id)
            WHERE i.entry_id = ? AND r.feature = 'still_caption' ORDER BY r.rowid DESC LIMIT 1
            """, [.text(entryId)]).first.map { r in
            StillCaption(runId: r.str("id") ?? "", status: r.str("status") ?? "", executor: r.str("executor") ?? "",
                         rung: r.str("ladder_rung"), variant: r.str("variant"), modelCalls: r.int("model_calls") ?? 0,
                         latencyMs: r.int("latency_ms"), caption: r.str("caption"), tags: Self.decode([String].self, r.str("tags")) ?? [])
        }
    }

    /// A cleared description: its run, the image it read, and the annotation that is the still's reading. ponytail: two
    /// writes; a crash between them leaves a run with no caption, which the detail offers to describe again.
    func insertStillCaption(_ run: AIRun, input: AIRunInput, annotation a: EntryAnnotation, tags: [String]) throws {
        try insertRun(run, inputs: [input])
        try db.run("""
            INSERT INTO entry_annotation (id, entry_id, ai_run_id, generator, title, summary, caption, tags, created_at)
            VALUES (?,?,?,?,?,?,?,?,?)
            """, [.text(a.id), .text(a.entryId), .text(a.aiRunId), .text(a.generator), a.title.sql, a.summary.sql, a.caption.sql,
                  .text(Self.json(tags)), .text(a.createdAt.iso)])
    }

    /// Makes the description the still's newest annotation again (DR-05: newest is current), after a reading of a
    /// caption the user has since cleared.
    func restoreStillCaption(runId: String) throws {
        try db.run("""
            INSERT INTO entry_annotation (id, entry_id, ai_run_id, generator, title, summary, caption, tags, created_at)
            SELECT ?, entry_id, ai_run_id, generator, title, summary, caption, tags, ? FROM entry_annotation
            WHERE ai_run_id = ? ORDER BY rowid DESC LIMIT 1
            """, [.text(UUID().uuidString), .text(Date.now.iso), .text(runId)])
    }
}
