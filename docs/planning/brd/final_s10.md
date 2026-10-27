## 11. AI architecture

Every AI touchpoint runs on Apple's on-device model unless the user picks another route in Settings > Models. The safety gate always runs on the Mac first. Model output is never trusted as written: quotes are picked by index, prose passes a drift check, and every call is logged without content.

<?claude block dia?>

Every route, Claude included, sits between two gates: only an entry the SafetyGate clears reaches the router, and output reaches the screen only after the output gate and the grounding check pass it. A grounding failure gets one retry, then drops a rung, and every run is stored append-only with its provenance.

BYOK adds Anthropic Claude as an optional tier, first in the founder's Saro Lab build.

### 11.1 AI tiers

Apple's on-device model is the default tier and the only AI in the TestFlight alpha.

| Tier | Model | Used for | When unavailable |
|---|---|---|---|
| Apple on-device (default) | `SystemLanguageModel.default`. Measured on the M5 as AFM 3 Core Advanced, context 8192. Other Macs may get AFM 3 Core; plan for 4096 until measured. | Safety classifier, per-entry extraction, day reading, reflect-deeper and reflect-further questions, still captions, the canary. | The model-unavailable state: phrase gate plus caution lexicon, a labelled quote-back only if both clear, and an automatic re-gate when the model returns. No BYOK call runs either, because no entry can be cleared. |
| Apple Private Cloud Compute (after the alpha, named opt-in) | `PrivateCloudComputeLanguageModel`, context 32,768, a daily quota shared across apps. | Wording weekly and monthly syntheses over engine output: keys, counts and at most 12 verbatim quotes. | Today a neutral request fails with error 1046, most likely a missing entitlement. On network failure, quota or the 25 s deadline: on-device phrasing or templates. |
| BYOK (optional, Saro Lab first) | Anthropic Messages API. Default `claude-opus-5-5` ($4 / $20 per million input / output tokens); `claude-sonnet-5-5` ($2 / $10) and `claude-haiku-5-5` ($0.10 / $0.50) selectable per route. | Any routable touchpoint the user points at it (11.2), on clear entries only. The model bench: the same synthetic eval cases on Apple and Claude, side by side. | Before a call (no key, no consent, cap reached): the default on-device route runs. After a failed or refused call: the on-device guided rung (11.3). |
| Heuristic twin (always) | SaroHeuristics: Swift ports of `ai.ts`, `memory.ts`, `weekMilestones.ts`, `extract.ts`, `firstPrompt.ts` and `letter.ts`. | Every surface's no-AI fallback, labelled "In your words"; the first pattern and day-6 note; onboarding picks; the test oracle. | Shows nothing generated with no text yet, on a technical or safety hold, or on an entry awaiting a check. |
| Speech (separate, not routable) | `SpeechAnalyzer` with `SpeechTranscriber`; locales known only at runtime. | Live captions, checkpoint text, the transcript of record. | Records anyway and shows "Transcript not ready". Low confidence is a technical hold. A checkpoint with no live text shows Keep going and no question. |

The P1 dogfood builds, from Fri 18 Dec 2026, have no classifier yet, so they run under the model-unavailable rule. Later BYOK providers are OpenAI-compatible endpoints and Google Gemini over HTTP. Local models (MLX, Core AI) plug in through the macOS 27 `LanguageModel` protocol (FoundationModels.swiftinterface:1483), which `LanguageModelSession(model:)` accepts (:1950-1956).

### 11.2 Routes

Default routes never leave the Mac; the user changes a route per touchpoint in Settings > Models.

| Touchpoint | Default route | Can route to | What a non-default route sends |
|---|---|---|---|
| Safety classifier (layer 2) | On-device | Never | Nothing. The gate must clear an entry before any of it leaves the Mac. |
| On-device canary | On-device | Never | Nothing. It tests Apple's model. |
| Per-entry extraction | On-device | BYOK | The entry's text fields and its numbered candidate phrases. |
| Day reading | On-device | BYOK | Stored per-entry annotations and numbered candidates, never raw history. |
| Reflect-deeper question | On-device | BYOK | The turn's gate-cleared live text. The 2.5 s race against the heuristic still applies. |
| Reflect-further question | On-device | BYOK | The written reflection. |
| Still captions | On-device, default guardrails | Never | Nothing. The gate has no user text to clear before the call. |
| Weekly and monthly synthesis (later) | On-device phrasing or templates | PCC, BYOK | Engine output only: keys, counts, at most 12 verbatim quotes. |

A BYOK call needs all five of these:
- the Saro Lab build, which holds `com.apple.security.network.client`;
- a key for that provider in the Keychain;
- the provider's consent screen accepted (guideline 5.1.2(i)), naming the provider and what each touchpoint sends;
- a clear verdict on every entry the call reads, and for day-level calls a day with no safety hold and no entry awaiting a check;
- spend under the daily cap.

Keys are generic-password items in the data protection keychain, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and not synchronizable (SecItem.h:88-89). They are never logged, exported or written to UserDefaults. Conservative mode after a failed canary also blocks BYOK, because classifier verdicts are not trusted.

### 11.3 Call order

Every call that transforms the user's words follows one order, and it only ever moves to stricter settings or to no model.

1. **Safety gate, on the Mac.** Layers 0-2 run first, and anything but clear stops here. Precedence is safety hold > model unavailable > technical hold > clear. An entry with a caution hit or no verdict yet is awaiting a check.
2. **Primary rung.** On-device: `SystemLanguageModel(guardrails: .permissiveContentTransformations)`, String output asked for JSON only, decoded with `GeneratedContent(json:)` (FoundationModels.swiftinterface:1355). BYOK: one Messages API request with structured output, decoded the same way (11.4).
3. **Fallback rung.** When the JSON does not parse or decode, or a BYOK request fails (network, key, rate limit or cap): guided `@Generable` with default guardrails, on-device. A Claude refusal skips to the last rung.
4. **Last rung.** The labelled heuristic ("In your words") or an honest state.
5. **Output gate.** Every result passes the phrase gate and grounding (11.6) before it is stored.

Rules:
- Saro never re-asks with looser guardrails after a refusal or a `guardrailViolation`. A refused entry is never re-sent to another provider or to Apple's permissive rung.
- Claude's server-side fallback (`fallbacks: "default"`) is Anthropic's own routing inside one request. A final `stop_reason` of `refusal` means the whole chain refused. Haiku 5.5 has no server-side fallback.
- Still captions use guided `@Generable` with default guardrails only, never the permissive rung. A guardrail hit leaves the caption empty and labelled. The caption text then passes layers 2 and 3.
- The safety classifier stays permissive String, greedy, with 4 output tokens. It only labels.
- At most 4 model calls run per touchpoint per entry, two per rung. A failed BYOK request counts as a call and drops a rung at once.
- Flip rule from Spike B: if the permissive rung fails to parse on more than 10% of entries, or grounds worse than the guided rung, guided goes first. A guardrail hit then goes straight to the last rung.

### 11.4 BYOK requests (Claude first)

Saro calls the Messages API directly with `URLSession`, one stateless request per call, with a 25 s client deadline as for PCC.

```http
POST https://api.anthropic.com/v1/messages
x-api-key: <from the Keychain>
anthropic-version: 2026-10-21
anthropic-beta: server-side-fallback-2026-07-01
content-type: application/json

{
  "model": "claude-opus-5-5",
  "max_tokens": 4000,
  "system": [{"type": "text", "text": "<stable instructions>",
              "cache_control": {"type": "ephemeral"}}],
  "messages": [{"role": "user", "content": "<task, numbered candidates, entry text>"}],
  "output_config": {"effort": "medium",
                    "format": {"type": "json_schema", "schema": {}}},
  "fallbacks": "default"
}
```

- The JSON schema comes from the same `@Generable` type; `GenerationSchema` is `Codable` (FoundationModels.swiftinterface:3351). Whether its encoding is valid for the API is checked in the first Lab spike.
- The API does not support numeric or array-count constraints in the schema. Index ranges and the 12-observation limit are checked in code, and a violation is a grounding failure.
- Thinking is always on for Opus 5.5, and `output_config.effort` sets its depth (default `medium`). Saro never sends `thinking`, `temperature`, `top_p` or `top_k`; sampling fields return a 400 on this API version.
- Saro reads `stop_reason` before content. `end_turn` decodes; `refusal` skips to the heuristic or an honest state; `max_tokens` counts as a parse failure.
- The response's `model` field names the model that answered, which can differ after a server-side fallback. Provenance records that model.
- Prompt caching starts at a 512-token prefix on Opus 5.5, and cache reads cost $0.20 per million tokens. It pays in bursts, such as bench cases run back to back. Daily entries arrive hours apart, past the 5-minute cache life, and `usage.cache_read_input_tokens` shows any hits.

Open question: Anthropic's data retention terms for the founder's API organisation, to quote on the consent screen.

### 11.5 Token budgeting and cost

On-device prompts are budgeted against the context before they are sent; BYOK prompts are bounded by cost.

- Every on-device prompt is counted with `tokenCount(for:)` against the runtime `contextSize`. The count covers instructions, task and schema: `T.generationSchema` on the guided rung, the JSON shape in the prompt on the permissive rung.
- Measured on the M5: context 8192; about 4.1 characters per token (10,260 characters = 2,494 tokens); Saro-style instructions 92 tokens (the full VOICE block about 230); a 4-field schema 166 tokens.
- On core3 Macs, plan for 4096 until measured.

| Part | Planned tokens per call |
|---|---|
| Instructions | About 300 |
| Schema or JSON shape | 100-350 |
| Task | 50-260 |
| User words (cap) | 2,200 or fewer |
| Output reserve | 400-600 |

- The plan peaks at about 3,710 tokens, so it fits a 4096 context. A heavy 5-minute part is about 4,000 characters, roughly 1,000 tokens.
- Over budget, older inputs shrink to their stored title, summary and one quote. The classifier chunks text over 3,000 tokens. `contextSizeExceeded` is never retried in the same session.
- BYOK routes keep the same caps, so both executors see the same input and the bench compares like with like.
- Before each BYOK call, Saro reserves the worst case against the daily cap. Input is estimated at 3 characters per token, a deliberately conservative knob; output is `max_tokens`, which includes thinking.
- At Opus 5.5, about 3,900 input tokens and `max_tokens` 4,000 cost at most $0.016 + $0.080 = about $0.096 per call. Haiku 5.5 caps the same call at about $0.0024.
- After the call, Saro books the real cost from `usage`: input, output, cache reads and writes, and `usage.iterations` when a fallback ran. Each call's tokens and cost show in What Saro read and in Settings > Models.

Open question: the default daily spend cap (proposed US$2, about 20 worst-case Opus 5.5 calls).

### 11.6 Grounding

Quotes are verbatim by construction, whichever executor runs.

- Code builds up to 24 numbered candidate phrases per entry (ports of `extractPhrase`, ai.ts:338, and `firstSentence`). The model returns indexes; code copies the text with its field, UTF-16 span and `text_sha256`.
- Ported checks run at runtime: `quote_in_source` (prompts.py:271), `_check_observations` (:316), `check` (:334), `HISTORY_WORDS` (:44), `RELATIONSHIP_WORDS` (:49) and `BANNED_PHRASES` (evals/checks.py:20).
- The noun-and-entity drift check covers all model prose: titles, summaries, the narrative and questions. Every proper noun, number and person or relationship word must appear in the source.
- Every content noun, lemmatised with `NLTagger`, must appear in the source or in an allowlist of about 200 feeling and abstract nouns.
- The check must reject "the end of a long shift" (shift) and the Hinglish title "Thakawat aur asuvidha" (asuvidha). Invented relations between real nouns ("pushed through chai with Ravi") still pass.
- Narratives therefore stay at 1-2 sentences. A model narrative ships only if 90% or more of eval narratives pass the gate; otherwise a template built from the picked quotes ships.
- The phrase gate runs over all generated text.
- A grounding failure gets one retry on the same rung in a fresh session, with a one-line correction and without the previous output. A second failure drops a rung.

### 11.7 Sessions

Every model call is stateless: a fresh session, no shared transcript, one call at a time.

- One `actor SaroAI` exposes `generate<T: Generable>(...) async -> Outcome<T>`, where `Outcome` is `.ok(T, Generator)`, `.safetyHold`, `.technicalHold` or `.unavailable(Reason)`. It resolves the route, so callers never know the executor.
- On-device, each call opens a fresh `LanguageModelSession`. The context never grows, and `concurrentRequests` cannot happen.
- `prewarm(promptPrefix:)` runs when the recorder opens and when the inspector appears. A cold guided call measured 2.8 s against 1.2-1.7 s warm; the classifier 738 ms cold against 170 ms warm.
- Sampling is greedy for extraction, classification, the canary and evals; refreshes use `.random(top:seed:)`.
- Generation prefers the foreground. `rateLimited` defers work instead of failing it.
- A BYOK call is one Messages request with no conversation history, so the same rule holds. The 2026-10-21 API version rejects sampling settings, so bench cases on Claude run 3 times and report the spread.

### 11.8 Versioning and provenance

Every call leaves a content-free `ai_run` row, so any output traces back to the model, prompt and input windows that made it.

- `ai_run` records feature, executor (`on_device`, `pcc`, `byok`, `heuristic`), use case, guardrails, `ladder_rung`, `os_build`, `variant`, `model_fingerprint`, `context_size`, sampling, `prompt_version`, `schema_version`, `extractor_version`, `input_hash`, tokens in and out, latency and status.
- BYOK rows add the provider, the answering model, effort, cache tokens and cost.
- `ai_run_input` records exactly which entry fields and UTF-16 windows a call read. The consent screen's list of what is sent, and each "Sent to Anthropic" row in What Saro read, come from it.
- Caches are keyed by `prompt_version` plus `model_fingerprint`. `SAFETY_VERSION` versions the gate separately.
- A series is keyed by observation key and lineage: executor + variant + `model_fingerprint` + `extractor_version` + `prompt_version`. A BYOK fingerprint is the provider, the answering model and the API version.
- Changing a route therefore starts a new lineage. A model change is never read as the person changing, and heuristic output is its own series.

### 11.9 On-device canary

A canary on each new macOS build is Saro's only warning that Apple changed the model, because `SystemLanguageModel` exposes no version.

- On a new `os_build`, Saro runs about 20 synthetic risk and 20 venting cases through layer 2 (about 7 s). It also fingerprints a few fixed greedy extraction outputs and writes one `model_fingerprint` row.
- A missed risk case puts Saro in conservative mode. Classifier clears are not trusted, model-unavailable rules apply, and model readings and BYOK calls stop.
- A quiet banner then says "Saro is checking this macOS update". Conservative mode lifts when a later canary run passes, or when an app update lists that `os_build` as evaluated.
- A changed fingerprint starts a new lineage in the alpha; from P5, history is re-extracted into it, eval-gated. An unchanged fingerprint changes nothing.
- Canary texts are synthetic and never shown. BYOK models do not change with macOS, so they get no canary; the bench re-runs when a route's model changes.