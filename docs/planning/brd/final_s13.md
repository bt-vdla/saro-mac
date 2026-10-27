## 14. Data model

Saro keeps the user's words and every derived artifact in one local SQLite ledger, where derived history is appended and never rewritten. Every artifact points to the run that made it, so any future engine can replay the inputs. BYOK adds five `ai_run` columns, one consent table and a Keychain item, and changes nothing else.

<?claude block dia?>

The user's words sit only in the journal tables. Every AI artifact (entry_annotation, observation, insight_snapshot) is an append-only row tied to both its entry and the ai_run that made it. The engine reads only the active_observation view, so a retracted, tombstoned or safety-held row never reaches it.

### 14.1 Data requirements

| ID | Requirement | Verification |
|---|---|---|
| DR-01 | One SQLite file, `Application Support/Saro/saro.sqlite`, opens through system libsqlite3 3.54.0 with WAL, `foreign_keys=ON` and `secure_delete=ON`. One `AppDatabase` actor does every write. | Pragma check at open (SaroCoreTests) |
| DR-02 | `PRAGMA user_version` tracks the schema, and the migrator holds the `CREATE INDEX` statements. One checked-in fixture database per version migrates to head on every commit. | Migration fixtures in CI |
| DR-03 | Ids are text UUIDs, every mutable row has `updated_at`, and deletes are tombstones. CKSyncEngine then needs no migration. | Schema test |
| DR-04 | `entry` holds only the user's words and has no AI column. `title_user`, `caption_user` and `summary_user` outrank `entry_annotation`, and no AI path writes them. | Test: AI output never changes an entry column |
| DR-05 | `observation`, `entry_annotation`, `insight_snapshot`, `ai_run` and `commitment_event` are append-only, enforced by BEFORE UPDATE triggers that abort. Snapshots are never upserted, and the newest annotation is current. | Test: an UPDATE on observation aborts |
| DR-06 | An edit retracts and re-inserts. `observation_retraction` records the reason, and `replaced_by` points to the new row. | Edit-path test |
| DR-07 | Every annotation, observation and snapshot links to an `ai_run`. The run records executor, guardrails, ladder rung, os_build, variant, model fingerprint, prompt and schema versions, tokens, latency and status, plus provider, answering model and cost for BYOK. | P2 exit test |
| DR-08 | `ai_run_input` records exactly which fields and UTF-16 windows a run read. No `ai_run` or `ai_run_input` row holds content. | Content scan test |
| DR-09 | An observation needs a verbatim quote unless `source='user'`, enforced by a CHECK. It stores field, UTF-16 span and `text_sha256`. | Constraint test; grounding suite |
| DR-10 | `local_day` is frozen at capture from `captured_at` (UTC) and `tz_id` (IANA). A capture made while viewing a past day takes that day, with `captured_at` = now and `backdated` = 1. | Time-zone and backdating tests |
| DR-11 | Media lives as files: `Media/<local_day>/<session or entry id>/part-<n>.mov`, `voice/<id>.mov` and `stills/<id>.heic`. Rows store relative paths only, and stills lose GPS. | Path test; ImageIO metadata test |
| DR-12 | The `media_asset` row is written before the first frame. A file is removed only when no live or trashed entry references it, and a launch sweep checks that every file has a row and every row a file. | Nightly kill harness |
| DR-13 | A series key is (observation key, lineage); lineage is executor + variant + model fingerprint + extractor version + prompt version. Heuristic, on-device and BYOK series are never diffed against each other. | Engine golden fixtures |
| DR-14 | `safety_verdict` is content-free, and day gates and the re-gate queue are lookups over it. Safety-held entries produce no observations. | State-table tests |
| DR-15 | Trash is a soft delete with one `trash_batch_id` per user action, undone with Cmd-Z and purged after 30 days. | XCUITest; purge test |
| DR-16 | Forget and Erase hard-delete every derived row in one transaction, delete `Backups/` and take a fresh snapshot. Erase also removes media, notifications, prefs, Keychain keys and, later, the CloudKit zone. | One test per artifact type |
| DR-17 | `memory_tombstone` stops a forgotten key from coming back, and nothing is learned inside a `memory_pause` window. | SaroCoreTests |
| DR-18 | `secure_delete` overwrites freed pages. A daily `VACUUM INTO Backups/saro-YYYY-MM-DD.sqlite` keeps 7 copies with no free pages, so routine deletes age out within 7 days. | Pragma test; snapshot test |
| DR-19 | Restore from snapshot closes the database, keeps the current file as a pre-restore snapshot, and swaps in the chosen one. | Restore test |
| DR-20 | Export writes a `.saroexport` folder (JSON with `export_version`, plus media), and Import is idempotent by UUID. The round trip matches rows and media sha256, and API keys are never exported. | Export-erase-import round-trip test |
| DR-21 | Device prefs, including BYOK routes and the daily spend cap, live in UserDefaults through one `@Observable PrefsStore`. No secret is ever stored there. | Prefs scan test |
| DR-22 | BYOK keys live only in the Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, not synchronizable). SQLite stores the provider id only, and consent goes into append-only `provider_consent`. | Keychain attribute test |
| DR-23 | Saro Lab has its own bundle id and container. Journal data moves between Saro and Saro Lab only through Export and Import. | Signing check per scheme |
| DR-24 | Alpha metrics are computed, never stored as content. A session is a local day with a saved entry, counted by the day of `captured_at`, with duplicates excluded. | Alpha report test |

### 14.2 Entities

| Entity | Purpose | Key fields | Append-only? |
|---|---|---|---|
| `entry` | The user's own words and capture facts | id, kind (moment, voice, reflection, still, music), session_id, turn_number, title_user, caption_user, summary_user, body, captured_at, tz_id, local_day, backdated, duplicated_from_id, media_id, processing_status, trashed_at, trash_batch_id | No: user-editable, tombstoned |
| `media_asset` | One recorded, dropped or imported file | id, file_name (unique), kind, origin, state (recording, ready, missing, failed), duration_ms, bytes, start_pts, poster_file | No: state changes |
| `transcript_word` | Timed words from the file transcript | media_id, idx, text, start_ms, dur_ms, confidence, extractor_version | No |
| `ai_run` | Provenance of every model or heuristic run | id, feature, executor (on_device, pcc, heuristic, byok), provider, model_id, guardrails, ladder_rung, os_build, variant, model_fingerprint, prompt_version, input_hash, tokens_in, tokens_out, cache_read_tokens, cost_micros, refusal_category, latency_ms, status, local_day | Yes |
| `ai_run_input` | Exactly what one run read | ai_run_id, entry_id, field, utf16_from, utf16_to, text_sha256 | Yes, written with its run |
| `entry_annotation` | AI title, summary, caption, mood and quote per entry | id, entry_id, ai_run_id, generator, title, summary, caption, mood_label, mood_basis, quote, quote_span | Yes; the newest row is current |
| `observation` | One extracted emotion, theme, person or intention with its quote | id, entry_id, ai_run_id, source (extractor, user, onboarding), kind, key, label, quote, field, span_start, span_end, text_sha256, local_day | Yes, by trigger |
| `observation_retraction` | Withdraws an observation without rewriting it | observation_id, reason (trashed, reextracted, user_deleted, user_edited, user_forgot_all, source_edited), replaced_by | Yes |
| `memory_tombstone` | Keeps a forgotten key forgotten | key_hash, at | Yes |
| `memory_pause` | Windows in which nothing is learned | from_at, to_at | No |
| `insight_snapshot` | Day readings, narratives, letters, patterns, weeks and timelines | id, kind, from_day, to_day, ai_run_id, generator, engine_version, input_hash, payload, quotes (entry_id, span) | Yes, never upserted |
| `day_state` | User-owned fields for a day | local_day, current_snapshot_id, mood_label_user, mood_source, mood_locked, question_answer, letter_opened_at, letter_kept_snapshot_id | No |
| `reflection_turn` | Every question Saro asked and the user's answer | id, kind (daily_question, reflect_deeper, reflect_further), entry_id, session_id, turn_number, question, answer, generator, local_day | Not stated (open question) |
| `commitment` | An intention and its carry-over | id, text, for_day, completed_at, let_go_on_day, carried_from_id, source_entry_id | No |
| `commitment_event` | Follow-through history | commitment_id, event (created, carried, completed, uncompleted, let_go), local_day | Yes |
| `safety_verdict` | Content-free gate results | entry_id, text_sha256, safety_version, layer, verdict (clear, technical_hold, safety_hold, unavailable_clear, unavailable_caution), reason_code | A re-gate adds a row |
| `model_fingerprint` | Model identity per os_build; decides lineage and conservative mode | os_build, variant, fingerprint, canary_passed, conservative | One row per os_build |
| `diagnostic_event` | Crash and hang counts from MetricKit | kind (crash, hang), app_build, os_build | Yes |
| `starter_context` | The t0 baseline from About you | version, answers, picks (kind, text, value, UTF-16 span, question), first_prompt, ritual_time | Versioned rows |
| `profile` | Name, tone and memory settings | name, called, tone, focus_areas, memory_paused, onboarding_done_at | No |
| `change_log` | What the engine must recompute | entity, id, op, at | Yes |
| `provider_consent` (new, BYOK) | Consent per BYOK provider | provider, consent_version, event (granted, scope_changed, revoked), scope (touchpoints and fields), at | Yes |

### 14.3 Views and indexes

- `live_entry` hides trashed entries.
- `active_observation` hides observations that are retracted, tombstoned, from trashed or duplicated entries, or from any local_day with a safety-held entry.
- Indexes: `entry_local_day ON entry(local_day)`, `observation_key_day ON observation(key, local_day)` and `snapshot_kind_day ON insight_snapshot(kind, from_day)`.
- Today's BYOK spend is `SUM(cost_micros)` over `ai_run` for today's local_day with executor `byok`, so it needs no table of its own.

### 14.4 Stores outside the database

| Store | Location | Holds | Rules |
|---|---|---|---|
| Media | `Media/` in the app container | Movie parts, voice notes, HEIC stills | Relative paths in rows; removed only when no live or trashed entry references them |
| Snapshots | `Backups/` in the app container | 7 daily `VACUUM INTO` copies | Deleted and retaken on Forget all and Erase |
| Export | A folder the user picks | `.saroexport` JSON plus media | Warns for iCloud Drive; never contains keys |
| Prefs | UserDefaults via `PrefsStore` | Text size, Writing Tools opt-in, app-open counter, BYOK routes, daily cap | No secrets; cleared by Erase |
| Keys | macOS Keychain | BYOK API keys, one item per provider | This device only; never synced, logged or exported; deleted by Erase |
| Bench reports | `Bench/` in the Saro Lab container | Model bench results per run | Synthetic cases only; keyed by executor, model, os_build and prompt_version |
| Developer eval reports | `evals/reports/<date>_<os_build>_<variant>_<prompt_version>.json` in the repo | Live eval results | Synthetic cases only |

### 14.5 Migrations after v1

| When | Change |
|---|---|
| Lab-2 (BYOK routes) | `ai_run` gains provider, model_id, cache_read_tokens, cost_micros and refusal_category; new `provider_consent` table. One migration ships in both builds, so Saro and Saro Lab share one schema |
| P5 | Nothing new; the backup folder's bookmark lives in UserDefaults |
| P6 | CloudKit columns `ck_system_fields` and `zone` |
| P7 | `card_layout(entry_id, x, y, w, h, user_placed, z)` with seeded jitter |
| P8 | `entry_fts` FTS5 table (title, summary, body, transcript, tags; porter unicode61 remove_diacritics 2) and an `fts5vocab` table |
| Engine design | `text_embedding`, `self_claim`, `self_claim_version` and `claim_evidence` |

### 14.6 Open questions

- Is `reflection_turn` append-only, or does the answer update the question's row?
- Does `transcript_word` keep earlier rows per `extractor_version` after a re-transcription, or replace them?