/// The focus picker's preview line (focus-data.ts), word for word: one pick's message, a pair's, or three's.
public enum FocusCopy {
    public static let three = "Three threads, one lens. Saro holds them all."
    public static let limit = "Three is the most. Unpick one to choose another."

    public static let single: [FocusArea: String] = [
        .clarity: "Remove the noise; what's left?",
        .steadiness: "Stay on tempo, not intensity.",
        .creative: "Move, then improve.",
        .relationships: "Listen past the words.",
        .habits: "Tiny action, same slot.",
        .confidence: "Back your taste.",
        .energy: "Say no to save your yes.",
        .purpose: "Cut what isn't the path.",
    ]

    /// Keyed by the two picks' raw values, sorted alphabetically and joined by "-", as the web looks them up.
    public static let pairs: [String: String] = [
        "clarity-steadiness": "Remove the noise and keep the tempo, not the intensity.",
        "clarity-creative": "Remove the noise, then move and improve what remains.",
        "clarity-relationships": "Remove the noise so you can listen past the words.",
        "clarity-habits": "Remove the noise and make a tiny action at the same slot.",
        "clarity-confidence": "Remove the noise and back your taste.",
        "clarity-energy": "Remove the noise and say no to save your yes.",
        "clarity-purpose": "Remove the noise and cut what isn't the path.",
        "creative-steadiness": "Keep the tempo as you move, then improve.",
        "relationships-steadiness": "Keep the tempo so you can listen past the words.",
        "habits-steadiness": "Keep the tempo by repeating a tiny action in the same slot.",
        "confidence-steadiness": "Keep the tempo and back your taste.",
        "energy-steadiness": "Keep the tempo by saying no to save your yes.",
        "purpose-steadiness": "Keep the tempo and cut what isn't the path.",
        "creative-relationships": "Move, then improve, and listen past the words.",
        "creative-habits": "Move, then improve with a tiny action in the same slot.",
        "creative-energy": "Move, then improve by saying no to save your yes.",
        "creative-purpose": "Move, then improve by cutting what isn't the path.",
        "habits-relationships": "Listen past the words and anchor a tiny action in the same slot.",
        "energy-relationships": "Listen past the words and say no to save your yes.",
        "purpose-relationships": "Listen past the words and cut what isn't the path.",
        "confidence-relationships": "Listen past the words and back your taste.",
        "confidence-habits": "Keep a tiny action in the same slot and back your taste.",
        "energy-habits": "Keep a tiny action in the same slot and say no to save your yes.",
        "habits-purpose": "Keep a tiny action in the same slot and cut what isn't the path.",
        "confidence-creative": "Move, then improve, and back your taste.",
        "confidence-energy": "Back your taste and say no to save your yes.",
        "confidence-purpose": "Back your taste and cut what isn't the path.",
        "energy-purpose": "Say no to save your yes and cut what isn't the path.",
    ]

    /// The preview line for a set of picks; nil when nothing is picked.
    public static func preview(_ picks: [FocusArea]) -> String? {
        switch picks.count {
        case 0: nil
        case 1: single[picks[0]]
        case 2: pairs[picks.map(\.rawValue).sorted().joined(separator: "-")]
        default: three
        }
    }
}
