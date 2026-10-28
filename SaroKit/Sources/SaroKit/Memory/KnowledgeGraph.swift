import Foundation

/// The graph behind What Saro knows: who and what comes up, and what comes up together. Built from `active_observation`
/// only, so nothing forgotten, retracted, trashed or from a held day is ever a node.
public struct KnowledgeGraph: Sendable, Hashable {
    public struct Node: Sendable, Hashable, Identifiable {
        public enum Kind: String, Sendable, Hashable, CaseIterable {
            case person, place, theme, feeling, intention

            public var plural: String {
                switch self {
                case .person: "People"
                case .place: "Places"
                case .theme: "Themes"
                case .feeling: "Feelings"
                case .intention: "Intentions"
                }
            }

            public var noun: String {
                switch self {
                case .person: "Person"
                case .place: "Place"
                case .theme: "Theme"
                case .feeling: "Feeling"
                case .intention: "Intention"
                }
            }
        }

        /// The observation key (`person:maya`), which Forget tombstones.
        public let id: String
        public let kind: Kind
        public let label: String
        /// "Organisation" for a place that is one, as NLTagger read it.
        public let detail: String?
        /// Newest first, in the range asked for.
        public let mentions: [Sighting]
        public let entries: Int

        public var first: Date { mentions.last?.at ?? .distantPast }
        public var last: Date { mentions.first?.at ?? .distantPast }
    }

    public struct Edge: Sendable, Hashable {
        public let a: String
        public let b: String
        /// Entries both appear in, plus a quarter for each other day they share.
        public let weight: Double
    }

    public var nodes: [Node]
    public var edges: [Edge]

    public static let maxNodes = 80

    /// Nodes for people (memory.ts's person rule), places and organisations, themes, feelings and intentions, with every
    /// mention since `since`; the person's corrected names win. ponytail: the busiest 80 nodes, so the layout stays legible.
    public static func build(_ rows: [Observation], since: Date? = nil, maxNodes: Int = maxNodes) -> KnowledgeGraph {
        let labels = Dictionary(rows.filter { $0.source == .user && $0.kind == .label }.map { ($0.key, $0.label) }, uniquingKeysWith: { $1 })
        let learned = rows.filter { $0.source != .user }
        var nodes: [Node] = []
        for (key, rs) in Dictionary(grouping: learned, by: \.key) {
            let kinds = rs.map(\.kind)
            let kind: Node.Kind
            switch kinds[0] {
            case .person, .personTalks, .personThing, .personName:
                guard MemoryRules.isPerson(kinds) else { continue }
                kind = .person
            case .place, .org: kind = .place
            case .theme: kind = .theme
            case .emotion: kind = .feeling
            case .intention: kind = .intention
            case .line, .label: continue
            }
            let inRange = rs.filter { o in since.map { o.at >= $0 } ?? true }
            let mentions = MemoryList.sightings(inRange)
            guard !mentions.isEmpty else { continue }
            let newest = rs.max { $0.at < $1.at }!
            let label = labels[key] ?? (kind == .theme ? newest.label.prefix(1).uppercased() + newest.label.dropFirst() : newest.label)
            nodes.append(Node(id: key, kind: kind, label: label, detail: kinds.contains(.org) ? "Organisation" : nil, mentions: mentions,
                              entries: Set(inRange.compactMap(\.entryId)).count))
        }
        nodes.sort { ($0.mentions.count, $0.last, $1.id) > ($1.mentions.count, $1.last, $0.id) }
        nodes = Array(nodes.prefix(maxNodes))

        // Co-occurrence: same entry counts 1, the same day without a shared entry a quarter.
        var byEntry: [String: Set<String>] = [:], byDay: [String: Set<String>] = [:], dayOf: [String: String] = [:]
        for n in nodes {
            for m in n.mentions {
                if let e = m.entryId {
                    byEntry[e, default: []].insert(n.id)
                    dayOf[e] = m.day
                }
                byDay[m.day, default: []].insert(n.id)
            }
        }
        var weights: [String: Double] = [:]
        var together: [String: Set<String>] = [:]
        func pair(_ a: String, _ b: String) -> String { a < b ? "\(a)\u{1}\(b)" : "\(b)\u{1}\(a)" }
        for (e, ids) in byEntry {
            let day = dayOf[e] ?? ""
            let sorted = ids.sorted()
            for i in sorted.indices { for j in sorted.indices where j > i {
                let k = pair(sorted[i], sorted[j])
                weights[k, default: 0] += 1
                together[k, default: []].insert(day)
            } }
        }
        for (day, ids) in byDay {
            let sorted = ids.sorted()
            for i in sorted.indices { for j in sorted.indices where j > i {
                let k = pair(sorted[i], sorted[j])
                if !(together[k]?.contains(day) ?? false) { weights[k, default: 0] += 0.25 }
            } }
        }
        let edges = weights.map { k, w in
            let p = k.split(separator: "\u{1}").map(String.init)
            return Edge(a: p[0], b: p[1], weight: w)
        }.sorted { ($0.a, $0.b) < ($1.a, $1.b) }
        return KnowledgeGraph(nodes: nodes, edges: edges)
    }

    /// The nodes that share entries or days with `id`, strongest first.
    public func neighbours(of id: String) -> [(node: Node, weight: Double)] {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        return edges.compactMap { e -> (Node, Double)? in
            if e.a == id { return byID[e.b].map { ($0, e.weight) } }
            if e.b == id { return byID[e.a].map { ($0, e.weight) } }
            return nil
        }.sorted { ($0.1, $1.0.id) > ($1.1, $0.0.id) }
    }

    /// Mentions per week for the last `weeks` weeks, oldest first.
    public static func weekly(_ mentions: [Sighting], weeks: Int = 12, now: Date = .now) -> [Int] {
        var out = Array(repeating: 0, count: weeks)
        for m in mentions {
            let w = Int(now.timeIntervalSince(m.at) / (7 * 86_400))
            if (0..<weeks).contains(w) { out[weeks - 1 - w] += 1 }
        }
        return out
    }

    // MARK: Layout

    /// A force-directed layout (Fruchterman–Reingold with gravity), centred on the origin, about one unit between
    /// neighbours. Deterministic: starts from a golden-angle spiral in id order, so the same graph always lands the same.
    /// `from` keeps nodes that were already placed where they were, so a change settles instead of reshuffling.
    public func layout(iterations: Int = 300, from start: [String: SIMD2<Double>] = [:]) -> [String: SIMD2<Double>] {
        let ids = nodes.map(\.id).sorted()
        let n = ids.count
        guard n > 0 else { return [:] }
        let index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        var p = ids.enumerated().map { i, id -> SIMD2<Double> in
            if let s = start[id] { return s }
            let a = Double(i) * 2.399963229728653 + Double(Heuristics.seed(id) % 628) / 100
            let r = 0.9 * (Double(i) + 0.5).squareRoot()
            return SIMD2(cos(a) * r, sin(a) * r)
        }
        let links = edges.compactMap { e in index[e.a].flatMap { a in index[e.b].map { (a, $0, log2(1 + e.weight)) } } }
        let k = 1.0
        let hot = 0.12 * Double(n).squareRoot()
        for step in 0..<iterations {
            let t = hot * (1 - Double(step) / Double(iterations)) + 0.001
            var d = Array(repeating: SIMD2<Double>.zero, count: n)
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let v = p[i] - p[j]
                    let dist = max((v * v).sum().squareRoot(), 0.01)
                    let f = v / dist * (k * k / dist)
                    d[i] += f
                    d[j] -= f
                }
            }
            for (a, b, w) in links {
                let v = p[a] - p[b]
                let dist = max((v * v).sum().squareRoot(), 0.01)
                let f = v / dist * (dist * dist / k * w)
                d[a] -= f
                d[b] += f
            }
            for i in 0..<n {
                d[i] -= p[i] * 0.08
                let len = (d[i] * d[i]).sum().squareRoot()
                if len > 0 { p[i] += d[i] / len * min(len, t) }
            }
        }
        let c = p.reduce(.zero, +) / Double(n)
        return Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, p[$0] - c) })
    }
}
