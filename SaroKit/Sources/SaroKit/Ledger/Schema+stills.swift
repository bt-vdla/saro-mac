extension Schema {
    /// Stills (P-STILLS): the tags of Saro's description beside its caption, and every still saved before captions
    /// existed goes back on the queue so the launch sweep describes it.
    static let stills = """
    ALTER TABLE entry_annotation ADD COLUMN tags TEXT;
    UPDATE entry SET processing_status = 'pending' WHERE kind = 'still' AND media_id IS NOT NULL AND trashed_at IS NULL;
    """
}
