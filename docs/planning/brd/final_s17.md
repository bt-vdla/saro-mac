## 18. Decision log

Twenty-two decisions are open, and twelve fall due by the P0 review on Fri 20 Nov 2026. Three are due today, Mon 26 Oct 2026: strategy, database and the web retirement.

| ID | Decision | Recommendation | Options (short) | Decide by | Status |
|---|---|---|---|---|---|
| D-01 | Overall strategy for the Mac port | Ritual-first native alpha with the moat ledger underneath | Ritual-first; faithful port to parity first (about 40 weeks to an alpha); moat-first, engine before capture; hybrid React-in-WebView | Mon 26 Oct 2026 | Open |
| D-02 | Default capture mode on the Mac | Voice first, with video and writing one click away | Voice first; video first (as SARO-FJE-001 specified); text first | Fri 30 Oct 2026 | Open |
| D-03 | Day surface for the alpha | Ordered day board now; week/month/year grid in P5; canvas, continuous lens and lit ground in P7 | Ordered board; free-form canvas in the alpha (+6-7 weeks) | Fri 30 Oct 2026 | Open |
| D-04 | Local database | System SQLite with a small in-house wrapper | System SQLite; GRDB 7 (saves about 2 days); SwiftData with a CloudKit-ready schema | Mon 26 Oct 2026 | Open |
| D-05 | Privacy promise, Writing Tools and PCC | On-device only and no network entitlement in the alpha; Writing Tools off by default; request PCC this week | On-device only with PCC later as a named opt-in; PCC for letters at the alpha; never PCC | Fri 30 Oct 2026 | Open |
| D-06 | Fate of the web app and backend | Freeze at ad4c7ed and retire the backend; dump your own entries only if wanted; decide the importer in P5 | Freeze and retire; same plus your entries and a P5 importer (0.75 dev-week); keep both running | Mon 26 Oct 2026 | Open |
| D-07 | Distribution channel | TestFlight under the company with external testers; Developer ID only for Bharat's Mac | TestFlight; Developer ID download for testers; App Store Connect roles for testers | Fri 30 Oct 2026 | Open |
| D-08 | Alpha languages | English only | English only, with Hinglish covered by the safety layers; promise Hinglish AI quality | Fri 20 Nov 2026 | Open |
| D-09 | AI ladder order | Permissive JSON first; flip to guided-first if Spike B shows worse parsing or grounding | Permissive JSON first; guided first with no permissive re-ask; guided first with a permissive re-ask | Fri 20 Nov 2026 | Open |
| D-10 | Safety bar, day rule and overrides | Recall first, whole-day rule for safety holds, no override; above 5% SafetyCards, accept up to 10% for Alpha-0 | Recall first, no override; an 'I'm okay, figure of speech' override; per-entry scope | Fri 20 Nov 2026 | Open |
| D-11 | Display when Apple Intelligence is unavailable | Labelled 'In your words' quote-back under the caution rule | Quote-back under the caution rule; only 'Saro didn't write about this one' with Retry | Fri 20 Nov 2026 | Open |
| D-12 | Alpha scope against the date | Keep full scope, and cut in the fixed order only on a slip | Full scope (alpha at dev week 23); move video, still captions and the Touch ID lock to v1 now (alpha about dev week 21-22) | Fri 20 Nov 2026 | Open |
| D-13 | Model-written day narrative in the alpha | Eval-gated: ship it only if 90% of eval narratives pass grounding | Eval-gated; always template; always model prose | Fri 12 Mar 2027 | Open |
| D-14 | Default video quality | 1080p HEVC at about 2.5 Mbps with a 720p Space saver | 1080p with Space saver; 720p default | Fri 2 Apr 2027 | Open |
| D-15 | History when Apple updates the model | Fingerprint boundaries in the alpha; eval-gated re-extraction from P5 | Boundaries then re-extraction; always re-extract everything; freeze old observations | Fri 16 Apr 2027 | Open |
| D-16 | Next after the alpha: iPhone or canvas | Written rule with the iPhone as default: iPhone next if under 50% of active testers reach 3+ sessions in 7 days, or testers ask for mobile capture | Written rule; canvas regardless; Mac only for v1 | Fri 21 May 2027; thresholds by Fri 2 Apr 2027 | Open |
| D-17 | Business model and App Store timing | Free alpha, then App Store 1.0 as a free core plus Saro+ (iPhone, sync, PCC) | Free core plus Saro+; an earlier free Mac 1.0 after P5; paid upfront | Fri 21 May 2027 | Open |
| D-18 | Team size | One developer to the alpha; decide a second at the iPhone-or-canvas call | One developer (iPhone parity about dev week 56); a contract developer from the call (about dev week 47) | Fri 21 May 2027 | Open |
| D-19 | BYOK in the public app | Keep the public app offline for App Store 1.0; BYOK stays in Saro Lab | Lab only; opt-in BYOK in the public app (network entitlement for every user, privacy line rewritten, 5.1.2(i) consent); a separate public Lab app | Fri 21 May 2027 | Open |
| D-20 | Default Claude model for BYOK routes | `claude-opus-5-5` (Claude Opus 5.5, $4 / $20 per million input / output tokens), confirmed by the bench | Opus 5.5; Sonnet 5.5 ($2 / $10); Haiku 5.5 ($0.10 / $0.50, no server-side fallback); each route can still pick its own | Fri 18 Dec 2026 (Lab-1 readout) | Open |
| D-21 | When Saro Lab gets BYOK routes (Lab-2, 1.0 dev-week) | After the Fri 21 May 2027 call | After the call (later dates move about 1 week, or none with a second developer); in P2 from its 0.9 buffer; never, bench only | Fri 22 Jan 2027 (end of P1) | Open |
| D-22 | Who owns the Claude executor | Saro's own executor on URLSession, about 300 lines, built for the bench | Saro's own executor; Anthropic's ClaudeForFoundationModels package (beta); the package for the synthetic bench, then Saro's executor before any journal text is sent | Fri 20 Nov 2026 (P0 review) | Open |

D-19 rests on the privacy promise. The network entitlement is per app, so BYOK in the public app makes 'Saro has no way online' false for every user, not only those who add a key.

D-20 favours Opus 5.5 because quality of listening is the core job and the founder's volume is small. The bench can still show that Sonnet 5.5 or Haiku 5.5 matches it on a given touchpoint.

D-22 keeps every byte sent to Anthropic under Saro's own tests: the current API version, explicit refusals and exact cost, with no dependency. D-21 protects the alpha path. The bench answers 'how does Claude compare', and daily journaling through Claude can wait until the habit data is in.