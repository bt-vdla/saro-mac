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
                does: "The in-window recorder for video moments and voice notes. Video is the default; each pause ends a turn and resume starts the next.",
                built: ["Video first at 720p HEVC (1080p in Settings)", "Camera picker incl. Continuity Camera",
                        "One file per turn, rows written before the first frame (crash-safe)", "Voice notes use the same turns"],
                stubbed: ["Countdown, orb, checkpoints and Keep going ritual (FR-CAP-04)", "Live captions (FR-CAP-05)",
                          "Checkpoint follow-up question (FR-REF-06)"],
                issues: ["The launch sweep that reconciles rows and files after a crash isn't verified with kill -9 (FR-CAP-11)"],
                brd: ["FR-CAP-01", "FR-CAP-04", "FR-CAP-05", "FR-CAP-11", "DR-11", "DR-12"])
        case .capturePanel:
            DevNotes(
                name: "Capture panel",
                does: "The floating ⌃⌘J panel: capture from any app without bringing Saro forward. Captures file under today.",
                built: ["⌃⌘J global hotkey", "Video, voice and writing from the panel"],
                stubbed: ["Changing the hotkey", "Dropping media onto the panel (FR-CAP-09)"],
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
                stubbed: ["Copy transcript, Show in Finder, Export a copy (FR-DAY-02)", "Edit caption and summary (FR-DAY-04)",
                          "Turn n of N navigation inside a session"],
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
                does: "The plain-text editor for a written reflection. It autosaves; only you write the body, and Writing Tools stays off.",
                built: ["Autosaving editor (0.8 s debounce), New York serif", "Writing Tools off in Saro's editors",
                        "The first line becomes the card title", "Closing an empty page discards it (B-16)",
                        "Gate and reading run when the editor closes"],
                stubbed: ["Follow-up question after the gate (FR-REF-07)", "Writing Tools opt-in (FR-SET-03)"],
                issues: [],
                brd: ["FR-CAP-03", "FR-REF-07", "FR-SET-03", "DR-04"])
        case .stillDetail:
            DevNotes(
                name: "Still detail",
                does: "A dropped or pasted image, saved as HEIC with every metadata field removed except orientation (so no GPS).",
                built: ["Drop or paste a still", "HEIC with location removed", "Colour palette and mono-caps metadata (FR-CAN-07)",
                        "Saro sees: an on-device caption and tags, guided on default guardrails only, gated by layers 3 and 2 (FR-CAP-08, SR-11)",
                        "The Vision twin without Apple Intelligence: labels and words in the photo, else its colours",
                        "Edit the caption in place: it becomes yours, is gated, and outranks Saro's; Describe again ⌘R",
                        "A cleared still feeds the day's digest; only your own words are ever quoted"],
                stubbed: ["The note pinned over the image on the canvas (FR-CAN-04)", "Downscaling very large images"],
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
                built: ["The 64 pt spine on the right (mood dot, letter mark); click or ⌥⌘I opens the 360 pt panel; Esc folds it",
                        "Per-entry reading on the guardrail ladder (permissive JSON, then guided, then heuristic)",
                        "Day reading by map-reduce over stored readings", "Four states: clear, technical hold, safety hold, model unavailable"],
                stubbed: ["Adjust the day's mood and answer the daily question (FR-REF-05)", "Refresh narrative or mood (FR-REF-11)"],
                issues: ["The narrative eval gate (D-13) isn't built: a model narrative shows if it passes the drift check",
                         "The day re-reads only when its inputs change (input hash); a ready day without a reading reads when this panel opens",
                         "No re-gate yet when Apple Intelligence becomes available after being off"],
                brd: ["FR-REF-01", "FR-REF-02", "FR-REF-03", "FR-REF-04", "FR-SAF-06", "SR-13", "DR-07"])
        case .letter:
            DevNotes(
                name: "Evening letter",
                does: "The day's letter, typeset from the verified day reading with links back to the quotes. No model-written prose (B-11).",
                built: ["The insight surface grows from the spine to the panel to the letter on the surface spring", "Typeset in Newsreader from the day reading",
                        "Quotes link back to their entry", "Keep (stored as a 'letter' snapshot)"],
                stubbed: ["Rewrite and Write back (FR-REF-08)", "Close the day early and the letter notification (FR-REF-09)"],
                issues: [],
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
                does: "The Settings window (⌘,).",
                built: ["Video quality: 720p default, 1080p option", "Intelligence: model, status, context size, macOS build",
                        "Export Everything (.saroexport: JSON + Media)", "Show journal in Finder", "Take the tour again"],
                stubbed: ["Name, tone, ritual and letter times (FR-SET-01)", "Comfort text size (FR-SET-02)", "Writing Tools opt-in (FR-SET-03)",
                          "Touch ID lock (FR-SET-04)", "Privacy & Data and What Saro read (FR-SET-05)"],
                issues: [],
                brd: ["FR-SET-01", "FR-SET-02", "FR-SET-03", "FR-SET-04", "FR-SET-05"])
        }
    }
}
#endif
