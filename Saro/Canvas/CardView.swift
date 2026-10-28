import AVFoundation
import ImageIO
import SaroKit
import SwiftUI

extension EntryKind {
    var tint: Color {
        switch self {
        case .moment: Tok.moment
        case .voice: Tok.echo
        case .still: Tok.still
        case .reflection: Tok.reflection
        case .music: Tok.music
        }
    }

    var noun: String {
        switch self {
        case .moment: "Moment"
        case .voice: "Voice note"
        case .still: "Still"
        case .reflection: "Writing"
        case .music: "Song"
        }
    }

    var symbol: String {
        switch self {
        case .moment: "video"
        case .voice: "waveform"
        case .still: "photo"
        case .reflection: "text.alignleft"
        case .music: "music.note"
        }
    }
}

extension AppModel {
    /// User words outrank AI (DR-04). A held or unchecked entry never shows an AI title.
    func title(for e: Entry) -> String {
        if let t = e.titleUser, !t.isEmpty { return t }
        if e.kind == .still { return caption(for: e) ?? e.kind.noun }
        if e.kind == .reflection, let first = e.body?.split(separator: "\n").first, !first.isEmpty, (e.body?.contains("\n") ?? false) {
            return String(first.prefix(80))
        }
        // A held day shows no AI text at all (SR-13), titles included.
        if verdicts[e.id]?.verdict == "clear", !isDayHeld, let t = annotations[e.id]?.title, let first = t.first { return first.uppercased() + t.dropFirst() }
        return e.kind.noun
    }

    /// A still's caption (ImageStillCard.tsx): the user's, else Saro's description once checked; a held or unchecked
    /// still, or any still on a held day (SR-13), shows only the user's.
    func caption(for e: Entry) -> String? {
        if let c = e.captionUser?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { return c }
        guard !isDayHeld, let v = verdicts[e.id]?.verdict, v == "clear" || v == "unavailable_clear" else { return nil }
        return annotations[e.id]?.caption
    }

    /// A short, honest status for the card footer, or nil when there's nothing to say.
    func status(for e: Entry) -> String? {
        switch e.processingStatus {
        case ProcessingStatus.recording: return "Recording…"
        case ProcessingStatus.transcribing: return "Transcribing…"
        case ProcessingStatus.pending, ProcessingStatus.gating, ProcessingStatus.reading:
            // A held entry being checked again after an edit stays held until its new text clears.
            if verdicts[e.id]?.verdict == "safety_hold" { return "Saved · not read" }
            return e.kind == .still ? nil : "Reading…"
        case ProcessingStatus.transcriptUnavailable: return "Transcript not ready"
        case ProcessingStatus.failed: return "Couldn't save"
        default: break
        }
        switch verdicts[e.id]?.verdict {
        case "safety_hold": return "Saved · not read"
        case "technical_hold": return "Couldn't hear clearly"
        case "unavailable_caution": return "Awaiting a check"
        default: return nil
        }
    }

    /// A writing card's title and the body under it: a multi-line page titles itself with its first line.
    func titleAndBody(_ e: Entry) -> (String, String) {
        let text = (e.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        if e.titleUser == nil, lines.count == 2, !lines[0].isEmpty {
            return (String(lines[0]), String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (title(for: e), text)
    }

    /// None for any entry on a day with a safety hold (SR-13's whole-day rule).
    func mood(for e: Entry) -> String? {
        guard verdicts[e.id]?.verdict == "clear", !isDayHeld else { return nil }
        return annotations[e.id]?.moodLabel
    }

    /// Saro's line about the entry, wherever its mood may show; the labelled 'In your words' quote-back stays in the detail.
    func summary(for e: Entry) -> String? {
        guard verdicts[e.id]?.verdict == "clear", !isDayHeld, let a = annotations[e.id], a.generator != "heuristic" else { return nil }
        return a.summary
    }
}

/// A card on the canvas, drawn to the web build's specs (VideoMomentCard, VoiceEchoCard, ImageStillCard,
/// TextReflectionCard): each type has its own shape, and every card shares the "title · time" footer.
struct CardFace: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    var selected = false
    /// A voice note open in place: the card takes the player's own size.
    var open = false
    /// The card's box while its handle is dragged; else its stored size.
    var size: CGSize?
    @State private var hover = false
    @State private var discHover = false

    var body: some View {
        content
            .frame(width: open ? nil : box.width, height: open ? nil : box.height)
            .overlay {
                if selected && entry.kind != .voice {
                    RoundedRectangle(cornerRadius: radius + 4).strokeBorder(Tok.sage.opacity(0.6), lineWidth: 2).padding(-4)
                }
            }
            .onHover { hover = $0 }
            .animation(Motion.small, value: hover)
            .accessibilityElement(children: open ? .contain : .combine)
            .accessibilityLabel("\(entry.kind.noun), \(model.title(for: entry)), \(entry.capturedAt.formatted(date: .omitted, time: .shortened))")
            .accessibilityAddTraits(.isButton)
    }

    private var box: CGSize { size ?? model.size(of: entry) }
    private var radius: CGFloat { CanvasMath.radius(entry.kind) }
    private var ready: Bool { model.media[entry.mediaId ?? ""]?.state == "ready" }

    @ViewBuilder private var content: some View {
        switch entry.kind {
        case .moment: moment
        case .voice: VoiceFace(entry: entry, selected: selected, open: open)
        case .still: still
        case .reflection, .music: reflection
        }
    }

    private var moment: some View {
        VStack(spacing: 0) {
            ZStack {
                MediaThumb(url: model.mediaURL(for: entry), kind: .moment, ready: ready)
                Color.black.opacity(hover ? 0.10 : 0)
                // ponytail: hover only, no 0.95 press; a gesture on the disc would take the card's tap and drag.
                Circle().fill(.white.opacity(0.9)).frame(width: 56, height: 56).elevation(.float)
                    .overlay(Image(systemName: "play.fill").font(.system(size: 20)).foregroundStyle(Tok.momentInk).offset(x: 2))
                    .scaleEffect(discHover ? 1.05 : 1)
                    .onHover { discHover = $0 }
                    .animation(Motion.small, value: discHover)
                if let ms = model.media[entry.mediaId ?? ""]?.durationMs {
                    Text(Duration.milliseconds(ms).formatted(.time(pattern: .minuteSecond)))
                        .font(Typo.ui(12, .medium).monospacedDigit()).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: .rect(cornerRadius: Radius.control))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 12).padding(.bottom, 10)
                }
            }
            .frame(width: box.width, height: box.height - 48)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: radius - 1, topTrailingRadius: radius - 1))
            CardMeta(entry: entry).padding(.horizontal, 16).frame(maxHeight: .infinity)
        }
        .frame(width: box.width, height: box.height)
        .cardSurface(radius: radius, tint: Tok.moment)
    }

    private var still: some View {
        VStack(spacing: 0) {
            MediaThumb(url: model.mediaURL(for: entry), kind: .still, ready: ready)
                .frame(width: box.width, height: box.height - 48)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: radius - 1, topTrailingRadius: radius - 1))
            CardMeta(entry: entry).padding(.horizontal, 14).frame(maxHeight: .infinity)
                .animation(Motion.fade, value: model.caption(for: entry))
        }
        .frame(width: box.width, height: box.height)
        .cardSurface(radius: radius, tint: nil, hover: hover)
    }

    private var reflection: some View {
        let (title, body) = model.titleAndBody(entry)
        // Given its own height, the page fills it; otherwise its words stop at 128 pt, as on the web.
        let sized = box.height != CanvasMath.size(entry.kind).height
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Typo.ui(15, .semibold)).foregroundStyle(Tok.reflectionInk).lineLimit(2)
            Text(body.isEmpty ? "Empty page" : body)
                .font(Typo.ui(13)).lineSpacing(2.5).foregroundStyle(body.isEmpty ? Tok.ink4 : Tok.ink2)
                .frame(maxWidth: .infinity, maxHeight: sized ? .infinity : 128, alignment: .topLeading)
                .clipped()
            if !sized { Spacer(minLength: 0) }
            CardMeta(entry: entry, showTitle: false)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(width: box.width, height: box.height)
        .cardSurface(radius: radius, tint: Tok.reflection, tintOpacity: 0.3)
    }
}

/// The "title · time" footer every card shares (CardMeta.tsx), with an honest status chip when there is one.
struct CardMeta: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    var showTitle = true

    var body: some View {
        HStack(spacing: 0) {
            if showTitle {
                Text(model.title(for: entry)).font(Typo.ui(12, .medium)).foregroundStyle(Tok.ink).lineLimit(1)
                Text(" · ").font(Typo.ui(12)).foregroundStyle(Tok.ink3)
            }
            Text(entry.capturedAt.formatted(date: .omitted, time: .shortened)).font(Typo.ui(12)).foregroundStyle(Tok.ink2)
                .fixedSize()
            Spacer(minLength: 8)
            if let s = model.status(for: entry) {
                Text(s).monoCaps(9.5, tracking: 0.06).foregroundStyle(Tok.ink3).lineLimit(1).fixedSize()
            } else if let m = model.mood(for: entry) {
                Text(m).monoCaps(9.5, tracking: 0.06).foregroundStyle(entry.kind.tint).lineLimit(1).fixedSize()
            }
        }
    }
}

/// A recording session: its turns as one card with ghost layers behind (VideoStackCard.tsx).
struct StackFace: View {
    @Environment(AppModel.self) private var model
    let entries: [Entry]
    var selected = false
    @State private var hover = false

    var body: some View {
        let first = entries[0]
        let r: CGFloat = 18
        ZStack {
            if entries.count > 2 {
                RoundedRectangle(cornerRadius: r).fill(Tok.rim.opacity(0.4)).elevation(.float).rotationEffect(.degrees(3.5)).offset(x: 10, y: 10)
            }
            RoundedRectangle(cornerRadius: r).fill(Tok.rim.opacity(0.6)).elevation(.float).rotationEffect(.degrees(2)).offset(x: 6, y: 6)
            ZStack(alignment: .bottomLeading) {
                Tok.ink
                if first.kind == .moment {
                    MediaThumb(url: model.mediaURL(for: first), kind: .moment, ready: model.media[first.mediaId ?? ""]?.state == "ready")
                } else {
                    EchoOrb(size: 92).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                LinearGradient(stops: [.init(color: .black.opacity(0.3), location: 0), .init(color: .black.opacity(0.2), location: 0.45),
                                       .init(color: .black.opacity(0.75), location: 1)], startPoint: .top, endPoint: .bottom)
                if first.kind == .moment {
                    Circle().fill(.white.opacity(0.9)).frame(width: 48, height: 48).elevation(.float)
                        .overlay(Image(systemName: "play.fill").font(.system(size: 17)).foregroundStyle(Tok.ink).offset(x: 2))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(hover ? 1 : 0)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title(for: entries.last!)).font(Typo.ui(14, .semibold)).foregroundStyle(.white).lineLimit(2)
                    Text(first.capturedAt.formatted(date: .omitted, time: .shortened)).font(Typo.ui(12)).foregroundStyle(.white.opacity(0.75))
                }
                .padding(14)
                Text("\(entries.count) turns").font(Typo.ui(11, .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(.black.opacity(0.6), in: .capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
            }
            .clipShape(.rect(cornerRadius: r))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: r + 4).strokeBorder(Tok.sage.opacity(0.6), lineWidth: 2).padding(-4) }
            }
            .offset(y: hover ? -2 : 0)
            .elevation(hover ? .overlay : .panel)
        }
        .frame(width: CanvasMath.stackSize.width, height: CanvasMath.stackSize.height)
        .onHover { hover = $0 }
        .animation(Motion.small, value: hover)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("A recording with \(entries.count) turns")
    }
}

/// The voice note's orb (EchoOrb.tsx): a lit lavender sphere in a glass ring, with a small dark play (or pause) chip.
struct EchoOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let size: CGFloat
    var playing = false

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.1))
            Circle()
                .fill(RadialGradient(stops: [.init(color: Color(0xD9D5F6, 0xD9D5F6), location: 0), .init(color: Color(0xB4ADEA, 0xB4ADEA), location: 0.45),
                                             .init(color: Color(0x8E87CF, 0x8E87CF), location: 1)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.45))
                .padding(size * 0.09)
            if playing && !reduceMotion { talking.padding(size * 0.09).transition(.opacity) }
            Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
            Circle().stroke(Color(0xB4AEEA, 0xB4AEEA).opacity(0.38), lineWidth: 1.5).padding(-2)
            Circle().fill(Color(0x1A102A, 0x1A102A).opacity(0.2)).frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(.white.opacity(0.1)))
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                .overlay(Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 14)).foregroundStyle(Tok.paper)
                    .shadow(color: .black.opacity(0.9), radius: 4).offset(x: playing ? 0 : 1))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: 30, y: 18)
        .animation(Motion.easeOut(0.5), value: playing)
    }

    /// ponytail: the web's WebGL orb, approximated: its colours flow round the sphere and a white ring swells at the
    /// shader's "talking" levels. Port orb.tsx to Metal if this reads flat.
    private var talking: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let level = 0.65 + sin(t * 4.8) * 0.22
            ZStack {
                Circle().fill(AngularGradient(colors: [Color(0xB4ADEA, 0xB4ADEA), Color(0x8E87CF, 0x8E87CF), Color(0xFAFAF6, 0xFAFAF6),
                                                       Color(0xB4ADEA, 0xB4ADEA)], center: .center, angle: .radians(t * 0.8)))
                    .blur(radius: size * 0.08)
                    .opacity(0.6)
                Circle().strokeBorder(.white.opacity(0.12 + 0.33 * level), lineWidth: 1.5).scaleEffect(0.7 + 0.25 * level)
            }
            .clipShape(.circle)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// A card's material: surface at 85%, a lit rim, an optional type-coloured ring, and the panel shadow (overlay on
    /// hover, which on the web only the still takes).
    func cardSurface(radius: CGFloat, tint: Color?, tintOpacity: Double = 0.2, hover: Bool = false) -> some View {
        background(Tok.surface.opacity(0.92), in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Tok.rim.opacity(0.6), lineWidth: 1))
            .overlay { if let tint { RoundedRectangle(cornerRadius: radius).strokeBorder(tint.opacity(tintOpacity), lineWidth: 1) } }
            .elevation(hover ? .overlay : .panel)
    }
}

/// A card's eight resize handles (CanvasCard.tsx), drawn in the card's own space at the same size on screen at any zoom:
/// 8 pt dots on the corners and 18 × 5 pills on the edges, on 44 pt corner and 12 pt edge targets that sit mostly outside
/// the card, so they never cover its own controls. While one is dragged, a quiet outline in the guides' hue and the size.
struct ResizeHandles: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let size: CGSize
    let zoom: CGFloat
    let active: CanvasMath.Handle?
    /// The handle, where the press landed and where the pointer is, on the stage.
    let onDrag: (CanvasMath.Handle, CGPoint, CGPoint) -> Void
    /// The drag ended or was cancelled.
    let onEnd: () -> Void
    @State private var hovered: CanvasMath.Handle?
    @GestureState private var dragging = false

    var body: some View {
        let k = 1 / zoom
        ZStack {
            if active != nil { Rectangle().strokeBorder(Tok.guide.opacity(0.6), lineWidth: 1.5 * k).padding(-1.5 * k) }
            ForEach(CanvasMath.Handle.allCases, id: \.self) { handle($0, k) }
            if let active { readout(active, k) }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: dragging) { _, now in if !now { onEnd() } }
        .accessibilityHidden(true)
    }

    private func handle(_ h: CanvasMath.Handle, _ k: CGFloat) -> some View {
        let (sx, sy) = h.sides
        let corner = sx != 0 && sy != 0, lit = active == h || hovered == h
        // A target's centre sits this far out from the card's edge; its mark sits on the edge.
        let out = (corner ? 14 : 2) * k
        let along = { (side: CGFloat, length: CGFloat) -> (at: CGFloat, length: CGFloat) in
            side == 0 ? (length / 2, length - 16 * k) : (length * (side + 1) / 2 + side * out, (corner ? 44 : 12) * k)
        }
        let x = along(sx, size.width), y = along(sy, size.height)
        return Capsule()
            .fill(active == h ? Tok.guide : Tok.surface)
            .strokeBorder(active == h ? Tok.guide : Tok.sage, lineWidth: 1.5 * k)
            .animation(Motion.easeOut(0.16), value: active == h)
            .frame(width: (corner ? 8 : sy == 0 ? 5 : 18) * k, height: (corner ? 8 : sx == 0 ? 5 : 18) * k)
            .elevation(.lift)
            .scaleEffect(lit ? 1.25 : 1)
            .animation(reduceMotion ? nil : Motion.easeOut(0.16), value: lit)
            .offset(x: -sx * out, y: -sy * out)
            .frame(width: x.length, height: y.length)
            .contentShape(.rect)
            .onHover { hovered = $0 ? h : hovered == h ? nil : hovered }
            .pointerStyle(.frameResize(position: Self.position(h)))
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(DayStage.space))
                .updating($dragging) { _, d, _ in d = true }
                .onChanged { onDrag(h, $0.startLocation, $0.location) })
            .position(x: x.at, y: y.at)
            .zIndex(corner ? 2 : 1)
    }

    /// "W × H" in an ink chip off the dragged handle, 10 pt clear of the card.
    private func readout(_ h: CanvasMath.Handle, _ k: CGFloat) -> some View {
        let (sx, sy) = h.sides
        return Text("\(Int(size.width.rounded())) × \(Int(size.height.rounded()))")
            .font(Typo.mono(11, .regular).monospacedDigit())
            .foregroundStyle(Tok.bg)
            .frame(height: 16)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Tok.ink, in: .rect(cornerRadius: Radius.control))
            .elevation(.lift)
            .fixedSize()
            .scaleEffect(k, anchor: UnitPoint(x: (1 - sx) / 2, y: (1 - sy) / 2))
            .frame(width: 0, height: 0, alignment: Alignment(horizontal: sx > 0 ? .leading : sx < 0 ? .trailing : .center,
                                                              vertical: sy > 0 ? .top : sy < 0 ? .bottom : .center))
            .position(x: size.width * (sx + 1) / 2 + sx * 10 * k, y: size.height * (sy + 1) / 2 + sy * 10 * k)
            .allowsHitTesting(false)
    }

    private static func position(_ h: CanvasMath.Handle) -> FrameResizePosition {
        switch h {
        case .nw: .topLeading
        case .n: .top
        case .ne: .topTrailing
        case .e: .trailing
        case .se: .bottomTrailing
        case .s: .bottom
        case .sw: .bottomLeading
        case .w: .leading
        }
    }
}

/// A poster frame for a moment or a downsampled still, cached while recent.
struct MediaThumb: View {
    let url: URL?
    let kind: EntryKind
    var ready = true
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(kind.tint.opacity(0.14))
            // The cache too, so a copy (a flight's face, drawn without running its task) has the picture from its first frame.
            if let image = image ?? (ready ? ThumbCache.cached(url) : nil) {
                Image(nsImage: image).resizable().scaledToFill().frame(minWidth: 0, minHeight: 0)
            } else {
                Image(systemName: kind.symbol).font(.system(size: 22)).foregroundStyle(kind.tint)
            }
        }
        .clipped()
        .task(id: "\(url?.path ?? "")\(ready)") {
            guard let url, ready else { return }
            image = await ThumbCache.image(for: url, kind: kind)
        }
    }
}

@MainActor
enum ThumbCache {
    /// The recent few hundred, about 1.2 MB each decoded; NSCache also lets them go under memory pressure.
    private static let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 200
        return c
    }()

    static func cached(_ url: URL?) -> NSImage? { url.flatMap { cache.object(forKey: $0 as NSURL) } }
    /// The aspect of a thumbnail already made, so an opened still can take the photo's shape at once.
    static func aspect(_ url: URL?) -> CGFloat? { url.flatMap { cache.object(forKey: $0 as NSURL) }.map { $0.size.width / $0.size.height } }

    static func image(for url: URL, kind: EntryKind) async -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        let cg: CGImage? = if kind == .still {
            await Task.detached { thumbnail(url) }.value
        } else {
            await poster(url)
        }
        guard let cg else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: url as NSURL)
        return img
    }

    nonisolated static func thumbnail(_ url: URL, max: Int = 640) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max,
        ] as CFDictionary)
    }

    static func poster(_ url: URL) async -> CGImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        return try? await gen.image(at: CMTime(seconds: 0.4, preferredTimescale: 600)).image
    }
}
