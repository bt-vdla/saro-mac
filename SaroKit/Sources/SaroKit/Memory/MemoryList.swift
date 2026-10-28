import Foundation

/// Where Saro saw something: the person's own words, on a day.
public struct Sighting: Sendable, Hashable, Identifiable {
    /// The observation's id.
    public let id: String
    public let entryId: String?
    public let day: String
    public let at: Date
    public let quote: String
    public let field: String?
    public let spanStart: Int?

    init(_ o: Observation) {
        id = o.id
        entryId = o.entryId
        day = o.localDay
        at = o.at
        quote = o.quote ?? o.label
        field = o.field
        spanStart = o.spanStart
    }
}

/// One line of What Saro knows (memory-service.ts Memory), derived at read time from `active_observation`, the latest
/// starter context and open commitments, so nothing derived is ever stored twice.
public struct Memory: Sendable, Hashable, Identifiable {
    public enum Group: String, Sendable, CaseIterable {
        case about, people, mind, work, feelings

        public var label: String {
            switch self {
            case .about: "About you"
            case .people: "People"
            case .mind: "On your mind"
            case .work: "What you’re working on"
            case .feelings: "Feelings"
            }
        }
    }

    public enum Source: Sendable, Hashable { case entries, onboarding, user, commitments }

    public var id: String { key }
    /// Stable across reads (`person:maya`, `theme:sleep`), and what a delete tombstones.
    public let key: String
    public var text: String
    public let group: Group
    public var source: Source
    /// Entries it was seen in; 0 for what the person told Saro or added.
    public let count: Int
    public let lastSeen: Date
    public var updatedAt: Date
    /// The name or theme the line is about, for prompts and the palette.
    public let label: String
    /// Every sighting, newest first: Why lists them all.
    public let sightings: [Sighting]
    /// The onboarding answer a line came from.
    public let told: String?

    /// The words Why opens on: the newest sighting of four words or more, else the newest, else the answer.
    public var evidence: String? {
        (sightings.first { $0.quote.split(separator: " ").count >= 4 } ?? sightings.first)?.quote ?? told
    }

    public var added: Bool { key.hasPrefix("user:") }
}

public enum MemoryList {
    public static let maxChars = 90
    static let evidenceMax = 140
    static let moodWindow: TimeInterval = 30 * 86_400
    static let maxThemes = 5
    static let maxMoods = 2
    static let personKinds: Set<Observation.Kind> = [.person, .personTalks, .personThing, .personName]

    /// Cut at a word, with an ellipsis, so a line stays one short line (memory.ts clip).
    public static func clip(_ s: String, _ max: Int) -> String {
        let clean = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard clean.count > max else { return clean }
        let cut = clean.prefix(max - 1)
        let at = cut.lastIndex(of: " ").map { cut.distance(from: cut.startIndex, to: $0) } ?? 0
        let kept = Double(at) > Double(max) * 0.6 ? String(cut.prefix(at)) : String(cut)
        return kept.replacingOccurrences(of: #"[\s,;:–—-]+$"#, with: "", options: .regularExpression) + "…"
    }

    /// One plain line: a Shift-Return break is a space; at most 90 characters.
    public static func oneLine(_ s: String) -> String {
        String(s.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(maxChars)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Derive (memory.ts deriveMemories + mergeMemories)

    public static func derive(_ rows: [Observation], starter: StarterContext? = nil, commitments: [OpenCommitment] = [],
                              tombstones: Set<String> = [], forgotAllAt: Date? = nil, pauses: [MemoryPause] = [], now: Date = .now) -> [Memory] {
        let gone = { (key: String) in tombstones.contains(sha256(key)) }
        let user = rows.filter { $0.source == .user }
        let labels = Dictionary(user.filter { $0.kind == .label }.map { ($0.key, $0.label) }, uniquingKeysWith: { $1 })
        let learned = rows.filter { $0.source != .user }
        var out: [Memory] = []

        func memory(_ key: String, _ text: String, _ group: Memory.Group, _ rows: [Observation], label: String) -> Memory {
            let s = sightings(rows)
            return Memory(key: key, text: clip(text, maxChars), group: group, source: .entries, count: Set(rows.compactMap(\.entryId)).count,
                          lastSeen: s.first?.at ?? now, updatedAt: s.first?.at ?? now, label: label, sightings: s, told: nil)
        }

        for (key, rs) in ranked(learned.filter { personKinds.contains($0.kind) }, min: 2) where MemoryRules.isPerson(rs.map(\.kind)) {
            let name = labels[key] ?? rs.max { $0.at < $1.at }?.label ?? key
            out.append(memory(key, "\(name) comes up often.", .people, rs, label: name))
        }
        for (key, rs) in ranked(learned.filter { $0.kind == .theme }, min: 2).prefix(maxThemes) {
            let theme = labels[key] ?? rs[0].label
            out.append(memory(key, "\(capitalize(theme)) \(theme.hasSuffix("s") ? "have" : "has") been on your mind.", .mind, rs, label: theme))
        }
        // A feeling counts within one lineage only (DR-13): heuristic and model moods are never added together.
        let recent = learned.filter { $0.kind == .emotion && $0.at >= now.addingTimeInterval(-moodWindow) }
        var moods: [String: [Observation]] = [:]
        for lineage in Set(recent.map { $0.lineage ?? "heuristic" }) {
            for (key, rs) in ranked(recent.filter { ($0.lineage ?? "heuristic") == lineage }, min: 3) where weight(rs) > moods[key].map(weight) ?? (0, .distantPast) {
                moods[key] = rs
            }
        }
        for (key, rs) in moods.sorted(by: { weight($0.value) > weight($1.value) }).prefix(maxMoods) {
            out.append(memory(key, "You’ve often felt \(rs[0].label.lowercased()) lately.", .feelings, rs, label: rs[0].label))
        }

        // A commitment carried over to a new day is the same commitment.
        let since = { (d: Date) in forgotAllAt.map { d > $0 } ?? true && !pauses.contains { $0.contains(d) } }
        var seen: [String: (text: String, at: [Date])] = [:]
        var order: [String] = []
        for c in commitments where since(c.createdAt) {
            let text = c.text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"[.!?]+$"#, with: "", options: .regularExpression)
            let key = "commitment:" + text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !text.isEmpty else { continue }
            if seen[key] == nil { order.append(key) }
            seen[key, default: (text, [])].at.append(c.createdAt)
        }
        for key in order {
            let c = seen[key]!, last = c.at.max() ?? now
            out.append(Memory(key: key, text: "You’re working on “\(clip(c.text, maxChars - 22))”.", group: .work, source: .commitments,
                              count: c.at.count, lastSeen: last, updatedAt: last, label: c.text, sightings: [], told: nil))
        }

        // About you: one line per onboarding pick; learned from entries wins, and one time of day, a clock time preferred.
        if let starter {
            let times = starter.picks.filter { $0.kind == .time }
            let clocks = times.filter { MemoryRules.clock($0.value) != nil }
            let reflectAt = clocks.first { $0.text.contains(where: \.isNumber) } ?? clocks.first ?? times.first
            for pick in starter.picks where pick.kind != .time || pick == reflectAt {
                guard let line = MemoryRules.starterLine(pick, answer: starter.answers[pick.q]), !out.contains(where: { $0.key == line.key })
                else { continue }
                out.append(Memory(key: line.key, text: clip(line.text, maxChars), group: .about, source: .onboarding, count: 0,
                                  lastSeen: starter.updatedAt, updatedAt: starter.updatedAt, label: pick.value, sightings: [],
                                  told: starter.answers[pick.q].map { clip($0, evidenceMax) }))
            }
        }

        // The person's own lines outrank everything learned with the same key, and stay when what it came from goes.
        for u in user.filter({ $0.kind == .line }).sorted(by: { $0.createdAt < $1.createdAt }) {
            if let i = out.firstIndex(where: { $0.key == u.key }) {
                out[i].text = u.label
                out[i].source = .user
                out[i].updatedAt = u.createdAt
            } else {
                out.append(Memory(key: u.key, text: u.label, group: group(ofKey: u.key), source: .user, count: 0, lastSeen: u.createdAt,
                                  updatedAt: u.createdAt, label: u.label, sightings: [], told: nil))
            }
        }
        return out.filter { !gone($0.key) }
    }

    /// The fixed group order, empty groups left out; most-seen first, then most recent.
    public static func group(_ memories: [Memory]) -> [(group: Memory.Group, items: [Memory])] {
        Memory.Group.allCases.compactMap { g in
            let items = memories.filter { $0.group == g }.sorted { ($0.count, $0.lastSeen) > ($1.count, $1.lastSeen) }
            return items.isEmpty ? nil : (g, items)
        }
    }

    /// Where a line came from and when (MemorySection.tsx metaLine): "From 6 entries · last Sep 24".
    public static func meta(_ m: Memory, now: Date = .now, calendar: Calendar = .current) -> String {
        let when = { (d: Date) in day(d, now: now, calendar: calendar) }
        switch m.source {
        case .user: return "\(m.added ? "Added" : "Edited") by you · \(when(m.updatedAt))"
        case .onboarding: return "You told Saro · \(when(m.updatedAt))"
        case .commitments: return "From your commitments · last \(when(m.lastSeen))"
        case .entries: return "From \(m.count) \(m.count == 1 ? "entry" : "entries") · last \(when(m.lastSeen))"
        }
    }

    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "Sep 24", and "Sep 24, 2025" when it isn't this year.
    public static func day(_ d: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        let year = c.year == calendar.component(.year, from: now) ? "" : ", \(c.year ?? 0)"
        return "\(months[((c.month ?? 1) - 1).clamped(0, 11)]) \(c.day ?? 1)\(year)"
    }

    /// Text and evidence, case- and diacritic-insensitive (Search.swift's matching).
    public static func matches(_ m: Memory, _ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || m.text.localizedStandardContains(q) || m.sightings.contains { $0.quote.localizedStandardContains(q) }
            || m.told?.localizedStandardContains(q) == true
    }

    /// What prompts may know (FR-MEM feeding): the name the person goes by, people's names, then the top themes.
    /// Only labels, never sentences; forgotten and held rows never reach `memories`.
    public static func knownLabels(_ memories: [Memory], called: String?) -> [String] {
        var out = called.map { [$0] } ?? []
        for m in memories where m.group == .people { out.append(m.label) }
        for m in memories where m.group == .mind { out.append(m.label) }
        var seen = Set<String>()
        return out.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    // MARK: Helpers

    static func sightings(_ rows: [Observation]) -> [Sighting] {
        var seen = Set<String>()
        return rows.sorted { $0.at > $1.at }.filter { seen.insert("\($0.entryId ?? $0.id)|\($0.spanStart ?? -1)").inserted }.map(Sighting.init)
    }

    /// Keys seen in at least `min` entries, most-seen first, then most recent.
    static func ranked(_ rows: [Observation], min: Int) -> [(key: String, rows: [Observation])] {
        Dictionary(grouping: rows, by: \.key)
            .filter { Set($0.value.compactMap(\.entryId)).count >= min }
            .map { ($0.key, $0.value) }
            .sorted { weight($0.rows) > weight($1.rows) }
    }

    static func weight(_ rows: [Observation]) -> (Int, Date) {
        (Set(rows.compactMap(\.entryId)).count, rows.map(\.at).max() ?? .distantPast)
    }

    static func group(ofKey key: String) -> Memory.Group {
        switch key.split(separator: ":").first {
        case "person": .people
        case "theme": .mind
        case "mood": .feelings
        case "commitment": .work
        default: .about
        }
    }

    private static func capitalize(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}

private extension Int {
    func clamped(_ lo: Int, _ hi: Int) -> Int { Swift.min(Swift.max(self, lo), hi) }
}
