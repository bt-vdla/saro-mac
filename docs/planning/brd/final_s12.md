## 13. Safety requirements

Saro's one on-device safety gate puts every entry into one of four states before any model reads it, and every unclear result is a safety hold. Self-harm text gets the SafetyCard and crisis resources, never an AI reflection. The same gate, states and day rules apply whether a touchpoint runs on-device, on PCC or on a BYOK provider.

<?claude block dia?>

Every entry waits in "Awaiting a check" until its transcript arrives, then passes through one SafetyGate (layers 0 to 3) into one of four states ranked safety hold > model unavailable > technical hold > clear. A Retry, the model becoming available, a SAFETY_VERSION change or an edit sends it back through the same gate, and a safety hold suppresses the whole day's reading, letter and notification.

### 13.1 Goals

- Self-harm text gets the SafetyCard and crisis resources, never an AI reflection.
- Generation fails closed: any uncertain result is a safety hold.
- Nothing generated is stored for a held entry.
- The recording is always saved.
- Logs carry no words.
- No held entry, and nothing from a safety-held day, leaves the Mac.

### 13.2 The four states

This table is the one definition of entry state, and every other section refers to it.

| State | When | What the user sees | Effect on the day | Effect on engine and notifications |
|---|---|---|---|---|
| Clear | Layer 0 passes (or the entry is typed), no phrase hit, and the classifier says NONE | Saro's reading of the entry | Contributes to the day reading | Observations feed the engine; the letter notification fires as normal; eligible for PCC and BYOK routes |
| Technical hold | Low transcription confidence (or a language mismatch, if that check is kept) while layers 1 and 2 find nothing; layer 2 must have run | 'Saro couldn't hear this one clearly' with Retry (re-transcribe, again after an OS update); no crisis link; the recording stays playable | Does not hold the day; the day reading uses the other clear entries | No observations until a retry clears it; never sent off the Mac |
| Safety hold | Phrase hit; PASSIVE or ACTIVE; or uncertain (classifier refusal, unparseable reply, timeout, output-gate hit) | The SafetyCard with regional resources; at a checkpoint the resources replace the question; About you shows the card instead of a personal prompt; the entry stays saved, playable and searchable; no override in the alpha | Whole-day rule (`insights.py:155-157`): no day reading, narrative, mood, quotes, 'In your words', letter or letter notification; ribbon, lens and replay hide that day's mood | Every observation from that local_day, clear entries included, is excluded from the engine, What's changed, the first-pattern note and the day-6 note; a re-gate that clears the day restores them; nothing from the day goes to PCC or BYOK |
| Model unavailable | Layer 2 can't run: deviceNotEligible, appleIntelligenceNotEnabled (including MDM-disabled), modelNotReady, an unsupported locale, conservative mode after a failed canary, or a P1 dogfood build | Layers 0 and 1 run with the caution lexicon. Both clear: the labelled 'In your words' quote-back. Caution hit: 'Saro will read this when Apple Intelligence is ready' and a quiet 'Talk to someone' link, with no checkpoint questions. A phrase hit is a safety hold | A day with a caution hit is awaiting a check: no letter and no letter notification until the re-gate; other clear entries keep their quote-backs | No model generation; when `SystemLanguageModel` becomes available or conservative mode lifts, every waiting entry re-gates through layer 2 before any generation; never sent to PCC or BYOK |

Precedence: safety hold > model unavailable > technical hold > clear. A low-confidence spoken entry on a Mac without layer 2 is therefore model unavailable, never a technical hold.

Awaiting a check means a model-unavailable entry with a caution hit, or any entry with no verdict yet, such as a transcript not ready. Its day gets no day reading, letter or letter notification until it is gated. Such entries are left out of the first-pattern and day-6 notes, and a checkpoint turn with no live text shows Keep going and no follow-up question.

A held entry never shows nothing at all. Help > If you're struggling is one click from anywhere, and it also sits in the menu bar extra.

### 13.3 Requirements

| ID | Requirement | Layer | Verification |
|---|---|---|---|
| SR-01 | One `actor SafetyGate` in SaroKit gates every path: model generation, the heuristic twin, onboarding answers, menu-bar, hotkey and App Intents text, and dropped, imported, recovered, backdated and duplicated entries. A duplicate reuses its source's verdict. | Gate | SaroCoreTests: one test per entry path; SaroAI refuses any entry without a verdict |
| SR-02 | The gate fails closed. A classifier refusal, an unparseable reply, a timeout or an output-gate hit is an uncertain result and a safety hold. | Gate | SaroCoreTests with injected refusal, garbage and timeout |
| SR-03 | Layer 0 checks spoken entries only: mean `transcriptionConfidence` below a tuned floor is a technical hold. Layer 0 never clears an entry; layers 1 and 2 still read whatever text exists. | L0 transcript | Floor chosen from Bharat's 10 recordings in Spike A; test that a low-confidence entry with a phrase hit is a safety hold |
| SR-04 | Layer 1 is the phrase gate: the 20 `safety.py:29-49` regexes, the `safety.ts` idiom guards, and an expanded Hinglish list (mar jaun, mar jaana hai, zinda nahi rehna, sab khatam kar dun, khud ko khatam) in romanised and Devanagari forms. It always runs, AI on or off, in under 1 ms. | L1 phrase gate | Ported `test_safety.py` and `safety.test.ts` corpora; the probe line 'main mar jaun' matches |
| SR-05 | One Unicode-preserving normaliser applies to patterns and text alike: lowercase, curly-quote folding, whitespace collapse, NFKC, case and diacritic folding. It never strips non-ASCII, unlike `safety.ts` normalize(). | L1 phrase gate | Test: a Devanagari phrase survives normalisation and matches |
| SR-06 | The caution lexicon runs only when layer 2 can't. A hit never shows the SafetyCard by itself; it blocks quote-backs and heuristic questions until the classifier reads the entry. | L1 caution | Model-unavailable ship gate (SR-26) |
| SR-07 | Layer 2 is a graded NONE, PASSIVE or ACTIVE classifier: permissive String, greedy, 4 output tokens, written definitions and few-shot idioms, prewarmed. Text over 3,000 tokens is chunked at sentence boundaries, and any risky chunk flags the entry. The naive RISK/NONE prompt is never used. | L2 classifier | Recall and false-positive ship gates (SR-24, SR-25); code review of the prompt |
| SR-08 | Layer 3 runs the phrase gate over every generated string from every executor: on-device, PCC, heuristic and BYOK. A hit suppresses the output and makes the entry a safety hold. | L3 output gate | SaroCoreTests per executor |
| SR-09 | Apple's `guardrailViolation` and a BYOK `stop_reason: "refusal"` are content policy, not safety signals. Each moves to the next stricter rung or an honest state, never shows the SafetyCard by itself, and never triggers a looser re-ask. | Ladder | Ladder tests with recorded violation and refusal fixtures |
| SR-10 | The ladder only tightens. The permissive rung runs only on gate-cleared entries, and each touchpoint makes at most 4 model calls per entry (two per rung). | Ladder | Ladder tests; runaway-guard test |
| SR-11 | Still captions use guided `@Generable` with default guardrails only, never the permissive path. A guardrail hit leaves the caption empty and labelled. The caption text passes layers 2 and 3, and a hit makes the still a safety hold. | Ladder | SaroCoreTests; stills eval cases |
| SR-12 | Entry state follows the precedence in 13.2. A technical hold requires layer 2 to have run. | States | One state-table test per state, plus precedence tests |
| SR-13 | A safety hold applies the whole-day rule to its local_day: no reading, narrative, mood, quotes, 'In your words', letter or letter notification. | States | Test: no letter notification on a safety-hold day |
| SR-14 | A day awaiting a check gets no day reading, letter or letter notification until gated, and its entries are excluded from the first-pattern and day-6 notes. A checkpoint turn with no live text shows Keep going and no question. | States | State-table tests; XCUITest with the speech model forced missing |
| SR-15 | Nothing generated is stored for a held entry: no AI text, mood or observation, only a content-free `safety_verdict` row. The recording is always saved. | States | P2 exit tests |
| SR-16 | The `active_observation` view hides every observation from a safety-held local_day. A re-gate that clears the day restores them. | States | Test: flagged-day observations excluded, then restored |
| SR-17 | The gate runs at save; on each turn's live text before a question and again on the file transcript; on every edit (the sha256 changes); on onboarding answers; and when the model becomes available. Before a generation it looks up cached verdicts and never re-gates joined text. | Gate | SaroCoreTests per trigger |
| SR-18 | Verdicts are keyed by entry, `text_sha256`, `SAFETY_VERSION` and layer. Bumping `SAFETY_VERSION` re-gates every entry in the background. | Gate | Test with a version bump |
| SR-19 | The SafetyCard shows resources from `lib/crisis-resources.ts` (988, Tele-MANAS 14416, findahelpline), chosen by `Locale.current.region` with findahelpline as the default. | UI | Tests for IN, US, GB and an unknown region; XCUITest |
| SR-20 | Help > If you're struggling is one click from every screen and from the menu bar extra. A held entry never shows an empty state. | UI | XCUITest; accessibility audit |
| SR-21 | P1 dogfood builds follow the model-unavailable rule: phrase gate plus the P0 draft caution lexicon, and a caution hit suppresses the quote-back and the checkpoint question. Until the SafetyCard lands in P2, a phrase hit hides the reading and shows the menu-bar crisis line. | States | P1 tests; dogfood build checklist |
| SR-22 | On each new os_build, about 20 synthetic risk and 20 venting canaries run through layer 2 (about 7 s), and a fingerprint is stored. A missed risk canary enters conservative mode until a later run passes or an app update lists that os_build as evaluated. | Canary | Forced-miss test (P2 exit); canary event in the Alpha report |
| SR-23 | In conservative mode, classifier clears aren't trusted, the model-unavailable rules apply, model readings are off, and a quiet banner says 'Saro is checking this macOS update'. Canary texts are never shown. | Canary | XCUITest with conservative mode forced |
| SR-24 | Recall gate: 100+ risk cases (passive ideation, plans and methods, paraphrase, Hinglish, Devanagari, past self-harm) at 100% recall before any non-founder user. | Ship gate | Eval report on the M5 and the M1/M2 (plus an 8 GB M3/M4 if available), per os_build and variant |
| SR-25 | False-positive gate: at most 5% SafetyCards on 100+ venting, idiom, grief, anger, abuse, drinking and intimacy cases, or Bharat's recorded decision under SR-30. | Ship gate | Eval report on both Macs |
| SR-26 | Model-unavailable gate: the phrase gate plus caution lexicon block a quote-back on 100% of the risk corpus. Each miss joins the lexicon after clinician review, and the phrase gate's own recall is recorded. | Ship gate | Eval run with layer 2 disabled |
| SR-27 | Hold-rate gate: technical holds on at most 10% of spoken entries, and any hold on at most 15% of days, on Bharat's journal plus the venting corpus. | Ship gate | Local run on Bharat's Mac, labelled by him |
| SR-28 | The eval corpus holds 200+ synthetic cases. Real user text never enters the committed corpus, the model bench or Apple feedback; `LanguageModelFeedback` gets synthetic cases only. | Process | Code review: loaders read only the corpus |
| SR-29 | Every gate re-runs on each prompt change and each macOS point release and beta. The P3 exit runs with AI on and with AI off. | Process | Eval reports keyed by os_build, variant, fingerprint and prompt_version |
| SR-30 | If SafetyCards still exceed 5% after tuning, Bharat chooses: (a) accept up to 10% for Alpha-0's five testers (recommended), or (b) per-entry scope. The rule never changes silently. | Process | Recorded decision (D-10) |
| SR-31 | Past self-harm ('I used to cut, three years clean') is a safety hold in the alpha, revisited with the clinician. Grief for someone else, fiction and song lyrics are NONE examples. | L2 classifier | Corpus cases |
| SR-32 | An external clinician, ideally Hindi-speaking, and Bharat sign off the phrase list, caution lexicon, classifier definitions, SafetyCard and hold copy, letter-notification suppression and crisis list by Fri 12 Mar 2027. | Process | Signed record |
| SR-33 | Safety logs are content-free: entry id, layer, state, reason_code, `SAFETY_VERSION` and time. | Logging | Log-scan test; the Alpha report contains no words (P3 exit) |
| SR-34 | 'Saro got this wrong' (P3) exports entry id, state, layer, reason_code, `SAFETY_VERSION`, os_build, variant and an optional synthetic paraphrase, never entry text. Bharat and the clinician triage reports weekly from Fri 2 Apr 2027. | Logging | Test of the export payload |
| SR-35 | The internal acceptable-use assessment is written by the end of P2, signed by Bharat and reused in App Review notes. It records that stills never use the permissive path. | Process | Signed document with the Spike B and P2 measurements attached |
| SR-36 | A BYOK call sends only Clear entries whose layer-2 verdict was made on this Mac. It never sends a held, model-unavailable or awaiting-a-check entry, anything from a day with a safety hold or an entry awaiting a check, or anything in conservative mode. A hold arriving later that day stops further sends from it. | BYOK | A stub `URLProtocol` records zero requests for each non-clear case |
| SR-37 | The safety gate and the canary always run on-device, and Settings > Models offers no route for them. Stills, audio and video never go to a BYOK provider. | BYOK | Route-list test; request-body test |
| SR-38 | Every BYOK output passes layer 3 and the same grounding checks as on-device output: candidate indexes, the drift check, history and relationship words, banned phrases. A failure drops a rung. | BYOK | Grounding suite run against the Claude executor in the model bench |
| SR-39 | Claude Opus 5.5 and Sonnet 5.5 routes opt into server-side fallbacks (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`); Haiku 5.5 has no server-side fallback, so its routes omit the parameter. `ai_run` records the model that answered. | BYOK | Request-body tests per model; refusal fixtures |
| SR-40 | Before a provider's first call, a consent screen names the provider, each routed touchpoint, and exactly what is sent and never sent. A scope change asks again, and consent can be revoked (App Store Guideline 5.1.2(i)). | BYOK | XCUITest; `provider_consent` rows |
| SR-41 | Every BYOK call writes a content-free `ai_run` and appears in What Saro read as 'Sent to Anthropic'. | BYOK | SaroCoreTests |
| SR-42 | API keys live only in the Keychain, this device only and not synchronizable. They never reach logs, UserDefaults, SQLite, exports, backups, crash data or the Alpha report, and Erase all data deletes them. | BYOK | Keychain attribute test; scan of prefs, database and export for the key |
| SR-43 | Only Saro Lab carries `com.apple.security.network.client`, and it connects only to the configured provider host (`api.anthropic.com`). The Saro Dev and TestFlight builds never carry it. | BYOK | CI `codesign -d --entitlements` per scheme; P3 network-log audit |

### 13.4 Open questions

- Which data-retention terms apply to API inputs on Bharat's Anthropic account, and does the consent copy need to state them?
- Should a later re-gate that holds an already-sent day be shown in What Saro read?