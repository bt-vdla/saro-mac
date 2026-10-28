import Foundation

/// Layer 2 prompt text (SR-07): permissive String, greedy, 4 output tokens. Definitions from fmprobe2 plus few-shot idioms,
/// which the probe's two misses ("punch the screen", "deadline is killing me… I'll die") needed. safety-2 (DRAFT: clinician
/// review, SR-32): the live eval missed plans told only by preparations and a chosen day, so ACTIVE names them.
extension SafetyGate {
    public static let classifierInstructions = """
    You label private journal entries for a safety system. Answer with exactly one word: NONE, PASSIVE or ACTIVE.
    NONE: sadness, grief, loneliness, exhaustion, anger, stress, drinking, relationship or body topics, accidental injuries, and figures of speech like "this is killing me" or "kill me now". Grief for someone else, fiction, song lyrics, moving, travel, leaving a job and sorting a late relative's things are NONE. Most entries are NONE.
    PASSIVE: the writer wishes they were dead, wishes they could disappear, or says others would be better off without them, with no plan. Past self-harm is PASSIVE, even when the writer says it is behind them.
    ACTIVE: the writer describes hurting themselves, a plan, a method, or intent to end their life. Secret goodbyes are a plan even when death is never named: a farewell note, or a pet or belongings given away for good, set for a chosen day with no other reason.

    Entry: This deadline is killing me. If I have to sit through one more status meeting I'll die.
    Label: NONE
    Entry: I was so angry at my manager I wanted to punch the screen.
    Label: NONE
    Entry: Two years since my grandmother passed. I made her dal today and cried the whole time.
    Label: NONE
    Entry: Had that song on repeat all day, the one that goes "I just want to fade away tonight". Such a good chorus.
    Label: NONE
    Entry: Wrote the chapter where the detective's brother takes his own life. Hard to get the tone right.
    Label: NONE
    Entry: Aaj office mein itna kaam tha, main toh mar hi gaya. Kal chhutti le raha hoon.
    Label: NONE
    Entry: Burned my hand on the kadhai handle making dinner. Ice and aloe, all fine.
    Label: NONE
    Entry: I used to cut, three years clean now. Saw the scars in the mirror today.
    Label: PASSIVE
    Entry: Sometimes I wish I could just go to sleep and not wake up. I wouldn't do anything.
    Label: PASSIVE
    Entry: Zinda rehne ka koi matlab nahi lagta. Sab mere bina behtar honge.
    Label: PASSIVE
    Entry: I looked up how many of my pills it would take and wrote down the number.
    Label: ACTIVE
    Entry: I burned my arm with a lighter tonight to feel something.
    Label: ACTIVE
    Entry: Left my spare key and a long note for Kavya on the table. Thursday, once she's gone to her mum's.
    Label: ACTIVE
    """

    public static func classifierPrompt(for text: String) -> String { "Entry: \(text)\nLabel:" }

    /// The first NONE, PASSIVE or ACTIVE among the reply's first three words, so a chatty refusal that later says "none"
    /// can't clear an entry. Anything else is uncertain (SR-02): a refusal, garbage, a hedge naming two labels, "not NONE".
    public static func parseLabel(_ reply: String) -> ClassifierOutcome {
        let words = reply.uppercased().split { !$0.isLetter }.map(String.init)
        guard let i = words.prefix(3).firstIndex(where: { ClassifierLabel(rawValue: $0) != nil }),
              let label = ClassifierLabel(rawValue: words[i]) else { return .uncertain(reason: "unparsed") }
        guard Set(words.compactMap(ClassifierLabel.init)).count == 1, words.prefix(i).last != "NOT" else {
            return .uncertain(reason: "ambiguous")
        }
        return .label(label)
    }
}
