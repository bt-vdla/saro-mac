import Foundation
import NaturalLanguage

extension Heuristics {
    /// The §11.6 drift check over model prose (titles, summaries, narratives, questions). Every proper noun, number,
    /// relationship word, history word and banned phrase in `generated` must appear in `source`, and so must every
    /// content noun (lemmatised with NLTagger) outside the feeling-and-abstract allowlist. A word NLTagger can't
    /// lemmatise, such as Hinglish the source never used, is drift. Verbs and adjectives may be new, so an invented
    /// relation between real nouns still passes.
    public static func driftOK(generated: String, source: String) -> Bool {
        let gen = fold(generated), src = fold(source)
        for regex in [Lexicon.historyWords, Lexicon.relationshipWords] where !matches(regex, gen).isSubset(of: matches(regex, src)) {
            return false
        }
        if Lexicon.bannedPhrases.contains(where: { gen.contains($0) && !src.contains($0) }) { return false }

        let sourceWords = tag(source)
        let known = Set(sourceWords.flatMap { [$0.lower, $0.lemma].compactMap { $0 } } + tokenize(src).map(\.lower))
        for w in tag(generated) where !w.lower.hasPrefix("'") {
            if known.contains(w.lower) || w.lemma.map(known.contains) == true { continue }
            if w.isName || (w.capitalisedMidSentence && !Lexicon.notNames.contains(w.lower)) { return false }
            if w.lexicalClass == .number || w.lower.first?.isNumber == true || Lexicon.numberWords.contains(w.lower) { return false }
            if Lexicon.stop.contains(w.lower) { continue }
            guard let lemma = w.lemma else { return false }
            switch w.lexicalClass {
            case .verb, .adjective, .adverb, .pronoun, .determiner, .particle, .preposition, .conjunction, .interjection: continue
            default: if !Lexicon.abstractNouns.contains(w.lower) && !Lexicon.abstractNouns.contains(lemma) { return false }
            }
        }
        return true
    }

    private struct Tagged {
        let lower: String
        let lemma: String?
        let lexicalClass: NLTag?
        let isName: Bool
        let capitalisedMidSentence: Bool
    }

    private static func fold(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "’", with: "'").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func matches(_ regex: NSRegularExpression, _ s: String) -> Set<String> {
        Set(regex.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length)).map {
            (s as NSString).substring(with: $0.range).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        })
    }

    private static func tag(_ text: String) -> [Tagged] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma, .nameType])
        tagger.string = text
        let whole = text.startIndex..<text.endIndex
        tagger.setLanguage(.english, range: whole)
        var out: [Tagged] = []
        tagger.enumerateTags(in: whole, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, r in
            let word = text[r]
            let name = tagger.tag(at: r.lowerBound, unit: .word, scheme: .nameType).0
            let before = text[..<r.lowerBound].last { !$0.isWhitespace }
            out.append(Tagged(
                lower: word.lowercased().replacingOccurrences(of: "’", with: "'"),
                lemma: tagger.tag(at: r.lowerBound, unit: .word, scheme: .lemma).0?.rawValue.lowercased(),
                lexicalClass: tag,
                isName: [.personalName, .placeName, .organizationName].contains(name),
                capitalisedMidSentence: word.first?.isUppercase == true && before.map { !".!?:;\"“”'‘’()—–".contains($0) } == true))
            return true
        }
        return out
    }
}
