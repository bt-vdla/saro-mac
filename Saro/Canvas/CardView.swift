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
        if verdicts[e.id]?.verdict == "clear", let t = annotations[e.id]?.title, !t.isEmpty { return t }
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

    func mood(for e: Entry) -> String? {
        guard verdicts[e.id]?.verdict == "clear" else { return nil }
        return annotations[e.id]?.moodLabel
    }
}

struct CardFace: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    var selected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            footer
        }
        .frame(width: CanvasMath.cardWidth, height: CanvasMath.cardHeight(entry.kind), alignment: .top)
        .saroSurface(radius: 14)
        .overlay {
            if selected { RoundedRectangle(cornerRadius: 14).strokeBorder(Tok.sage, lineWidth: 2) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.kind.noun), \(model.title(for: entry)), \(entry.capturedAt.formatted(date: .omitted, time: .shortened))")
    }

    @ViewBuilder private var content: some View {
        switch entry.kind {
        case .moment, .still:
            MediaThumb(url: model.mediaURL(for: entry), kind: entry.kind, ready: model.media[entry.mediaId ?? ""]?.state == "ready")
                .frame(height: 132)
                .frame(maxWidth: .infinity)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 13, topTrailingRadius: 13))
                .overlay(alignment: .bottomTrailing) {
                    if let ms = model.media[entry.mediaId ?? ""]?.durationMs, entry.kind == .moment {
                        Text(Duration.milliseconds(ms).formatted(.time(pattern: .minuteSecond)))
                            .font(Typo.mono(10)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.45), in: .capsule)
                            .padding(8)
                    }
                }
        case .voice:
            HStack(spacing: 10) {
                Image(systemName: "waveform").font(.system(size: 22, weight: .medium)).foregroundStyle(Tok.echo)
                    .frame(width: 44, height: 44).background(Tok.echo.opacity(0.12), in: .circle)
                if let ms = model.media[entry.mediaId ?? ""]?.durationMs {
                    Text(Duration.milliseconds(ms).formatted(.time(pattern: .minuteSecond))).font(Typo.mono(11)).foregroundStyle(Tok.ink3)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 14)
        case .reflection, .music:
            Text(entry.body?.isEmpty == false ? entry.body! : "Empty page")
                .font(Typo.serif(14))
                .foregroundStyle(entry.body?.isEmpty == false ? Tok.ink2 : Tok.ink4)
                .lineSpacing(2)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 14).padding(.top, 14)
                .frame(height: 104, alignment: .topLeading)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.title(for: entry))
                .font(Typo.ui(13.5, .medium)).foregroundStyle(Tok.ink).lineLimit(1)
            HStack(spacing: 6) {
                Circle().fill(entry.kind.tint).frame(width: 6, height: 6)
                Text(entry.capturedAt.formatted(date: .omitted, time: .shortened).uppercased())
                if let s = model.status(for: entry) {
                    Text("·")
                    Text(s.uppercased())
                } else if let m = model.mood(for: entry) {
                    Text("·")
                    Text(m.uppercased())
                }
                if entry.backdated { Text("· ADDED LATER") }
            }
            .font(Typo.mono(9.5)).foregroundStyle(Tok.ink3).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
                Image(nsImage: image).resizable().scaledToFill()
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
