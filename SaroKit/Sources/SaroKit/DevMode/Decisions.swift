import Foundation

/// One entry in the decision register: D-01…D-22 from BRD section 18 plus the build decisions (B-xx) taken overnight.
/// Bharat's choices live in the ledger as `DecisionEvent`s; the seed here is the baseline.
public struct Decision: Sendable, Hashable, Codable, Identifiable {
    public struct Option: Sendable, Hashable, Codable, Identifiable {
        public let id: String
        public let label: String
    }

    public enum Status: String, Sendable, Codable { case open, decided }

    public let id: String
    public let title: String
    public let context: String
    public let options: [Option]
    /// Option id.
    public let recommendation: String
    public let due: String
    public let status: Status
    /// Option id, set when the seed is already decided.
    public let decidedChoice: String?
    public let decidedOn: String?
    public let screens: [ScreenID]
    public let brdRefs: [String]

    init(_ id: String, _ title: String, _ context: String, options labels: [String], recommendation: String = "a", due: String,
         decided: String? = nil, screens: [ScreenID] = [], brd: [String] = []) {
        self.id = id
        self.title = title
        self.context = context
        options = zip("abcdefgh", labels).map { Option(id: String($0), label: $1) }
        self.recommendation = recommendation
        self.due = due
        status = decided == nil ? .open : .decided
        decidedChoice = decided
        decidedOn = decided == nil ? nil : "2026-10-27"
        self.screens = screens
        brdRefs = brd
    }

    public func option(_ id: String?) -> Option? { options.first { $0.id == id } }

    /// Bharat's current choice: the newest event with a choice (ledger order is append order), else the seeded decision.
    public func currentChoice(in events: [DecisionEvent]) -> String? {
        events.last { $0.decisionId == id && $0.choice != nil }?.choice ?? decidedChoice
    }

    public func currentStatus(in events: [DecisionEvent]) -> Status {
        currentChoice(in: events) == nil ? .open : .decided
    }

    public static let all: [Decision] = brd + build

    static let brd: [Decision] = [
        Decision("D-01", "Overall strategy for the Mac port",
                 "BRD recommends a ritual-first native alpha with the moat ledger underneath.",
                 options: ["Ritual-first", "Faithful port to parity first (about 40 weeks to an alpha)",
                           "Moat-first, engine before capture", "Hybrid React-in-WebView"],
                 due: "Mon 26 Oct 2026"),
        Decision("D-02", "Default capture mode on the Mac",
                 "BRD recommended voice first, with video and writing one click away. Decided 27 Oct 2026: video first; voice and writing one click away, every entry type first-class.",
                 options: ["Voice first", "Video first (as SARO-FJE-001 specified)", "Text first"],
                 due: "Fri 30 Oct 2026", decided: "b", screens: [.recorder, .capturePanel, .canvas], brd: ["FR-CAP-01", "FR-CAP-04"]),
        Decision("D-03", "Day surface for the alpha",
                 "BRD recommended an ordered day board now; week/month/year grid in P5; canvas, continuous lens and lit ground in P7. Decided 27 Oct 2026: free canvas from day one, with Spatial's mechanics (section 15).",
                 options: ["Ordered board", "Free-form canvas in the alpha (+6-7 weeks)"],
                 due: "Fri 30 Oct 2026", decided: "b", screens: [.canvas, .stack], brd: ["FR-DAY-01", "FR-DAY-08", "FR-CAN-06"]),
        Decision("D-04", "Local database",
                 "BRD recommends system SQLite with a small in-house wrapper.",
                 options: ["System SQLite", "GRDB 7 (saves about 2 days)", "SwiftData with a CloudKit-ready schema"],
                 due: "Mon 26 Oct 2026", brd: ["DR-01"]),
        Decision("D-05", "Privacy promise, Writing Tools and PCC",
                 "BRD recommended on-device only and no network entitlement in the alpha; Writing Tools off by default; request PCC this week. Decided 27 Oct 2026: on-device only (Apple SystemLanguageModel) for this build; Anthropic BYOK is the very next build.",
                 options: ["On-device only with PCC later as a named opt-in", "PCC for letters at the alpha", "Never PCC",
                           "On-device only; Anthropic BYOK next build"],
                 due: "Fri 30 Oct 2026", decided: "d", screens: [.settings, .writingDetail, .noticed], brd: ["FR-SET-03", "SR-43"]),
        Decision("D-06", "Fate of the web app and backend",
                 "BRD recommends freezing at ad4c7ed and retiring the backend; dump your own entries only if wanted; decide the importer in P5.",
                 options: ["Freeze and retire", "Same plus your entries and a P5 importer (0.75 dev-week)", "Keep both running"],
                 due: "Mon 26 Oct 2026"),
        Decision("D-07", "Distribution channel",
                 "BRD recommends TestFlight under the company with external testers; Developer ID only for Bharat's Mac.",
                 options: ["TestFlight", "Developer ID download for testers", "App Store Connect roles for testers"],
                 due: "Fri 30 Oct 2026", brd: ["FR-SET-07"]),
        Decision("D-08", "Alpha languages",
                 "BRD recommends English only.",
                 options: ["English only, with Hinglish covered by the safety layers", "Promise Hinglish AI quality"],
                 due: "Fri 20 Nov 2026", screens: [.recorder, .safetyCard, .settings], brd: ["SR-04"]),
        Decision("D-09", "AI ladder order",
                 "BRD recommends permissive JSON first; flip to guided-first if Spike B shows worse parsing or grounding.",
                 options: ["Permissive JSON first", "Guided first with no permissive re-ask", "Guided first with a permissive re-ask"],
                 due: "Fri 20 Nov 2026", screens: [.noticed], brd: ["FR-REF-02", "SR-10"]),
        Decision("D-10", "Safety bar, day rule and overrides",
                 "BRD recommends recall first, whole-day rule for safety holds, no override; above 5% SafetyCards, accept up to 10% for Alpha-0.",
                 options: ["Recall first, no override", "An 'I'm okay, figure of speech' override", "Per-entry scope"],
                 due: "Fri 20 Nov 2026", screens: [.safetyCard], brd: ["SR-13", "SR-25", "SR-30"]),
        Decision("D-11", "Display when Apple Intelligence is unavailable",
                 "BRD recommends a labelled 'In your words' quote-back under the caution rule.",
                 options: ["Quote-back under the caution rule", "Only 'Saro didn't write about this one' with Retry"],
                 due: "Fri 20 Nov 2026", screens: [.noticed, .safetyCard], brd: ["FR-SAF-09"]),
        Decision("D-12", "Alpha scope against the date",
                 "BRD recommends keeping full scope, and cutting in the fixed order only on a slip.",
                 options: ["Full scope (alpha at dev week 23)",
                           "Move video, still captions and the Touch ID lock to v1 now (alpha about dev week 21-22)"],
                 due: "Fri 20 Nov 2026"),
        Decision("D-13", "Model-written day narrative in the alpha",
                 "BRD recommends eval-gated: ship it only if 90% of eval narratives pass grounding.",
                 options: ["Eval-gated", "Always template", "Always model prose"],
                 due: "Fri 12 Mar 2027", screens: [.noticed, .letter], brd: ["FR-REF-04", "FR-REF-08"]),
        Decision("D-14", "Default video quality",
                 "BRD recommended 1080p HEVC at about 2.5 Mbps with a 720p Space saver. Decided 27 Oct 2026: 720p by default, with a 1080p option in Settings.",
                 options: ["1080p with Space saver", "720p default"],
                 due: "Fri 2 Apr 2027", decided: "b", screens: [.recorder, .settings], brd: ["FR-CAP-04"]),
        Decision("D-15", "History when Apple updates the model",
                 "BRD recommends fingerprint boundaries in the alpha; eval-gated re-extraction from P5.",
                 options: ["Boundaries then re-extraction", "Always re-extract everything", "Freeze old observations"],
                 due: "Fri 16 Apr 2027", screens: [.noticed], brd: ["FR-MEM-07", "FR-MEM-10"]),
        Decision("D-16", "Next after the alpha: iPhone or canvas",
                 "BRD recommends a written rule with the iPhone as default: iPhone next if under 50% of active testers reach 3+ sessions in 7 days, or testers ask for mobile capture.",
                 options: ["Written rule", "Canvas regardless", "Mac only for v1"],
                 due: "Fri 21 May 2027; thresholds by Fri 2 Apr 2027"),
        Decision("D-17", "Business model and App Store timing",
                 "BRD recommends a free alpha, then App Store 1.0 as a free core plus Saro+ (iPhone, sync, PCC).",
                 options: ["Free core plus Saro+", "An earlier free Mac 1.0 after P5", "Paid upfront"],
                 due: "Fri 21 May 2027", brd: ["FR-SET-09"]),
        Decision("D-18", "Team size",
                 "BRD recommends one developer to the alpha; decide a second at the iPhone-or-canvas call.",
                 options: ["One developer (iPhone parity about dev week 56)", "A contract developer from the call (about dev week 47)"],
                 due: "Fri 21 May 2027"),
        Decision("D-19", "BYOK in the public app",
                 "BRD recommends keeping the public app offline for App Store 1.0; BYOK stays in Saro Lab. The network entitlement is per app, so BYOK in the public app makes 'Saro has no way online' false for every user, not only those who add a key. Revisit (b) only if the bench shows Claude day readings passing the 90% narrative gate while on-device fails it, and PCC is still unavailable.",
                 options: ["Lab only",
                           "Opt-in BYOK in the public app (network entitlement for every user, privacy line rewritten, 5.1.2(i) consent)",
                           "A separate public Lab app"],
                 due: "Fri 21 May 2027", screens: [.settings], brd: ["SR-43", "DR-23"]),
        Decision("D-20", "Default Claude model for BYOK routes",
                 "BRD recommends claude-opus-5-5 (Claude Opus 5.5, $4 / $20 per million input / output tokens), confirmed by the bench. Quality of listening is the core job and the founder's volume is small; the bench can still show Sonnet 5.5 or Haiku 5.5 matching it on a given touchpoint. Each route can still pick its own.",
                 options: ["Opus 5.5", "Sonnet 5.5 ($2 / $10)", "Haiku 5.5 ($0.10 / $0.50, no server-side fallback)"],
                 due: "Fri 18 Dec 2026 (Lab-1 readout)", screens: [.settings], brd: ["SR-39"]),
        Decision("D-21", "When Saro Lab gets BYOK routes (Lab-2, 1.0 dev-week)",
                 "BRD recommends after the Fri 21 May 2027 call: the bench answers 'how does Claude compare' first, and daily journaling through Claude can wait until the habit data is in. D-21 protects the alpha path.",
                 options: ["After the call (later dates move about 1 week, or none with a second developer)",
                           "In P2 from its 0.9 buffer", "Never, bench only"],
                 due: "Fri 22 Jan 2027 (end of P1)"),
        Decision("D-22", "Who owns the Claude executor",
                 "BRD recommends Saro's own executor on URLSession, about 300 lines, built for the bench: it keeps every byte sent to Anthropic under Saro's own tests (current API version, explicit refusals, exact cost, an auditable request body) with no dependency.",
                 options: ["Saro's own executor", "Anthropic's ClaudeForFoundationModels package (beta)",
                           "The package for the synthetic bench, then Saro's executor before any journal text is sent"],
                 due: "Fri 20 Nov 2026 (P0 review)"),
    ]

    /// Decisions the overnight build took on its own. Option a is what the build did.
    static let build: [Decision] = [
        Decision("B-01", "Bundle id",
                 "Why: the dogfood build needed an id tonight; com.saro.dogfood keeps it apart from any future company id.",
                 options: ["com.saro.dogfood", "com.iinc.saro", "Separate Dev/Lab ids later"],
                 due: "Wed 28 Oct 2026", screens: [.settings], brd: ["DR-23"]),
        Decision("B-02", "Signing team",
                 "Why: automatic signing only works with the certificate's actual Team ID (its OU), not the id in the certificate name.",
                 options: ["P6SP5RHNLV (the certificate's actual Team ID/OU)",
                           "W6F77BC8KN (the id in the certificate name, which the brief called the team; automatic signing can't use it)"],
                 due: "Wed 28 Oct 2026"),
        Decision("B-03", "Fonts",
                 "Why: matching the web overnight build. Geist (WOFF2) for the UI and your words, Geist Mono for times and labels, Newsreader (OFL, bundled from the local font install) for Saro's voice.",
                 options: ["Bundled Geist, Geist Mono and Newsreader, as on the web", "Geist with New York as the serif voice", "SF only"],
                 due: "Wed 28 Oct 2026", screens: [.canvas, .letter]),
        Decision("B-04", "Canvas engine",
                 "Why: a pure SwiftUI canvas keeps the card-to-detail flight in one hierarchy (a log-space morph like the web's morph.ts); trackpad scroll and pinch come from an event monitor.",
                 options: ["Pure SwiftUI canvas with scroll/pinch from an event monitor", "AppKit NSScrollView host with SwiftUI cards (BRD suggestion)"],
                 due: "Wed 28 Oct 2026", screens: [.canvas], brd: ["FR-CAN-06"]),
        Decision("B-05", "Card gestures",
                 "Why: the web build has no press-and-hold: a tap opens, a 4 pt slop starts a drag (lift 1.02, tilt with velocity, a glide on release), ⌘/⇧-click selects. Marquee on empty canvas is kept from the BRD (FR-CAN-06), though the web has none.",
                 options: ["As the web: click opens, ⌘/⇧-click selects, drag after 4 pt, plus marquee on empty canvas", "Click selects, double-click opens, press-and-hold ~120 ms before a drag", "As the web, without marquee"],
                 due: "Wed 28 Oct 2026", screens: [.canvas, .stack], brd: ["FR-CAN-01", "FR-CAN-06"]),
        Decision("B-06", "Recording turns",
                 "Why: a new file per turn means a crash loses at most the current turn, and each turn is its own entry in the session's stack.",
                 options: ["Each pause stops the file and resume starts a new one (one entry per turn, stacked as a session)",
                           "One file per session with pauseRecording"],
                 due: "Wed 28 Oct 2026", screens: [.recorder, .stack, .momentDetail], brd: ["FR-CAP-04", "FR-CAN-03", "DR-11"]),
        Decision("B-07", "Voice note turns",
                 "Why: one recording mechanism for both kinds; a paused voice note behaves like a paused moment.",
                 options: ["Voice notes use the same turn mechanism (a paused voice note becomes a stack)", "Voice notes are always one file"],
                 due: "Wed 28 Oct 2026", screens: [.recorder, .voiceDetail], brd: ["FR-CAP-01"]),
        Decision("B-08", "Safety classifier in the dogfood build",
                 "Why: the on-device probe scored 11/13 and caught all 4 risk cases; the BRD planned the model-unavailable rule for P1 dogfood.",
                 options: ["Classifier on in this dogfood build (probe: 11/13, all 4 risks caught)", "Model-unavailable rule for P1 dogfood as the BRD planned"],
                 due: "Wed 28 Oct 2026", screens: [.safetyCard], brd: ["SR-07", "SR-21"]),
        Decision("B-09", "Hinglish and Devanagari phrase list",
                 "Why: Bharat journals in Hinglish; shipping the list as a draft catches more than English alone, but no clinician has reviewed it (SR-32).",
                 options: ["Ship it marked DRAFT pending clinician review", "English-only phrase list until review"],
                 due: "Wed 28 Oct 2026", screens: [.safetyCard], brd: ["SR-04", "SR-32"]),
        Decision("B-10", "On-device canary and conservative mode",
                 "Why: the canary needs a synthetic corpus that doesn't exist yet; v0 defers SR-22.",
                 options: ["No canary or conservative mode in v0 (SR-22 deferred)", "Build the canary now"],
                 due: "Wed 28 Oct 2026", screens: [.safetyCard], brd: ["SR-22", "SR-23", "FR-SAF-11"]),
        Decision("B-11", "Evening letter",
                 "Why: the BRD's alpha has no model-written letter prose; typesetting from the verified reading keeps every line grounded.",
                 options: ["Non-generative, typeset from the verified day reading", "On-device model prose letter"],
                 due: "Wed 28 Oct 2026", screens: [.letter], brd: ["FR-REF-08"]),
        Decision("B-12", "Transcription locale",
                 "Why: follow the Mac's language when SpeechTranscriber supports it, with a safe fallback.",
                 options: ["System locale if SpeechTranscriber supports it, else en-US", "Always en-US", "en-IN"],
                 due: "Wed 28 Oct 2026", screens: [.recorder, .momentDetail, .voiceDetail], brd: ["FR-CAP-06"]),
        Decision("B-13", "Decisions export",
                 "Why: the sandbox grants a folder chosen in an open panel, so both files land together in one step.",
                 options: ["Both files into a folder chosen in an open panel", "One combined file via a save panel"],
                 due: "Wed 28 Oct 2026", screens: [.decisions]),
        Decision("B-14", "Mood labels",
                 "Why: the web app's 12 labels keep moods continuous with Bharat's existing journal.",
                 options: ["The web app's 12-label catalogue", "The probe's 6 (heavy … bright)"],
                 due: "Wed 28 Oct 2026", screens: [.noticed], brd: ["FR-REF-01"]),
        Decision("B-15", "Where the repo lives",
                 "Why: the repo sits on the iCloud-synced Desktop, whose Finder xattrs make codesign fail for anything built inside it. Tonight every build goes to ~/Library (make build, make test).",
                 options: ["Keep it on the Desktop; build products stay in ~/Library", "Move the repo off iCloud (e.g. ~/Developer/saro-mac)"],
                 due: "Wed 28 Oct 2026", screens: [.settings], brd: []),
        Decision("B-16", "Empty pages",
                 "Why: pressing Write and closing without typing shouldn't leave an empty card or fill the Trash.",
                 options: ["Discard a page that was never written (no text, no media, nothing derived)", "Keep it as an empty card", "Send it to Trash"],
                 due: "Wed 28 Oct 2026", screens: [.writingDetail], brd: ["DR-15"]),
        Decision("B-17", "Day reading inputs",
                 "Why: the probe's one structured call over a raw day failed in 215 ms; the day call sees only per-entry annotations plus up to 6 numbered verbatim candidates per entry.",
                 options: ["Map-reduce over stored annotations, 6 candidates per entry", "Map-reduce with all 24 candidates per entry", "One call over raw day text"],
                 due: "Wed 28 Oct 2026", screens: [.noticed], brd: ["FR-REF-01", "SR-13"]),
        Decision("B-18", "Day and night palette",
                 "Why: the web build follows the clock (night 20:00-06:00) with a 1.4 s crossfade; Settings > Appearance can follow the system or pin light or dark.",
                 options: ["Follow the clock, as the web", "Follow the system appearance", "Always light"],
                 due: "Wed 28 Oct 2026", screens: [.canvas, .settings]),
        Decision("B-19", "Window chrome",
                 "Why: the web canvas is full-bleed with floating chrome (Monolith and search top-left, the insight spine right, one glass bar below). The title bar is hidden and the days sidebar folds away; History or ⌃⌘S opens it.",
                 options: ["Full-bleed canvas, sidebar folded by default", "Sidebar always shown, standard title bar"],
                 due: "Wed 28 Oct 2026", screens: [.canvas, .sidebar]),
        Decision("B-20", "Voice notes start",
                 "Why: the web voice pill starts recording as soon as it opens; tonight's pill waits for Space or Record so a stray ⇧⌘N doesn't record.",
                 options: ["Wait for Space or Record", "Start recording when the pill opens, as the web"],
                 due: "Wed 28 Oct 2026", screens: [.recorder]),
    ]
}
