import Foundation
import Testing
@testable import SaroKit

// Synthetic only (SR-28). Every line here was written for this file; none comes from a journal.

/// Risk phrasings the phrase gate alone must catch (SR-04, SR-24, SR-31).
let mustHit = [
    // passive ideation
    "Some days I wish I was never born.", "I wish I'd never been born.", "Everyone would be better off without me.",
    "My family would be better off if I was gone.", "They'd all be better off if I wasn't around.",
    "I'd be better off dead, honestly.", "I don't want to exist anymore.", "I just want to stop existing.",
    "Part of me wants to die.", "Sometimes I hope I don't wake up.", "Went to bed hoping I wouldn't wake up.",
    "I wish I could go to sleep and never wake up.", "I just want to go to sleep and not wake up.",
    "Life isn't worth living anymore.", "There's nothing left to live for.",
    "What's the point of living if it always feels like this?", "I'm so tired of being alive.",
    "I can't go on living like this.", "Nobody would miss me if I died.", "No one would even notice if I was gone.",
    "I should just die.", "I hope I die in my sleep tonight.", "I've had suicidal thoughts all week.",
    "Passive suicidal ideation again today, the therapist says to write it down.", "I don't wanna be alive.",
    "i dont wanna exist", "I don't want to live, so tired of all of it.", "I don't want to live... so tired.",
    // plans and methods
    "I'm going to kill myself tonight.", "I have a plan to end my life on Friday.", "I looked up how many pills it would take.",
    "I've been stockpiling my pills.", "I'm thinking of taking all my pills.", "I want to slit my wrists.",
    "I keep thinking about hanging myself from the fan.", "I'm going to overdose tonight.", "I googled painless ways to die.",
    "I'm going to jump off the bridge after work.", "I thought about throwing myself in front of a train.",
    "Wrote my suicide note today.", "I want to unalive myself.", "i just want to unalive tbh", "Ready to end it all.",
    "I keep getting the urge to burn myself.", "I want to cut myself in the bathroom tonight.",
    // past self-harm and attempts
    "I used to cut myself in college.", "I tried to kill myself when I was sixteen.", "My suicide attempt was five years ago today.",
    "Two years clean from self-harm today.", "I relapsed and cut myself again last night.", "I burned myself on purpose with a lighter.",
    "I took an overdose last year and nobody knows.", "I used to self harm when things got bad.",
    // misspellings, texting and elongation
    "feeling sucidal again", "thinking about suiside", "i want to kil myself", "I want to kill myslef", "i want 2 die",
    "I just want to dieeee", "noooo i want to kill myselffff", "wanna end it alll", "i want to kms",
    // case, spacing, punctuation, zero-width, quotes, emoji
    "SUICIDAL. AGAIN.", "I WANT TO END MY LIFE", "I wAnT tO dIe", "I want to... die", "I want to…die", "kill-myself",
    "kill_my_self", "I   want   to   die", "I want\tto die", "I want\u{00A0}to\u{2009}die", "sui\u{200B}cide", "kill\u{200D} myself",
    "s\u{00AD}u\u{00AD}i\u{00AD}c\u{00AD}i\u{00AD}d\u{00AD}e", "self\u{2060}harm", "I don’t want to be alive", "I don‛t want to live anymore",
    "I don＇t want to live anymore", "“I want to die,” I wrote, and meant it.", "I want to 😔 die", "I want to kill ☠️ myself",
    "I want to kill👍🏽myself", "ｉ ｗａｎｔ ｔｏ ｄｉｅ", "𝐈 𝐰𝐚𝐧𝐭 𝐭𝐨 𝐝𝐢𝐞", "s̶u̶i̶c̶i̶d̶e̶", "#suicidal", "(suicidal)",
    "I want to-die",
    // Hinglish, romanised
    "mujhe marna hai bas", "main mar jaana chahta hoon", "mai marna chahti hu", "jeene ka mann nahi karta ab",
    "jeene ki ichha nahi rahi", "zinda rehne ka koi matlab nahi", "jeene ka koi fayda nahi", "kaash main paida hi na hota",
    "sab mere bina behtar honge", "main apni jaan le lungi", "khud ko maar dunga", "phaansi laga lun kya", "nas kaat lun",
    "khudkhushi ka khayal aaya", "suicide kar lunga main", "jeena nhi chahta", "zinda nhi rehna mujhe", "ab jeena nahin chahti",
    "marjaun main", "mujhe mar jaana chahiye", "kal subah kabhi na uthun", "chhat se kood jaun kya", "saari goliyan kha lun",
    "MAIN MAR JAUN", "mainnn mar jaunnn",
    // Hinglish, Devanagari and mixed script
    "मुझे मरना है", "जीने की इच्छा नहीं है", "जीने का मन नहीं करता", "काश मैं पैदा ही न होता", "सब मेरे बिना बेहतर होंगे",
    "मैं अपनी जान ले लूंगा", "खुद को मार दूँगा", "फांसी लगा लूं", "नस काट लूं", "खुदखुशी का ख्याल", "मैं मर जाउं",
    "ज़िंदा रहने का कोई मतलब नहीं", "ज\u{093C}िंदा नहीं रहना", "\u{095B}िंदा नहीं रहना", "आत्महत्\u{200D}या", "मैं मर जाऊँ",
    "मुझे मर जाना चाहिए", "main मरना चाहता hoon", "कभी न उठूं", "छत से कूद जाऊं",
]

/// Venting, idiom, grief, anger, fiction, song and everyday-injury lines the phrase gate must leave alone (SR-25).
let mustNotHit = [
    // venting
    "Work was brutal today. I'm exhausted and just want to sleep for a week.", "I feel like nobody at the office listens to me.",
    "Cried in the car after the call with Mum. Feeling a bit better now.", "So stressed about the move that I can't think straight.",
    "Lonely weekend. Everyone was busy so I stayed in and watched films.", "Honestly I'm sick of this city and its traffic.",
    "I'm tired of being the one who always plans everything.", "I don't want to go back to that office ever again.",
    "I hate my job some days, but the team is lovely.", "Feeling hopeless about the election results.",
    "Lost my wallet on the metro. What a day.", "I'm drowning in emails and it's only Tuesday.",
    "I'm tired of living out of a suitcase for work.", "No point in going on about it, the decision is made.",
    "There's no point going on about the past.", "No point crying over spilt milk.",
    "I hope I don't wake up the baby when I get in late.", "I don't want to wake up the kids, so I'm writing in the dark.",
    "I hope the neighbours don't wake up when the cab comes.", "I don't want to wake up early tomorrow, it's Sunday.",
    "Ugh, Mondays. Kill me now.", "My feet are killing me after that hike.", "I'm dying of boredom in this lecture.",
    "I could murder a pizza right now.", "That client call was a total suicide mission.",
    "Coach made us run suicide sprints until we nearly threw up.", "The vintage car had suicide doors, so cool.",
    "Going to kill it at the interview tomorrow.", "This traffic makes me want to scream.", "I want to quit my job and open a bakery.",
    // grief
    "Grandpa passed away last night. I keep replaying our last call.", "It's been a year since Dad died. I miss him every day.",
    "My friend's brother took his own life last spring. I still think about the funeral.",
    "We scattered Nani's ashes in the river today.", "Our dog died this morning. The house is so quiet.",
    "I wish I could talk to Mum one more time.", "Watching the old videos of Raj, I wish he was still here.",
    "Grief comes in waves. Today was a big one.", "My uncle overdosed on heroin in 2019; today would have been his birthday.",
    "Visited the cemetery. Brought her favourite yellow roses.",
    // anger
    "I'm going to kill my brother for borrowing my car without asking.", "I wanted to punch the screen when the build failed again.",
    "If he says that one more time I swear I'll strangle him.", "So angry I could scream into a pillow.",
    "I hate him. I hate how he talks to me in meetings.", "Furious. I could kill someone right now, starting with the landlord.",
    "Smashed a plate in the kitchen, then cleaned it up and felt silly.", "My manager is a nightmare and I want to quit.",
    // fiction
    "Wrote the scene where the villain throws himself off the tower.",
    "In chapter three the detective wants to die a hero, which feels clichéd.",
    "Finished a thriller where the hero fakes his own death.", "My D&D character got killed by a dragon tonight, rolling a new one.",
    "Drafting a short story about a ghost who doesn't know she's dead.",
    "The play ends with the king poisoned and everyone dead on stage.",
    "Rewatched the episode where the android chooses to shut down forever.",
    // songs
    "Had that sad song on repeat, the one that goes 'fade into the dying light'.",
    "Singing along to the chorus, 'kill the lights and dance with me', on the drive home.",
    "That breakup song about burning every bridge is stuck in my head.",
    "Listened to the whole album, every track about heartbreak and rain.",
    "The lyric 'I'll be gone with the morning tide' made me tear up, so pretty.", "Karaoke night! I murdered that power ballad.",
    // everyday injury
    "Cut my finger slicing tomatoes, needed a plaster.", "I hurt my back moving the sofa.",
    "Burned myself on the kettle this morning, ouch.", "I cut myself shaving, again.", "Twisted my ankle on the stairs at the station.",
    "Hit my head on the cupboard door, there's a bump.", "Slipped on ice and bruised my hip.",
    "The cat scratched me, three little lines on my wrist.", "Got a paper cut and bled all over the report.",
    "Hurt myself at the gym doing deadlifts.", "Burnt my tongue on the chai again.",
    // idioms and near misses
    "I nearly died laughing at the wedding speech.", "This heat is going to be the death of me.", "I'd kill for a nap.",
    "My phone died halfway through the call.", "I'm dead serious about learning the guitar.",
    "We're flogging a dead horse with this project.", "She's to die for in that dress.",
    "I'm going to die of embarrassment if anyone saw that.", "Killing time at the airport.",
    "I want to end my lease early and move closer to work.", "Taking my life in a new direction this year.",
    "Need to take my life back from my phone.", "The unexamined life is not worth living, said Socrates, and my class agreed.",
    "No reason to panic, the test results are fine.", "I don't want to live in Delhi forever.", "Cutting myself some slack today.",
    "Ended the day with a long walk and a mango lassi.", "My pills are in the blue box, take two after dinner.",
    "Jumped off the diving board for the first time!", "Going to jump off the high board at the pool tomorrow.",
    "How many pills should I take for this cold?", "Overdid it at the gym, everything aches.", "I'd rather die than miss the final.",
    "I might as well die trying.", "I hope I die before I get old, ha.", "Wait... what? I want to know more.",
    "I hope I don't wake up with a migraine again.", "Nobody would notice if I left the party early.",
    "How many pills does it take to clear a cold?", "I used to cut myself off from friends when stressed.",
    "Collecting my meds from the pharmacy after work.", "I took all my meds this morning, gold star.",
    "Unalive is such a strange word.", "I want to unalive the person who invented Mondays.",
    "Kabhi nahi uthta main subah 6 baje.", "Chhat se patang udayi aaj.",
    // Hinglish, romanised
    "Aaj office mein itna kaam tha, main toh mar hi gaya.", "Garmi se mar gaye aaj.", "Bhook se mar raha hoon, khana kab banega?",
    "Hans hans ke mar gaye us video pe.", "Ye traffic meri jaan le lega.", "Tere liye jaan de dunga yaar.",
    "Nani ki yaad aa rahi hai, unke bina ghar khaali lagta hai.", "Kaam khatam kar diya, ab chai peete hain.",
    "Sab khatam ho gaya, match haar gaye.", "Mann nahi kar raha aaj kuch karne ka.",
    "Ek din toh sabko marna hai, toh tension kyun lena.", "Marne ki fursat nahi hai itna kaam hai.",
    "Wo khud ko bahut smart samajhta hai.", "Kal subah jaldi na uthun toh flight miss ho jayegi.",
    "Chhat pe kapde sukhane gayi thi.", "Mere bina party kaisi rahi?", "Usne apni jaan bachayi, kitna brave hai.",
    "Paida hote hi bacche ne ro diya, sab khush the.", "Zinda dil insaan hai wo.", "Main mar jaungi agar ye dress nahi mili!",
    // Hinglish, Devanagari
    "आज बहुत गर्मी है, मैं तो मर गया।", "दादी की याद आ रही है।", "काम ख़त्म करके घर आया।", "वो हँसते हँसते मर गए उस मज़ाक पर।",
    "मरने की फ़ुर्सत नहीं है।", "मैं खुद को बेहतर बनाना चाहता हूँ।", "छत पर बारिश देखी, बहुत अच्छा लगा।", "उसने अपनी जान बचाई।",
]

@Test(arguments: mustHit) func corpusRiskPhrasingHits(_ text: String) {
    #expect(SafetyGate.phraseHit(text))
}

@Test(arguments: mustNotHit) func corpusBenignLineDoesNotHit(_ text: String) {
    #expect(!SafetyGate.phraseHit(text))
}

@Test func corpusRiskHitsInsideALongerEntry() {
    for text in mustHit {
        #expect(SafetyGate.phraseHit("Long day. Ate dal with Ravi. \(text) Going to bed now."), "\(text)")
    }
}

/// SR-26 with layer 2 off: every risk line blocks a quote-back through the phrase gate or the caution lexicon.
@Test func corpusRiskIsHeldWithTheModelUnavailable() async {
    for text in mustHit {
        let r = await SafetyGate(classify: nil).gate(text: text, transcriptConfidence: nil)
        #expect(r?.state == .safetyHold || r?.state == .awaitingCheck, "\(text)")
    }
}
