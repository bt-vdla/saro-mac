## 7. Business requirements

Saro for Mac has 14 business requirements: 12 are Must for the alpha, 1 is Should for App Store 1.0 and 1 is Could. Priority is MoSCoW against the alpha: Must (alpha), Should (App Store 1.0), Could (later), Won't (cut on purpose). BR-14 is Could for the public app; the founder-only Saro Lab build carries it earlier (section 12).

| ID | Requirement | Rationale | Priority |
|---|---|---|---|
| BR-01 | Replace the web app with a native macOS 27 app for Apple silicon, built in Swift 6.4 and SwiftUI, with no Saro server. | Retiring Supabase and OpenAI ends spend and closes the web backend's security backlog. Zero server cost keeps a one-time price or a generous free tier possible. | Must |
| BR-02 | Answer one alpha question: will people keep a journaling habit on a Mac? The test is 3 or more sessions in a tester's first 7 days. | A session is a local day with a saved entry. The habit numbers decide the iPhone-or-canvas call on Fri 21 May 2027. | Must |
| BR-03 | Put Alpha-0 (Bharat plus 4 external testers, voice and writing) on TestFlight by Fri 2 Apr 2027. Ship the alpha (15-30 testers, adding video) by Fri 16 Apr 2027. | The alpha range is dev weeks 21-27, Fri 2 Apr to Fri 14 May 2027. The decision needs at least 3 weeks of alpha data. | Must |
| BR-04 | Make voice the default and let people capture from any app on the Mac. | Talking to Saro is the product. Voice has no camera friction at a desk and uses about 0.5 MB per minute against about 20 MB for video. | Must |
| BR-05 | Keep every journal word on the Mac in the alpha: no network entitlement, and Apple's on-device model as the only AI. | "Saro never sends your words anywhere" must be provable from the sandbox, not only stated. | Must |
| BR-06 | Never invent content: every quote is verbatim, and all model prose passes a grounding check. | One made-up quote breaks trust in a reflection app. The on-device probe showed drift that quote checks alone miss. | Must |
| BR-07 | Answer self-harm text with crisis resources, never an AI reflection, and get clinician sign-off before any non-founder user. | No moderation model runs on device. A missed risk could put an AI reflection on a crisis entry. | Must |
| BR-08 | Never lose a recording, and let people export, import and erase everything. | People won't build a habit on a journal they can't trust to keep, or to delete, their words. | Must |
| BR-09 | Record the self-model ledger from the first entry: append-only, with provenance for every derived row. | The longitudinal self-model is the moat. Diff/timeline engine v0 must run on alpha data by Fri 7 May 2027. | Must |
| BR-10 | Show people what Saro has learned about them, and let them correct, pause or forget it. | A ledger about a person is only acceptable if that person can see and control it. | Must |
| BR-11 | Stay useful and honest when Apple Intelligence is unavailable, and when a macOS update changes the model. | Work Macs with Apple Intelligence turned off, pending downloads and unsupported locales are common. A model change must never read as the person changing. | Must |
| BR-12 | Be accessible from the alpha: VoiceOver, full keyboard use and an in-app text size. | The web app never had a screen-reader pass. Retrofitting access later costs more than building it in. | Must |
| BR-13 | Reach Mac parity and App Store 1.0 with a business model, about Fri 24 Sep 2027 if the canvas goes first. | The suggested default is a free core plus Saro+ for the iPhone app, sync and PCC. The model is chosen on Fri 21 May 2027. | Should |
| BR-14 | Let the founder route AI work to his own model keys, Claude first, and compare the results with Apple on-device. | A side-by-side bench shows where on-device quality falls short. Whether the public app carries BYOK is decision D-19. | Could |

The alpha succeeds when BR-02 gets a clear answer from at least the minimum number of active testers. Bharat writes down that minimum, the habit thresholds and their definitions by Fri 2 Apr 2027.
