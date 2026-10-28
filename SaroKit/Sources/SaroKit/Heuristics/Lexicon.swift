import Foundation

/// Lexicon themes (THEME_WORDS in `saro/frontend/lib/demo/ai.ts`).
public enum Theme: String, Sendable, Hashable, CaseIterable {
    case work, family, sleep, health, creativity, relationships, money, purpose, nature, learning
}

/// Word lists ported from `ai.ts`, `prompts.py` and `evals/checks.py`.
enum Lexicon {
    static let emotionWords: [Mood: String] = [
        .calm: "calm calmer calmest peaceful peace quiet quieter stillness settled relaxed relax relaxing ease eased easy gentle slow slower serene content rested unhurried exhaled relief relieved",
        .reflective: "reflective reflecting reflect wonder wondering wondered realise realised realize realized noticed noticing ponder pondering remember remembered remembering thoughtful",
        .grateful: "grateful gratitude thankful thanks lucky appreciate appreciated blessed glad happy happier joy joyful smiled smiling laughed laughing",
        .frustrated: "frustrated frustrating frustration annoyed annoying angry mad irritated irritating stuck ugh furious resentful blocked",
        .tender: "tender soft miss missed missing love loved loving hug hugged cried cry crying tears vulnerable raw sad sadness lonely heartfelt",
        .anxious: "anxious anxiety worried worry worrying nervous stress stressed stressful panic panicky dread uneasy restless overthinking scared afraid fear tense wired spiral spiralling spiraling",
        .energised: "energised energized energy excited exciting pumped buzzing alive strong motivated proud unstoppable brilliant thrilled",
        .neutral: "fine ordinary usual normal routine meh",
        .bittersweet: "bittersweet nostalgic nostalgia wistful goodbye farewell",
        .surprised: "surprised surprising unexpected unexpectedly suddenly shocked wow",
        .overwhelmed: "overwhelmed overwhelming swamped drowning exhausting burnout frazzled chaotic chaos heavy heavier fed_up too_much burnt_out burned_out",
        .inspired: "inspired inspiring inspiration clarity spark ideas vision hopeful hope curious possibility",
    ]

    static let themeWords: [Theme: String] = [
        .work: "work working worked job jobs office meeting meetings boss manager team teams deadline deadlines launch launched launching project projects client clients colleague colleagues coworker coworkers email emails inbox presentation career standup sprint slack retro promotion interview shipped shipping checklist",
        .family: "family mum mom mother dad father parents parent sister sisters brother brothers sibling siblings son daughter kids children grandma grandmother grandpa grandfather aunt uncle cousin nephew niece",
        .sleep: "sleep sleeping slept asleep insomnia awake bed bedtime nap napping rested restful tired exhausted dream dreams dreaming 3am alarm woke wake waking",
        .health: "run running runner runs jog jogging workout gym exercise exercising body health healthy doctor sick ill headache yoga stretch stretching legs knee steps 3k 5k 8k 10k marathon kilometres kilometers miles swim swimming cycling bike breathing",
        .creativity: "write writing wrote draw drawing paint painting guitar piano sing singing design designing create creating creative craft photo photos camera poem poetry story sketch sketching",
        .relationships: "friend friends friendship partner boyfriend girlfriend husband wife dating relationship lonely together conversation conversations call called calling texted laugh",
        .money: "money rent bills bill budget salary pay paid payday savings saving debt spend spent spending expensive cost costs afford loan bank",
        .purpose: "purpose meaning meaningful direction future goal goals values calling mission legacy",
        .nature: "outside outdoors park tree trees sky sun sunlight sunset sunrise rain garden walk walked walking ocean sea beach river path mountain mountains birds leaves weather",
        .learning: "learn learning learned learnt read reading book books course class study studying practice skill skills lesson lessons teacher podcast",
    ]

    /// Later keys win on a shared word, as in `buildIndex`; both are walked in catalogue order.
    static let emotionIndex = buildIndex(emotionWords, order: Mood.allCases)
    static let themeIndex = buildIndex(themeWords, order: Theme.allCases)

    private static func buildIndex<L: Hashable>(_ words: [L: String], order: [L]) -> [String: L] {
        var index: [String: L] = [:]
        for label in order {
            for w in words[label, default: ""].split(separator: " ") { index[w.replacingOccurrences(of: "_", with: " ")] = label }
        }
        return index
    }

    static let stop = Set((
        "a about above after again against all almost also am an and any are around as at away back be because been before being " +
        "below between both but by can could did do does doing done down during each else even ever every few for from further get " +
        "gets getting go goes going gone got had has have having he her here hers herself him himself his how however i if in into is " +
        "it its itself just keep kept know knew let like lot lots made make makes making many maybe me might mine more most much must " +
        "my myself never no nor not now of off on once only onto or other our ours ourselves out over own quite rather really said same " +
        "say says see seem seemed she should since so some something somehow still such than that the their theirs them themselves then " +
        "there these they thing things think thinking thought this those though through thus to too took under until up upon us very was " +
        "way we well went were what whatever when where whether which while who whom whose why will with within without would yet you " +
        "your yours yourself i'm i've i'd i'll it's that's there's what's don't didn't doesn't isn't wasn't aren't weren't can't couldn't " +
        "won't wouldn't shouldn't haven't hasn't hadn't let's you're you've we're we've they're they've he's she's " +
        "um uh er okay ok yeah yes honestly basically actually literally kinda sorta gonna wanna gotta stuff bit " +
        "today tonight tomorrow yesterday day days week weeks time times morning evening night nights afternoon last next new good great " +
        "little big long feel feels felt feeling want wanted wants need needed needs try trying tried come came coming take taking give " +
        "gave put none one two three four five six seven eight nine ten twenty first second third once twice hour hours minute minutes " +
        "probably instead everything nothing anything everyone someone anyone finally again part being enough whole else"
    ).split(separator: " ").map(String.init))

    static let negators = Set("not no never nothing don't didn't doesn't isn't wasn't aren't weren't can't couldn't won't wouldn't hardly barely without".split(separator: " ").map(String.init))
    static let commonCaps = Set("monday tuesday wednesday thursday friday saturday sunday january february march april june july august september october november december".split(separator: " ").map(String.init))
    static let leadingFiller = Set("and but so or then also because cause um uh er like well okay ok honestly basically actually anyway yeah yes just really plus probably".split(separator: " ").map(String.init))
    /// Only stripped where a clause was cut short, never from a clause's natural end.
    static let trailingDangle = Set(("a an the and but or so to of for with at in on by from than that when while because as if i my your his her their our its " +
        "she he they we it is was were be been am are just really very all this these those through into about up").split(separator: " ").map(String.init))
    static let leadingDangle = Set("of to at in on for with by from than that".split(separator: " ").map(String.init))
    static let subjectStart = Set("i i'm i've i'd we my she he they it the our her his their you".split(separator: " ").map(String.init))
    static let lowValue = Set("the a an really very just actually literally".split(separator: " ").map(String.init))
    static let hedges = ["i think", "i guess", "i mean", "you know", "kind of", "sort of", "i feel like", "to be honest"].map { $0.split(separator: " ").map(String.init) }

    /// QUESTION_LIBRARY in `ai.ts`.
    static let questions: [Theme?: [String]] = [
        .work: [
            "What part of your work felt like yours, not just assigned to you?",
            "If work took up less room tomorrow, what would you put in the space?",
            "What would 'enough' look like at work this week?",
            "Which piece of work are you carrying home that could stay at your desk?",
            "Who at work would you like to thank, and for what?",
        ],
        .family: [
            "What do you want the people at home to know about your week?",
            "Which family moment from today would you like to remember in a year?",
            "What's one thing you'd like to ask someone in your family, but haven't?",
            "Where do you feel most like yourself with your family?",
        ],
        .sleep: [
            "What would make tonight a little easier to settle into?",
            "What's still running in your head when the lights go out?",
            "What helped you rest recently, even a little?",
            "If tonight were a gentle night, how would it start?",
        ],
        .health: [
            "What is your body asking for that you haven't given it yet?",
            "When did you last feel strong, and what were you doing?",
            "How did moving today change the rest of your day?",
            "What small thing could you do for your body tomorrow morning?",
        ],
        .creativity: [
            "What idea keeps tugging at you, even when you're busy?",
            "What would you make if no one ever had to see it?",
            "When did you last lose track of time making something?",
            "What's one small creative thing you could try this week?",
        ],
        .relationships: [
            "Who made today lighter, and do they know?",
            "What conversation are you still having in your head?",
            "Who would you like to be closer to, and what's one step toward that?",
            "What do you need more of from the people around you?",
        ],
        .money: [
            "What would feeling secure with money look like this month?",
            "Which spending choice this week felt most aligned with what you value?",
            "What money worry would you set down if you could?",
            "What's one small money decision that would make next week easier?",
        ],
        .purpose: [
            "What did today teach you about what matters to you?",
            "If this week were a chapter, what would you title it?",
            "What would you do more of if you trusted it mattered?",
            "Where did you feel most useful today?",
        ],
        .nature: [
            "Where outside did you feel most at ease recently?",
            "What did you notice outdoors that you'd usually walk past?",
            "How does being outside change the way you think?",
            "What would a little more time outside look like this week?",
        ],
        .learning: [
            "What's something you understood today that you didn't yesterday?",
            "What are you curious about right now, just for its own sake?",
            "What would you like to get better at, slowly?",
            "Who or what taught you something this week?",
        ],
        nil: [
            "Would today feel different if you didn't label it productive or unproductive?",
            "What's one moment from today you'd like to keep?",
            "What felt heavier than it needed to be today?",
            "What would you like to tell yourself from a week ago?",
            "What surprised you about today?",
            "What are you ready to let go of before tomorrow?",
        ],
    ]

    // MARK: Grounding (prompts.py:44-49, evals/checks.py:20)

    static let historyWords = try! NSRegularExpression(
        pattern: #"\b(again|lately|last\s+(week|month|night|time)|returning|recurring|these\s+days|as\s+usual|once\s+more|keeps?\s+coming\s+back|as\s+always|usual\s+pattern)\b"#,
        options: .caseInsensitive)
    static let relationshipWords = try! NSRegularExpression(
        pattern: #"\b(mom|mum|mother|dad|father|parents?|sister|brother|sibling|wife|husband|spouse|partner|girlfriend|boyfriend|fianc[eé]e?|son|daughter|kids?|grand(ma|pa|mother|father|parent)s?|aunt|uncle|cousin|friends?|bestie|colleagues?|boss|family|couple|mama|papa)\b"#,
        options: .caseInsensitive)
    static let bannedPhrases = ["journey", "embrace", "you've got this", "be kind to yourself", "self-care", "remember to", "you should",
                                "it's okay to", "consider therapy", "trust the process", "honor your", "the universe", "your truth",
                                "small victories", "give yourself grace", "proud of you"]
    /// Spelled numbers that must be backed by the source; "one", "first" and friends are too often not numbers.
    static let numberWords = Set("two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty thirty forty fifty hundred thousand million".split(separator: " ").map(String.init))
    /// Capitalised words that are not names (NOT_NAMES in evals/checks.py).
    static let notNames = commonCaps.union(Mood.allCases.map { $0.rawValue.lowercased() }).union(["i", "you", "your", "saro", "may"])

    /// Feeling and abstract nouns a model may use without the source naming them (§11.6). Anything concrete is not here.
    static let abstractNouns = Set("""
    feeling feelings emotion emotions mood moods sense senses heart mind thought thoughts idea ideas self
    calm calmness peace quiet stillness ease rest relief comfort contentment serenity balance steadiness
    joy happiness delight gladness gratitude thanks warmth tenderness softness love care kindness affection closeness connection
    sadness sorrow grief loss longing ache heaviness weight burden loneliness solitude distance emptiness
    worry worries anxiety fear fears dread nerves nervousness tension stress pressure panic unease restlessness doubt doubts
    anger frustration irritation annoyance resentment impatience friction resistance
    tiredness fatigue exhaustion weariness energy spark drive motivation momentum pace rhythm flow
    hope hopes wish wishes dream dreams desire wants need needs courage confidence pride shame guilt regret embarrassment
    surprise wonder curiosity clarity focus attention presence awareness meaning purpose direction intention
    change progress growth effort struggle challenge strain release space breath
    day today tonight morning afternoon evening night week moment moments while time times hour hours beginning
    part bit kind sort way ways thing things something nothing everything anything lot look
    reason reasons question questions answer answers choice choices decision decisions plan plans
    memory memories experience experiences reflection reflections words word entry entries mix contrast
    bittersweetness nostalgia inspiration overwhelm excitement satisfaction accomplishment
    patience trust pain hurt freedom honesty uncertainty belonging safety
    """.split(whereSeparator: \.isWhitespace).map(String.init))
}
