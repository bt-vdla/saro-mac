## 4. Goals, non-goals and success metrics

The alpha's headline metric is week-1 habit: the share of active testers with 3 or more sessions in their first 7 days, against a 50% bar.

### 4.1 Goals

Saro for Mac has eight goals, and the first one decides what gets built after the alpha.

1. **Test the Mac habit.** Learn whether people keep journaling on a Mac, and let the answer choose iPhone or canvas on Fri 21 May 2027.
2. **Make privacy provable.** No account, no server and no network entitlement in the alpha build.
3. **Listen without inventing.** Every quote is verbatim, and every reading traces back to the user's own words.
4. **Put safety first.** One gate on every path, recall over precision, and clinician sign-off before any non-founder user.
5. **Never lose a recording or a journal.** Crash-safe capture, a working Export and Import, and 7 daily snapshots.
6. **Start the moat on day one.** Every input and AI output is stored append-only with provenance, ready for engine v0 by Fri 7 May 2027.
7. **Keep Saro's server cost at zero.** No per-user spend at any number of users.
8. **Let the founder compare models.** Saro Lab routes chosen touchpoints to Claude on his own key and benchmarks it against on-device.

### 4.2 Non-goals

Saro for Mac is not therapy, and the alpha leaves out the network, the canvas and the iPhone on purpose.

- Not a clinical tool: no therapist portal, no diagnosis, no health wording, and mood stays out of HealthKit.
- No account, sign-in or Saro server.
- No network access in the TestFlight alpha build, so no PCC, BYOK or music metadata there.
- No free-form canvas, lit ground or morph flights in the alpha; they return in P7.
- No iPhone app or sync in the alpha; P6 builds them if the habit rule picks them.
- No promise of Hindi or Hinglish AI quality; the alpha is English only.
- No Intel Macs and nothing below macOS 27.
- No user override of a safety hold in the alpha.
- No model-written evening letters; letters are typeset from the reading.
- No analytics or third-party SDKs; the Alpha report holds no words.
- No custom-instructions box; it conflicts with 'never invent' and invites prompt injection.
- No new web features; the web app stays frozen.

### 4.3 Success metrics

Each metric has one definition, one target and one point where it is read.

| Metric | Definition | Target | When measured |
|---|---|---|---|
| Week-1 habit (headline) | Share of active testers with 3 or more sessions in their first 7 days. A session is a local day with at least one saved entry, counted by the local day of captured_at. Backdated entries and duplicates don't count | 50% or more. Below 50%, or if testers ask for on-the-go capture, the iPhone companion comes next (D-16) | Each tester's first 7 days; read on Fri 21 May 2027 |
| Minimum sample | Active testers who send the weekly Alpha report | At least the count Bharat writes down by Fri 2 Apr 2027; below it, the decision waits | Weekly from Alpha-0 |
| Session 1 to 2 drop-off | Share of testers with a first session and no second within 7 days | 35% or less (JTBD week-1 target) | Each tester's first 7 days |
| Capture mix | Entries by kind: voice, video, text, still | Recorded; no target | Weekly Alpha report |
| Time to first entry | Seconds from first launch to the first saved entry | 180 s or less for all 5 Alpha-0 testers, with Apple Intelligence on and off | P3 exit, by Fri 2 Apr 2027 |
| Lost recordings | Recordings with no playable file, or files with no row | 0 across 20 kill -9 runs, and 0 across the alpha cohort | Nightly kill harness from P1; alpha week 1 |
| Crash-free days | Days of use with no crash, from MetricKit counts cross-checked with TestFlight | 99% or more | P4 exit, by Fri 16 Apr 2027 |
| Safety recall | Risk cases that end in a safety hold | 100% of 100+ cases on both Macs, and 100% again on the shipping os_build | P2 exit (Fri 12 Mar 2027); P4 exit |
| Safety false positives | Venting cases that show a SafetyCard | 5% or less of 100+ cases; up to 10% for Alpha-0 only if Bharat records that choice (D-10) | P2 exit |
| Holds on real speech | Technical holds among spoken entries; days with any hold | 10% or less; 15% or less, on Bharat's journal plus the venting corpus | P2 exit |
| Grounding | Quotes that are not verbatim from the source entry | 0 across all eval cases | P2 exit; every prompt change and macOS release |
| Extraction coverage | Clear entries extracted on the primary or fallback rung | 90% or more | P2 exit |
| Follow-up latency | Time to a reflect-deeper question at a checkpoint | p50 2.5 s or less on the M5; a question within 3 s on the M1/M2 | P2 exit |
| Network silence | Connections from Saro's process in the alpha build | 0, with signed entitlements matching the P3 set | P3 exit; CI on every build |
| Words in telemetry | Journal words in the Alpha report and logs | 0 | Every build, by test |
| Engine v0 | Diff/timeline engine running on alpha observations, every line quote-backed | Running by Fri 7 May 2027 | P5 |
| Server cost | Saro's monthly spend on servers and AI APIs | $0 once the backend is retired | From Mon 26 Oct 2026 |
| BYOK safety routing | Safety-held or awaiting-a-check entries sent to a BYOK provider | 0 | Model bench and every Saro Lab build |
| BYOK bench | Same eval cases on on-device and Claude: grounding failures, safety routing, quality, latency, cost per call | Reported side by side, per touchpoint | First Saro Lab use |

Open question: what bench result would justify proposing BYOK for the public app under D-19?