#if DOGFOOD
import SaroKit

/// What each screen does and how far it got tonight. Plain data, edited by hand; a screen's open decisions come from
/// `Decision.screens` in SaroKit so the register stays the one place they're listed.
struct DevNotes {
    let name: String
    let does: String
    let built: [String]
    let stubbed: [String]
    let issues: [String]
    let brd: [String]

    static func decisions(for screen: ScreenID) -> [Decision] { Decision.all.filter { $0.screens.contains(screen) } }

    static func of(_ screen: ScreenID) -> DevNotes {
        switch screen {
        case .canvas:
            DevNotes(
                name: "Day canvas",
                does: "One free canvas per local day, built to the web overnight build: a lit ground, cards that fly open, floating chrome (Monolith + search top-left, the insight spine right, one glass bar below).",
                built: ["Cards drawn to the web specs: moment, turns stack with ghost layers, voice orb + pill, still, reflection; 'title · time' footer",
                        "Click opens (a log-space flight over an 85% ground scrim with blur); ⌘/⇧-click selects; Return opens the selection",
                        "Drag after 4 pt: lift to 1.02, tilt with velocity (±3°), glide on release (velocity × 0.12) on the release spring",
                        "The uneven drag grid (web DragGuides): a seeded 24/40/64/104 rhythm draws out around a held card with radial falloff; edges snap 3 pt to it, any anchor 6 pt to other cards (⌥ frees)",
                        "Two-finger pan, pinch and ⌘-scroll zoom (0.2-3×); the day stays framed until you move it; Recenter (⌘0)",
                        "Marquee on empty canvas and the contextual toolbar: Stack ⌘S, Grid ⌘G, Delete",
                        "Chevrons slide the whole day (viewport + 32 pt, surface spring); ⌘[ ⌘] switch instantly; tomorrow leans 24 pt and comes back",
                        "The glass bar: History (days sidebar), date + 7-day mood ribbon, Moment ⌘N, Voice ⇧⌘N, Still, Write ⌥⌘W, Recenter",
                        "Lit ground: the web's WebGL shader ported to Metal, keyed to the hour; palette follows the clock (B-18)",
                        "Drop, paste or pick photos as stills; -SaroDemo YES opens a throwaway journal of synthetic entries"],
                stubbed: ["Resize handles", "Motion blur on flights",
                          "Collections / folders (FR-CAN-05)", "Notes pinned to an image (FR-CAN-04)", "Time lens, day replay (FR-DAY-06)"],
                issues: ["Overnight, gestures and motion were checked from builds and off-screen snapshots only; nobody has clicked or flicked them on a trackpad yet",
                         "Zooming far in scales cards as layers, so text can look soft above 150%",
                         "A day sliding out re-reads titles from the new day for its last frames (cards keep their places)"],
                brd: ["FR-CAN-01", "FR-CAN-02", "FR-CAN-03", "FR-CAN-06", "FR-CAN-11", "FR-DAY-01", "FR-DAY-03", "FR-DAY-05", "DR-10"])
        case .sidebar:
            DevNotes(
                name: "Sidebar",
                does: "The list of days with entry counts, plus Trash and Decisions.",
                built: ["Days with entry counts, Today always listed", "Trash and Decisions rows"],
                stubbed: ["What Saro knows (FR-MEM-03)", "Search (FR-SRC-01)", "Date picker for jumping to a day (FR-DAY-03)"],
                issues: [],
                brd: ["FR-DAY-01", "FR-DAY-03", "FR-SRC-01"])
        case .recorder:
            DevNotes(
                name: "Recorder",
                does: "The in-window recorder for video moments and voice notes. A pause keeps the part; Pause & reflect ends it, Saro asks, and Keep going starts the next.",
                built: ["Video first at 720p HEVC (1080p in Settings)", "Camera picker incl. Continuity Camera",
                        "One file per part, rows written before the first frame (crash-safe); pause and resume in the same file",
                        "Today's prompt under Saro's orb, frozen at the first part and kept as its prompt row",
                        "3-2-1 that Cancel (or Space) stops; default focus on the record disc; no entrance animation by key",
                        "Live captions on this Mac (SpeechAnalyzer volatile results), never stored (FR-CAP-05); Captions always on",
                        "Pause & reflect (R): the gate on the live words, then reflect_deeper raced against its twin for 2.5 s",
                        "Observation line and the question arriving word by word; held words show the night SafetyCard",
                        "Keep going (Return or K), Saving… only past 150 ms; the question is the next part's prompt",
                        "Finish dialog with two-step discard of the part not yet kept (Ledger.discardTake)",
                        "The last frame develops, then flies into its card after a click",
                        "Voice pill: starts on open, one live caption line, review with bars, transcript and Keep this / Record again",
                        "Mic errors offer Try again; a disconnect keeps what was said"],
                stubbed: [],
                issues: ["The launch sweep that reconciles rows and files after a crash isn't verified with kill -9 (FR-CAP-11)",
                         "Live captions, checkpoints and the develop flight need a person at the Mac to check (camera, mic, speech)"],
                brd: ["FR-CAP-01", "FR-CAP-04", "FR-CAP-05", "FR-CAP-11", "FR-REF-06", "DR-11", "DR-12"])
        case .capturePanel:
            DevNotes(
                name: "Capture panel",
                does: "The floating ⌃⌘J panel: capture from any app without bringing Saro forward. Captures file under today.",
                built: ["⌃⌘J global hotkey", "Video, voice and writing from the panel", "Photos, audio and video dropped on the panel go to today"],
                stubbed: ["Changing the hotkey"],
                issues: [],
                brd: ["FR-CAN-09", "FR-CAP-02", "FR-CAP-09"])
        case .menuBar:
            DevNotes(
                name: "Menu bar extra",
                does: "Saro's menu bar item: start a capture, open the app, and Help → If you're struggling.",
                built: ["Capture actions", "Open Saro"],
                stubbed: ["Recent entries"],
                issues: [],
                brd: ["FR-CAP-02", "SR-20"])
        case .momentDetail:
            DevNotes(
                name: "Moment detail",
                does: "A video moment opened from its card: the player, the timed transcript (tap a sentence to seek) and Saro's reading of it.",
                built: ["Morphs open from its card and back", "Player with timed transcript", "Tap a sentence to seek; the playing sentence is highlighted",
                        "Your own title (outranks Saro's)", "What Saro heard: summary, mood, a verbatim quote that seeks, provenance line",
                        "Held entries show the SafetyCard instead; technical holds offer Try again"],
                stubbed: ["Copy transcript, Show in Finder, Export a copy (FR-DAY-02)", "Edit summary (FR-DAY-04); Edit details ⌘I edits the title"],
                // Turn n of N with the turn's question, ← →, and Play all (AVQueuePlayer) are built.
                issues: ["Transcription follows the system locale when supported, else en-US (B-12)"],
                brd: ["FR-CAN-01", "FR-DAY-02", "FR-DAY-04", "FR-CAP-06"])
        case .voiceDetail:
            DevNotes(
                name: "Voice detail",
                does: "A voice note opens in place on its card and plays: the orb glides into the player, with a progress track and the timed transcript (tap a sentence to seek). What Saro heard opens the full detail.",
                built: ["Opens in place (VoiceEchoCard): click outside or Esc folds it", "Scrub the track; tap a sentence to seek",
                        "Full detail: your own title, What Saro heard"],
                stubbed: ["Copy transcript, Show in Finder, Export a copy (FR-DAY-02)", "Edit summary (FR-DAY-04)"],
                issues: [],
                brd: ["FR-CAP-01", "FR-CAP-06", "FR-DAY-02"])
        case .writingDetail:
            DevNotes(
                name: "Writing",
                does: "The reading page for a written reflection, or a song's view. It autosaves; only you write the body.",
                built: ["Autosaving editor (0.8 s debounce)", "Title field (Untitled), TODAY · 4:16 PM · EDITED, the prompt row, your caption",
                        "The first line becomes the card title when none is typed", "Closing an empty page discards it (B-16)",
                        "Gate and reading run when the editor closes", "Edit on the card: the second click on a selected page edits its title or body",
                        "Reflect further after the gate: reflect_further on the ladder, Another question, Retry, the SafetyCard when held",
                        "Questions and gated answers are reflection_turn rows, never the body (DR-04)",
                        "Songs: 560 pt view with Open in … and Copy link; Edit details ⌘I for title and artist, which are gated, never read"],
                stubbed: [],
                issues: [],
                brd: ["FR-CAP-03", "FR-REF-07", "FR-SET-03", "DR-04"])
        case .stillDetail:
            DevNotes(
                name: "Still detail",
                does: "A dropped or pasted image, saved as HEIC with every metadata field removed except orientation (so no GPS).",
                built: ["Drop or paste a still", "HEIC at most 4096 px with location removed (FR-CAP-07)", "Mono-caps metadata (FR-CAN-07)",
                        "Opens in the photo's own shape within 86% × 74% of the window, its caption under it on the scrim",
                        "Saro sees: an on-device caption and tags, guided on default guardrails only, gated by layers 3 and 2 (FR-CAP-08, SR-11)",
                        "The Vision twin without Apple Intelligence: labels and words in the photo, else its colours",
                        "Edit the caption in place: it becomes yours, is gated, and outranks Saro's; Describe again ⌘R",
                        "A cleared still feeds the day's digest; only your own words are ever quoted"],
                stubbed: ["The note pinned over the image on the canvas (FR-CAN-04)", "Search over Saro's descriptions (navigation)",
                          "A mood from a still: skipped, no claims about the user"],
                issues: [],
                brd: ["FR-CAP-07", "FR-CAP-08", "FR-CAN-07", "SR-11"])
        case .stack:
            DevNotes(
                name: "Stack",
                does: "A recording session's turns piled together. Opening it fans the turns out in place and dims the canvas behind.",
                built: ["A session's turns stack automatically", "Fan out in place with the canvas dimmed", "Unstack", "Stack ⌘S from any selection"],
                stubbed: ["Turn numbers inside the opened detail"],
                issues: [],
                brd: ["FR-CAN-02", "FR-CAN-03"])
        case .noticed:
            DevNotes(
                name: "What Saro noticed",
                does: "Saro's reading of the day, made on this Mac from per-entry readings (title, summary, mood, quotes by index), only for entries the safety gate cleared.",
                built: ["The spine: glyphs, up to three commitment marks and +N, the dashed carry ring, a loading shimmer, the empty-day tip, a 44 pt fold",
                        "⌥⌘I, Esc and ⌘K are instant, the pointer springs; the evening arrival eases in (0.7 s)",
                        "Last-inferred line, the D-13 template narrative (titles, counts, 14-day recurrence), single-open sections",
                        "Adjust emotion (locked, gated note), the daily question with a gated answer and a lock, refresh insights / narrative / question",
                        "Copy summary, narrative, emotion tag and question as Markdown", "My commitments with carry-over, let go, undo (FR-REF-12)",
                        "First week: a first pattern, the day 4–5 check-in, the day-6 weekly letter (FR-REF-10)",
                        "Tone, name and focus in the model's instructions (entry-2, day-2)"],
                stubbed: ["Add commitments to the canvas (needs a non-entry canvas item)"],
                issues: ["The narrative eval gate (D-13) isn't built: a model narrative stands in for the subtitle if it passes the drift check",
                         "The 14-day recurrence is read with the day; an older day's change shows at the next re-read"],
                brd: ["FR-REF-01", "FR-REF-02", "FR-REF-03", "FR-REF-04", "FR-SAF-06", "SR-13", "DR-07"])
        case .letter:
            DevNotes(
                name: "Evening letter",
                does: "The day's letter, typeset from the verified day reading with links back to the quotes. No model-written prose (B-11).",
                built: ["Header with the eyebrow, date and close; 'Dear {name},' isolated, or 'Hello,'",
                        "Up to three paragraphs from the narrative; quotes fly into their entry; 'In your words' lists only unplaced quotes",
                        "Write back (the daily question's answer), Keep (the kept copy reads on return), Write a new letter",
                        "Available after the letter time (Close the day opens it early), unread dot, opened record in the ledger",
                        "Evening arrival when the window is key and the canvas idle; a content-free notification at the letter time"],
                stubbed: [],
                issues: ["The quote's flight starts from its paragraph's frame, not the quote's own run"],
                brd: ["FR-REF-08", "FR-REF-09", "SR-13"])
        case .safetyCard:
            DevNotes(
                name: "Safety card",
                does: "Shown when an entry is on a safety hold: crisis resources for your region, and nothing generated for the whole day.",
                built: ["Phrase gate incl. a DRAFT Hinglish and Devanagari list (B-09)", "Graded on-device classifier NONE / PASSIVE / ACTIVE (B-08)",
                        "SafetyCard with 988, Tele-MANAS 14416 and findahelpline", "Whole-day rule"],
                stubbed: ["Canary and conservative mode (B-10, SR-22)", "'Saro got this wrong' report (FR-SAF-12)"],
                issues: ["Phrase list, classifier definitions and card copy are not clinician-reviewed (SR-32)",
                         "The classifier probe missed idioms like 'punch the screen' (11/13)"],
                brd: ["FR-SAF-01", "FR-SAF-03", "FR-SAF-04", "FR-SAF-06", "FR-SAF-07", "SR-01", "SR-02", "SR-07", "SR-13", "SR-19", "SR-20"])
        case .trash:
            DevNotes(
                name: "Trash",
                does: "Deleted entries, one batch per action, restorable with ⌘Z or from here.",
                built: ["Soft delete by batch", "Undo from the toast or ⌘Z", "Restore from this pane"],
                stubbed: ["Purge after 30 days (DR-15)", "Two-step Empty Trash (FR-DAY-05)"],
                issues: [],
                brd: ["FR-DAY-05", "DR-15"])
        case .decisions:
            DevNotes(
                name: "Decisions",
                does: "The decision register: D-01…D-22 from the BRD and the build decisions (B-xx) taken overnight. Record a choice and a note, then export both files for Claude.",
                built: ["Choices and notes stored as append-only events", "File → Export Decisions for Claude… (⇧⌘E)", "Copy Decisions for Claude"],
                stubbed: [],
                issues: ["Decision wording is seeded in code (SaroKit/DevMode/Decisions.swift); changing it needs a build"],
                brd: [])
        case .settings:
            DevNotes(
                name: "Settings",
                does: "The Settings window (⌘,, ⌘K → Settings…, saro://settings/<section>): one page on the lit ground with a numbered rail (⌘1–⌘8) and Say it at the top.",
                built: ["Say it: settings in your own words, a diff to Apply (⌘↵) and Undo (⌘Z), never applied without a yes",
                        "01 You: name and what Saro calls you, where the journal lives, Replay onboarding, About",
                        "02 How Saro talks: your own sentence said four ways (held days never used), focus picker up to three",
                        "03 Rhythm: daily reminder with weekdays, preview and Send a test; letter time; rhythm strip and suggestion with Undo",
                        "04 Appearance: palette and Preview the day", "05 Comfort: text size 90–150% everywhere, captions, Saro's own reduce motion and transparency, sounds, haptics on snap, Writing Tools opt-in",
                        "07 Intelligence: readiness per reason, speech per language, details", "08 Your data: NFR-02 with proofs, storage by kind, recording quality, Export with progress and an iCloud warning, Import (idempotent), Book of the year as HTML or PDF, What Saro read, Erase everything",
                        "On-device tone rewrite and Say it fallback: one call each, output gate and drift check, logged as tone-preview and settings-parse"],
                stubbed: ["06 What Saro knows: pause works; the list arrives with memory", "Touch ID lock and Hide from screen sharing: saved, applied by shell (FR-SET-04)",
                          "About Saro opens the standard About panel until shell's About window lands",
                          "Captions always on: saved, read by capture's live captions (the caption language already steers transcripts)",
                          "Settings… and Profile… in the avatar menu arrive with shell's AvatarButton (menu bar and ⌘K have them)"],
                issues: ["The tone preview's on-device rewrite and Say it's model fallback are untested against the real model: their checks are unit-tested with canned replies"],
                brd: ["FR-SET-01", "FR-SET-02", "FR-SET-03", "FR-SET-04", "FR-SET-05"])
        case .onboardingWelcome:
            DevNotes(
                name: "Welcome door",
                does: "First launch of a real journal: the lit door with the hour's greeting, the three NFR-02 privacy lines word for word, Begin, and 'You're in.'.",
                built: ["Clock eyebrow and greeting band on the minute", "NFR-02 lines verbatim, no account", "Promise pages in place with proofs (Esc returns focus)",
                        "Rise-in stagger (y 10, 0.4 s)", "'You're in.' word reveal, 2.5 s, skippable by click or any key, shown once",
                        "Steps resume after a quit (onboarding.step, .furthest, .aboutStep); demo and snapshot runs skip it (-SaroOnboarding YES shows it)"],
                stubbed: [],
                issues: ["Promise copy points at Settings → Your data, which the settings package builds"],
                brd: ["FR-ONB-01", "NFR-02"])
        case .onboardingAboutYou:
            DevNotes(
                name: "About you",
                does: "Five questions, with what Saro picks up underlined in the answer as it's typed, then a first question made from the answers.",
                built: ["extract.ts ported, plus NLTagger personal names on top of the lists", "NSTextView field: Return commits, Shift-Return new line, ⌥← at the start goes back, IME-safe",
                        "Live marks as layout-manager temporary attributes (400 ms settle near the caret, 160 ms fade)", "'Saro heard' toggles; Q5 tone chips after 1.5 s",
                        "Every answer through SafetyGate before it's saved; a held answer shows the SafetyCard instead of a personal prompt",
                        "First prompt (firstPrompt.ts) with their words set in sans; Ask me something else", "Q1 prefilled from this Mac's user name",
                        "An answer awaiting a check (caution hit, no verdict) is kept but feeds no name, focus, tone, goal or ritual; re-gated on each step and on activation",
                        "A caution hit shows 'Talk to someone' under the first question", "Return presses Answer it once the screen has risen, never on a held key's repeat"],
                stubbed: ["On-device model drafts of the first prompt (templates only, by design for the alpha)", "Onboarding observations for What Saro knows (memory package)"],
                issues: ["Unchecked answers re-gate only while onboarding is open; after it they stay unused until a replay"],
                brd: ["FR-ONB-02", "FR-ONB-03", "SR-01", "SR-14", "SR-17"])
        case .onboardingFirstWeek:
            DevNotes(
                name: "First week",
                does: "The week at the ritual hour: seven days on one horizon, each a reminder toggle, the ritual time, the reminder word for word, then the ask.",
                built: ["Ritual time from the answers (ritualFromSpans), typed or ↑↓ by 15 min, Esc restores", "Week row: one tab stop, arrows, Home/End, Space toggles; today stays on",
                        "Milestones and VoiceOver change lines (weekChange)", "Seven Sunrises entrance on one clock (WeekLight timings), landing on a click or key",
                        "Content-free NotificationPreview; Allow → test notification; denied → System Settings", "Palette follows the ritual hour while open",
                        "Return starts today's moment only once the week is at rest (and not while the time is typed)", "Below a 1256 pt window the ritual, preview and ask stack"],
                stubbed: ["The WeekSky Metal shader: the light is drawn in a SwiftUI Canvas instead"],
                issues: [],
                brd: ["FR-ONB-04", "R-03"])
        case .onboardingFindLight:
            DevNotes(
                name: "Find your light",
                does: "The camera and mic check as a mirror on its own preview-only session: light, direction, framing (Vision) and mic. Nothing is recorded.",
                built: ["Phases and copy from the web, rewritten for macOS", "64×36 readings every 166 ms with holds", "Oval, mic rim, light arc and eye-line marks",
                        "Status rows with Turn off and Esc", "Camera picker incl. Continuity Camera", "Readiness card: Apple Intelligence and speech download",
                        "Hand-off: moment recorder, voice pill, or a writing page with the prompt as its question",
                        "The first question shows under Saro's orb in the recorder, atop the voice pill and on the page as its prompt row"],
                stubbed: [],
                issues: ["Light thresholds (LightRead.Light) are the web's; tune against Bharat's cameras"],
                brd: ["FR-ONB-05", "FR-ONB-03"])
        case .knows:
            DevNotes(
                name: "What Saro knows",
                does: "The memory pane (⌥⌘K, ⌘K, the sidebar): what Saro picked up from cleared entries, as a knowledge graph or the web's list, every line editable and deletable.",
                built: ["Learning after each entry's gate and reading: verbatim sentence quotes with UTF-16 spans, one transaction with a content-free ai_run (mem-1); an edit retracts (source_edited) and re-learns; launch backfill",
                        "Model rung: a guided call picks people, themes and intentions by phrase number; an invented name rejects the reply; heuristic twin ports memory.ts plus NLTagger places",
                        "active_observation hides retracted, forgotten, trashed, duplicated and held-day rows; a re-gate that clears the day brings them back",
                        "List: About you, People, On your mind, What you're working on, Feelings; meta lines; Why lists every dated sighting and opens it (recordings play from the quote)",
                        "Edit (↵ save · esc cancel, 90 chars), Add, Delete with in-row Undo for 6 s and ⌘Z, Forget everything with its inline confirm, Memory switch (pause)",
                        "Graph: force-directed, sized by mentions, coloured by kind, kind and time filters, hover lights neighbours, side panel with mentions, 12-week bars, related, Forget and Rename",
                        "SR-15: a verdict that doesn't clear an entry deletes what was learned from it; Delete and Forget delete the words, keeping only key hashes",
                        "Export everything carries a readable memories array; ⌘K lists matching memories and jumps to the line"],
                stubbed: ["What you're working on needs reflection's commitment table (v4); it reads it once it exists",
                          "About you lines use a short goalPhrase until onboarding's SayBack merges; they are read from the starter context, so the graph doesn't show them",
                          "Feeding prompts: knownLabels is ready; reflection's setPersonalization reads it",
                          "Settings: WhatSaroKnowsView(embedded: true) is ready for the settings package to place"],
                issues: ["Pausing is recorded per window; text gated while paused is learned once memory is back on only if it was written outside the pause",
                         "Forget everything removes memories only; readings and letters stay (decision flagged)"],
                brd: ["FR-MEM-01", "FR-MEM-02", "FR-MEM-03", "FR-MEM-04", "FR-MEM-05", "FR-MEM-06", "FR-MEM-09", "DR-06", "DR-09", "DR-13", "DR-17"])
        }
    }
}
#endif
