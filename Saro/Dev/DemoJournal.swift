#if DOGFOOD
import AppKit
import ImageIO
import SaroKit
import SwiftUI

/// `-SaroDemo YES`'s throwaway journal (lib/demo/seed.ts): today's pages, a still and a spoken voice note, as the gate's
/// own tests read them, and before them two weeks of Alex's journal whose threads recur across days (sister Maya,
/// sleep getting better, a launch at work, running), so the mood ribbon, search and the replay have something to find.
/// Synthetic text only (SR-28: real user text never enters fixtures).
@MainActor
enum DemoJournal {
    private struct Item {
        var day: Int
        var at: String
        enum Kind { case page(title: String?, body: String), voice(String), still(caption: String, colors: [UInt32]),
                    song(url: String, title: String, artist: String), commitment(String, done: Bool) }
        var kind: Kind
    }

    private static let today = [
        "Long day at work. Shipped the onboarding flow finally. Had chai with Ravi and we talked about his move to Pune. Feeling tired but good.",
        "It's been a year since Dad died. I keep picking up the phone to call him on Sundays. Today I cried in the car outside the grocery store and couldn't go in.",
        "This deadline is killing me. If I have to sit through one more status meeting I'll die.\nAnyway, walked home the long way and the sky was pink over the park.",
    ]

    private static let history: [Item] = [
        Item(day: 13, at: "23:40", kind: .page(title: "Awake at 3am again", body: "Third night in a row I was awake at 3am running through the launch checklist in my head. I know none of it can be fixed at that hour, but my brain won't switch off and I feel wired. Tomorrow I'm leaving my phone in the kitchen to see if that helps.")),
        Item(day: 13, at: "22:10", kind: .song(url: "https://open.spotify.com/search/weightless%20marconi%20union", title: "Weightless", artist: "Marconi Union")),
        Item(day: 12, at: "08:30", kind: .voice("Slept badly again, maybe four hours, but I'm trying not to spiral about it. My sister Maya called last night and we laughed about nothing for an hour. Honestly, that helped more than anything I tried this week.")),
        Item(day: 10, at: "20:15", kind: .page(title: "Maya's coming to stay", body: "My sister Maya is coming to stay next weekend. I haven't seen her since spring, and on the phone tonight I realised how much I've missed her laugh. I want to actually be present when she's here instead of half-checking Slack.")),
        Item(day: 8, at: "18:20", kind: .still(caption: "River path after the run", colors: [0x7FB7BE, 0x2E5E6E, 0xD8F1F0])),
        Item(day: 8, at: "07:50", kind: .commitment("Run before work twice this week", done: true)),
        Item(day: 7, at: "22:05", kind: .page(title: "Launch week nerves", body: "The launch is in five days and the list keeps growing. I felt anxious most of the afternoon, then went for a slow run by the river and it loosened something. Slept a little better, maybe five hours instead of four.")),
        Item(day: 6, at: "18:40", kind: .voice("Just got back from a run, only three kilometres, but my legs feel alive. For twenty minutes I wasn't thinking about the launch at all, which is new.")),
        Item(day: 5, at: "21:00", kind: .song(url: "https://www.youtube.com/results?search_query=bon+iver+holocene", title: "Holocene", artist: "Bon Iver")),
        Item(day: 5, at: "09:10", kind: .commitment("Send the launch checklist to the team", done: true)),
        Item(day: 4, at: "21:30", kind: .page(title: "Dinner with Maya", body: "Cooked for Maya tonight and we stayed up talking about Mum and the old house. It was tender in a way I didn't expect. She said I seem calmer than last year, which surprised me.")),
        Item(day: 3, at: "12:40", kind: .still(caption: "Flowers Maya left on the table", colors: [0xF7C6C7, 0x7A9E7E, 0xFFE3E3])),
        Item(day: 3, at: "09:00", kind: .commitment("Call Maya back about the weekend", done: false)),
        Item(day: 2, at: "19:50", kind: .page(title: "It shipped", body: "We launched this morning. Nothing broke, the team was brilliant, and I finally exhaled. I slept seven hours last night for the first time in weeks. Grateful is the only word for it.")),
        Item(day: 2, at: "08:15", kind: .still(caption: "Launch morning sky", colors: [0xFFB26B, 0x3E3A7A, 0xFFE0B2])),
        Item(day: 1, at: "07:20", kind: .page(title: "Morning run", body: "Ran 8k along the river before work. My legs are sore but my head is quiet. I think the running is doing more for my sleep than any app ever did.")),
        Item(day: 1, at: "22:10", kind: .voice("Launch retro today. The team said the week felt calmer than they expected, and I think part of that was me finally sleeping. I want to remember this feeling of things being enough.")),
    ]

    /// Seeds the journal, telling LaunchProgress how far it has got, then reads today's entries first.
    static func seed(_ model: AppModel) async {
        let progress = LaunchProgress.shared
        progress.demo = 0
        defer { progress.demo = nil }
        // Alex's journal, named as the web's demo account is (seed.ts), so the avatar and the account menu say whose it is.
        if !UserDefaults.standard.bool(forKey: "SaroOnboarding") {
            await model.saveProfile {
                $0.name = "Alex Demo"
                $0.called = "Alex"
                $0.onboardingDoneAt = .now
            }
        }
        let total = Double(today.count + 2 + history.count)
        var done = 0.0
        func tick() { done += 1; progress.demo = done / total }
        var made: [String] = []
        let ledger = model.ledger

        for (i, t) in today.enumerated() {
            let e = Entry(kind: .reflection, body: t, capturedAt: .now.addingTimeInterval(Double(i - 3) * 3600))
            if (try? await ledger.insertEntry(e)) != nil { made.append(e.id) }
            tick()
        }
        if let still = gradient([0xF2A078, 0x1E4A38]) {
            await model.importStill(still, origin: "demo", at: nil)
            if let id = model.entries.last(where: { $0.kind == .still })?.id { made.append(id) }
        }
        tick()
        if let id = await voice("I walked home through the park after work. The sky was pink, and I felt lighter than I have in weeks.",
                                at: .now.addingTimeInterval(-1800), ledger) { made.append(id) }
        tick()

        for item in history {
            let at = time(item)
            let day = LocalDay.string(for: at)
            switch item.kind {
            case .page(let title, let body):
                let e = Entry(kind: .reflection, titleUser: title, body: body, capturedAt: at)
                if (try? await ledger.insertEntry(e)) != nil { made.append(e.id) }
            case .voice(let words):
                if let id = await voice(words, at: at, ledger) { made.append(id) }
            case .still(let caption, let colors):
                if let id = await still(colors, caption: caption, at: at, ledger) { made.append(id) }
            case .song(let url, let title, let artist):
                let e = Entry(kind: .music, titleUser: title, captionUser: artist, body: url, capturedAt: at)
                if (try? await ledger.insertEntry(e)) != nil { made.append(e.id) }
            case .commitment(let text, let isDone):
                if let c = try? await ledger.addCommitment(text, day: day), isDone { try? await ledger.setDone(c.id, true) }
            }
            tick()
        }
        await model.reload()
        for id in made { model.process(id) }
    }

    /// Developer → Reset Demo Journal: everything erased, then seeded again.
    static func reset(_ model: AppModel) async {
        guard model.isDemo else { return }
        LaunchProgress.shared.demo = 0
        try? await model.ledger.eraseAll()
        await model.loadProfile()
        await seed(model)
    }

    /// The seed's clock (seed.ts seedTime): `day` days ago at `at`, local.
    private static func time(_ item: Item) -> Date {
        let hm = item.at.split(separator: ":").compactMap { Int($0) }
        let base = Calendar.current.date(byAdding: .day, value: -item.day, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: hm.first ?? 12, minute: hm.last ?? 0, second: 0, of: base) ?? base
    }

    private static func voice(_ words: String, at: Date, _ ledger: Ledger) async -> String? {
        var e = Entry(kind: .voice, capturedAt: at, processingStatus: ProcessingStatus.pending)
        let asset = MediaAsset(fileName: "\(e.localDay)/voice/\(e.id).caf", kind: .audio, origin: "demo", state: "ready")
        guard await DemoSpeech.write(words, to: ledger.url(for: asset)) else { return nil }
        e.mediaId = asset.id
        guard (try? await ledger.insertMedia(asset)) != nil, (try? await ledger.insertEntry(e)) != nil else { return nil }
        return e.id
    }

    private static func still(_ colors: [UInt32], caption: String, at: Date, _ ledger: Ledger) async -> String? {
        var e = Entry(kind: .still, captionUser: caption, capturedAt: at, processingStatus: ProcessingStatus.pending)
        let asset = MediaAsset(fileName: "\(e.localDay)/stills/\(e.id).heic", kind: .image, origin: "demo", state: "ready")
        let url = ledger.url(for: asset)
        guard let png = gradient(colors), let src = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
              (try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.heic" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        e.mediaId = asset.id
        guard (try? await ledger.insertMedia(asset)) != nil, (try? await ledger.insertEntry(e)) != nil else { return nil }
        return e.id
    }

    /// A 640 × 420 diagonal gradient through the colours, as PNG.
    private static func gradient(_ hex: [UInt32]) -> Data? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: 640, height: 420, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = hex.map { CGColor(srgbRed: CGFloat($0 >> 16 & 0xFF) / 255, green: CGFloat($0 >> 8 & 0xFF) / 255, blue: CGFloat($0 & 0xFF) / 255, alpha: 1) }
        guard let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil) else { return nil }
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 640, y: 420), options: [])
        return ctx.makeImage().flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }
}
#endif
