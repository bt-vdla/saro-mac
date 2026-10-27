## 17. Risks, assumptions, dependencies and constraints

Seven of 30 risks are high, and safety recall is the one that could cause real harm. The three BYOK risks are medium, because Saro Lab stays founder-only and the gate runs before every send. Section 12.19 adds five BYOK build risks, R-31 to R-35.

### 17.1 Risks

| ID | Risk | Severity | Mitigation |
|---|---|---|---|
| R-01 | Safety recall without a moderation model: the classifier's 4 of 4 comes from 13 synthetic cases, and a mis-transcribed crisis could slip past both layers | High | Low confidence holds the entry, and layer 0 never clears text; expanded clinician-reviewed Hinglish list with Devanagari; one gate failing closed; 100% recall on 100+ cases on both Macs, re-run on every change; canary; held days never feed AI |
| R-02 | Safety false positives: idioms came back ACTIVE although the prompt defined them as NONE, and the whole-day rule blanks a venting day | High | Few-shot idioms measured on 100+ venting cases and Bharat's journal; a pre-decided choice above 5% (D-10); technical holds show no crisis link and don't hold the day; never changed silently |
| R-03 | The Mac is the wrong capture context, and testers may not reach 3 sessions in 7 days | High | Voice default; Ctrl-Cmd-J, menu bar and floating pill; content-free reminders; habit metric from Fri 16 Apr 2027; written rule on Fri 21 May 2027; multiplatform codebase from day 1 |
| R-04 | On-device readings feel thin, echo the user or drift, so users don't feel heard | High | Candidate-index quotes, map-reduce and the drift check; model narrative only behind a 90% eval gate; a typeset letter and one good question; PCC requested; the Lab-1 bench measures Claude on the same cases |
| R-05 | A lost recording or wrong quote timing: MovieFileOutput with the Speech output, the HEVC bitrate and pause mapping are unverified on macOS | High | Spike A in week 1 with kill -9 and pause tests, AVAssetWriter as fallback; rows before the first frame; transcript from the saved file; nightly kill harness; P1 exit of zero lost audio |
| R-06 | One developer is a single point of failure, and AI and capture are the likeliest overruns | High | Sequential spikes; buffers in P1 (0.5 after Lab-1) and P2 (0.9); a published alpha range of dev weeks 21-27 (Fri 2 Apr – Fri 14 May 2027); fixed cut order; AI slip rule; weekly demo; second developer from the May 2027 decision |
| R-07 | A macOS update changes the model on a tester's Mac before evals run, and there is no remote switch | High | Canary on every new os_build with conservative mode; evaluated os_build list in each build; a TestFlight build at least every 60 days; evals on every point release and beta |
| R-08 | Apple reads the permissive-first ladder as outside the Foundation Models acceptable-use requirements, or the mode misbehaves | Medium | Documented purpose, on the user's own words, gate-cleared only; never loosens; internal assessment reused in review notes; Spike B flip rule; stills never permissive |
| R-09 | Quality and context on core3 Macs are unmeasured, and 8 GB M3/M4 Macs may get core3 | Medium | M1/M2 by Fri 30 Oct 2026, measured in week 2; runtime budgets planned for 4096; pass rates per variant; fewer observation kinds on core3 if it is worse |
| R-10 | Apple changes the model or guardrails at WWDC 2027 (dev week 31) or in September, so prompts regress and people seem to change | Medium | os_build, variant and fingerprint on every run; a new lineage on a changed fingerprint; eval passes on the beta and release; eval-gated re-extraction from P5 |
| R-11 | Lose the Mac, lose the journal: there is no sync until P6 | Medium | Export, Import and Restore from the first dogfood build; 7 daily snapshots and Time Machine; backup to a chosen folder in P5; sync-ready schema; testers told app containers aren't in iCloud |
| R-12 | Speech accuracy for Indian English and code-switched speech is unknown, and transcripts are the quote source | Medium | Measured on Bharat's 10 recordings in week 1; English-only copy; technical hold with Retry; learned names as contextualStrings from P5 |
| R-13 | Technical holds swallow most entries from Hinglish speakers | Medium | Holds don't hold the day or show a crisis link; the language check stays only if useful, never for typed text; ship gate at 10% of spoken entries and 15% of days |
| R-14 | New users see an empty moat, because 'What's changed' needs weeks of entries | Medium | About you as a t0 baseline; What Saro knows from the first entry; first pattern after 3 entries and a day-6 note; an empty state that counts entries needed; 3-week tester commitment |
| R-15 | Without the canvas and lit ground, the alpha reads as another tidy journal app | Medium | Design-system port in P1; card views reused by the canvas; the canvas promised in writing for P7; measure whether testers miss it |
| R-16 | Distribution delays: D-U-N-S, Beta App Review of a mental-health-adjacent app, acceptable-use scrutiny | Medium | Enrollment from week 1; Beta App Review build on Mon 15 Mar 2027, the first day of P3 and 18 days before Alpha-0, with a 0.35-week buffer; review notes from the assessment; Developer ID only for Bharat's Mac |
| R-17 | Testers don't send the Alpha report, so the decision rests on thin, self-selected data | Medium | Sending is part of the 3-week commitment; one-click copy; TestFlight cross-check; a minimum active-tester count below which the decision waits |
| R-18 | Apple treats iCloud sync of mood labels and safety verdicts as health data under Guideline 5.1.3(ii) | Medium | App Review inquiry by Fri 7 May 2027; mood kept out of HealthKit and medical wording; P6 contingency of non-health text only, or a folder or local transfer |
| R-19 | Speech asset downloads might need `network.client`, weakening 'no way online' | Medium | Verified in Spike A; if needed, added only for that, with a re-audited network log and reworded promise |
| R-20 | Saro Lab's network entitlement or a BYOK code path reaches a tester build, making 'no way online' false | Medium | Separate scheme, bundle id and container; CI asserts each scheme's entitlements; P3 network-log audit; Saro Lab never distributed |
| R-21 | Journal text reaches Anthropic wrongly: a misrouted held entry, a leaked key, or retention terms nobody checked | Medium | Gate before every send (SR-36); consent per provider; keys in the Keychain, this device only; content-free 'Sent to Anthropic' log; retention terms checked before Lab-2 |
| R-22 | Mixing executors makes the self-model show a change that is really a model switch | Medium | Executor and model in every lineage; series compared only within one lineage; the bench runs before any route change |
| R-23 | Background work runs only while Saro runs, and background generation may be rate-limited | Low | Processing at save in the foreground; menu bar extra and optional login item; deferral on rateLimited; quiet queue state |
| R-24 | The PCC entitlement is slow or denied, or its quota and reliability bite | Low | Nothing depends on PCC; requested in week 1; a 25 s deadline with fallback when used |
| R-25 | TestFlight builds expire after 90 days, and a returning tester finds an app that won't open | Low | A new build at least every 60 days; an expiry date and Export nudge from 14 days out; the container survives |
| R-26 | Bugs in the in-house SQLite wrapper | Low | One write path; tests for transactions, triggers, migrations and the forget cascade; GRDB with Bharat's approval if the wrapper passes 3 days |
| R-27 | Screen-share hiding may fail against ScreenCaptureKit apps; hotkey collisions; NSPanel focus quirks; video disk growth on 256 GB Macs | Low | No screen-share promise until tested on 27; a changeable hotkey; voice first, 2.5 Mbps HEVC, Space saver and a storage meter |
| R-28 | BYOK spend runs away, since Claude Opus 5.5 thinks on every call | Low | Cost shown per call; a daily cap that falls back to on-device; at most 4 model calls per touchpoint per entry; effort set explicitly (default medium) |
| R-29 | Anthropic API drift: the API version, the fallback beta header or a model retirement changes behaviour | Low | One pinned `anthropic-version` (2026-10-21); request-body tests; the bench re-runs on any change; on-device stays the default route |
| R-30 | App Review rejects BYOK in the public app under Guideline 5.1.2(i) | Low | Applies only if D-19 says yes; consent names the provider and the data; Lab-only stays the default |

### 17.2 Assumptions

| Assumption | Basis | If wrong |
|---|---|---|
| One experienced Swift and AppKit developer works full time with AI coding help | Estimate basis | Every date moves, and the cut order applies |
| Bharat gives 3-6 hours a week to decisions, labels, dogfooding and recruiting | Estimate basis | Decisions and labels slip, and the P0 review moves |
| Macs that get core3 have a 4096 context until measured | SDK fallback; only the M5 is measured | Nothing breaks, because budgets are read at runtime; quality is tracked per variant |
| AVCaptureMovieFileOutput honours about 2.5 Mbps HEVC on macOS | Spike A | AVAssetWriter, about +1 week inside the range |
| Speech assets download without `network.client` | Spike A | The entitlement is added only for that, and privacy line 1 is rewritten |
| The Carbon hotkey works in the sandbox without Accessibility permission | Spike A | Open question: no fallback is chosen yet |
| Mean transcriptionConfidence separates poor audio | Spike A on 10 recordings | Layer 0 is retuned in P2 |
| The permissive JSON rung parses on 90%+ of entries and grounds no worse than the guided rung | Probe run 3; Spike B | The order flips to guided-first, with no schedule change |
| Few-shot tuning brings SafetyCards near 5% on venting text | Probe: 11 of 13 correct | The founder's pre-decided choice (D-10), with no schedule change |
| Greedy outputs repeat exactly on one os_build | Spike B | The fingerprint can't mark lineage; open question |
| Testers have M1 or later Macs on macOS 27 with Apple Intelligence on | Recruiting | A smaller cohort, and the decision waits for the minimum count |
| Anthropic's Messages API (version 2026-10-21) behaves as documented | Published docs; not measured | Lab-1 finds out first, with no alpha impact |

### 17.3 Dependencies

| Dependency | Owner | Needed by | If late |
|---|---|---|---|
| Apple Developer Program under the company legal entity, with D-U-N-S | Bharat | Started by Fri 30 Oct 2026; in place before Mon 15 Mar 2027 | Alpha-0 slips; Developer ID is not a tester fallback |
| App Store Connect record 'Saro' with a fallback name, and Small Business Program enrollment | Bharat | Fri 30 Oct 2026 | Listing and pricing work waits |
| PCC managed entitlement (key read from the provisioning profile once granted) | Apple, requested by Bharat | Requested by Fri 30 Oct 2026; not on the critical path | Templates and on-device cover every feature |
| Paid external clinician, ideally Hindi-speaking | Bharat | Booked by Fri 20 Nov 2026; sign-off by Fri 12 Mar 2027 | No non-founder user until sign-off |
| 4 Alpha-0 and 15-30 alpha testers on macOS 27 with Apple Intelligence on, each committing to 3 weeks | Bharat | Fri 12 Mar 2027 | Alpha-0 or the alpha waits for the minimum count |
| An M1 or M2 Mac (8-16 GB) on macOS 27 with Apple Intelligence on, plus an 8 GB M3/M4 if a tester has one | Bharat | Fri 30 Oct 2026, measured in week 2 | Spike B runs on one Mac, and core3 stays unmeasured |
| Bharat's 10 voice notes (en-IN and Hinglish, some noisy) | Bharat | Thu 29 Oct 2026 | The layer-0 rule and locale choice slip past Spike A |
| Static privacy-policy and support page | Bharat | Fri 26 Feb 2027 | The first external build can't be listed |
| Anthropic API key on Bharat's own account with billing, plus a separate development key never committed to the repo or CI | Bharat | Fri 11 Dec 2026 (Lab-1) | The model bench waits, with no alpha impact |
| Developer ID certificate for Saro Lab | Bharat | Fri 11 Dec 2026 | Lab-1 runs only from Xcode on Bharat's Mac |
| macOS 28 betas (about 7-11 Jun 2027) and release (about mid-September 2027) | Apple | Dev weeks 31 and 45 | The eval passes move with them |
| App Review's answer on Guideline 5.1.3(ii) | Apple, asked by Bharat | Inquiry sent by Fri 7 May 2027 | The P6 contingency applies |

Open question: does Saro Lab sign with the company's Developer ID or Bharat's individual account?

Open question: what default daily spend cap should BYOK routes start with?

### 17.4 Constraints

- One Swift developer, full time, until at least the Fri 21 May 2027 call; Bharat gives 3-6 hours a week.
- macOS 27.0 or later, arm64 only; testers need an M1 or later with Apple Intelligence on and an English device language.
- No server, no account, no third-party SDKs and no analytics; Apple frameworks plus system SQLite only.
- The alpha sandbox has no `com.apple.security.network.client`; only Saro Lab may go online.
- Foundation Models doesn't support hi_IN, and the on-device context is 8192 on the M5 and planned at 4096 elsewhere.
- Hosted CI has no Apple Intelligence, so live evals and the bench run on the M5 and the M1/M2.
- TestFlight builds expire after 90 days, and internal testers must hold company App Store Connect roles.
- The calendar counts only the weeks of 9 Nov and 28 Dec 2026 as holidays.
- The Foundation Models acceptable-use requirements and App Store Guidelines 5.1.1(ix), 5.1.2(i) and 5.1.3(ii) apply.
- BYOK calls bill Bharat's own Anthropic account; Saro itself carries no AI cost.