## 8. Functional requirements

Saro needs 90 functional requirements: 64 Must for the alpha, 14 Should for App Store 1.0, 10 Could and 2 Won't. Each row derives from the plan's feature list, AI touchpoints, safety design, privacy promise or release plan. Measured targets live in section 9, and BYOK detail lives in section 12.

### 8.1 Capture (CAP)

Every capture path saves to disk first and runs AI later, so recording never waits on a model. Traces to BR-04, BR-05 and BR-08.

| ID | Requirement | Priority | Acceptance criterion |
|---|---|---|---|
| FR-CAP-01 | Record voice notes from the voice pill, with a level meter, pause, resume, stop and review. | Must | A voice note saves as AAC 64 kbps mono. Review seeks to any word using the saved file's word times. |
| FR-CAP-02 | Start capture from any app through the menu bar extra, a global hotkey (Ctrl-Cmd-J, changeable) and a floating non-activating voice pill. | Must | From another app, the hotkey starts recording in under 2 s. It needs no Accessibility permission in the sandbox. |
| FR-CAP-03 | Write reflections in a plain-text editor that autosaves. Only the user writes `entry.body`, and Writing Tools stays off unless the user opts in. | Must | No AI path writes `entry.body` (test). Every journal editor carries `.writingToolsBehavior(.disabled)` by default. |
| FR-CAP-04 | Record video moments with the ritual: countdown, orb, timer, checkpoints, Keep going, confirm finish and two-step discard. Multi-turn sessions show as one stack card with a set view. | Must | Video saves as 1080p HEVC at 2.5 Mbps, within 20%, in 2 s fragments. A 720p Space saver toggle and a framing tip exist. Video is the first item cut on slip. |
| FR-CAP-05 | Show two-line live captions while recording, used for display and the checkpoint question only. | Must | Captions appear within about 1 s. Output is discarded while paused, and no live text is ever stored as a quote. |
| FR-CAP-06 | Transcribe every saved or dropped file into the transcript of record, with timed words and confidence. Tapping a sentence seeks to it. | Must | Word times land within 100 ms of file time across a pause. Without a speech model, the entry shows "Transcript not ready" and resolves later. |
| FR-CAP-07 | Add stills by paste, drop or picker, normalised to HEIC at most 4096 px with GPS stripped. | Must | A JPEG with GPS imports as HEIC with no location metadata. Its thumbnail exists at write time. |
| FR-CAP-08 | Caption stills on-device when the model reports vision, with default guardrails only. The user can edit the caption. | Must | A guardrail hit leaves the caption empty and labelled. Caption text passes layers 2 and 3, and a hit there makes the still a safety hold. Second item cut on slip. |
| FR-CAP-09 | Accept text, images, audio, video and music URLs by Space, paste, drop and File > Import Media… on the board and the pill. | Must | Dropped audio or video becomes a voice note or moment with a poster and a queued transcript. A music URL saves as a link with no fetch. Space never fires inside a text field. |
| FR-CAP-10 | File a capture made while viewing a past day under that day. | Must | The entry gets `local_day` = the viewed day, `captured_at` = now and `backdated` = 1. It creates no session in the Alpha report. |
| FR-CAP-11 | Keep every interrupted take: write the rows before the first frame, and reconcile rows and files at launch. | Must | After kill -9, the take plays up to its last 2 s fragment. Every file has a row and every row has a file. |
| FR-CAP-12 | Show music cards with title and artwork (P8). | Should | Ships only if Bharat approves the network entitlement and the matching privacy copy change. |

### 8.2 Day surface (DAY)

The alpha shows an ordered day board, and the free-form canvas returns in P7 once the habit is proven. Card views are pure SwiftUI, so the canvas reuses them unchanged. Traces to BR-02 and BR-13.

| ID | Requirement | Priority | Acceptance criterion |
|---|---|---|---|
| FR-DAY-01 | Show each day as an ordered board of entry cards, in a split view with a sidebar of days, What Saro knows and Trash. | Must | Cards sort by `captured_at`. The static time-of-day tint passes AA contrast at every hour (unit test). |
| FR-DAY-02 | Open any card to a detail view with a player, the timed transcript and Saro's turn questions. Offer Copy transcript, Show in Finder and Export a copy. | Must | Starting a second player pauses the first. Copy transcript puts the full transcript on the pasteboard. |
| FR-DAY-03 | Move between days with Cmd-Left, Cmd-Right, Cmd-T and a date picker, with honest empty and future-day states. | Must | The board rolls to the new day at midnight and on a time-zone change, without a relaunch. |
| FR-DAY-04 | Let the user edit an entry's title, caption and summary. User edits outrank AI output and count as gold labels. | Must | Edits land in `title_user`, `caption_user` or `summary_user`. No later regeneration replaces them. |
| FR-DAY-05 | Support card context menus, keyboard selection, and delete to Trash with undo, restore all and a two-step empty. | Must | Cmd-Z restores a deleted card with its media. Trashed items purge after 30 days. |
| FR-DAY-06 | Show a week, month and year time-lens grid and a 7-day mood ribbon, built from per-entry moods (P5). | Should | A safety-held day shows no mood in the grid or the ribbon. No past day is generated just to colour a tile. |
| FR-DAY-07 | Duplicate an entry to Today, Yesterday or a chosen date (P5). | Should | The copy reuses the source media, inherits the source's safety verdict and is excluded from engine counts. |
| FR-DAY-08 | Bring back the free-form canvas in P7: pan, zoom, drag, throw, resize, guides, saved positions, day replay, the lens pinch and morph flights. | Could | Meets the canvas targets in section 9 (NFR-15). Day replay shows no mood on flagged days. |

### 8.3 Reflection (REF)

Saro reads each cleared entry once at save, and code builds everything the user sees from those stored readings. The model picks quotes by number and never types them. Traces to BR-06 and BR-11.

| ID | Requirement | Priority | Acceptance criterion |
|---|---|---|---|
| FR-REF-01 | Process each cleared entry at save into a title, summary, mood (12 labels), mood basis, one quote and up to 12 observations. Quotes come from up to 24 numbered candidate phrases. | Must | At least 90% of clear entries extract on the primary or fallback rung. Every stored quote matches its source by UTF-16 span and `text_sha256`. |
| FR-REF-02 | Run every call that transforms the user's words on one ladder: permissive JSON first, guided @Generable fallback, then the heuristic or an honest state. Still captions are not on the ladder. | Must | The ladder never re-asks with looser guardrails. At most 4 model calls run per touchpoint per entry, two per rung. Heuristic output is labelled "In your words". |
| FR-REF-03 | Check all model prose for drift. Every proper noun, number, relationship word and content noun must appear in the source or an allowlist of about 200 nouns. | Must | The check rejects "the end of a long shift" and "Thakawat aur asuvidha". A failure gets one retry on the same rung, then drops a rung. |
| FR-REF-04 | Build the day reading by map-reduce over stored annotations and numbered candidates, never over raw day text. Show it in the "What Saro noticed" inspector. | Must | The reading has a last-inferred line, a mood with basis, 1-3 quotes and one question. A model narrative ships only if 90% of eval narratives pass grounding; otherwise a quote template ships. |
| FR-REF-05 | Let the user adjust the day's mood and answer the daily question, with an answer lock, an exclusion list and an archive. | Must | A mood correction writes a user observation and survives regeneration. Answers are stored as `reflection_turn` rows. |
| FR-REF-06 | Ask one follow-up question at each voice or video checkpoint, raced about 2.5 s against the heuristic. Live text shapes the question but is never stored. | Must | p50 is 2.5 s or less on the M5, and a question appears within 3 s on the M1/M2. A held turn shows resources; a turn with no live text shows only Keep going. |
| FR-REF-07 | Ask one follow-up on a written reflection, after the gate, with history-word and banned-phrase checks. | Must | A safety-held reflection shows the SafetyCard instead of a question. |
| FR-REF-08 | Typeset the evening letter from the verified reading, with quote links, Keep, Rewrite and Write back. The alpha has no model-written letter prose. | Must | Every quote link opens its entry at `saro://entry/{id}`. Rewrite creates a new reading snapshot, and Keep stores a letter snapshot. |
| FR-REF-09 | Open the letter early with "Close the day" once a reading exists, and send a content-free letter notification at letter time. | Must | Neither happens on a safety-hold day or a day awaiting a check (one test per case). |
| FR-REF-10 | Deliver the first pattern after 3 moments and the first weekly note on day 6, from stored quotes only. | Must | Safety-held and awaiting-a-check entries, and safety-held days, are skipped. Each note arrives by a content-free notification. |
| FR-REF-11 | Refresh the narrative, mood or question with one seeded random-sampling call each (P5). | Should | Each refresh passes the same grounding checks and writes a new snapshot. |
| FR-REF-12 | Track commitments with carry-over and let-go in an append-only `commitment_event` log (P5). | Should | Created, carried, completed, uncompleted and let-go events all persist, so follow-through shows over weeks. |

### 8.4 Safety (SAF)

One native gate with four states decides what Saro may say about any entry, on every path, with AI on or off. The measured ship gates are NFR-07 to NFR-10 in section 9. Traces to BR-07 and BR-11.

| ID | Requirement | Priority | Acceptance criterion |
|---|---|---|---|
| FR-SAF-01 | Run one SafetyGate on every path: model, heuristic, onboarding, menu bar, hotkey, intents, and dropped, imported, recovered, backdated and duplicated entries. Re-run it on every edit, `SAFETY_VERSION` bump and model return. | Must | A test per path proves the gate ran, and a duplicate reuses its source's verdict. A changed `text_sha256` or version re-gates before any generation. |
| FR-SAF-02 | Layer 0: give spoken entries with low mean transcription confidence a technical hold. Layer 0 never clears an entry by itself. | Must | Low-confidence text still passes layers 1 and 2, and any hit there is a safety hold. |
| FR-SAF-03 | Layer 1: match a phrase gate built from the 20 `safety.py` regexes, the `safety.ts` idiom guards and an expanded Hinglish list with Devanagari. One Unicode-preserving normaliser serves both sides. | Must | "main mar jaun" matches. A Devanagari phrase survives normalisation and matches. The gate runs in under 1 ms. |
| FR-SAF-04 | Layer 2: classify text as NONE, PASSIVE or ACTIVE on-device (permissive String, greedy, 4 tokens, few-shot). Any other reply, a refusal or a timeout is a safety hold. | Must | Strict-parse tests cover refusal text, prose and timeouts. Text over 3,000 tokens is chunked, and any risky chunk flags the entry. |
| FR-SAF-05 | Layer 3: run the phrase gate over every generated string. Treat an Apple guardrail violation as content policy, not a safety signal. | Must | An output-gate hit suppresses the output and holds the entry. A guardrail violation moves to the heuristic or an honest state, never the SafetyCard. |
| FR-SAF-06 | Give each entry exactly one of four states: clear, technical hold, safety hold or model unavailable. Precedence is safety hold, then model unavailable, then technical hold, then clear. | Must | One test per state passes. A technical hold requires layer 2 to have run. |
| FR-SAF-07 | Safety hold: show the SafetyCard with region-keyed crisis resources (988, Tele-MANAS 14416, findahelpline), and apply the whole-day rule. Help > If you're struggling is always one click away. | Must | The day gets no reading, mood, quotes, letter or letter notification. Tests pass for IN, US, GB and an unknown region. |
| FR-SAF-08 | Technical hold: show "Saro couldn't hear this one clearly" with Retry and no crisis link. The day still gets a reading from its clear entries. | Must | The recording stays playable. The entry yields no observations until a retry clears it. |
| FR-SAF-09 | Model unavailable: run layers 0 and 1 with the caution lexicon, and quote back "In your words" only when both clear. Dogfood builds before P2 follow this rule too. | Must | A caution hit shows "Saro will read this when Apple Intelligence is ready" and a quiet "Talk to someone" link. Waiting entries re-gate through layer 2 automatically. |
| FR-SAF-10 | Mark an entry awaiting a check when it has a caution hit with the model unavailable, or no verdict yet. Its day gets no reading, letter or notification until it is gated. | Must | A day with an untranscribed voice note sends no letter notification (test). |
| FR-SAF-11 | Run about 20 risk and 20 venting canaries on each new os_build. A missed risk canary turns on conservative mode. | Must | A forced miss applies the model-unavailable rules and shows "Saro is checking this macOS update". The event appears in the Alpha report. |
| FR-SAF-12 | Let testers send a "Saro got this wrong" report from Alpha-0 on Fri 2 Apr 2027. | Must | The report holds entry id, state, layer, reason_code, `SAFETY_VERSION`, os_build, variant and an optional synthetic paraphrase. A test proves it holds no entry text. |

### 8.5 Memory and self-model (MEM)

Every input is stored with provenance and nothing derived is updated in place, so any future engine can replay the ledger. Traces to BR-09 and BR-10.

| ID | Requirement | Priority | Acceptance criterion |
|---|---|---|---|
| FR-MEM-01 | Write each extraction in one transaction to an append-only ledger: `ai_run`, `ai_run_input`, `entry_annotation` and observations with UTF-16 spans and hashes. | Must | An UPDATE on `observation` aborts. Every artifact links to an `ai_run` with executor, os_build, variant, model_fingerprint, prompt_version and ladder_rung. |
| FR-MEM-02 | Retract and re-insert observations when entry text changes, never update them. AI never writes the user's own columns. | Must | An edit adds an `observation_retraction` whose `replaced_by` points to the new row. |
| FR-MEM-03 | Show "What Saro knows" as a filtered list, with Why (dated verbatim quotes), delete and pause. | Must | Why opens the source entry. Delete writes a retraction and a tombstone, and a tombstoned key never returns. Nothing is learned inside a pause. |
| FR-MEM-04 | Forget all: hard-delete every derived row in one transaction, rebuild snapshots, delete `Backups/` and take a fresh snapshot. | Must | One test per artifact type finds no remaining row. |
| FR-MEM-05 | Hide observations from any safety-held day from the engine, What's changed and both first-week notes. Restore them when a re-gate clears the day. | Must | The `active_observation` view filters them, and a re-gate test brings them back. |
| FR-MEM-06 | Backfill every entry since the dogfood build through the gate and extraction when model processing ships in P2. | Must | Every entry since Fri 18 Dec 2026 has a model annotation or an honest state. |
| FR-MEM-07 | Fingerprint the model on each new os_build. A changed fingerprint starts a new lineage, so a model change never reads as the person changing. | Must | Golden fixtures with an unchanged fingerprint start no lineage, and a changed one starts one. Heuristic output is never diffed against a model series. |
| FR-MEM-08 | Show "What's changed" weekly and monthly from deterministic engine v0, every line quote-backed (P5, by Fri 7 May 2027). | Should | The same ledger always yields the same snapshot hash. Bharat finds at least 3 accurate lines in his journal and none invented. |
| FR-MEM-09 | Let the user edit and add memories as user observations that outrank extraction (P5). | Should | A user observation survives re-extraction and needs no quote. |
| FR-MEM-10 | Re-extract history into a new lineage when the fingerprint changes, gated by evals (P5). | Should | Re-extraction runs only if the new eval report doesn't regress. It defers on `rateLimited`. |

### 8.6 Search and commands (SRC)

The alpha searches with a substring filter, and the ranked Cmd-K palette arrives in P8. Traces to BR-04 and BR-12.

| ID | Requirement | Priority | Acceptance criterion |
|---|---|---|---|
| FR-SRC-01 | Search from the sidebar over title, summary, transcript and body, and filter What Saro knows by label and quote. | Must | A word spoken in a voice note finds that note. |
| FR-SRC-02 | Drive menus and shortcuts from one command registry: Cmd-N write, Cmd-Shift-V voice, Cmd-Shift-M moment and the day commands. | Must | Every action has a menu command. Single-key shortcuts fire only when the board has focus and no text field is active. |
| FR-SRC-03 | Add a Cmd-K palette on FTS5 with bm25 field weights, snippets, typo tolerance and typed-date jumps (P8). | Should | The `search.test.ts` fixtures pass. p95 is 5 ms or less per keystroke at 1,000 entries. |
| FR-SRC-04 | Offer "Record a voice note" through App Intents, Shortcuts and Siri (P5). | Should | Text that arrives through an intent passes the gate like any other path. |

### 8.7 Onboarding (ONB)

A new user reaches a first entry within 180 s of first launch, with or without Apple Intelligence. Traces to BR-02, BR-05 and BR-11.

| ID | Requirement | Priority | Acceptance criterion |
|---|---|---|---|
| FR-ONB-01 | Open on a lit-door welcome with the exact three-line privacy copy, and ask for no account. | Must | The welcome text matches NFR-02 word for word. |
| FR-ONB-02 | Ask five About-you questions and show what "Saro heard" after each answer. | Must | Answers write `starter_context` and onboarding observations. A safety-held answer shows the SafetyCard instead of a personal prompt. |
| FR-ONB-03 | Compose a first prompt from the answers and show it as TODAY'S PROMPT. The first step opens the voice pill or Write. | Must | All 5 Alpha-0 testers make a first entry within 180 s, once with AI on and once with it off. |
| FR-ONB-04 | Set the ritual time and weekdays, preview the notification, then ask permission. Send one content-free reminder per chosen weekday. | Must | Reminder actions open `saro://capture/voice` and `saro://capture/write`. |
| FR-ONB-05 | Show camera and mic pre-permission screens, a mic check, and a readiness card for Apple Intelligence and speech downloads. | Must | Each unavailable reason, including a work Mac where management turns Apple Intelligence off, shows its own honest copy. |

### 8.8 Settings (SET)

Settings holds every preference, the privacy controls and the content-free reports testers send back. Traces to BR-05, BR-10 and BR-12.

| ID | Requirement | Priority | Acceptance criterion |
|---|---|---|---|
| FR-SET-01 | Provide a Settings scene (Cmd-comma) with name, what Saro calls you, tone (Gentle, Neutral, Direct, Contemplative), ritual and letter times, and caption language. | Must | A tone change applies to the next model session. Changing a time reschedules its triggers. |
| FR-SET-02 | Provide Comfort settings: an in-app text size (0.9, 1, 1.125, 1.25, 1.5) and captions always on. | Must | Every screen renders at 1.5 without clipping (XCUITest). |
| FR-SET-03 | Provide a Writing Tools opt-in, off by default, that says Writing Tools may use PCC or ChatGPT for selected text. | Must | With the toggle off, no journal editor offers Writing Tools. |
| FR-SET-04 | Offer a Touch ID lock at launch and after time away, with copy that says lock, not encryption. Third item cut on slip. | Must | No journal content shows until authentication succeeds. |
| FR-SET-05 | Show Privacy & Data: a storage meter, the "What this means" copy and the content-free "What Saro read" log. | Must | "What Saro read" lists feature, time, entry count, executor, rung and status, and never words. |
| FR-SET-06 | Show a weekly Alpha report: days active, sessions, entries by kind, ladder rungs, holds by state, canary events, and crash and hang counts. | Must | The report holds no words (test). One click copies it for the weekly survey. |
| FR-SET-07 | Warn from 14 days before a TestFlight build expires, show the date and offer Export. | Must | A build 76 days old shows the nudge with its expiry date. |
| FR-SET-08 | Add the rhythm suggestion, focus areas (up to 3), Follow-the-day appearance and screen-share hiding. | Should | Screen-share hiding ships only after tests with Zoom, Meet and QuickTime on macOS 27. |
| FR-SET-09 | Sell Saro+ through StoreKit for the business model chosen on Fri 21 May 2027 (P8). | Should | StoreKit sells only features that exist in the shipped build. |
| FR-SET-10 | Accept free-text custom instructions. | Won't | Cut: they conflict with never-invent and open prompt injection. Revisit after the alpha. |
| FR-SET-11 | Require an account, sign-in, profile extras or account deletion. | Won't | First launch needs no account. Erase all data replaces account deletion. |

### 8.9 Export and backup (EXP)

People can take the whole journal out, put it back and undo a mistake, with no server. Traces to BR-08.

| ID | Requirement | Priority | Acceptance criterion |
|---|---|---|---|
| FR-EXP-01 | Export everything to a `.saroexport` folder: JSON with `export_version` plus the real media files. | Must | The export-erase-import round trip matches every row and media sha256. The panel warns when the folder is in iCloud Drive. |
| FR-EXP-02 | Import a Saro export through File > Import Saro Export…, idempotent by UUID. | Must | Importing the same export twice creates no duplicates. |
| FR-EXP-03 | Take a daily database snapshot with VACUUM INTO, keep 7, and offer Restore from snapshot. | Must | Restore keeps the current file as a pre-restore snapshot, then swaps in the chosen one. |
| FR-EXP-04 | Erase all data: store, media, backups, notifications and prefs. | Must | After Erase, the container holds no journal file, media or snapshot (test). |
| FR-EXP-05 | Back up weekly to a folder the user chooses, with a "Last backup N days ago" nudge (P5). | Should | The folder survives relaunch through a security-scoped bookmark. |
| FR-EXP-06 | Sync through iCloud with journal text end-to-end encrypted, and add the iPhone capture companion (P6). | Should | An iPhone entry appears on the Mac within 1 minute when online. 0 entries are lost or duplicated over 2 weeks. In the canvas-first order this ships as 1.1. |

### 8.10 Bring your own model (BYOK)

BYOK's requirements are FR-BYOK-01 to FR-BYOK-23 in section 12.16. The TestFlight alpha carries none of it and stays offline (FR-BYOK-01, Must). BYOK ships first in the founder-only Saro Lab build, and D-19 decides by Fri 21 May 2027 whether the public app carries it.
