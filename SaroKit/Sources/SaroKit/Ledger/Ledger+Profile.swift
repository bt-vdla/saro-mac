import Foundation

extension Ledger {
    // MARK: Profile

    /// The one profile row. Erase leaves none, so a missing row comes back empty (onboarding not done).
    public func profile() throws -> Profile {
        let now = Date.now.iso
        try db.run("INSERT OR IGNORE INTO profile (id, created_at, updated_at) VALUES (1, ?, ?)", [.text(now), .text(now)])
        return try db.run("SELECT * FROM profile WHERE id=1").first.map(Profile.init) ?? Profile()
    }

    /// Saves the row and bumps updated_at. Pausing or resuming memory, from anywhere, opens or closes a pause window
    /// in the same transaction (prefs.ts setPrefs).
    public func saveProfile(_ p: Profile) throws {
        try db.transaction {
            let now = Date.now
            let wasPaused = try db.run("SELECT memory_paused FROM profile WHERE id=1").first?.int("memory_paused") == 1
            try db.run("""
                INSERT INTO profile (id, name, called, tone, focus_areas, memory_paused, onboarding_done_at, created_at, updated_at)
                VALUES (1,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name, called=excluded.called, tone=excluded.tone,
                  focus_areas=excluded.focus_areas, memory_paused=excluded.memory_paused,
                  onboarding_done_at=excluded.onboarding_done_at, updated_at=excluded.updated_at
                """, [p.name.sql, p.called.sql, .text(p.tone.rawValue), .text(Self.json(p.focusAreas.map(\.rawValue))),
                      .int(p.memoryPaused ? 1 : 0), p.onboardingDoneAt.map { .text($0.iso) } ?? .null, .text(p.createdAt.iso), .text(now.iso)])
            if p.memoryPaused != wasPaused { try p.memoryPaused ? insertPause(at: now) : endPause(at: now) }
        }
    }

    // MARK: Starter context

    /// The current onboarding pass's starter context, if any.
    public func latestStarter() throws -> StarterContext? {
        try db.run("SELECT * FROM starter_context ORDER BY version DESC LIMIT 1").first.map(StarterContext.init)
    }

    /// Saves this pass's row (the same id updates it) and bumps updated_at. Only the storable part is written: nothing
    /// derived from a held answer.
    public func saveStarter(_ starter: StarterContext) throws {
        let s = starter.storable
        try db.run("""
            INSERT INTO starter_context (id, version, answers, picks, dropped, held, reflect_time, first_prompt, source, created_at, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET answers=excluded.answers, picks=excluded.picks, dropped=excluded.dropped, held=excluded.held,
              reflect_time=excluded.reflect_time, first_prompt=excluded.first_prompt, source=excluded.source, updated_at=excluded.updated_at
            """, [.text(s.id), .int(Int64(s.version)), .text(Self.json(Dictionary(uniqueKeysWithValues: s.answers.map { (String($0), $1) }))),
                  .text(Self.json(s.picks)), .text(Self.json(s.dropped.sorted())), .text(Self.json(s.held.sorted())),
                  s.reflectTime.sql, s.firstPrompt.sql, .text(s.source.rawValue), .text(s.createdAt.iso), .text(Date.now.iso)])
    }

    /// The version a new onboarding pass (a first run, or Replay Onboarding) starts.
    public func newStarterVersion() throws -> Int {
        (try db.run("SELECT MAX(version) AS v FROM starter_context").first?.int("v") ?? 0) + 1
    }

    // MARK: Reflection turns

    public func insertTurn(_ t: ReflectionTurn) throws {
        try db.run("""
            INSERT INTO reflection_turn (id, kind, entry_id, session_id, turn_number, question, answer, answer_verdict, generator,
              ai_run_id, local_day, archived_at, created_at, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, [.text(t.id), .text(t.kind.rawValue), t.entryId.sql, t.sessionId.sql, t.turnNumber.sql, .text(t.question), t.answer.sql,
                  t.answerVerdict.sql, .text(t.generator), t.aiRunId.sql, .text(t.localDay), t.archivedAt.map { .text($0.iso) } ?? .null,
                  .text(t.createdAt.iso), .text(Date.now.iso)])
    }

    /// Records the answer with the gate's verdict on it; the schema refuses an answer without one. A safety hold drops
    /// the day's readings and letters, as an entry's hold does (SR-13, SR-15).
    public func setTurnAnswer(id: String, answer: String, verdict: String) throws {
        try db.transaction {
            try db.run("UPDATE reflection_turn SET answer=?, answer_verdict=?, updated_at=? WHERE id=?",
                       [.text(answer), .text(verdict), .text(Date.now.iso), .text(id)])
            guard verdict == "safety_hold", let day = try db.run("SELECT local_day FROM reflection_turn WHERE id=?", [.text(id)]).first?.str("local_day")
            else { return }
            try dropDayReadings(day)
        }
    }

    /// A day's turns, oldest first; `kind` narrows them, and archived (refreshed) ones come back only when asked for.
    public func turns(day: String, kind: ReflectionTurn.Kind? = nil, includeArchived: Bool = false) throws -> [ReflectionTurn] {
        try db.run("""
            SELECT * FROM reflection_turn WHERE local_day=? AND (? IS NULL OR kind=?) AND (? OR archived_at IS NULL)
            ORDER BY created_at, rowid
            """, [.text(day), kind.map { .text($0.rawValue) } ?? .null, kind.map { .text($0.rawValue) } ?? .null, .int(includeArchived ? 1 : 0)])
            .map(ReflectionTurn.init)
    }

    public func turns(entryId: String) throws -> [ReflectionTurn] {
        try db.run("SELECT * FROM reflection_turn WHERE entry_id=? ORDER BY created_at, rowid", [.text(entryId)]).map(ReflectionTurn.init)
    }

    // MARK: Memory pauses

    /// Opens a pause window unless one is open.
    public func openPause(at date: Date = .now) throws { try insertPause(at: date) }

    /// Closes the open pause window, if any.
    public func closePause(at date: Date = .now) throws { try endPause(at: date) }

    public func pauses() throws -> [MemoryPause] {
        try db.run("SELECT * FROM memory_pause ORDER BY from_at").map {
            MemoryPause(id: $0.str("id") ?? "", from: $0.date("from_at") ?? .distantPast, to: $0.date("to_at"))
        }
    }

    private func insertPause(at date: Date) throws {
        try db.run("INSERT INTO memory_pause (id, from_at) SELECT ?, ? WHERE NOT EXISTS (SELECT 1 FROM memory_pause WHERE to_at IS NULL)",
                   [.text(UUID().uuidString), .text(date.iso)])
    }

    private func endPause(at date: Date) throws {
        try db.run("UPDATE memory_pause SET to_at=? WHERE to_at IS NULL", [.text(date.iso)])
    }

    static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

    static func decode<T: Decodable>(_ type: T.Type, _ text: String?) -> T? {
        text.flatMap { try? JSONDecoder().decode(T.self, from: Data($0.utf8)) }
    }
}

extension Profile {
    init(row: Row) {
        name = row.str("name")
        called = row.str("called")
        tone = Tone(rawValue: row.str("tone") ?? "") ?? .neutral
        focusAreas = (Ledger.decode([String].self, row.str("focus_areas")) ?? []).compactMap(FocusArea.init)
        memoryPaused = row.int("memory_paused") == 1
        onboardingDoneAt = row.date("onboarding_done_at")
        createdAt = row.date("created_at") ?? .distantPast
        updatedAt = row.date("updated_at") ?? .distantPast
    }
}

extension StarterContext {
    init(row: Row) {
        id = row.str("id") ?? ""
        version = row.int("version") ?? 1
        answers = Dictionary(uniqueKeysWithValues: (Ledger.decode([String: String].self, row.str("answers")) ?? [:])
            .compactMap { k, v in Int(k).map { ($0, v) } })
        picks = Ledger.decode([Pick].self, row.str("picks")) ?? []
        dropped = Set(Ledger.decode([String].self, row.str("dropped")) ?? [])
        held = Set(Ledger.decode([Int].self, row.str("held")) ?? [])
        reflectTime = row.str("reflect_time")
        firstPrompt = row.str("first_prompt")
        source = Source(rawValue: row.str("source") ?? "") ?? .local
        createdAt = row.date("created_at") ?? .distantPast
        updatedAt = row.date("updated_at") ?? .distantPast
    }
}

extension ReflectionTurn {
    init(row: Row) {
        id = row.str("id") ?? ""
        kind = Kind(rawValue: row.str("kind") ?? "") ?? .prompt
        entryId = row.str("entry_id")
        sessionId = row.str("session_id")
        turnNumber = row.int("turn_number")
        question = row.str("question") ?? ""
        answer = row.str("answer")
        answerVerdict = row.str("answer_verdict")
        generator = row.str("generator") ?? ""
        aiRunId = row.str("ai_run_id")
        localDay = row.str("local_day") ?? ""
        archivedAt = row.date("archived_at")
        createdAt = row.date("created_at") ?? .distantPast
        updatedAt = row.date("updated_at") ?? .distantPast
    }
}
