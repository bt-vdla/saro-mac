import Foundation

/// One line on the SafetyCard (port of `lib/crisis-resources.ts`). Keep this list reviewed (SR-32).
public struct CrisisResource: Sendable, Hashable {
    public let region: String
    public let name: String
    public let contact: String
    public let detail: String
    /// tel: for phone lines, https: for websites.
    public let url: URL
}

public enum CrisisResources {
    public static let lifeline988 = CrisisResource(region: "United States", name: "988 Suicide & Crisis Lifeline",
                                                   contact: "Call or text 988", detail: "24/7, free and confidential",
                                                   url: URL(string: "tel:988")!)
    public static let teleManas = CrisisResource(region: "India", name: "Tele-MANAS", contact: "Call 14416 or 1-800-891-4416",
                                                 detail: "24/7, free, in 20+ languages", url: URL(string: "tel:14416")!)
    public static let findAHelpline = CrisisResource(region: "Anywhere else", name: "Find A Helpline", contact: "findahelpline.com",
                                                     detail: "Free, local helplines in 130+ countries",
                                                     url: URL(string: "https://findahelpline.com")!)

    /// SR-19: the region's own line first (IN, US), else Find A Helpline first. Every list carries all three.
    public static func forRegion(_ code: String? = Locale.current.region?.identifier) -> [CrisisResource] {
        let first = switch code?.uppercased() {
        case "IN": teleManas
        case "US": lifeline988
        default: findAHelpline
        }
        return [first] + [lifeline988, teleManas, findAHelpline].filter { $0 != first }
    }
}
