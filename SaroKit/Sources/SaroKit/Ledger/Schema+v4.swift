extension Schema {
    /// Reflection (BRD §14.2, FR-REF-05, FR-REF-12): the person's own mood for a day, locked against re-reads, with an
    /// optional gated note; and commitments, whose every change is an append-only event (DR-05). A deleted commitment is
    /// a tombstone (DR-03); 'restored' is an undo of a delete or a let-go. The trigger isn't named *_append_only: that
    /// name belongs to v1's generated list (Schema.appendOnly), which a later migration can't extend.
    static let v4 = """
    ALTER TABLE day_state ADD COLUMN mood_source TEXT;
    ALTER TABLE day_state ADD COLUMN mood_locked INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE day_state ADD COLUMN mood_note TEXT;
    ALTER TABLE day_state ADD COLUMN mood_note_verdict TEXT
      CHECK (mood_note_verdict IN ('clear','technical_hold','safety_hold','unavailable_clear','unavailable_caution'));

    CREATE TABLE commitment (
      id TEXT PRIMARY KEY,
      text TEXT NOT NULL CHECK (length(text) <= 280),
      for_day TEXT NOT NULL,
      completed_at TEXT,
      let_go_on_day TEXT,
      carried_from_id TEXT REFERENCES commitment(id),
      source_entry_id TEXT REFERENCES entry(id),
      deleted_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX commitment_day ON commitment(for_day);

    CREATE TABLE commitment_event (
      id TEXT PRIMARY KEY,
      commitment_id TEXT NOT NULL REFERENCES commitment(id),
      event TEXT NOT NULL CHECK (event IN ('created','carried','completed','uncompleted','edited','let_go','deleted','restored')),
      local_day TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE INDEX commitment_event_commitment ON commitment_event(commitment_id);
    CREATE TRIGGER commitment_event_no_update BEFORE UPDATE ON commitment_event BEGIN SELECT RAISE(ABORT, 'commitment_event is append-only'); END;
    """
}
