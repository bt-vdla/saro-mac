extension Schema {
    /// Foundation (BRD §14.2): the local profile, About you's starter context, every question Saro asked with its answer,
    /// and memory pauses. A journal that already has entries was kept before onboarding existed, so it starts done.
    static let v3 = """
    CREATE TABLE profile (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      name TEXT,
      called TEXT,
      tone TEXT NOT NULL DEFAULT 'neutral' CHECK (tone IN ('gentle','neutral','direct','contemplative')),
      focus_areas TEXT NOT NULL DEFAULT '[]',
      memory_paused INTEGER NOT NULL DEFAULT 0,
      onboarding_done_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    INSERT INTO profile (id, onboarding_done_at, created_at, updated_at)
    SELECT 1, CASE WHEN EXISTS (SELECT 1 FROM entry) THEN strftime('%Y-%m-%dT%H:%M:%fZ', 'now') END,
           strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now');

    CREATE TABLE starter_context (
      id TEXT PRIMARY KEY,
      version INTEGER NOT NULL UNIQUE,
      answers TEXT NOT NULL DEFAULT '{}',
      picks TEXT NOT NULL DEFAULT '[]',
      dropped TEXT NOT NULL DEFAULT '[]',
      held TEXT NOT NULL DEFAULT '[]',
      reflect_time TEXT,
      first_prompt TEXT,
      source TEXT NOT NULL DEFAULT 'local' CHECK (source IN ('local','ai')),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE reflection_turn (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL CHECK (kind IN ('prompt','daily_question','reflect_deeper','reflect_further')),
      entry_id TEXT REFERENCES entry(id),
      session_id TEXT,
      turn_number INTEGER,
      question TEXT NOT NULL,
      answer TEXT,
      answer_verdict TEXT CHECK (answer_verdict IN ('clear','technical_hold','safety_hold','unavailable_clear','unavailable_caution')),
      generator TEXT NOT NULL,
      ai_run_id TEXT REFERENCES ai_run(id),
      local_day TEXT NOT NULL,
      archived_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK (answer IS NULL OR answer_verdict IS NOT NULL)
    );
    CREATE INDEX reflection_turn_day_kind ON reflection_turn(local_day, kind);
    CREATE INDEX reflection_turn_entry ON reflection_turn(entry_id);

    CREATE TABLE memory_pause (
      id TEXT PRIMARY KEY,
      from_at TEXT NOT NULL,
      to_at TEXT
    );
    """
}
