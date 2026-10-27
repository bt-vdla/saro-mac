## 9. Non-functional requirements

Saro's quality bar is 34 measurable targets, each with a named check in CI, the eval suite or a phase exit. Targets apply to the TestFlight alpha unless a row names Saro Lab or a later phase.

The test Macs are the founder's M5 (AFM 3 Core Advanced, context 8192) and a borrowed M1/M2. An 8 GB M3/M4 joins when one is available.

| ID | Quality | Requirement and target | How verified |
|---|---|---|---|
| NFR-01 | Privacy: network | The alpha's process makes 0 network connections. Its signed entitlements contain no `com.apple.security.network.client`. | `codesign -d --entitlements` in Xcode Cloud on every push; a network-log audit of Saro's process at the P3 exit. |
| NFR-02 | Privacy: the promise | The welcome screen says exactly: "Saro has no account, no server and no way online. This version is built without permission to use the internet." Line 2: "Saro reads your words with Apple Intelligence, here on this Mac. Saro never sends what you record or write to us, to Apple or to anyone else." Line 3: "Your journal is yours. Export it, or erase it, whenever you like." | Before each TestFlight build, the copy is retested against Writing Tools, Universal Clipboard, Time Machine, iCloud Drive and the Services menu. Any PCC or BYOK use changes the copy in the same release. |
| NFR-03 | Privacy: content-free records | 0 journal words in logs, `ai_run`, `safety_verdict`, the Alpha report, crash data or the "Saro got this wrong" report. | A unit test seeds a sentinel phrase and scans every log, row and report output for it. |
| NFR-04 | Privacy: no tracking | No analytics, Spotlight indexing off, and GPS removed from 100% of stills. | Dependency check in CI; an ImageIO metadata test on imported stills. |
| NFR-05 | Privacy: deletion | Deleted rows are overwritten (`secure_delete=ON`) and leave the 7 daily backups within 7 days. Forget all and Erase remove the backups at once. | SaroCoreTests assert the pragma, the 7-snapshot rotation and the `Backups/` delete. |
| NFR-06 | Privacy: Saro Lab | With default routes, Saro Lab makes 0 connections. With a Claude route, it connects only to `api.anthropic.com`, only after consent and only for clear entries. | A network-log audit of the Lab build in both configurations. |
| NFR-07 | Safety: recall | 100% recall on 100+ risk cases: passive ideation, plans and methods, paraphrase, natural Hinglish, Devanagari and past self-harm. | SaroEvals on both test Macs before any non-founder user, then on every prompt change, macOS point release and beta. A clinician and Bharat sign off. |
| NFR-08 | Safety: false positives | 5% or fewer SafetyCards on 100+ venting, idiom, grief, anger, abuse, drinking and intimacy cases. Above 5% after tuning, the founder records a decision, up to 10% for Alpha-0. | The same SaroEvals runs. The decision is recorded at the P0 review or the P2 exit, never applied silently. |
| NFR-09 | Safety: model unavailable | The phrase gate plus the caution lexicon block a quote-back on 100% of the risk corpus. | SaroCoreTests offline on every push. Each miss joins the lexicon after clinician review. |
| NFR-10 | Safety: hold rates | Technical holds on 10% or fewer of spoken entries, and days with any hold at 15% or fewer. | Measured on Bharat's journal plus the venting corpus at the P2 exit. |
| NFR-11 | Grounding | 0 non-verbatim quotes across all eval cases. A model narrative ships only if 90% or more of eval narratives pass the drift check. | The SaroEvals report, per os_build, variant and prompt_version. |
| NFR-12 | Performance: capture | Hotkey to recording in under 2 s from another app; live captions within about 1 s; the phrase gate in under 1 ms. | P1 exit timing runs and XCUITest timing assertions. |
| NFR-13 | Performance: AI | Reflect-deeper p50 of 2.5 s or less on the M5, and a question within 3 s on the M1/M2. The model prewarms when the recorder opens. | Latency fields in the SaroEvals report on both Macs (probe baseline: classifier about 170 ms warm, 738 ms cold). |
| NFR-14 | Performance: first run | First entry within 180 s of first launch, with Apple Intelligence on and off. | The P3 exit with all 5 Alpha-0 testers. |
| NFR-15 | Performance: canvas (P7) | On a 150-card day: 0 hitches in pan, pinch and drag at 120 Hz. The first frame draws in 100 ms or less, within 400 MB. The lens holds 361 tiles in 100 MB or less on an M1/M2, with 0 GPU draws at rest. | Instruments at the P7 entry gate and exit. |
| NFR-16 | Performance: search (P8) | Cmd-K palette p95 of 5 ms or less per keystroke at 1,000 entries. | The P8 exit benchmark. |
| NFR-17 | Reliability: recordings | 0 lost audio across 20 kill -9 runs, lid close, a nearly full disk, a mic unplugged mid-take and quit while recording. Every file has a row and every row has a file. | The kill harness, nightly on the M5 and before every build reaches Bharat. |
| NFR-18 | Reliability: cohort | 0 lost recordings across the alpha cohort, and crash-free days of use at 99% or better. | MetricKit counts from the Alpha reports, cross-checked against TestFlight, at the P4 exit. |
| NFR-19 | Data integrity | Export, erase and import restore 100% of rows and media (sha256 match). Every `user_version` fixture migrates to head with its invariants intact. | SaroCoreTests on every commit, required before any build reaches Bharat. |
| NFR-20 | Determinism (P5) | The same ledger always yields the same engine snapshot hash, and the golden fixtures match exactly. | Engine tests over two 8-week golden fixture journals with planted changes. |
| NFR-21 | Accessibility: VoiceOver | Every control has a label. The countdown, throttled captions and Saro's question are announced, and the floating pill takes focus. | `performAccessibilityAudit()` on every screen in both AI modes, plus an Accessibility Inspector pass at P3. |
| NFR-22 | Accessibility: keyboard | A keyboard-only run goes from first launch to capture to reading. Every action has a menu command. | A scripted keyboard-only run at the P3 exit. |
| NFR-23 | Accessibility: text and contrast | The in-app text scale works from 0.9 to 1.5 on every screen. Every colour token has Any, Dark and High Contrast variants, with AA contrast at every tint hour. | A unit test per tint hour; XCUITest at scale 1.5 and with Increase Contrast on. |
| NFR-24 | Accessibility: motion | Reduce Motion and Reduce Transparency are honoured on every animated or translucent surface. | XCUITest with each setting on, plus a manual pass at P3. |
| NFR-25 | Localization groundwork | 100% of UI strings live in `Localizable.xcstrings`. Dates use `Date.FormatStyle` for en-IN, en-US and 12- or 24-hour clocks. The alpha ships English only. | A string-catalog audit at P3. Unit tests for crisis resources in IN, US, GB and an unknown region; SafetyCard strings marked "do not machine-translate". |
| NFR-26 | Security: sandbox | App Sandbox is on. The alpha set is exactly app-sandbox, device.camera, device.audio-input and files.user-selected.read-write; later phases add only their listed entitlements. | CI asserts the signed set on every push. |
| NFR-27 | Security: keys (Saro Lab) | BYOK keys live only in the Keychain, this device only and never synchronised. 0 copies exist anywhere else. | A Keychain attribute test (`ThisDeviceOnly` accessibility, `kSecAttrSynchronizable` false) and a sentinel-key scan of logs, exports, UserDefaults, `ai_run` and crash data. |
| NFR-28 | Security: transport (Saro Lab) | BYOK traffic uses HTTPS under default App Transport Security, with no exceptions in Info.plist. | An Info.plist check in CI for the Lab target. |
| NFR-29 | Compatibility | macOS 27.0 or later on Apple silicon (M1 or later) only. Alpha testers need Apple Intelligence on and an English device language. | The test matrix above, with variant.displayName and contextSize recorded on every run. |
| NFR-30 | Compatibility: context | Every prompt fits the runtime `contextSize`: 8192 measured on the M5, 4096 assumed on AFM 3 Core Macs until measured. | Unit tests budget prompts at 4096. `contextSizeExceeded` is never retried in the same session. |
| NFR-31 | Maintainability: evals | SaroEvals runs on both Macs for every prompt change, macOS point release and beta. Reports are keyed by os_build, variant, model_fingerprint and prompt_version. | A committed script writes `evals/reports/{date}_{os_build}_{variant}_{prompt_version}.json` and diffs it against the last baseline. |
| NFR-32 | Maintainability: canary | The shipped canary set passes on every evaluated os_build, and each build embeds that list. | A canary run per new os_build, and a forced-miss test in SaroCoreTests. |
| NFR-33 | Maintainability: dependencies | 0 third-party code dependencies: Apple frameworks and system SQLite 3.54.0 only. Fonts ship under the SIL Open Font License with OFL.txt. | A package-manifest check in CI, and a licence check at P1. |
| NFR-34 | Cost (Saro Lab) | Each BYOK call's cost comes from its returned token usage, cache reads included, and the price table. No call starts once the daily cap is reached. | Unit tests over recorded usage fixtures (Opus 5.5 at $4 / $20 per million input / output tokens), plus a cap-reached test. |

A new TestFlight build ships at least every 60 days until App Store 1.0, because builds expire after 90 days. The Swift heuristic twin must match the frozen TypeScript output on every fixture, checked by a local differential script.

Open question: what launch and scroll targets does the P4 check on a seeded 60-day journal use?

Open question: what latency must a Claude route meet before it can replace an on-device route?

Open question: does macOS 27 give third-party Mac apps system Dynamic Type? The in-app scale stays either way.
