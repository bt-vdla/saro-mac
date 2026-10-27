## 16. Delivery plan

Alpha-0 ships Fri 2 Apr 2027 and the alpha Fri 16 Apr 2027, after 23 dev-weeks for one developer. Mac parity lands about Fri 24 Sep 2027 if the canvas goes first, and parity with the iPhone about Fri 3 Dec 2027. BYOK runs on a separate Saro Lab track that leaves these dates unchanged.

<?claude block dia?>

P0 to P4 add up to 23 dev-weeks (3 + 8 + 7 + 3 + 2): 25 calendar weeks less the Diwali and year-end weeks off. That puts the alpha on Fri 16 Apr 2027, two weeks after Alpha-0 on Fri 2 Apr, and 33 more dev-weeks after that lead to parity with iPhone on Fri 3 Dec 2027.

### 16.1 Calendar basis

- Dev week 1 starts Mon 26 Oct 2026.
- The weeks of Mon 9 Nov 2026 (Diwali) and Mon 28 Dec 2026 (year-end) are off; no other holidays are counted.
- Dev week n ends on the Friday of calendar week n for weeks 1-2, n+1 for weeks 3-8, and n+2 from week 9.
- Diwali 2027 falls in P8 and is not counted; the parity ranges cover about a week of it.
- Effort labels: S up to 0.5 dev-week, M over 0.5 up to 1.5, L over 1.5 up to 3, XL over 3.

### 16.2 Phases

| Phase | Dev weeks | Dates | Goal | Exit criteria (summary) |
|---|---|---|---|---|
| P0 Foundations and spikes | 1-3 (3.0) | Mon 26 Oct – Fri 20 Nov 2026; spike readout Fri 6 Nov | Prove crash-safe capture with transcription, then the on-device ladder and classifier on two Macs; lay the ledger core | A kill -9 file plays to its last 2 s fragment; permissive JSON fails to parse on 10% or fewer entries; the classifier catches every smoke risk case with 10% or fewer SafetyCards; ported tests pass |
| P1 Capture ritual (dogfood) | 4-11 (8.0; buffer 0.5 after Lab-1) | Mon 23 Nov 2026 – Fri 22 Jan 2027; build 1 Fri 18 Dec, build 2 Fri 8 Jan | Daily capture that never loses audio; from Fri 8 Jan the heuristic reading under the model-unavailable rule | Zero lost audio over 20 kill -9 runs, lid close, disk full and unplug; export-erase-import matches; hotkey under 2 s; daily dogfood since Fri 18 Dec |
| P2 What Saro noticed | 12-18 (7.0; buffer 0.9) | Mon 25 Jan – Fri 12 Mar 2027 | Four-state gate and grounded on-device readings with provenance; December entries backfilled | Ship gates met on both Macs and signed off; zero non-verbatim quotes; every artifact links to an ai_run; a forced canary miss enters conservative mode |
| P3 Shell and Alpha-0 | 19-21 (3.0; review buffer 0.35) | Mon 15 Mar – Fri 2 Apr 2027 | Bharat plus 4 external testers use voice and writing daily | Beta App Review approved; first entry within 180 s with AI on and off; no connections in the network log; Alpha report has no words |
| P4 Video and the alpha | 22-23 (2.0; 0.15 freed) | Mon 5 Apr – Fri 16 Apr 2027 | Video moments on the same engine; 15-30 testers | 15+ testers active in week 1; zero lost recordings; crash-free days at 99% or better; habit metrics from the minimum tester count |
| P5 Alpha learning and engine v0 | 24-29 (6.0; buffer 0.45) | Mon 19 Apr – Fri 28 May 2027; engine v0 Fri 7 May; decision Fri 21 May | Engine v0 on alpha data, 'What's changed', the time lens grid and the iPhone-or-canvas call | Golden fixtures match; 3+ accurate quote-backed 'what changed' lines in Bharat's journal, none invented; nothing draws on safety-held days |
| P6 iPhone companion and sync | 30-39 (10.0; buffer 1.0) | Mon 31 May – Fri 6 Aug 2027 | The same journal on iPhone, end-to-end encrypted sync, no Saro server | iPhone entry on the Mac within 1 minute; zero lost or duplicated entries over 2 weeks; suites pass on the iPhone variant; Guideline 5.1.3 settled |
| P7 Canvas and time surfaces | 40-49 (10.0; buffer 0.5) | Mon 9 Aug – Fri 15 Oct 2027 | Canvas, continuous lens and lit ground on the unchanged ledger | 150-card day: 0 hitches at 120 Hz, first frame 100 ms or less, 400 MB or less; lens of 361 tiles in 100 MB or less; evals pass on macOS 28 |
| P8 Parity tail and App Store 1.0 | 50-56 (7.0; buffer 0.5) | Mon 18 Oct – Fri 3 Dec 2027 | Close the remaining web features; submit App Store 1.0 | Every alpha and v1 row exists natively (canvas-first: the iPhone row ships as 1.1); no regressions; palette p95 5 ms or less; submitted with StoreKit |

The table shows the default iPhone-first order after P5. Deliverables sum exactly to each phase total.

### 16.3 Milestones

| Milestone | Dev week | Target | Range |
|---|---|---|---|
| Dogfood build (Saro Dev on Bharat's M5: capture, transcript, write, board, export and import) | End of 7 | Fri 18 Dec 2026 | Dev weeks 6-9: Fri 11 Dec 2026 – Fri 8 Jan 2027 |
| Alpha-0 (voice and writing; Bharat plus 4 external testers) | End of 21 | Fri 2 Apr 2027 | Dev weeks 19-24: Fri 19 Mar – Fri 23 Apr 2027; also needs Beta App Review, submitted Mon 15 Mar |
| Alpha (adds video; 15-30 testers) | End of 23 | Fri 16 Apr 2027 | Dev weeks 21-27: Fri 2 Apr – Fri 14 May 2027 |
| Diff/timeline engine v0 on alpha data | End of 26 | Fri 7 May 2027 | Dev weeks 25-30: Fri 30 Apr – Fri 4 Jun 2027 |
| iPhone-or-canvas decision (with business model, second developer and D-19) | End of 28 | Fri 21 May 2027 | Dev weeks 26-31: Fri 7 May – Fri 11 Jun 2027; needs at least 3 weeks of alpha data |
| Mac parity and App Store 1.0 (canvas-first order) | End of 46 | Fri 24 Sep 2027 | Dev weeks 41-52: Fri 20 Aug – Fri 5 Nov 2027 |
| Parity with the iPhone companion and sync | End of 56 | Fri 3 Dec 2027 | Dev weeks 50-64: Fri 22 Oct 2027 – Fri 28 Jan 2028; about Fri 1 Oct 2027 (dev week 47) with a second developer |

In the default iPhone-first order, Mac parity and App Store 1.0 land with parity with the iPhone on Fri 3 Dec 2027.

### 16.4 Changes from the last consistency check

- The alpha range is dev weeks 21-27 (Fri 2 Apr – Fri 14 May 2027), because the alpha can't precede Alpha-0.
- The Beta App Review build goes in Mon 15 Mar 2027, the first day of P3 and 18 days before Alpha-0.
- The privacy manifest, App Privacy and age-rating answers, review notes and external group move into P2's last week, using 0.1 of the P2 buffer.
- P3 release plumbing keeps the submission, StoreKit check, expiry nudge and network audit at 0.4.
- 'Saro got this wrong' (S, 0.15) moves into P3, funded from the review buffer, so testers can report misfires from Alpha-0. P3's review buffer is now 0.35, and P4 frees 0.15.
- P1 dogfood builds follow the model-unavailable rule (SR-21).
- Day view, Opened views, Stills, What Saro knows, Commitments, Day replay and Seven Sunrises are relabelled S to match their scheduled effort.
- Still captions use default guardrails only, and the image test leaves Spike B.
- The runaway guard allows 4 model calls per touchpoint per entry, two per rung.
- In the canvas-first order, the iPhone and sync row ships as 1.1, the macOS 28 beta eval pass moves to P7, and the release pass to P8.

### 16.5 Slip rules

- Cut order on any slip: video, then still captions, then the Touch ID lock.
- If P2 overruns its buffer, Alpha-0 ships with per-entry processing, the full gate and the heuristic day reading, and the model day reading follows in P4.
- If MovieFileOutput fails Spike A, capture switches to AVAssetWriter, about +1 week inside the range.
- A ladder flip or a classifier false-positive fallback costs no schedule.
- If company enrollment lags past P2, Alpha-0 slips; Developer ID is not a tester fallback.

### 16.6 Order after the alpha

| Order | P6 iPhone and sync | P7 Canvas | P8 Parity and 1.0 | Mac parity and 1.0 | Parity with iPhone |
|---|---|---|---|---|---|
| iPhone-first (default) | Dev weeks 30-39: Mon 31 May – Fri 6 Aug 2027 | Dev weeks 40-49: Mon 9 Aug – Fri 15 Oct 2027 | Dev weeks 50-56: Mon 18 Oct – Fri 3 Dec 2027 | Fri 3 Dec 2027 | Fri 3 Dec 2027 |
| Canvas-first | Dev weeks 47-56: Mon 27 Sep – Fri 3 Dec 2027 | Dev weeks 30-39: Mon 31 May – Fri 6 Aug 2027 | Dev weeks 40-46: Mon 9 Aug – Fri 24 Sep 2027 | Fri 24 Sep 2027 | Fri 3 Dec 2027 |

WWDC 2027 (about 7-11 Jun, dev week 31) and the macOS 28 release (about mid-September, dev week 45) each cost a 0.5 dev-week eval pass. A second developer hired at the call takes the track the rule doesn't put first, from dev week 30, with about 15% coordination overhead.

### 16.7 Lab track: BYOK in Saro Lab

BYOK ships first in Saro Lab, a founder-only build, so the TestFlight alpha keeps 'Saro has no way online'. Saro Lab is Developer ID-signed, carries `network.client`, has its own bundle id and container, and is never given to testers.

| Item | Size | Contents | Depends on | Target |
|---|---|---|---|---|
| Lab-1 Model bench | S, 0.5 dev-week, from the P1 buffer | Saro Lab scheme; Anthropic Messages API client over URLSession; key entry into the Keychain; the same synthetic eval cases on Apple on-device and Claude, compared on grounding, safety routing, quality, latency and cost | SaroEvals harness and ported checks (P0); Bharat's Anthropic key | Ready Fri 11 Dec 2026; readout with Bharat Fri 18 Dec 2026, which settles D-20 |
| Lab-2 BYOK routes | M, 1.0 dev-week, unfunded (D-21) | Settings > Models routes per touchpoint; consent screen; cost per call and daily cap; 'Sent to Anthropic' rows; the gate wired before every send | P2's SaroAI runtime, four-state gate, ai_run and What Saro read | Recommended after the Fri 21 May 2027 call |

Lab-1 leaves the P1 buffer at 0.5 dev-week and moves no date. Lab-2 after the call moves later dates about 1 week with one developer, inside their ranges, or none with a second developer. Whether the public app ever carries BYOK is D-19, decided Fri 21 May 2027.

Open question: what does one full bench run cost? Lab-1's first run measures it.

### 16.8 Founder actions

| When | Action |
|---|---|
| Mon 26 Oct 2026 | Run the Supabase count query; export any other real user first; dump your own entries only if wanted (about 2 hours). Pause the project, revoke the OpenAI key, purge Logfire and delete old `.env` copies. Decide D-01, D-04 and D-06. |
| By Fri 30 Oct 2026 | Confirm the developer account is the company (start D-U-N-S if not). Create the App Store Connect record 'Saro' with a fallback name, request PCC and enroll in the Small Business Program. Decide D-02, D-03, D-05 and D-07. |
| By Fri 30 Oct 2026 | Borrow or buy an M1 or M2 (8-16 GB) on macOS 27 with Apple Intelligence on. Record 10 voice notes (en-IN and Hinglish, some in a noisy room) by Thu 29 Oct. |
| Week of Mon 2 Nov 2026 | Label about 60 extraction cases, write 30 risk and 30 venting smoke cases, review labels and draft two 8-week fixture journals (4-5 hours). Join the 30-minute spike readout on Fri 6 Nov. |
| By Fri 20 Nov 2026 | Book the clinician. Decide D-08 to D-12 at the P0 review. |
| By Fri 11 Dec 2026 | Create an Anthropic API key on your own account and enter it in Saro Lab. |
| Fri 18 Dec 2026 | Start journaling daily in Saro Dev, and export before each new build. Review the Lab-1 bench and decide D-20. |
| By Fri 22 Jan 2027 | Decide D-21. |
| By Fri 26 Feb 2027 | Put up the static privacy-policy and support page. |
| By Fri 12 Mar 2027 | Recruit 4 Alpha-0 and 15-30 alpha testers. Sign the acceptable-use assessment and the privacy copy, and hold the clinician's sign-off. Decide D-13. |
| By Fri 2 Apr 2027 | Write down the habit thresholds, session definition and minimum active-tester count. Decide D-14. |
| Weekly from Fri 2 Apr 2027 | Triage 'Saro got this wrong' reports with the clinician. |
| By Fri 16 Apr 2027 | Decide D-15. |
| By Fri 7 May 2027 | Send the App Review inquiry on iCloud sync under Guideline 5.1.3(ii). |
| Fri 21 May 2027 | Decide D-16 to D-19. |
| Every 60 days until App Store 1.0 | Ship a new TestFlight build before the current one's 90-day expiry. |