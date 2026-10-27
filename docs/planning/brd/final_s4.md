## 5. Scope by release

The alpha carries capture, reading, safety, memory and export; the canvas, iPhone and sync wait for the habit answer.

### 5.1 Builds and releases

Six builds take Saro from the founder's Mac to the App Store, and before 1.0 only Saro Lab can go online.

| Build | Date | Who uses it | What it adds | AI |
|---|---|---|---|---|
| Dogfood 1 (Saro Dev) | Fri 18 Dec 2026 | Bharat | Capture, file transcripts, writing, the day board, Export and Import | No model AI |
| Dogfood 2 | Fri 8 Jan 2027 | Bharat | The heuristic reading and capture from anywhere | Heuristic twin under the model-unavailable rule |
| Alpha-0 (TestFlight) | Fri 2 Apr 2027 | Bharat plus 4 external testers | The voice-and-writing ritual, the full safety gate, What Saro noticed, the evening letter | On-device only |
| Alpha (TestFlight) | Fri 16 Apr 2027 (range to Fri 14 May) | 15-30 testers | Video moments and still captions | On-device only |
| Saro Lab (Developer ID) | Open question | Bharat only | Settings > Models, the Claude provider and the model bench | On-device plus Claude on his key |
| App Store 1.0 | About Fri 24 Sep 2027 (canvas first), or with iPhone parity about Fri 3 Dec 2027 | Public | Parity with the surviving web features, and StoreKit | On-device; PCC opt-in if entitled; BYOK per D-19 |

The dogfood builds have no classifier, so they follow the model-unavailable rule. A phrase or caution-lexicon hit suppresses the quote-back and the checkpoint question. Until the SafetyCard lands in P2, a phrase hit hides the reading and shows the menu-bar crisis line.

If the alpha slips, scope is cut in a fixed order: video, then still captions, then the Touch ID lock.

### 5.2 Scope by area

Each row condenses one area of the 119-row feature plan, and the appendix holds every row. Must ships in the alpha, Should in App Store 1.0, Could later, and Won't is cut on purpose. Could items may land in P7-P8, but 1.0 does not wait for them.

| Area | Must (alpha) | Should (App Store 1.0) | Could (later) | Won't (cut) |
|---|---|---|---|---|
| Capture (CAP) | Voice notes with the voice pill (default mode); written reflections; video moments and the recording ritual (first cut on slip); multi-part sessions; live captions; timed file transcripts; stills by paste, drop or picker; still captions on default guardrails only (second cut); capture from any app (Ctrl-Cmd-J, menu bar, floating pill); in-app paste, drop and media import; backdating; today's prompt; mic check and framing tip; music URLs saved as links | Music cards with title and artwork (needs a network decision); full Find your light coaching | Last frame flies into its card | Upload queue, save counter, 5 MB and 10 MB caps |
| Day surface and time (DAY) | Ordered day board with a sidebar of days and a static time-of-day tint; opened entry views; edit title, caption and summary; day navigation and date picker; context menus, keyboard selection, delete with undo; native toolbar | 7-day mood ribbon; week, month and year time lens (P5); typed-date jumps; duplicate to another day | Free-form canvas (pan, zoom, drag, resize, snap guides, saved positions); lit ground and night palette; morph flights; day and week replay; continuous lens pinch; day export as an image | Day slide (plan 006); motion blur |
| Reflection (REF) | What Saro noticed; last-inferred line; day narrative behind a 90% eval gate, else a template (D-13); mood with basis and correction; daily question; typeset evening letter with Keep, Rewrite and Write back; Close the day; content-free letter notification; reflect deeper and reflect further; first pattern after 3 moments; day-6 weekly note; What Saro read log | Refresh narrative, mood or question; commitments with carry-over and let-go | Streamed insights with per-field checks; glass morph | None |
| Safety (SAF) | One SafetyGate on every path (transcript quality, phrase gate with expanded Hinglish and Devanagari, graded classifier, output gate); four states with precedence safety hold > model unavailable > technical hold > clear, plus awaiting a check; whole-day rule for safety holds; SafetyCard with regional crisis lines; Help > If you're struggling; 'Saro got this wrong' report (P3); canary and conservative mode | None | None | User override of a hold; SensitiveContentAnalysis as a safety signal; permissive mode for still captions |
| Memory and self-model (MEM) | Append-only ledger with provenance on every AI run; What Saro knows (Why, delete, pause, forget all) with a filter | Edit and add memories; What's changed (engine v0, P5) | None | Supermemory; D3 mind maps |
| Search and commands (SRC) | Sidebar search; menu commands and shortcuts from one CommandRegistry | Cmd-K palette on FTS5; typo-tolerant search | Semantic 'ask your journal' | None |
| Onboarding (ONB) | Welcome with the exact privacy copy and no account; About you with 'Saro heard'; a first prompt of their own; first-week setup; first reflection; Apple Intelligence and speech readiness card | None | Live inline highlighting; Seven Sunrises animation | Email, password, OAuth and magic-link sign-in |
| Settings (SET) | Settings window; name; tone (4 options); rhythm (reminder and letter times, weekdays); comfort (text size, captions always on); Writing Tools opt-in; privacy and data (storage meter, export, erase) | Focus areas; rhythm suggestion; Follow the day appearance | Tone preview; 'Say it, and it's set'; Book of the year export | Custom instructions; sounds and haptics |
| Export, backup and sync (EXP) | Export everything; Import and Restore from snapshot; 7 daily snapshots | Back up to a chosen folder (P5); iCloud sync and the iPhone companion (P6; ships as 1.1 in the canvas-first order) | Import from the web app, only if Bharat wants his entries | Server storage |
| Shell and account | Touch ID lock (third cut on slip); ritual reminders with deep links; trash with undo; local day frozen at capture; Alpha report; TestFlight expiry nudge; acknowledgements and font licences | Screen-share hiding, after testing; 'Record a voice note' Shortcut; StoreKit for Saro+ | Share extension, Services menu, widgets, Control Center control | Accounts, profile extras, demo account (DEBUG only), analytics SDKs |
| AI models (BYOK) | Apple on-device as the only AI; heuristic twin as the floor; no network entitlement | PCC opt-in for weekly letters, if entitled; BYOK in the public app only if D-19 approves it | More BYOK providers: OpenAI-compatible endpoints, Google Gemini, local MLX or Core AI models through the LanguageModel protocol | BYOK or any network call in the TestFlight alpha build |

### 5.3 AI models and BYOK

BYOK is an optional third AI tier that ships first in Saro Lab, and the public app's answer is D-19 on Fri 21 May 2027.

| Capability | TestFlight alpha | Saro Lab (founder) | App Store 1.0 |
|---|---|---|---|
| Apple on-device model | Default and only AI | Default for every touchpoint | Default for every touchpoint |
| Heuristic twin ('In your words') | No-AI floor | No-AI floor | No-AI floor |
| Apple PCC | Off | When entitled | Named opt-in for weekly letters, if entitled |
| Settings > Models: one route per touchpoint | Absent | Present | Per D-19 |
| Anthropic Claude: Opus 5.5 by default; Sonnet 5.5 and Haiku 5.5 per route | Absent | First provider | Per D-19 |
| API keys in the macOS Keychain, this device only | Absent | Present | Per D-19 |
| Per-provider consent screen (App Store guideline 5.1.2(i)) | Absent | Present | Required if BYOK ships |
| Model bench: on-device and Claude on the same eval cases | Absent | The first use | Open question |
| com.apple.security.network.client | Absent, asserted by CI | Present | Per D-19 |

Every BYOK route follows the same rules:

- Default routes never leave the Mac, and BYOK stays off until the user adds a key and accepts the consent screen.
- Only entries the on-device gate has cleared are sent. Safety-held and awaiting-a-check entries, and safety-held days, never are.
- BYOK therefore runs only where Apple Intelligence is on and Saro is not in conservative mode.
- Each output passes the same output gate and grounding check as on-device output.
- Each call is logged content-free in What Saro read as 'Sent to Anthropic', with its tokens and cost, and a daily spend cap stops further calls.

One Claude Opus 5.5 extraction call costs about $0.04, assuming 3,000 input and 1,500 output tokens including thinking. The bench measures the real figure. The guard allows at most 4 model calls per touchpoint per entry, so the worst case is about $0.17.

Open question: which phase builds Saro Lab and the model bench, and at what dev-week cost?

Open question: what default daily spend cap does Bharat want?

Open question: can Saro Lab, signed with Developer ID, open the TestFlight build's journal, or does data move by Export and Import?