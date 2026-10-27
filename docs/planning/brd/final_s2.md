## 3. Background and problem

Saro today is a web app whose live captions and reflect-deeper are broken, and whose backend is not safe for a real user.

### 3.1 What exists today

The web app is frozen at commit ad4c7ed, and its offline demo becomes the blueprint for the Mac app.

| Part | What it is today | Fate in this plan |
|---|---|---|
| Web frontend | Next.js, about 47k non-test TS/TSX lines. Canvas.tsx is 2,654 lines and VideoReflectionScreen.tsx 1,735 | Frozen at ad4c7ed (branch overnight/mvp-hardening) as the reference |
| Backend | FastAPI on Supabase: Postgres, Auth, 3 storage buckets, 9 never-applied migrations, a cleanup-trash edge function | Retired. prompts.py, safety.py, schemas.py, checks.py and the 25 eval cases stay in git as specs |
| Cloud AI | OpenAI gpt-5-mini for insights and still captions, gpt-transcribe and omni-moderation; a cap of 200 calls per user per day | Key revoked; replaced by Apple's on-device models |
| Offline demo | frontend/lib/demo/*, about 3.9k non-test lines plus tests. Every feature runs in the browser with no server | Ported to Swift as the heuristic twin and the test oracle |
| Product docs | Goals and JTBD (9 areas), the Sep and Oct 2025 stories, the Jan 2026 roadmap, the Aug 2025 Blitzy spec | Source of the goals and personas in this BRD |

The demo already runs every feature, with the same function signatures as the real services. Its Swift port gives the Mac app a no-AI floor and a set of test vectors at once. The plan assumes no real user besides Bharat, and a Supabase count query confirms it on Mon 26 Oct 2026.

The Mac plan returns Saro to its first spec. The Sep 2025 stories asked for local-first storage (SARO-ONB-001) and on-device transcription (SARO-FJE-005). The Jan 2026 roadmap already listed a migration plan to SwiftUI.

### 3.2 What is broken

Seven problems block real use of the web app, and the native app removes all seven.

| Problem | Cause | Effect on the user | Fixed on the Mac by |
|---|---|---|---|
| Live captions | OpenAI's Realtime beta was removed on 12 May 2026; gpt-4o-mini-transcribe shuts down on 26 Feb 2027 | Real accounts see no words while they speak | SpeechTranscriber on the capture session, on-device |
| Reflect-deeper | The checkpoint reads the dead live captions (VideoReflectionScreen.tsx:1142) | Real accounts get a generic follow-up, so the 'be listened to' job fails | Live on-device text at every checkpoint |
| Security backlog (HANDOFF section 4) | Key rotation (N01), open sign-ups (N05), RLS never applied (N07), Logfire purge (C2), cleanup-trash (H6) | The leaked April anon key can reach every table, so no real user can be invited | No server: deleting the Supabase project closes all five |
| Crash-safe recording (T14) | Recordings are held in memory until upload | Closing the tab mid-take loses the part | AVFoundation writes 2 s movie fragments to disk |
| Upload caps | 5 MB voice notes (about 10 min at 64 kbps), 10 MB stills, iPhone HEIC rejected | Long voice notes never upload | Local files; nothing uploads |
| Overwritten history | cached_insights is overwritten once per day | The diff engine loses the history it needs | Append-only insight_snapshot rows |
| Privacy copy | PROMISES[0] must disclose that words, audio and photos go to OpenAI | Trust fails on the welcome screen | A promise the sandbox enforces |

### 3.3 Why native Mac and Apple Intelligence

On-device AI makes the privacy promise provable and takes Saro's server cost to zero.

- **Provable privacy.** The alpha build has no network entitlement, and CI checks the signed entitlements on every build.
- **Zero marginal cost.** No OpenAI, Supabase or Logfire spend, and no per-user AI cap.
- **Both AI bugs fixed.** On-device Speech gives live captions and text at every checkpoint.
- **Nothing lost.** Recordings are written to disk as they happen, so a crash leaves a playable file.
- **Capture from anywhere.** A global hotkey and a menu bar extra replace a browser tab that had to be open.

The trade-off is reach and context. Mac users are fewer than iPhone users, and a desk is not where most people unload. The alpha tests this directly through the week-1 habit metric instead of assuming it.

### 3.4 What the probe measured

A probe on Bharat's M5 (macOS 27.0.1, 25 Oct 2026) shows the on-device model works when Saro is built around its limits.

| Test | Result | Design response |
|---|---|---|
| Model and context | AFM 3 Core Advanced; 8,192 tokens; vision, guided generation and tool calling yes, reasoning no | Budget every prompt at runtime; plan for 4,096 on Macs that get AFM 3 Core until measured |
| Locales | en_IN supported; hi_IN not supported | English-only alpha; Hinglish covered by the safety phrase list |
| Token rate | 10,260 characters = 2,494 tokens (about 4.1 per token) | A heavy 5-minute part (about 1,000 tokens) fits even in 4,096 |
| Structured extraction, default guardrails | 8 of 10 entries OK; 2 guardrail errors (explicit self-harm; 'punch the screen'); 1.2-1.7 s each | Guided output becomes the fallback rung, not the first |
| Permissive text output | 10 of 10 OK at 0.5-0.8 s; line format failed grounding 4 of 10 | Permissive JSON first, only on gate-cleared entries |
| Day-level structured call | Guardrail error in 215 ms on a 5-entry day | Read each entry at save; code composes the day |
| Permissive JSON on the day call | OK in 2.8 s; quotes verbatim; small narrative drift ('the end of a long shift') | Quotes by index, plus a noun-and-entity drift check on narratives |
| Naive RISK/NONE classifier | Flagged 9 of 10 entries, including grief and anger | Never used |
| Graded classifier (NONE / PASSIVE / ACTIVE) | 11 of 13 correct at about 170 ms; caught 4 of 4 risks, including Hinglish 'main mar jaun'; 2 idiom false positives | Layer 2 of the safety gate, tuned with few-shot idioms |
| Streamed evening letter | First token 349 ms, 2.2 s total; mostly a pronoun-swapped echo | Letters typeset from the reading, never free prose |
| Private Cloud Compute | Available, 32,768 tokens, quota below limit; a request failed with ModelManagerError 1046 | Not used until Apple grants the entitlement |

### 3.5 Why add BYOK now

BYOK lets Bharat measure the on-device quality gap against Claude today, while PCC stays blocked. He asked for it on Mon 26 Oct 2026, with Claude as the first model to test. The probe shows on-device models extract, classify and ask questions well but write weak letters.

A model bench runs the same eval cases on both and compares them side by side. BYOK stays off the alpha's default path, because its network entitlement would break the promise that Saro has no way online.