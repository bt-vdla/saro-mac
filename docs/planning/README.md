# Saro for Mac — planning inputs

This folder holds everything the native build is based on. The working BRD is the Docs artifact
"Saro for Mac BRD": https://claude.ai/artifact/QDHLkdLrDbrBwhbZrkriWV (copies of its sections are in `brd/`).

| File | What it is |
| --- | --- |
| `brd/final_s1.md` … `final_s17.md` | BRD sections 2-18 as written on 26 Oct 2026 (s14 is the canvas section, `final_s14_canvas.md`) |
| `revised.json` | The full revised plan: architecture, AI tiers, 27 AI touchpoints, 119-row feature plan, phases, data model, safety design |
| `probe_results.md` | Live measurements of the on-device model on Bharat's M5 (25 Oct 2026) |
| `probes/` | The Swift probe sources and outputs (Foundation Models, guardrail ladder, classifier, custom `LanguageModel` for Claude) |

## Decisions Bharat made on 27 Oct 2026 (these override the BRD where they differ)

| ID | Decision | Choice |
| --- | --- | --- |
| D-02 | Default capture mode | **Video first.** Voice and writing one click away; every entry type is first-class |
| D-03 | Day surface | **Free canvas from day one**, with Spatial's mechanics (`brd/final_s14_canvas.md`) |
| D-05 | AI routes for this build | **On-device only** (Apple `SystemLanguageModel`). Anthropic BYOK is the very next build |
| D-14 | Video quality | **720p by default**, with a 1080p option in Settings |
| — | Repo and git | Build in `bt-vdla/saro-mac`. Commit locally in small Conventional Commits; **never push**. Bharat reviews in the morning |
| — | Dev mode | The app ships an **internal tour** and **in-app dev notes** on every screen. Bharat makes decisions in the app; they are stored and **exported from the app as a file** he hands back to Claude |
| — | Signing | Bharat's Apple Development identity (team `W6F77BC8KN`); local builds only, no TestFlight yet |

Defaults taken where Bharat didn't decide (each is a Dev Notes decision card in the app, so he can change it):
macOS 27+, Apple silicon only; system SQLite with a small wrapper (no third-party dependencies); no account; Saro's
Evergreen palette with Newsreader / Geist / Geist Mono; ⌃⌘J capture hotkey; safety gate on (phrase list incl.
Hinglish + Devanagari, then the graded on-device classifier); English only; Writing Tools off in Saro's editors.

## v0 scope: usable from the first morning

1. **Video moments** (camera picker incl. Continuity Camera, pause/resume, turns as separate files written to disk while
   recording, crash-safe), **voice notes**, **writing**, **stills** (drop/paste), all on the canvas.
2. **Free canvas** per local day: pan, pinch/⌘-scroll zoom, drag, marquee select, contextual toolbar (Stack, Grid,
   Delete), stacks that fan out in place, cards that morph open into detail views (player + timed transcript).
3. **On-device transcription** of every saved recording (Speech `SpeechAnalyzer`/`SpeechTranscriber`), tap a sentence to seek.
4. **On-device AI**: per-entry title/summary/mood/quotes-by-index on the guardrail ladder; "What Saro noticed" day
   reading; a typeset evening letter; all behind the safety gate with the four-state model.
5. **Ledger**: append-only AI layer with provenance; trash with undo; Export everything.
6. **Capture from anywhere**: menu bar extra + ⌃⌘J floating capture panel.
7. **Dev mode**: guided tour, per-screen dev notes, the decision register (D-01…D-22 plus new ones), and
   "Export decisions for Claude" → `saro-decisions.json` + `saro-decisions.md`.

Out of v0 (next builds): Claude BYOK (next), time lens, collections, onboarding polish, PCC, sync, iPhone.
