extension Schema {
    /// Memory (BRD §13, FR-MEM-01…05, DR-17). `observation` is rebuilt with SQLite's 12-step procedure so a row the person
    /// added needs no entry and every row carries its key's hash. Retractions are set aside and put back around the rebuild,
    /// so no foreign key is ever left pointing at a dropped table (PRAGMA foreign_keys can't change inside the migration's
    /// transaction). `active_observation` is the only thing the engine and the UI read.
    static let v5 = """
    CREATE TEMP TABLE retraction_v5 AS SELECT * FROM observation_retraction;
    DELETE FROM observation_retraction;

    CREATE TABLE observation_v5 (
      id TEXT PRIMARY KEY,
      entry_id TEXT REFERENCES entry(id),
      ai_run_id TEXT REFERENCES ai_run(id),
      source TEXT NOT NULL CHECK (source IN ('extractor','user','onboarding')),
      kind TEXT NOT NULL,
      key TEXT NOT NULL,
      key_sha256 TEXT NOT NULL,
      label TEXT NOT NULL,
      quote TEXT,
      field TEXT,
      span_start INTEGER,
      span_end INTEGER,
      text_sha256 TEXT,
      local_day TEXT NOT NULL,
      created_at TEXT NOT NULL,
      CHECK (source = 'user' OR quote IS NOT NULL),
      CHECK (source <> 'extractor' OR entry_id IS NOT NULL)
    );
    -- ponytail: SQLite has no sha256(), so a row from before v5 gets an empty hash; no journal has one (nothing inserted
    -- into observation before v5), and forgetting deletes and retracts by key, so such a row still goes.
    INSERT INTO observation_v5 (id, entry_id, ai_run_id, source, kind, key, key_sha256, label, quote, field, span_start, span_end,
                                text_sha256, local_day, created_at)
      SELECT id, entry_id, ai_run_id, source, kind, key, '', label, quote, field, span_start, span_end, text_sha256, local_day, created_at
      FROM observation;
    DROP TABLE observation;
    ALTER TABLE observation_v5 RENAME TO observation;
    CREATE INDEX observation_key_day ON observation(key, local_day);
    CREATE INDEX observation_entry ON observation(entry_id);
    CREATE TRIGGER observation_append_only BEFORE UPDATE ON observation BEGIN SELECT RAISE(ABORT, 'observation is append-only'); END;

    INSERT INTO observation_retraction SELECT * FROM retraction_v5;
    DROP TABLE retraction_v5;
    CREATE INDEX observation_retraction_observation ON observation_retraction(observation_id);

    -- A forgotten key, kept only as its hash. ponytail: the key 'all' holds the forget-everything cutoff, so one table
    -- carries both and Export shows no words for either.
    CREATE TABLE memory_tombstone (
      key_sha256 TEXT PRIMARY KEY,
      at TEXT NOT NULL
    );
    CREATE TRIGGER memory_tombstone_immutable BEFORE UPDATE ON memory_tombstone
      BEGIN SELECT RAISE(ABORT, 'memory_tombstone is append-only'); END;

    -- Hides retracted rows, forgotten keys, rows from before forget-everything, rows from trashed or duplicated entries,
    -- and every entry's row on a local_day with a live safety hold (SR-16, FR-MEM-05); a re-gate that clears the day
    -- brings them back. A row the person wrote themselves belongs to no day's entries, so a held day doesn't hide it.
    CREATE VIEW active_observation AS
    SELECT o.* FROM observation o
    LEFT JOIN entry e ON e.id = o.entry_id
    WHERE NOT EXISTS (SELECT 1 FROM observation_retraction r WHERE r.observation_id = o.id)
      AND NOT EXISTS (SELECT 1 FROM memory_tombstone t WHERE t.key_sha256 = o.key_sha256)
      AND o.created_at > COALESCE((SELECT at FROM memory_tombstone WHERE key_sha256 = 'all'), '')
      AND (o.entry_id IS NULL OR (
        e.trashed_at IS NULL AND e.duplicated_from_id IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM live_entry h JOIN safety_verdict v ON v.entry_id = h.id
          WHERE h.local_day = o.local_day AND v.verdict = 'safety_hold'
            AND v.rowid = (SELECT MAX(rowid) FROM safety_verdict WHERE entry_id = h.id))
        AND NOT EXISTS (SELECT 1 FROM reflection_turn t WHERE t.local_day = o.local_day AND t.answer_verdict = 'safety_hold')));
    """
}
