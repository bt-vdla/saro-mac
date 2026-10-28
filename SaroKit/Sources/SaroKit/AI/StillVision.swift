import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import Vision

@Generable
struct StillOut {
    @Guide(description: "One plain sentence, at most 20 words, saying only what is visible in the photo")
    var caption: String
    @Guide(description: "3 to 6 single nouns for what is in the photo", .count(3...6))
    var tags: [String]
}

/// What Saro made of a still: a caption and tags, or none (a guardrail, a refusal, an image that won't decode), with
/// the content-free provenance of the run. `provenance.status` is `ok` or why it has no caption.
public struct StillDescription: Sendable, Hashable {
    public var caption: String?
    public var tags: [String]
    public var provenance: Provenance
}

extension SaroAI {
    public static let stillPromptVersion = "still-1"
    public static let stillHeuristicVersion = "still-vision-1"
    static let stillInstructions = """
    You describe one photo for its owner's private journal. Say only what is plainly visible. \
    Never guess who anyone is, their name, age or how they feel. Never give advice or judge.
    """
    static let stillTask = "Describe this photo."
    static let stillTimeout: Duration = .seconds(20)

    /// Whether the on-device model can take an image (FoundationModels capabilities; the test stand-in always can).
    public nonisolated var canSee: Bool {
        status == .available && (stub != nil || SystemLanguageModel.default.capabilities.contains(.vision))
    }

    /// FR-CAP-08, SR-11: a fresh session, guided `@Generable` on default guardrails only, never the permissive rung, at
    /// most two calls. A guardrail or refusal leaves no caption (SR-09: never re-asked looser). Without the model, or when
    /// it fails for any other reason, the Vision twin describes it. Nil when rate-limited (§11.7): ask again later.
    public func describeStill(at url: URL) async -> StillDescription? {
        let start = ContinuousClock.now
        guard let image = StillVision.image(at: url) else {
            return StillDescription(caption: nil, tags: [], provenance: stillProvenance(.heuristic, 0, start, "unreadable"))
        }
        var calls = 0
        if canSee {
            let stub = self.stub
            for attempt in 0..<2 {
                calls += 1
                do {
                    let task = attempt == 0 ? Self.stillTask : Self.stillTask + " " + Self.stillCorrection
                    let out = try await Self.withTimeout(Self.stillTimeout) { try await Self.see(image, task, stub) }
                    guard let out else { break }
                    if let caption = StillVision.clean(out.caption) {
                        return StillDescription(caption: caption, tags: StillVision.tags(out.tags), provenance: stillProvenance(.guided, calls, start))
                    }
                } catch let error where Ladder.isStop(error) {
                    let reason = Ladder.reason(error)
                    if reason == "rate_limited" { return nil }
                    if reason == "guardrail" || reason == "refusal" {
                        return StillDescription(caption: nil, tags: [], provenance: stillProvenance(.guided, calls, start, reason))
                    }
                    break
                } catch {}
            }
        }
        let twin = await StillVision.heuristic(image)
        return StillDescription(caption: twin.caption, tags: twin.tags, provenance: stillProvenance(.heuristic, calls, start))
    }

    static let stillCorrection = "Your last reply could not be used. Reply with one plain sentence about what is visible."

    private static func see(_ image: CGImage, _ task: String, _ stub: (@Sendable (String) async throws -> String)?) async throws -> StillOut {
        if let stub { return try await Ladder.decode(StillOut.self, from: stub(task)) }
        return try await LanguageModelSession(model: SystemLanguageModel.default, instructions: stillInstructions)
            .respond(to: Prompt { task; Attachment(image) }, generating: StillOut.self, options: options).content
    }

    private func stillProvenance(_ rung: Rung, _ calls: Int, _ start: ContinuousClock.Instant, _ status: String = "ok") -> Provenance {
        Provenance(executor: rung == .heuristic ? "heuristic" : "on_device", rung: rung, guardrails: rung == .guided ? "default" : nil,
                   variant: rung == .guided ? variant : nil, osBuild: Self.osBuild, contextSize: rung == .guided ? contextSize : nil,
                   promptVersion: rung == .guided ? Self.stillPromptVersion : Self.stillHeuristicVersion, tokensIn: nil,
                   modelCalls: calls, latencyMs: Int((ContinuousClock.now - start) / .milliseconds(1)), status: status)
    }
}

/// The offline twin: Vision's labels and any words in the photo, else its colours (`describePixels`, ai.ts:373).
/// Saro's description, never "In your words".
public enum StillVision {
    /// Downscaled to at most `maxPixels` on the long side, upright.
    static func image(at url: URL, maxPixels: Int = 1024) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary)
    }

    /// The text the gate reads and the hash a description's verdict is keyed by: the caption, then its tags.
    public static func gatedText(_ caption: String, _ tags: [String]) -> String {
        tags.isEmpty ? caption : caption + "\n" + tags.joined(separator: ", ")
    }

    /// One line, at most 240 characters; nil when nothing is left.
    static func clean(_ caption: String) -> String? {
        let one = caption.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return one.isEmpty ? nil : Ladder.truncated(one, maxChars: 240)
    }

    /// Lowercased, de-duplicated, at most six, each a short word or two.
    static func tags(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased() }
            .filter { !$0.isEmpty && $0.count <= 24 && seen.insert($0).inserted }
            .prefix(6).map { $0 }
    }

    static func heuristic(_ image: CGImage) async -> (caption: String, tags: [String]) {
        let labels = ((try? await ClassifyImageRequest().perform(on: image)) ?? []).map { ($0.identifier, $0.confidence) }
        var text = RecognizeTextRequest()
        text.recognitionLevel = .accurate
        let words = ((try? await text.perform(on: image)) ?? []).compactMap { $0.topCandidates(1).first }
            .filter { $0.confidence >= 0.5 }.map(\.string)
        return caption(labels: labels, words: words) ?? describePixels(rgba(image))
    }

    /// Labels Vision gives every photo, or that say nothing on their own.
    static let vague: Set<String> = ["outdoor", "indoor", "structure", "land", "material", "art", "cloudy", "sunny", "night_sky",
                                     "consumable", "conveyance", "machine", "liquid", "water_body", "plant", "animal", "mammal"]
    static let massNouns: Set<String> = ["water", "grass", "snow", "sand", "food", "foliage", "greenery", "people", "text", "fog"]

    /// "A photo of a blue sky, a hill and a road, with the words “OPEN LATE”." from labels at confidence 0.3 or more and
    /// recognised lines. Nil when neither says anything.
    static func caption(labels: [(String, Float)], words: [String]) -> (caption: String, tags: [String])? {
        var names: [String] = []
        for (id, c) in labels.sorted(by: { $0.1 > $1.1 }) where c >= 0.3 && !vague.contains(id) {
            let name = id.replacingOccurrences(of: "_other", with: "").replacingOccurrences(of: "_", with: " ")
            if !names.contains(name) { names.append(name) }
        }
        // "sky" says less than "blue sky": keep the longer of two labels that share a word.
        names = names.filter { n in !names.contains { $0 != n && $0.split(separator: " ").contains(Substring(n)) } }
        let shown = Array(names.prefix(3))
        let quote = words.joined(separator: " ").split(separator: " ").prefix(6).joined(separator: " ")
        guard !shown.isEmpty || !quote.isEmpty else { return nil }
        var s = "A photo"
        if !shown.isEmpty { s += " of " + list(shown.map(article)) }
        if !quote.isEmpty { s += (shown.isEmpty ? " with" : ", with") + " the words “\(quote)”" }
        return (s + ".", Array(names.prefix(6)))
    }

    static func article(_ noun: String) -> String {
        if massNouns.contains(noun) || noun.hasSuffix("s") && !noun.hasSuffix("ss") { return noun }
        if ["sky", "sea", "ocean", "sun", "moon", "horizon"].contains(noun) { return "the " + noun }
        return ("aeiou".contains(noun.first ?? "x") ? "an " : "a ") + noun
    }

    static func list(_ items: [String]) -> String {
        items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }

    /// 24 × 24 RGBA samples, as the web draws the still into a 24 px canvas.
    static func rgba(_ image: CGImage) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: 24 * 24 * 4)
        px.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: 24, height: 24, bitsPerComponent: 8, bytesPerRow: 96,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        return px
    }

    static let hueNames = ["red", "orange", "yellow", "lime", "green", "teal", "cyan", "blue", "indigo", "violet", "pink", "rose"]

    /// A caption from the pixels' colours alone (ai.ts `describePixels`), so it never guesses at what is in the photo.
    public static func describePixels(_ rgba: [UInt8]) -> (caption: String, tags: [String]) {
        var (lum, sat, warm, cool, n) = (0.0, 0.0, 0.0, 0.0, 0)
        var bins = [Double](repeating: 0, count: 12)
        var i = 0
        while i + 3 < rgba.count {
            defer { i += 4 }
            if rgba[i + 3] < 16 { continue }
            let (r, g, b) = (Double(rgba[i]) / 255, Double(rgba[i + 1]) / 255, Double(rgba[i + 2]) / 255)
            let (mx, mn) = (max(r, g, b), min(r, g, b))
            let l = (mx + mn) / 2
            let d = mx - mn
            let s = d == 0 ? 0 : d / (1 - abs(2 * l - 1))
            var h = 0.0
            if d != 0 {
                h = mx == r ? ((g - b) / d).truncatingRemainder(dividingBy: 6) : mx == g ? (b - r) / d + 2 : (r - g) / d + 4
                h = (h * 60 + 360).truncatingRemainder(dividingBy: 360)
            }
            lum += 0.2126 * r + 0.7152 * g + 0.0722 * b
            sat += s
            n += 1
            if s > 0.15 {
                bins[Int(h / 30) % 12] += s
                if h < 70 || h >= 330 { warm += s } else if h >= 160 && h < 300 { cool += s }
            }
        }
        guard n > 0 else { return ("A still.", []) }
        let avg = lum / Double(n)
        let light = avg > 0.68 ? "bright" : avg > 0.4 ? "soft" : "dim"
        if sat / Double(n) < 0.12 { return ("A \(light), muted still in greys.", [light, "muted"]) }
        let hue = hueNames[bins.firstIndex(of: bins.max() ?? 0) ?? 0]
        let temp = warm > cool * 1.3 ? "warm" : cool > warm * 1.3 ? "cool" : "mixed"
        return temp == "mixed"
            ? ("A \(light) still, mostly \(hue).", [light, hue])
            : ("A \(light), \(temp)-toned still, mostly \(hue).", [light, temp, hue])
    }
}
