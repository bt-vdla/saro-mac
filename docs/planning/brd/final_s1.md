## 2. Executive summary

Build Saro for Mac as a native macOS 27 app on Apple's on-device model, and ship Alpha-0 to five people on Fri 2 Apr 2027.

### 2.1 Recommendation

Saro becomes a native Swift 6.4 app for Apple silicon Macs, built in SwiftUI with @Observable and AppKit where needed. Every entry and every AI result lands in a local, append-only SQLite ledger that records where it came from. That ledger is the first layer of the longitudinal self-model, which is Saro's moat.

The alpha is ritual-first, with voice as the default and video and writing one click away. Ctrl-Cmd-J, the menu bar and a floating voice pill capture from any app. An ordered day board stands in for the free-form canvas until the habit is proven.

Saro listens without inventing. The model picks numbered phrases from the user's own words, so every quote is verbatim, and code assembles the day's reading and letter. One on-device safety gate runs before every AI call, and one flagged entry still holds the whole day.

Apple's on-device model is the default route and the only AI in the TestFlight alpha. Private Cloud Compute (PCC) and bring-your-own-key (BYOK) models are optional routes, set per AI touchpoint in Settings > Models. BYOK starts with Anthropic's Claude in a separate founder build, Saro Lab, so the alpha keeps its promise that Saro has no way online.

The alpha answers one question: will people keep a journaling habit on a Mac? The test is 3 or more sessions in a tester's first 7 days, where a session is a local day with a saved entry. The answer picks the next track, iPhone companion or canvas, on Fri 21 May 2027.

### 2.2 Key facts

Saro needs no server, costs nothing per user to run, and reaches the alpha in 23 dev-weeks.

| Fact | Value |
|---|---|
| Platform | macOS 27 minimum, Apple silicon (arm64) only. Swift 6.4, SwiftUI with @Observable, AppKit where needed |
| Calendar | Dev week 1 starts Mon 26 Oct 2026. The weeks of Mon 9 Nov (Diwali) and Mon 28 Dec 2026 are off |
| Dogfood build | Fri 18 Dec 2026 (dev week 7), on Bharat's M5 |
| Alpha-0 | Fri 2 Apr 2027 (dev week 21): voice and writing; Bharat plus 4 external TestFlight testers |
| Alpha | Fri 16 Apr 2027 (dev week 23): adds video; 15-30 testers. Range: dev weeks 21-27, Fri 2 Apr - Fri 14 May 2027 |
| Next calls | Engine v0 on alpha data by Fri 7 May 2027; iPhone-or-canvas call on Fri 21 May 2027 |
| Parity | Mac parity about Fri 24 Sep 2027 if the canvas goes first; parity with the iPhone about Fri 3 Dec 2027 |
| AI tier 1: on-device (default) | Apple's SystemLanguageModel. Measured on the M5: AFM 3 Core Advanced, 8,192-token context. The only AI in the alpha build |
| AI tier 2: PCC (opt-in) | Apple Private Cloud Compute, 32,768-token context, for weekly letters once Apple grants the entitlement. Fails today with error 1046 |
| AI tier 3: BYOK (opt-in) | The user's own API key. Anthropic Claude first: Claude Opus 5.5 by default ($4 / $20 per million input / output tokens). Saro Lab only until D-19 |
| No-AI floor | The heuristic twin, a Swift port of the web demo, labelled 'In your words' |
| Server cost | $0 a month: no account and no Saro server. BYOK usage is billed by the provider to the key's owner, under a daily spend cap |
| Team | One full-time Swift/AppKit developer with AI coding help; Bharat 3-6 hours a week |

### 2.3 Decisions needed this week

Five calls are due this week, and together they settle decisions D-01 to D-07.

| # | Decision | Recommendation | Decide by | IDs |
|---|---|---|---|---|
| 1 | Strategy and alpha shape | Ritual-first native alpha with the ledger underneath; voice-first capture; ordered day board now, canvas in P7 | Mon 26 Oct 2026 (D-01); Fri 30 Oct 2026 (D-02, D-03) | D-01, D-02, D-03 |
| 2 | Web app and backend | Freeze the web app at ad4c7ed as the offline reference. After the count query, pause and delete Supabase, revoke the OpenAI key and purge Logfire | Mon 26 Oct 2026 | D-06 |
| 3 | Local database | System SQLite 3.54.0 with FTS5 and a small in-house wrapper. GRDB only if the wrapper takes more than 3 days | Mon 26 Oct 2026 | D-04 |
| 4 | Privacy promise and AI routes | On-device only in the alpha build, with no network entitlement. Writing Tools off with an opt-in. Request PCC now. BYOK only in Saro Lab; the public app's BYOK call is D-19 by Fri 21 May 2027 | Fri 30 Oct 2026 | D-05 |
| 5 | Distribution | TestFlight under the company, with external testers after Beta App Review. Start D-U-N-S now so enrollment lands before Mon 15 Mar 2027 | Fri 30 Oct 2026 | D-07 |

The same week, Bharat runs the Supabase data check and files the PCC access request. He also borrows an M1 or M2 Mac and records 10 voice notes for Spike A.