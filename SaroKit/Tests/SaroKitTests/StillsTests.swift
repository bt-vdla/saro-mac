import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SaroKit

// P-STILLS: Saro's description of a still. Synthetic images and text only (SR-28).

actor StillCalls {
    private(set) var count = 0
    func add() { count += 1 }
}

/// A model stand-in that describes every photo as `caption` (or throws `fail`), labels every classifier prompt `label`,
/// and answers entry and day readings with `echo`.
func stillAI(_ caption: String = "A path through a green park.", tags: [String] = ["path", "park", "trees"], label: String = "NONE",
             fail: (any Error)? = nil, calls: StillCalls? = nil, status: SaroAI.Status = .available) -> SaroAI {
    SaroAI(stub: { prompt in
        if prompt.hasPrefix(SaroAI.stillTask) {
            await calls?.add()
            if let fail { throw fail }
            return json(["caption": caption, "tags": tags])
        }
        if prompt.hasSuffix("Label:") { return label }
        return echo(prompt.hasPrefix("Notes on today's entries") ? .day : .entry, prompt)
    }, status: status)
}

/// A still whose image is a flat colour on disk, ready to describe.
func stillEntry(_ l: Ledger, caption: String? = nil, rgb: (CGFloat, CGFloat, CGFloat) = (1, 0.55, 0)) async throws -> Entry {
    var e = Entry(kind: .still, captionUser: caption)
    let asset = MediaAsset(fileName: "\(e.localDay)/stills/\(e.id).png", kind: .image, origin: "test", state: "ready")
    let url = l.url(for: asset)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let ctx = try #require(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
    let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), nil)
    #expect(CGImageDestinationFinalize(dest))
    e.mediaId = asset.id
    try await l.insertMedia(asset)
    try await l.insertEntry(e)
    return e
}

/// Every word the journal holds, as Export writes it.
func exported(_ l: Ledger) async throws -> String {
    let url = FileManager.default.temporaryDirectory.appending(path: "saro-export-\(UUID().uuidString).json")
    try await l.exportJSON(to: url)
    return try String(contentsOf: url, encoding: .utf8)
}

// MARK: The offline twin

@Test func visionLabelsAndWordsMakeATemplatedCaption() throws {
    let labels: [(String, Float)] = [("outdoor", 0.78), ("sky", 0.78), ("blue_sky", 0.77), ("hill", 0.7), ("road", 0.56),
                                     ("road_other", 0.56), ("cloudy", 0.36), ("structure", 0.3), ("painting", 0.29)]
    let road = try #require(StillVision.caption(labels: labels, words: []))
    #expect(road.caption == "A photo of a blue sky, a hill and a road.")
    #expect(road.tags == ["blue sky", "hill", "road"])
    #expect(StillVision.caption(labels: [("sign", 0.9)], words: ["OPEN", "LATE"])?.caption == "A photo of a sign, with the words “OPEN LATE”.")
    #expect(StillVision.caption(labels: [], words: ["Happy birthday to you and many more"])?.caption
        == "A photo with the words “Happy birthday to you and many”.")
    #expect(StillVision.caption(labels: [("sky", 0.8), ("apple", 0.6), ("rocks", 0.5), ("people", 0.4)], words: [])?.caption
        == "A photo of the sky, an apple and rocks.")
    #expect(StillVision.caption(labels: [("outdoor", 0.9), ("dog", 0.2)], words: []) == nil)
    // Labels that end in "s" but name one thing, and ones that take no article.
    #expect(StillVision.caption(labels: [("bus", 0.9), ("cactus", 0.6), ("shoes", 0.5)], words: [])?.caption
        == "A photo of a bus, a cactus and shoes.")
    #expect(StillVision.caption(labels: [("chess", 0.9), ("wedding_dress", 0.6), ("stained_glass", 0.5)], words: [])?.caption
        == "A photo of chess, a wedding dress and stained glass.")
}

@Test func aLargeStillIsKeptAt4096PixelsUpright() throws {
    func png(_ w: Int, _ h: Int) throws -> CGImageSource {
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let data = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), nil)
        #expect(CGImageDestinationFinalize(dest))
        return try #require(CGImageSourceCreateWithData(data, nil))
    }
    let big = try #require(StillVision.keepable(try png(5000, 100)))
    #expect(big.width == 4096 && (81...82).contains(big.height))
    let small = try #require(StillVision.keepable(try png(64, 48)))
    #expect(small.width == 64 && small.height == 48)

    // A photo turned on its side (EXIF 6) reports its upright size.
    let url = FileManager.default.temporaryDirectory.appending(path: "saro-still-\(UUID().uuidString).jpg")
    let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(dest, small, [kCGImagePropertyOrientation: 6] as CFDictionary)
    #expect(CGImageDestinationFinalize(dest))
    #expect(StillVision.pixelSize(at: url) == CGSize(width: 48, height: 64))
}

@Test func theOpenedStillTakesThePhotosShape() {
    let window = CGSize(width: 1320, height: 860)
    for aspect: CGFloat in [1.5, 0.75, 4, 1] {
        let f = CanvasMath.stillFrame(in: window, aspect: aspect, below: 170)
        #expect(abs(f.width / f.height - aspect) < 0.001)
        #expect(f.width <= window.width * 0.86 + 0.001 && f.height <= window.height * 0.74 + 0.001)
        #expect(abs(f.midX - window.width / 2) < 0.001 && f.minY >= 24 && f.maxY + 170 <= window.height)
    }
    #expect(CanvasMath.stillFrame(in: window, aspect: 1.5, below: 170).width > CanvasMath.stillFrame(in: window, aspect: 0.75, below: 170).width)
    let unknown = CanvasMath.stillFrame(in: window, aspect: nil, below: 170)
    #expect(abs(unknown.width / unknown.height - 4 / 3) < 0.001)
}

@Test func describePixelsSaysWhatTheWebSays() {
    let fill = { (r: UInt8, g: UInt8, b: UInt8, a: UInt8) in Array(repeating: [r, g, b, a], count: 576).flatMap { $0 } }
    #expect(StillVision.describePixels(fill(128, 128, 128, 255)) == ("A soft, muted still in greys.", ["soft", "muted"]))
    #expect(StillVision.describePixels(fill(255, 140, 0, 255)) == ("A soft, warm-toned still, mostly orange.", ["soft", "warm", "orange"]))
    #expect(StillVision.describePixels(fill(30, 60, 200, 255)).caption == "A dim, cool-toned still, mostly blue.")
    #expect(StillVision.describePixels(fill(0, 0, 0, 0)) == ("A still.", []))
}

@Test func gatedTextIsTheCaptionThenItsTags() {
    #expect(StillVision.gatedText("A dog.", ["dog", "grass"]) == "A dog.\ndog, grass")
    #expect(StillVision.gatedText("A dog.", []) == "A dog.")
    #expect(StillVision.tags([" Dog ", "dog", "", "Grass.", "a very long tag that goes on and on"]) == ["dog", "grass"])
    #expect(StillVision.clean("  Two\nlines ") == "Two lines")
    #expect(StillVision.clean(" \n ") == nil)
}

// MARK: The pipeline

@Test func aStillIsDescribedGatedAndBecomesItsDaysDigest() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: stillAI())
    let s = try await stillEntry(l)
    await p.process(entryId: s.id) {}

    let c = try #require(try await l.stillCaption(entryId: s.id))
    #expect(c.caption == "A path through a green park." && c.tags == ["path", "park", "trees"])
    #expect(c.status == "ok" && c.executor == "on_device" && c.rung == "guided" && c.modelCalls == 1)
    let run = try #require(try await l.run("SELECT * FROM ai_run WHERE feature='still_caption'").first)
    #expect(run["guardrails"]?.string == "default" && run["prompt_version"]?.string == SaroAI.stillPromptVersion)
    #expect(try await rowCount(l, "ai_run_input", "field='image' AND entry_id='\(s.id)'") == 1)
    let v = try #require(try await l.verdicts(day: s.localDay)[s.id])
    #expect(v.verdict == "clear" && v.textSha256 == sha256(StillVision.gatedText(c.caption!, c.tags)))
    // DR-04: no AI path writes the entry.
    let e = try #require(try await l.entry(s.id))
    #expect(e.captionUser == nil && e.processingStatus == ProcessingStatus.done)
    #expect(try await p.text(for: e)?.field == Pipeline.aiCaptionField)

    #expect(await p.dayStatus(s.localDay) == .ready)
    let day = try #require(await p.readDay(s.localDay))
    #expect(day.entryIds == [s.id] && day.quotes.isEmpty)
    // Described once: another pass makes no call.
    await p.process(entryId: s.id) {}
    #expect(try await rowCount(l, "ai_run", "feature='still_caption'") == 1)
}

@Test func onlyTheUsersWordsAreQuotedAndTheirCaptionOutranksSaros() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: stillAI())
    let page = Entry(kind: .reflection, body: "Walked home through the park after work. The sky was pink over the trees.")
    try await l.insertEntry(page)
    let s = try await stillEntry(l)
    await p.process(entryId: page.id) {}
    await p.process(entryId: s.id) {}
    let first = try #require(await p.readDay(s.localDay))
    #expect(Set(first.entryIds) == [page.id, s.id])
    #expect(first.quotes.allSatisfy { $0.entryId == page.id && $0.field == "body" })
    try await expectVerbatim(first, l)

    // The user's caption becomes the still's text of record, and its words can be quoted.
    try await l.updateEntryText(id: s.id, body: nil, titleUser: nil, captionUser: "Ravi's new flat in Pune, finally unpacked.")
    await p.process(entryId: s.id) {}
    let e = try #require(try await l.entry(s.id))
    #expect(try await p.text(for: e)?.field == "caption_user")
    let second = try #require(await p.readDay(s.localDay))
    #expect(second.quotes.allSatisfy { $0.field != Pipeline.aiCaptionField })
    try await expectVerbatim(second, l)

    // Cleared again, Saro's description is the still's reading once more.
    try await l.updateEntryText(id: s.id, body: nil, titleUser: nil, captionUser: nil)
    await p.process(entryId: s.id) {}
    #expect(try await l.annotations(day: s.localDay)[s.id]?.caption == "A path through a green park.")
    #expect(await p.dayStatus(s.localDay) == .ready)
    #expect(try #require(await p.readDay(s.localDay)).entryIds.contains(s.id))
}

@Test func aRiskPhraseInTheDescriptionHoldsTheStillAndStoresNothing() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: stillAI("A note on the fridge that says I want to die."))
    let s = try await stillEntry(l)
    await p.process(entryId: s.id) {}
    let v = try #require(try await l.verdicts(day: s.localDay)[s.id])
    #expect(v.verdict == "safety_hold" && v.layer == 3 && v.reasonCode == "output_gate")
    #expect(try await rowCount(l, "entry_annotation") == 0)
    #expect(try await l.stillCaption(entryId: s.id)?.status == StillCaption.held)
    #expect(!(try await exported(l)).contains("fridge"))
    #expect(await p.dayStatus(s.localDay) == .held)
    #expect(await p.readDay(s.localDay) == nil)

    // The hold stands whatever caption is written, and Describe again isn't run on a held still.
    try await l.updateEntryText(id: s.id, body: nil, titleUser: nil, captionUser: "Just the fridge.")
    await p.describeAgain(s.id)
    await p.process(entryId: s.id) {}
    #expect(await p.dayStatus(s.localDay) == .held)
    #expect(try await rowCount(l, "ai_run", "feature='still_caption'") == 1)
}

@Test func theClassifierHoldsADescriptionToo() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: stillAI(label: "PASSIVE"))
    let s = try await stillEntry(l)
    await p.process(entryId: s.id) {}
    let v = try #require(try await l.verdicts(day: s.localDay)[s.id])
    #expect(v.verdict == "safety_hold" && v.layer == 2)
    #expect(try await rowCount(l, "entry_annotation") == 0)
    #expect(await p.dayStatus(s.localDay) == .held)
}

@Test func aGuardrailLeavesNoCaptionAndIsNeverAskedLooser() async throws {
    let l = try tempLedger()
    let calls = StillCalls()
    let p = Pipeline(ledger: l, ai: stillAI(fail: guardrail, calls: calls))
    let s = try await stillEntry(l)
    await p.process(entryId: s.id) {}
    #expect(await calls.count == 1)
    let c = try #require(try await l.stillCaption(entryId: s.id))
    #expect(c.status == "guardrail" && c.caption == nil)
    #expect(try await rowCount(l, "safety_verdict") == 0)
    #expect(try await rowCount(l, "entry_annotation") == 0)
    #expect(await p.dayStatus(s.localDay) == .empty)
    #expect(try await l.entry(s.id)?.processingStatus == ProcessingStatus.done)
}

/// SR-13: a description held when its own text is checked again (here an SR-17 re-gate once the classifier is back, as
/// after a SAFETY_VERSION bump) holds the day, though its run was cleared.
@Test func aReGateHoldOnTheDescriptionHoldsTheDay() async throws {
    let l = try tempLedger()
    let checks = StillCalls()
    let p = Pipeline(ledger: l, ai: SaroAI(stub: { prompt in
        if prompt.hasPrefix(SaroAI.stillTask) { return json(["caption": "A path through a green park.", "tags": ["path", "park"]]) }
        if prompt.hasSuffix("Label:") {
            guard prompt.contains("green park") else { return "NONE" }
            await checks.add()
            if await checks.count == 1 { throw assetsMissing }
            return "PASSIVE"
        }
        return echo(prompt.hasPrefix("Notes on today's entries") ? .day : .entry, prompt)
    }))
    let page = Entry(kind: .reflection, body: "Walked home through the park after work. The sky was pink over the trees.")
    try await l.insertEntry(page)
    let s = try await stillEntry(l)
    await p.process(entryId: page.id) {}
    await p.process(entryId: s.id) {}

    #expect(await checks.count == 2)
    let v = try #require(try await l.verdicts(day: s.localDay)[s.id])
    #expect(v.verdict == "safety_hold" && v.layer == 2)
    let c = try #require(try await l.stillCaption(entryId: s.id))
    #expect(c.status == StillCaption.held && c.standsHeld && c.caption == nil)
    #expect(try await p.text(for: try #require(try await l.entry(s.id))) == nil)
    #expect(await p.dayStatus(s.localDay) == .held)
    #expect(await p.readDay(s.localDay) == nil)
    #expect(try await rowCount(l, "insight_snapshot") == 0)
    #expect(!(try await exported(l)).contains("green park"))

    // It stands whatever caption is written, and isn't described again until a newer gate.
    try await l.updateEntryText(id: s.id, body: nil, titleUser: nil, captionUser: "The park.")
    await p.describeAgain(s.id)
    await p.process(entryId: s.id) {}
    #expect(await p.dayStatus(s.localDay) == .held)
    #expect(try await rowCount(l, "ai_run", "feature='still_caption'") == 1)
}

/// SR-15: a still held by its own caption (here one the migration queued) is never sent to the model.
@Test func aStillHeldByItsCaptionIsNotDescribed() async throws {
    let l = try tempLedger()
    let calls = StillCalls()
    let p = Pipeline(ledger: l, ai: stillAI(calls: calls))
    let caption = "A note to myself: I want to die."
    let s = try await stillEntry(l, caption: caption)
    try await l.insertVerdict(SafetyVerdictRow(entryId: s.id, textSha256: sha256(caption), safetyVersion: SafetyGate.version, layer: 1,
                                               verdict: "safety_hold", reasonCode: "phrase_hit"))
    await p.process(entryId: s.id) {}
    #expect(await calls.count == 0)
    #expect(try await l.stillCaption(entryId: s.id) == nil)
    #expect(await p.dayStatus(s.localDay) == .held)
}

/// A new description doesn't displace the reading of the user's own caption, so the unchanged caption isn't read again.
@Test func describeAgainKeepsTheReadingOfTheUsersCaption() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: stillAI())
    let s = try await stillEntry(l, caption: "Ravi's new flat in Pune, finally unpacked.")
    await p.process(entryId: s.id) {}
    let reading = try #require(try await l.annotations(day: s.localDay)[s.id])
    #expect(try await rowCount(l, "ai_run", "feature='entry_reading'") == 1)

    await p.describeAgain(s.id)
    await p.process(entryId: s.id) {}
    #expect(try await rowCount(l, "ai_run", "feature='still_caption'") == 2)
    #expect(try await rowCount(l, "ai_run", "feature='entry_reading'") == 1)
    let kept = try #require(try await l.annotations(day: s.localDay)[s.id])
    #expect(kept.aiRunId == reading.aiRunId && kept.title == reading.title && kept.quote == reading.quote && kept.moodLabel == reading.moodLabel)
    #expect(try await l.stillCaption(entryId: s.id)?.caption == "A path through a green park.")
    let day = try #require(await p.readDay(s.localDay))
    #expect(day.entryIds == [s.id] && day.quotes.allSatisfy { $0.field == "caption_user" })
}

actor Switch {
    private(set) var on = false
    func set(_ v: Bool) { on = v }
}

@Test func aDescribeAgainDeferredByARateLimitRunsOnTheNextPass() async throws {
    let l = try tempLedger()
    let limited = Switch()
    let p = Pipeline(ledger: l, ai: SaroAI(stub: { prompt in
        if prompt.hasPrefix(SaroAI.stillTask) {
            if await limited.on { throw rateLimited }
            return json(["caption": "A path through a green park.", "tags": ["path", "park"]])
        }
        if prompt.hasSuffix("Label:") { return "NONE" }
        return echo(prompt.hasPrefix("Notes on today's entries") ? .day : .entry, prompt)
    }))
    let s = try await stillEntry(l)
    await p.process(entryId: s.id) {}
    await limited.set(true)
    await p.describeAgain(s.id)
    await p.process(entryId: s.id) {}
    #expect(try await rowCount(l, "ai_run", "feature='still_caption'") == 1)
    #expect(try await l.entry(s.id)?.processingStatus == ProcessingStatus.pending)

    await limited.set(false)
    await p.process(entryId: s.id) {}
    #expect(try await rowCount(l, "ai_run", "feature='still_caption'") == 2)
    #expect(try await l.entry(s.id)?.processingStatus == ProcessingStatus.done)
}

@Test func aRateLimitDefersTheDescription() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: stillAI(fail: rateLimited))
    let s = try await stillEntry(l)
    await p.process(entryId: s.id) {}
    #expect(try await l.stillCaption(entryId: s.id) == nil)
    #expect(try await l.entry(s.id)?.processingStatus == ProcessingStatus.pending)
}

@Test func withoutTheModelTheVisionTwinDescribesItAndTheModelLaterRetells() async throws {
    let l = try tempLedger()
    let calls = StillCalls()
    let off = Pipeline(ledger: l, ai: stillAI(calls: calls, status: .unavailable(reason: "appleIntelligenceNotEnabled")))
    let s = try await stillEntry(l)
    await off.process(entryId: s.id) {}
    let twin = try #require(try await l.stillCaption(entryId: s.id))
    #expect(twin.executor == "heuristic" && twin.rung == "heuristic" && twin.caption != nil && twin.modelCalls == 0)
    #expect(await calls.count == 0)
    #expect(try await l.verdicts(day: s.localDay)[s.id]?.verdict == "unavailable_clear")
    #expect(await off.dayStatus(s.localDay) == .ready)

    // Once the model can see, the still is described again by it.
    let on = Pipeline(ledger: l, ai: stillAI(calls: calls))
    await on.process(entryId: s.id) {}
    #expect(await calls.count == 1)
    #expect(try await l.stillCaption(entryId: s.id)?.executor == "on_device")
    #expect(try await l.verdicts(day: s.localDay)[s.id]?.verdict == "clear")
}

@Test func describeAgainRunsAFreshDescription() async throws {
    let l = try tempLedger()
    let calls = StillCalls()
    let p = Pipeline(ledger: l, ai: stillAI(calls: calls))
    let s = try await stillEntry(l)
    await p.process(entryId: s.id) {}
    await p.process(entryId: s.id) {}
    #expect(await calls.count == 1)
    await p.describeAgain(s.id)
    await p.process(entryId: s.id) {}
    #expect(await calls.count == 2)
    #expect(try await rowCount(l, "ai_run", "feature='still_caption'") == 2)
    #expect(try await l.stillCaption(entryId: s.id)?.caption != nil)
}

@Test func anUnreadableImageIsLabelledNotGated() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: stillAI())
    var e = Entry(kind: .still)
    let asset = MediaAsset(fileName: "\(e.localDay)/stills/\(e.id).png", kind: .image, origin: "test", state: "ready")
    try FileManager.default.createDirectory(at: l.url(for: asset).deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not an image".utf8).write(to: l.url(for: asset))
    e.mediaId = asset.id
    try await l.insertMedia(asset)
    try await l.insertEntry(e)
    await p.process(entryId: e.id) {}
    #expect(try await l.stillCaption(entryId: e.id)?.status == "unreadable")
    #expect(try await rowCount(l, "safety_verdict") == 0)
}

// MARK: Live model (a synthetic image, SR-28)

@Test(.enabled(if: liveModelAvailable && SaroAI().canSee), .liveModel) func liveStillIsDescribedAndCleared() async throws {
    let l = try tempLedger()
    let p = Pipeline(ledger: l, ai: SaroAI())
    let s = try await stillEntry(l, rgb: (0.12, 0.29, 0.22))
    await p.process(entryId: s.id) {}
    let c = try #require(try await l.stillCaption(entryId: s.id))
    #expect(c.executor == "on_device" && c.rung == "guided" && (1...2).contains(c.modelCalls))
    #expect(c.caption != nil && (1...6).contains(c.tags.count))
    #expect(try await l.verdicts(day: s.localDay)[s.id]?.verdict == "clear")
    #expect(await p.dayStatus(s.localDay) == .ready)
    print("live still:", c)
}
