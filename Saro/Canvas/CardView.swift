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
        if e.kind == .reflection, let first = e.body?.split(separator: "\n").first, !first.isEmpty, (e.body?.contains("\n") ?? false) {
            return String(first.prefix(80))
        }
        if verdicts[e.id]?.verdict == "clear", let t = annotations[e.id]?.title, let first = t.first { return first.uppercased() + t.dropFirst() }
        if e.kind == .still, let c = e.captionUser, !c.isEmpty { return c }
        return e.kind.noun
    }

    /// A short, honest status for the card footer, or nil when there's nothing to say.
    func status(for e: Entry) -> String? {
        switch e.processingStatus {
        case ProcessingStatus.recording: return "Recording…"
        case ProcessingStatus.transcribing: return "Transcribing…"
        case ProcessingStatus.pending, ProcessingStatus.gating, ProcessingStatus.reading:
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

    func mood(for e: Entry) -> String? {
        guard verdicts[e.id]?.verdict == "clear" else { return nil }
        return annotations[e.id]?.moodLabel
    }
}

/// A card on the canvas, drawn to the web build's specs (VideoMomentCard, VoiceEchoCard, ImageStillCard,
/// TextReflectionCard): each type has its own shape, and every card shares the "title · time" footer.
struct CardFace: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    var selected = false
    @State private var hover = false

    var body: some View {
        content
            .frame(width: size.width, height: size.height)
            .overlay {
                if selected && entry.kind != .voice {
                    RoundedRectangle(cornerRadius: radius + 4).strokeBorder(Tok.sage.opacity(0.6), lineWidth: 2).padding(-4)
                }
            }
            .onHover { hover = $0 }
            .animation(Motion.small, value: hover)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(entry.kind.noun), \(model.title(for: entry)), \(entry.capturedAt.formatted(date: .omitted, time: .shortened))")
            .accessibilityAddTraits(.isButton)
    }

    private var size: CGSize { CanvasMath.size(entry.kind) }
    private var radius: CGFloat { CanvasMath.radius(entry.kind) }
    private var ready: Bool { model.media[entry.mediaId ?? ""]?.state == "ready" }

    @ViewBuilder private var content: some View {
        switch entry.kind {
        case .moment: moment
        case .voice: voice
        case .still: still
        case .reflection, .music: reflection
        }
    }

    private var moment: some View {
        VStack(spacing: 0) {
            ZStack {
                MediaThumb(url: model.mediaURL(for: entry), kind: .moment, ready: ready)
                Color.black.opacity(hover ? 0.10 : 0)
                Circle().fill(.white.opacity(0.9)).frame(width: 56, height: 56).elevation(.float)
                    .overlay(Image(systemName: "play.fill").font(.system(size: 18)).foregroundStyle(Tok.ink).offset(x: 2))
                    .scaleEffect(hover ? 1.05 : 1)
                if let ms = model.media[entry.mediaId ?? ""]?.durationMs {
                    Text(Duration.milliseconds(ms).formatted(.time(pattern: .minuteSecond)))
                        .font(Typo.ui(12, .medium).monospacedDigit()).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: .rect(cornerRadius: Radius.control))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 12).padding(.bottom, 10)
                }
            }
            .frame(width: size.width, height: CanvasMath.momentMediaHeight)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: radius - 1, topTrailingRadius: radius - 1))
            CardMeta(entry: entry).padding(.horizontal, 16).frame(maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height)
        .cardSurface(radius: radius, tint: Tok.moment, hover: hover)
    }

    private var still: some View {
        VStack(spacing: 0) {
            MediaThumb(url: model.mediaURL(for: entry), kind: .still, ready: ready)
                .frame(width: size.width, height: CanvasMath.stillMediaHeight)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: radius - 1, topTrailingRadius: radius - 1))
            CardMeta(entry: entry).padding(.horizontal, 14).frame(maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height)
        .cardSurface(radius: radius, tint: nil, hover: hover)
    }

    private var reflection: some View {
        let (title, body) = model.titleAndBody(entry)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Typo.ui(15, .semibold)).foregroundStyle(Tok.reflectionInk).lineLimit(2)
            Text(body.isEmpty ? "Empty page" : body)
                .font(Typo.ui(13)).lineSpacing(2.5).foregroundStyle(body.isEmpty ? Tok.ink4 : Tok.ink2)
                .frame(maxWidth: .infinity, maxHeight: 128, alignment: .topLeading)
                .clipped()
            Spacer(minLength: 0)
            CardMeta(entry: entry, showTitle: false)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(width: size.width, height: size.height)
        .cardSurface(radius: radius, tint: Tok.reflection, tintOpacity: 0.3, hover: hover)
    }

    /// The orb and a one-line "title · time · duration" pill that hugs its words; the selection ring hugs both.
    private var voice: some View {
        HStack(spacing: 12) {
            EchoOrb(size: 80)
            HStack(spacing: 6) {
                Text(model.title(for: entry)).font(Typo.ui(12, .medium)).foregroundStyle(Tok.ink).lineLimit(1)
                Text("·")
                Text(entry.capturedAt.formatted(date: .omitted, time: .shortened)).fixedSize()
                if let ms = model.media[entry.mediaId ?? ""]?.durationMs {
                    Text("·")
                    Text(Duration.milliseconds(ms).formatted(.time(pattern: .minuteSecond))).fixedSize()
                }
                if let s = model.status(for: entry) {
                    Text(s).monoCaps(9.5, tracking: 0.06).foregroundStyle(Tok.ink3).lineLimit(1).fixedSize()
                }
            }
            .font(Typo.ui(12)).foregroundStyle(Tok.ink2)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Tok.paper.opacity(0.8), in: .capsule)
            .overlay(Capsule().strokeBorder(Tok.rim.opacity(0.6)))
            .elevation(.lift)
        }
        .overlay { if selected { Capsule().strokeBorder(Tok.sage.opacity(0.6), lineWidth: 2).padding(-4) } }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            RoundedRectangle(cornerRadius: r).fill(Tok.rim.opacity(0.4)).rotationEffect(.degrees(3.5)).offset(x: 10, y: 10)
            RoundedRectangle(cornerRadius: r).fill(Tok.rim.opacity(0.6)).rotationEffect(.degrees(2)).offset(x: 6, y: 6)
            ZStack(alignment: .bottomLeading) {
                Tok.ink
                if first.kind == .moment {
                    MediaThumb(url: model.mediaURL(for: first), kind: .moment, ready: model.media[first.mediaId ?? ""]?.state == "ready")
                } else {
                    EchoOrb(size: 92).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                LinearGradient(stops: [.init(color: .black.opacity(0.3), location: 0), .init(color: .black.opacity(0.2), location: 0.45),
                                       .init(color: .black.opacity(0.75), location: 1)], startPoint: .top, endPoint: .bottom)
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

/// The voice note's orb (EchoOrb.tsx): a lit lavender sphere in a glass ring, with a small dark play chip.
struct EchoOrb: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.1))
            Circle()
                .fill(RadialGradient(stops: [.init(color: Color(0xD9D5F6, 0xD9D5F6), location: 0), .init(color: Color(0xB4ADEA, 0xB4ADEA), location: 0.45),
                                             .init(color: Color(0x8E87CF, 0x8E87CF), location: 1)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.45))
                .padding(size * 0.09)
            Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
            Circle().stroke(Color(0xB4AEEA, 0xB4AEEA).opacity(0.38), lineWidth: 1.5).padding(-2)
            Circle().fill(Color(0x1A102A, 0x1A102A).opacity(0.2)).frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(.white.opacity(0.1)))
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                .overlay(Image(systemName: "play.fill").font(.system(size: 14)).foregroundStyle(Tok.paper)
                    .shadow(color: .black.opacity(0.9), radius: 4).offset(x: 1))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: 30, y: 18)
    }
}

extension View {
    /// A card's material: surface at 85%, a lit rim, an optional type-coloured ring, and the panel shadow (overlay on hover).
    func cardSurface(radius: CGFloat, tint: Color?, tintOpacity: Double = 0.2, hover: Bool) -> some View {
        background(Tok.surface.opacity(0.92), in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Tok.rim.opacity(0.6), lineWidth: 1))
            .overlay { if let tint { RoundedRectangle(cornerRadius: radius).strokeBorder(tint.opacity(tintOpacity), lineWidth: 1) } }
            .elevation(hover ? .overlay : .panel)
    }
}

/// A poster frame for a moment or a downsampled still, cached for the session.
struct MediaThumb: View {
    let url: URL?
    let kind: EntryKind
    var ready = true
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(kind.tint.opacity(0.14))
            if let image {
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
    private static var cache: [URL: NSImage] = [:]

    static func image(for url: URL, kind: EntryKind) async -> NSImage? {
        if let hit = cache[url] { return hit }
        let cg: CGImage? = if kind == .still {
            await Task.detached { thumbnail(url) }.value
        } else {
            await poster(url)
        }
        guard let cg else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache[url] = img
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
