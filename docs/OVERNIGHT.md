# Saro for Mac: the overnight build, 27–28 Oct 2026

The build is on `dogfood/v0` at github.com/bt-vdla/saro-mac. The app is signed with your Apple Development identity
(team `P6SP5RHNLV`). It runs entirely on this Mac: no network entitlement, no accounts, no paid calls.

**Where it stands at 09:30.** Everything is pushed: parity F1–F9, stills, reflection, onboarding, Settings, What Saro
knows with the knowledge graph, and then capture, shell and navigation, each reviewed and fixed before it went up. The
merged build passes all 525 SaroKit tests and renders all 114 snapshot states.

## Run it

```bash
make run
```

This regenerates the project with XcodeGen, builds Debug into `~/Library/Developer/Xcode/DerivedData/Saro-dogfood` and
opens Saro. `make test` runs SaroKit's tests. Build output lives in `~/Library` because the repo sits on the iCloud
Desktop, whose Finder metadata breaks `codesign`.

- **Without touching your journal:** `open ~/Library/Developer/Xcode/DerivedData/Saro-dogfood/Build/Products/Debug/Saro.app --args -SaroDemo YES`
  opens a throwaway journal of synthetic entries and runs the real on-device model over them. Demo runs skip onboarding.
- **Your real journal** opens onboarding the first time (it has no profile yet). Settings → You → Replay Onboarding, or
  ⌘K → Replay onboarding, walks it again later.

## What needs you

1. **Try it by hand.** The screen was locked all night, so nobody clicked, dragged, typed or recorded in this build. Every
   surface was checked through builds, about 500 unit tests and an off-screen snapshot harness that renders the real views
   (about 110 states, PNGs). Please try: onboarding end to end (including Find your light with the camera), a moment and a
   voice note, dragging, resizing and throwing cards, ⌘K, What Saro knows and Settings; and the time
   lens, the recorder's live captions, Space for a voice note, Trash and the Touch ID lock.
2. **A clinician review of the safety phrase changes.** Tonight's safety testing added 49 missed risk phrasings and spared
   7 idioms in the phrase gate, plus Hinglish and Devanagari lines. Every changed line is marked
   `DRAFT: clinician review (SR-32)` in `SaroKit/Sources/SaroKit/Safety/PhraseGate.swift`; the summary is in
   `docs/safety-phrase-changes-for-review.md`.
3. **Decisions.** Your open product decisions are in the app (the sidebar's Decisions row, or ⌘K → Decisions; Export
   Decisions for Claude… hands your answers back). Tonight added these:
   - **Forget everything** removes what Saro knows but keeps readings and letters, as the web does; the BRD says every
     derived row. Which do you want?
   - **Stacks can't be resized.** The web resizes video stacks; here sizes are stored per card, so a stack's size needs a
     rule for where it lives and what Unstack does with it.
   - **Pause keeps one part.** A plain pause now pauses and resumes the same file; only Pause & reflect starts a new
     part, as on the web. Yesterday's build split a part at every pause. The capture spec flagged this; confirm.
   - **Notifications never quote you.** The web's reminder says what you said; Saro's say nothing personal (content-free,
     by plan). Confirm.
   - **The palette follows the clock** (night from 20:00) even when macOS is in light mode (B-18). Settings → Appearance
     can pin it.
   - Dev notes moved from ⌥⌘D to **⇧⌘D**.
4. **Permissions** on first use: camera and microphone (the first moment or voice note, or Find your light), speech
   recognition (asked at the first recording), notifications (First week's reminder ask).

## What's new since yesterday evening

Everything below follows the web overnight build (`overnight/mvp-hardening`), copied for content, copy and behaviour,
then made native: Evergreen tokens, springs, keyboard-first, VoiceOver labels, Reduce Motion and Reduce Transparency.

**The canvas (parity F1–F9)**
- **F1** A voice note opens in place: the orb glides into a player with a scrubbable track and the timed transcript.
- **F2** Day replay: History replays the day, cards landing in capture order, the ground following the hour (⌘K → Replay).
- **F3** The uneven drag grid draws out around a held card; edges snap to it and to other cards.
- **F4** Motion blur on thrown cards, the fanned stack and the open/close flight.
- **F5** The moment recorder and the voice pill grow out of their bar buttons and close back into them.
- **F6** A deleted card flies into the Undo toast, and Undo flies it back.
- **F7** ⌘K on a result opens its actions (Open, Go to day, Replay, Copy text, Move to Trash).
- **F8** A slow day shows shimmer blocks; a day that can't be read says so, with Try again.
- **F9** Resize handles on cards, with the web's limits, snapping and a size readout; sizes survive Stack and Unstack.

**Stills that Saro understands.** On import Saro describes a photo on this Mac (the on-device model with the image,
or Apple's Vision as a fallback), gates the description like any text, and shows it under the opened photo as
"Saro sees", with tags, provenance and Describe again. Type over it and it becomes your caption, which always wins.
Stills feed the day's reading and letter; only your own words are ever quoted. Palettes are gone from stills.

**What Saro noticed and the evening letter (reflection).** The insight spine, the panel's narrative, mood (adjustable),
the day's question with your answer, commitments with yesterday's carry-over, first-week notes, and the letter's
header, write-back, keep and rewrite. A held day shows the SafetyCard alone.

**Onboarding.** The welcome door, About you (five questions, with what Saro picks up marked as you type), the first
prompt made from your answers, First week (your ritual time and reminders), and Find your light (a camera and mic
check that records nothing), handing off to your first moment, voice note or page.

**Settings.** Eight sections as on the web: You, How Saro talks (tone with live previews), Rhythm, Appearance,
Comfort (text size, Reduce Motion and Transparency, Writing Tools, sounds), What Saro knows, Intelligence, and Your
data (export, import, the Book, erase). "Say it" changes settings from a sentence.

**What Saro knows and the knowledge graph (memory).** Saro learns people, places, themes, feelings and intentions from
cleared entries, each with a verbatim quote. You see them as a list (edit, delete, add, Forget everything, pause) or
as a force-directed graph with a side panel: mentions over time, related nodes, where each comes up. Nothing from a
held day is ever learned or shown. ⌘K finds memories too.

**Capture.** The recording ritual: today's prompt under Saro's orb, live captions as you speak (on-device
SpeechAnalyzer; live text is never stored), pause and resume within a part, Pause & reflect with Saro's follow-up question
(gated, on this Mac), a Finish dialog with a two-step discard, and the last frame developing and flying into its card.
The voice pill records as it opens, shows a live caption line, and lets you listen back before you keep it. Music links
(Spotify, Apple Music, YouTube, SoundCloud, JioSaavn) become song cards. Drop or paste anything: audio becomes a voice
note, video a moment, a photo a still, text a page (File → Import Media… ⇧⌘I). Writing: edit on the card, a reading page
with its own title and "edited" time, and Reflect further. Edit Details (⌘I) for every kind. A stack's set view shows
each turn's question and plays them all.

**Shell.** A glass toast stack with plain failure copy and Retry. A save dot on your avatar (pending, saved, or Not saved
with Retry), and the account menu (Settings…, Profile…, Lock). Trash as a popover and a pane with days left, Restore,
Delete for good, a two-step Empty Trash, and the 30-day purge. A daily database snapshot (seven kept). Card and canvas
menus (Edit Details, Duplicate To, Export a Copy, Show in Finder) and an Entry menu. Export Day as Image. The Touch ID
lock and Hide from screen sharing. A recovery screen when the journal won't open. About Saro, Keyboard Shortcuts (⌘/),
Acknowledgements. In dogfood builds: the Developer menu, the Light Lab and Simulate Apple Intelligence Unavailable.

**Navigation.** The time lens (⌥⌘T, or pinch out past the day): week, month and year tiles with each day's mood, ⌘1–⌘4
for the levels, and a week replay. Go to a date (⌥⌘G). The web's search engine in ⌘K (stems, prefixes, typos, weights).
Neighbouring days read ahead, the web's placement for new cards, the slide to a new day at midnight, keyboard selection
on the canvas (arrows, Tab, ⌥-arrows nudge, ⇧⌥-arrows resize), drag-pan with a glide, and a bar that re-lays itself in
one or two rows.

## How it was checked

Every feature was built by one agent, then checked by a second that hadn't built it (against the web source, the BRD and
the build), repaired when it objected, and checked again. Then:

- **Integration review.** With the five packages merged, five independent reviewers read the whole build through one lens
  each: safety, data, concurrency and robustness, UI parity, and journeys that cross packages. They raised 56 findings; each
  was put to one or two skeptics told to refute it, which confirmed 46 (5 blocking, 16 major, 25 minor). Eight fixers
  fixed them by area, and five re-checkers confirmed 54 fixes on the merged tree and sent 19 leftovers to a second round
  of fixes. The blocking ones were all safety: a day still in progress could show Saro's text while held, ⌘K showed AI
  titles on held days, commitments were never gated and appeared in What Saro knows, memory learned from Saro's own photo
  descriptions, and Import could bring back what a hold had deleted.
- **Final check.** With capture, shell and navigation merged on top, six more independent checkers (one per package, plus
  keyboard and focus, safety, and every snapshot) raised 53 findings; skeptics confirmed 48 (5 blocking, 17 major, 26
  minor) and six fixers fixed them before the push. The blocking ones were again safety: captions, summaries and titles
  typed in Edit Details or on failed recordings weren't gated, the ⌃⌘J panel judged a hold by the window's day instead of
  today's, and a hold left follow-up questions stored for its entry.
- **Bugs I found while merging,** fixed with tests: the model sometimes reports a context size of 0 while busy, which
  marked short entries "too long" for good; stubbed test models still waited on the real model service, stalling the
  test run for a minute; live-model tests now take turns; the snapshot harness now works while the screen is locked;
  migrations are pinned to the order dogfood journals ran them, and a journal newer than the app is refused.
- **Snapshots.** An off-screen harness renders the real views to PNG (114 states across every surface, light and
  150% text). I looked at them after every merge. The Metal ground doesn't render there, so day surfaces sit on dark.
- **Tests.** 525 SaroKit tests pass on the merged build, in under two minutes,
  including the live on-device model, Speech and Vision tests (synthetic text, audio and images only). The app target has no
  test target, so app-only logic (views, the queue, menus) is covered by the build, the snapshots and the reviewers.

## Not built, or only partly

- **Out of scope tonight, per the plan:** Claude BYOK (next build), PCC, sync, iPhone, TestFlight.
- **Stacks can't be resized** (see Decisions).
- **"Add to canvas"** for a commitment, the rhythm suggestion surfacing on the canvas, and a photo avatar (initials only).
- **First week's sky** is drawn in a SwiftUI Canvas, not the web's WebGL shader (same timings; the shader tests aren't ported).
- **The knowledge graph** has no "recurring nouns" kind; themes cover them.
- **What Saro knows** doesn't yet feed Saro's prompts: the labels are ready, but nothing reads them, so the app doesn't
  claim it.

## Known issues

- **Nothing has been clicked, typed, dragged or recorded by hand** (the screen was locked overnight). Space (tap opens the
  voice pill, hold pans), the recorder and camera, Find your light, live captions, Touch ID, drag-and-drop and Import
  Media need a first real try.
- **Snapshots don't show the Metal ground**, so I judged the lit ground from earlier renders, not tonight's.
- **Left as is, knowingly:** a recording you give a typed title shows none of Saro's text in ⌘K or the time lens (it fails
  closed); cards can't be dragged out as files (the moment detail's Export can); a stack opened with Return still fans out
  with its animation; and "Reflecting…" at Pause & reflect waits for an entry being read to finish.
- **Three idle demo processes** from a snapshot run (`Saro-pkg-memory`) were still running; I wasn't allowed to stop them.
  They use throwaway journals; quit them from Activity Monitor or ignore them.

## The next build: Claude BYOK in Saro Lab (BRD §12)

A separate **Saro Lab** scheme and bundle ID. Only Saro Lab carries `com.apple.security.network.client`, and only to
`api.anthropic.com`: Saro's own `URLSession` executor for the Messages API (D-22), the key in the Keychain (this device
only), a consent screen per provider, and per-touchpoint routes in Settings → Intelligence. It plugs into the `SaroAI`
ladder as a primary rung, behind the same SafetyGate, drift and output gates, with `ai_run` rows recording provider,
model and cost. First step: the Lab-1 model bench, the same synthetic cases on Apple and Claude side by side.

## Commits

498 commits on `dogfood/v0`. Last night's pushes, in order:

- `3e978f8…6f8908d` foundation: profile, prefs, reminders, deep links, schema v3
- `6f8908d…abfe86b` parity F4–F8, the snapshot harness fix, a recorder fix and ⌘K Copy text
- `abfe86b…22f8aec` F9 resize handles, with its repair and a Stack/Unstack size fix
- `22f8aec…d241158` the five packages, integrated, reviewed and fixed (one merge commit whose tree is the tested one)
- `d241158…0de1f84` this report and the clinician summary
- `0de1f84…e7a56b7` capture, shell and navigation, merged, checked and fixed

`git log --first-parent dogfood/v0` reads as the story; `git log dogfood/v0` has every small commit.
