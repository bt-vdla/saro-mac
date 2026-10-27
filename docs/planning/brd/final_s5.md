## 6. Stakeholders and personas

Saro's alpha serves one founder, one developer, one clinician and up to 30 testers, and it must pass Apple's review.

### 6.1 Stakeholders

Bharat decides; the developer builds; the clinician signs off safety; Apple controls distribution.

| Stakeholder | Role | What they need | What they give or decide | Key dates |
|---|---|---|---|---|
| Bharat (founder, I Inc., India) | Product owner and first user | A daily journal he trusts; data for the post-alpha calls; a model bench | Every D-nn decision; about 60 labelled extraction cases and 60 safety smoke cases; tester recruiting; copy review; 3-6 hours a week | Day-1 decisions Mon 26 Oct 2026; journals daily from Fri 18 Dec 2026; iPhone-or-canvas call Fri 21 May 2027 |
| Swift/AppKit developer (one, full-time) | Builds and ships the app | Decisions on time; Bharat's recordings and labels | Spikes, the app, CI, TestFlight builds | Spike readout Fri 6 Nov 2026; P0 review Fri 20 Nov 2026 |
| Clinician (paid, external, ideally Hindi-speaking) | Safety reviewer | The phrase list, caution lexicon, classifier definitions, SafetyCard and hold copy, and crisis list | Sign-off before any non-founder user; weekly triage of 'Saro got this wrong' reports with Bharat | Booked by Fri 20 Nov 2026; sign-off by Fri 12 Mar 2027 |
| Alpha-0 testers (4, external) | First outside users, on macOS 27 with Apple Intelligence on | A private ritual that works; Export before a build expires | Daily use for 3 weeks; the weekly Alpha report pasted into the survey | From Fri 2 Apr 2027 |
| Alpha testers (15-30) | The habit cohort | The same | The same, plus the week-1 habit data | From Fri 16 Apr 2027 |
| Apple | Platform owner and reviewer | A legal entity for a sensitive-data app; honest review notes | Developer enrollment and D-U-N-S; Beta App Review; answers on guidelines 5.1.2(i) and 5.1.3(ii); the PCC entitlement | Enrollment before Mon 15 Mar 2027; Beta App Review submitted Mon 15 Mar 2027, 18 days before Alpha-0; App Review inquiry by Fri 7 May 2027 |
| Anthropic | First BYOK provider | Valid requests from the key's owner | Claude through the Messages API, billed to the key's owner | Saro Lab only, until D-19 on Fri 21 May 2027 |
| Second developer (contract, possible) | Takes the track the habit rule doesn't put first | A stable ledger and codebase | Parallel iPhone or canvas work | Decided Fri 21 May 2027; starts dev week 30 (Mon 31 May 2027) |
| Anyone with real web data | Existing account holder | Their data before deletion | An export via GET /api/account/export | Checked Mon 26 Oct 2026; none expected |

### 6.2 Mac journaling contexts

The Mac covers the desk, the evening and capture from any app, and the alpha measures what it misses away from the Mac.

| Context | When and where | Capture path | What Saro does |
|---|---|---|---|
| Desk | The workday at a laptop or desktop, often in a shared room, an open office or on a work Mac | Ctrl-Cmd-J voice pill or a typed note from inside another app | Voice or text by default; Touch ID lock; content-free notifications; no screen-share promise until tested |
| Evening | When the day goes quiet (onboarding Q3), often a laptop on the sofa | The main window: voice, video or writing, with checkpoints | Reflect deeper, What Saro noticed, the evening letter, and a reminder at the user's quiet time |
| Capture from anywhere | Any app, whenever the Mac is open | Menu bar extra, Ctrl-Cmd-J (recording in under 2 s), floating pill, paste and drop | Files the entry under today or the viewed day; gates and reads it at save |
| Away from the Mac | Walks, the car, bed | None in the alpha | The habit metric measures the cost; the iPhone companion is the default next step |

### 6.3 Personas

The evening unloader is the primary persona, and the other three test the edges of the promise.

| Persona | Context | Job (JTBD) | What Saro must do | What breaks trust |
|---|---|---|---|---|
| The evening unloader (primary) | Works on a MacBook all day; journals for a few minutes when the day goes quiet, mostly by voice | 'I want a safe place to unload my thoughts without judgment.' | Voice first; one grounded follow-up; a reading that quotes their own words; a typeset evening letter; a reminder at their quiet time | Generic or invented reflections; nagging; a lost recording |
| The between-meetings capturer | Knowledge worker on an MDM-managed work Mac in an open office; shares the screen often | 'I want to express what I feel right now, quickly and privately.' | Ctrl-Cmd-J from any app; a short voice note or a typed line; Touch ID lock; content-free notifications; honest copy on employer backups; the model-unavailable path if MDM turns Apple Intelligence off | Journal text visible during a screen share; words in a notification preview |
| The cautious first-timer | New to journaling and wary of apps with their data; may speak Indian English with Hindi mixed in | 'I want to know my data is private and safe before I open up.' | No account; the three-line privacy promise; a first entry within 180 s, even while the model downloads; honest English-only copy; crisis lines for their region (Tele-MANAS 14416 in India) | A sign-up wall; wrong quotes of their speech; a SafetyCard on a figure of speech |
| The founder-tester (Bharat) | Journals daily on an M5 from Fri 18 Dec 2026; runs Saro Lab with his own Claude key | Choose model routes and the post-alpha calls from measured data | Every new build reads his journal back; the model bench; cost per call and a daily spend cap; content-free logs | Entries lost across builds; BYOK code or the network entitlement leaking into the TestFlight build |