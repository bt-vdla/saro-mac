import Foundation

/// Schema migrations, indexed by `PRAGMA user_version`: position decides the version, the names are only labels.
/// Append a new migration at the END for every change; never insert, reorder or edit a shipped one.
enum Schema {
    // cardSize shipped third on dogfood/v0 before the packages' migrations, so it keeps that place.
    static let migrations: [String] = [v1, v3, cardSize, stills, v4, v5]

    /// Tables that may only be inserted into (DR-05). The trigger aborts any UPDATE.
    static let appendOnly = [
        "ai_run", "ai_run_input", "entry_annotation", "observation", "observation_retraction",
        "insight_snapshot", "safety_verdict", "decision_event", "screen_note",
    ]

    /// A card's own size, set by its resize handles; NULL is the default size for its type.
    static let cardSize = "ALTER TABLE card_layout ADD COLUMN w REAL; ALTER TABLE card_layout ADD COLUMN h REAL;"

    static let v1 = """
    CREATE TABLE media_asset (
      id TEXT PRIMARY KEY,
      file_name TEXT NOT NULL UNIQUE,
      kind TEXT NOT NULL CHECK (kind IN ('video','audio','image')),
      origin TEXT NOT NULL,
      state TEXT NOT NULL CHECK (state IN ('recording','ready','missing','failed')),
      duration_ms INTEGER,
      bytes INTEGER,
      start_pts INTEGER,
      poster_file TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE entry (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL CHECK (kind IN ('moment','voice','reflection','still','music')),
      session_id TEXT,
      turn_number INTEGER,
      title_user TEXT,
      caption_user TEXT,
      summary_user TEXT,
      body TEXT,
      captured_at TEXT NOT NULL,
      tz_id TEXT NOT NULL,
      local_day TEXT NOT NULL,
      backdated INTEGER NOT NULL DEFAULT 0,
      duplicated_from_id TEXT REFERENCES entry(id),
      media_id TEXT REFERENCES media_asset(id),
      processing_status TEXT NOT NULL DEFAULT 'pending',
      trashed_at TEXT,
      trash_batch_id TEXT,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX entry_local_day ON entry(local_day);
    CREATE VIEW live_entry AS SELECT * FROM entry WHERE trashed_at IS NULL;

    CREATE TABLE transcript_word (
      media_id TEXT NOT NULL REFERENCES media_asset(id),
      extractor_version TEXT NOT NULL,
      idx INTEGER NOT NULL,
      text TEXT NOT NULL,
      start_ms INTEGER NOT NULL,
      dur_ms INTEGER NOT NULL,
      confidence REAL,
      PRIMARY KEY (media_id, extractor_version, idx)
    );

    CREATE TABLE ai_run (
      id TEXT PRIMARY KEY,
      feature TEXT NOT NULL,
      executor TEXT NOT NULL CHECK (executor IN ('on_device','pcc','heuristic','byok')),
      provider TEXT,
      model_id TEXT,
      guardrails TEXT,
      ladder_rung TEXT,
      os_build TEXT,
      variant TEXT,
      model_fingerprint TEXT,
      context_size INTEGER,
      sampling TEXT,
      prompt_version TEXT,
      schema_version TEXT,
      extractor_version TEXT,
      input_hash TEXT,
      tokens_in INTEGER,
      tokens_out INTEGER,
      model_calls INTEGER,
      latency_ms INTEGER,
      status TEXT NOT NULL,
      local_day TEXT,
      created_at TEXT NOT NULL
    );

    CREATE TABLE ai_run_input (
      ai_run_id TEXT NOT NULL REFERENCES ai_run(id),
      entry_id TEXT NOT NULL REFERENCES entry(id),
      field TEXT NOT NULL,
      utf16_from INTEGER NOT NULL,
      utf16_to INTEGER NOT NULL,
      text_sha256 TEXT NOT NULL
    );

    CREATE TABLE entry_annotation (
      id TEXT PRIMARY KEY,
      entry_id TEXT NOT NULL REFERENCES entry(id),
      ai_run_id TEXT NOT NULL REFERENCES ai_run(id),
      generator TEXT NOT NULL,
      title TEXT,
      summary TEXT,
      caption TEXT,
      mood_label TEXT,
      mood_basis TEXT,
      quote TEXT,
      quote_field TEXT,
      quote_from INTEGER,
      quote_to INTEGER,
      quote_sha256 TEXT,
      created_at TEXT NOT NULL
    );
    CREATE INDEX entry_annotation_entry ON entry_annotation(entry_id, created_at);

    CREATE TABLE observation (
      id TEXT PRIMARY KEY,
      entry_id TEXT NOT NULL REFERENCES entry(id),
      ai_run_id TEXT REFERENCES ai_run(id),
      source TEXT NOT NULL CHECK (source IN ('extractor','user','onboarding')),
      kind TEXT NOT NULL,
      key TEXT NOT NULL,
      label TEXT NOT NULL,
      quote TEXT,
      field TEXT,
      span_start INTEGER,
      span_end INTEGER,
      text_sha256 TEXT,
      local_day TEXT NOT NULL,
      created_at TEXT NOT NULL,
      CHECK (source = 'user' OR quote IS NOT NULL)
    );
    CREATE INDEX observation_key_day ON observation(key, local_day);

    CREATE TABLE observation_retraction (
      observation_id TEXT NOT NULL REFERENCES observation(id),
      reason TEXT NOT NULL,
      replaced_by TEXT,
      created_at TEXT NOT NULL
    );

    CREATE TABLE insight_snapshot (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      from_day TEXT NOT NULL,
      to_day TEXT NOT NULL,
      ai_run_id TEXT REFERENCES ai_run(id),
      generator TEXT NOT NULL,
      engine_version TEXT,
      input_hash TEXT,
      payload TEXT NOT NULL,
      quotes TEXT,
      created_at TEXT NOT NULL
    );
    CREATE INDEX snapshot_kind_day ON insight_snapshot(kind, from_day);

    CREATE TABLE day_state (
      local_day TEXT PRIMARY KEY,
      current_snapshot_id TEXT,
      mood_label_user TEXT,
      letter_opened_at TEXT,
      letter_kept_snapshot_id TEXT,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE safety_verdict (
      id TEXT PRIMARY KEY,
      entry_id TEXT NOT NULL REFERENCES entry(id),
      text_sha256 TEXT NOT NULL,
      safety_version TEXT NOT NULL,
      layer INTEGER NOT NULL,
      verdict TEXT NOT NULL CHECK (verdict IN ('clear','technical_hold','safety_hold','unavailable_clear','unavailable_caution')),
      reason_code TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE INDEX safety_verdict_entry ON safety_verdict(entry_id, created_at);

    CREATE TABLE model_fingerprint (
      os_build TEXT PRIMARY KEY,
      variant TEXT,
      fingerprint TEXT,
      canary_passed INTEGER,
      conservative INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    );

    CREATE TABLE card_layout (
      entry_id TEXT PRIMARY KEY REFERENCES entry(id),
      x REAL NOT NULL,
      y REAL NOT NULL,
      z INTEGER NOT NULL DEFAULT 0,
      stack_id TEXT,
      user_placed INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE decision_event (
      id TEXT PRIMARY KEY,
      decision_id TEXT NOT NULL,
      choice TEXT,
      note TEXT,
      screen_id TEXT,
      app_version TEXT NOT NULL,
      created_at TEXT NOT NULL
    );

    CREATE TABLE screen_note (
      id TEXT PRIMARY KEY,
      screen_id TEXT NOT NULL,
      note TEXT NOT NULL,
      app_version TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    """
        + appendOnly.map {
            "\nCREATE TRIGGER \($0)_append_only BEFORE UPDATE ON \($0) BEGIN SELECT RAISE(ABORT, '\($0) is append-only'); END;"
        }.joined()
}
