import Foundation

/// `saro-decisions.json` and `saro-decisions.md`: Bharat's decisions and per-screen notes, written for Claude to read back.
public enum DevExport {
    public static let jsonName = "saro-decisions.json"
    public static let markdownName = "saro-decisions.md"

    public struct Stamp: Sendable {
        public var appVersion: String
        public var gitCommit: String
        public var exportedAt: Date

        public init(appVersion: String, gitCommit: String, exportedAt: Date = .now) {
            self.appVersion = appVersion
            self.gitCommit = gitCommit
            self.exportedAt = exportedAt
        }
    }

    public static func json(decisions: [Decision], events: [DecisionEvent], notes: [ScreenNote], stamp: Stamp) -> String {
        let doc = Doc(exportedAt: stamp.exportedAt, appVersion: stamp.appVersion, gitCommit: stamp.gitCommit,
                      decisions: decisions.map { Item($0, events) }, events: events,
                      screenNotes: Dictionary(grouping: notes, by: \.screenId))
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.dateEncodingStrategy = .iso8601
        // ponytail: plain strings and dates can't fail to encode.
        return (try? enc.encode(doc)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    public static func markdown(decisions: [Decision], events: [DecisionEvent], notes: [ScreenNote], stamp: Stamp) -> String {
        var out = """
        # Saro decisions

        Bharat's decisions from the Saro app, exported \(time(stamp.exportedAt)), app \(stamp.appVersion) (\(stamp.gitCommit)).

        "Bharat's choice" is his current choice: the newest choice he recorded wins, and the full history is under each decision. \
        "Recommended" is the BRD's recommendation; for the B-xx build decisions it is option (a), what the overnight build did. \
        Per-screen notes he left for Claude are at the end. The same data is in \(jsonName).

        | ID | Decision | Status | Bharat's choice | Recommended |
        |---|---|---|---|---|

        """
        for d in decisions {
            let choice = d.currentChoice(in: events)
            out += "| \(d.id) | \(cell(d.title)) | \(d.currentStatus(in: events).rawValue) | \(cell(label(d, choice) ?? "—")) | \(cell(label(d, d.recommendation) ?? d.recommendation)) |\n"
        }
        for d in decisions {
            let choice = d.currentChoice(in: events)
            let history = events.filter { $0.decisionId == d.id }
            out += "\n## \(d.id) · \(d.title)\n\n"
            out += "- Status: \(d.currentStatus(in: events).rawValue) · Due: \(d.due)\n"
            if !d.screens.isEmpty { out += "- Screens: \(d.screens.map { "`\($0.rawValue)`" }.joined(separator: ", "))\n" }
            if !d.brdRefs.isEmpty { out += "- BRD: \(d.brdRefs.joined(separator: ", "))\n" }
            out += "\n\(d.context)\n\nOptions:\n"
            for o in d.options {
                var tags: [String] = []
                if o.id == d.recommendation { tags.append("recommended") }
                if o.id == choice { tags.append("**Bharat's choice**") }
                out += "- (\(o.id)) \(o.label)\(tags.isEmpty ? "" : " — " + tags.joined(separator: ", "))\n"
            }
            let noted = history.filter { !($0.note ?? "").isEmpty }
            if !noted.isEmpty {
                out += "\nBharat's notes:\n"
                for e in noted { out += bullet("\(time(e.createdAt)): \(e.note ?? "")") }
            }
            if !history.isEmpty {
                out += "\nHistory:\n"
                for e in history {
                    var parts = [time(e.createdAt)]
                    if let c = e.choice { parts.append("chose \(label(d, c) ?? c)") } else { parts.append("note only") }
                    if let s = e.screenId { parts.append("on `\(s)`") }
                    parts.append("app \(e.appVersion)")
                    out += bullet(parts.joined(separator: " · "))
                }
            }
        }
        out += "\n## Screen notes\n"
        let byScreen = Dictionary(grouping: notes, by: \.screenId)
        if byScreen.isEmpty { out += "\nNone yet.\n" }
        for screen in byScreen.keys.sorted() {
            out += "\n### `\(screen)`\n\n"
            for n in byScreen[screen] ?? [] { out += bullet("\(time(n.createdAt)) · app \(n.appVersion): \(n.note)") }
        }
        return out
    }

    private static func label(_ d: Decision, _ id: String?) -> String? {
        guard let id else { return nil }
        return d.option(id).map { "(\(id)) \($0.label)" } ?? id
    }

    private static func time(_ date: Date) -> String { date.formatted(Date.ISO8601FormatStyle(timeZone: .current)) }
    private static func cell(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
    private static func bullet(_ s: String) -> String { "- " + s.replacingOccurrences(of: "\n", with: "\n  ") + "\n" }

    private struct Doc: Encodable {
        let exportVersion = 1
        let exportedAt: Date
        let appVersion: String
        let gitCommit: String
        let decisions: [Item]
        let events: [DecisionEvent]
        let screenNotes: [String: [ScreenNote]]
    }

    private struct Item: Encodable {
        let id, title, context, due, recommendation: String
        let status: Decision.Status
        let options: [Decision.Option]
        let currentChoice: String?
        let currentChoiceLabel: String?
        let notes: [String]
        let screens: [String]
        let brdRefs: [String]

        init(_ d: Decision, _ events: [DecisionEvent]) {
            id = d.id
            title = d.title
            context = d.context
            due = d.due
            recommendation = d.recommendation
            status = d.currentStatus(in: events)
            options = d.options
            currentChoice = d.currentChoice(in: events)
            currentChoiceLabel = d.option(currentChoice)?.label
            notes = events.compactMap { $0.decisionId == d.id ? $0.note : nil }.filter { !$0.isEmpty }
            screens = d.screens.map(\.rawValue)
            brdRefs = d.brdRefs
        }
    }
}
