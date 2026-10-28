import AppKit
import SaroKit
import SwiftUI

/// The Music capture's link field (MusicLinkInput.tsx): a pill that grows out of the Music button and sits 8 pt above the
/// bar, min(544, width − 32) wide, paper/70 on a heavy blur with a sage focus ring. Return adds the link; Esc or ✕ closes
/// it back into the button.
struct MusicField: View {
    /// The Music button a click opened it from.
    var origin: Anchor<CGRect>?
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    @State private var wrong = false
    @State private var grown = 0.0
    @State private var leaving = false
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geo in
            let width = max(0, min(544, geo.size.width - 32))
            // 8 pt above the bar, in one row or two.
            let rest = CGRect(x: (geo.size.width - width) / 2, y: geo.size.height - model.barClear - 8 - 48, width: width, height: 48)
            let from = reduceMotion ? nil : origin.map { geo[$0] }
            field
                .frame(width: width, height: 48)
                .modifier(GrowFlight(v: from == nil ? 1 : grown, from: from ?? rest, to: rest, outbound: !leaving,
                                     face: CaptureFace(title: "Music", symbol: "opticaldisc", tint: Tok.music)))
                .offset(x: rest.minX, y: rest.minY)
        }
        .onAppear {
            focused = true
            withAnimation(Motion.small) { grown = 1 }
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "link").font(.system(size: 14, weight: .medium)).foregroundStyle(Tok.ink2)
            TextField("Music link", text: $text, prompt: Text("Paste a music link…").foregroundStyle(Tok.ink3))
                .textFieldStyle(.plain)
                .font(Typo.ui(14))
                .foregroundStyle(Tok.ink)
                .focused($focused)
                .onSubmit(add)
                .onExitCommand(perform: close)
                .onChange(of: text) { wrong = false }
                .accessibilityLabel("Music link")
            if wrong {
                Text("That isn’t a link").font(Typo.ui(12)).foregroundStyle(Tok.danger).transition(.opacity)
            }
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Tok.ink2)
                    .frame(width: 32, height: 32).contentShape(.circle)
            }
            .buttonStyle(PressStyle(hoverFill: true, radius: 16))
            .accessibilityLabel("Close")
        }
        .padding(.leading, 16).padding(.trailing, 8)
        .background(Tok.paper.opacity(0.7), in: .capsule)
        .background(.frosted(.thickMaterial, solid: Tok.paper), in: .capsule)
        .overlay(Capsule().strokeBorder(focused ? Tok.sage : Tok.rim.opacity(0.7), lineWidth: focused ? 2 : 1))
        .elevation(.float)
        .animation(Motion.fade, value: focused)
        .animation(Motion.fade, value: wrong)
    }

    private func add() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let url = Music.link(text) else { wrong = true; return }
        close()
        Task { await model.newMusic(url: url, at: nil) }
    }

    /// Back into the button it grew from; from a key, or with nothing to fold into, it just goes.
    private func close() {
        guard !leaving else { return }
        guard origin != nil, !reduceMotion, !Motion.byKey else { CaptureUI.shared.musicOpen = false; return }
        leaving = true
        withAnimation(Motion.small) { grown = 0 } completion: { CaptureUI.shared.musicOpen = false }
    }
}

extension MusicInfo.Source {
    /// A small mark for the source, drawn here: no remote images.
    var mark: String {
        switch self {
        case .spotify: "dot.radiowaves.up.forward"
        case .youtube, .ytmusic: "play.fill"
        case .apple, .jiosaavn: "music.note"
        case .soundcloud: "cloud.fill"
        case .tidal: "diamond.fill"
        case .unknown: "link"
        }
    }

    var color: Color { Color(brand, brand) }
}

extension MusicInfo {
    /// "artist · album", each only when the link names it, and the album only when it isn't already the title.
    var byline: String {
        [artist, album == title ? "" : album].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

extension AppModel {
    /// A song's link, as read offline, with the person's own title and artist over it (Edit details).
    func music(_ e: Entry) -> (url: URL, info: MusicInfo)? {
        guard let url = e.body.flatMap(Music.link) else { return nil }
        var info = Music.resolve(url)
        if let t = e.titleUser?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { info.title = t }
        if let a = e.captionUser?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty { info.artist = a }
        return (url, info)
    }
}

/// The song's tile: a gradient from the link's hue into the source's colour, with a ring and a centre dot (musicArtwork).
struct MusicArtwork: View {
    let url: URL?

    var body: some View {
        if let url {
            let a = Music.artwork(url)
            GeometryReader { geo in
                let d = min(geo.size.width, geo.size.height)
                ZStack {
                    LinearGradient(colors: [Color(a.top, a.top), Color(a.bottom, a.bottom)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().strokeBorder(.white.opacity(0.35), lineWidth: d * 0.05).frame(width: d * 0.58, height: d * 0.58)
                    Circle().fill(.white.opacity(0.6)).frame(width: d * 0.14, height: d * 0.14)
                }
            }
            .accessibilityHidden(true)
        } else {
            ZStack {
                Tok.music.opacity(0.15)
                Image(systemName: "opticaldisc").font(.system(size: 22)).foregroundStyle(Tok.music)
            }
        }
    }
}

/// The song card (MusicCard.tsx): 280 × 88 at radius 18, artwork at 74:88, the title, "artist · album", and the source as a
/// link that opens it, with the platform's mark bottom-right.
struct MusicFace: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    let box: CGSize
    @State private var hover = false

    var body: some View {
        let song = model.music(entry)
        let info = song?.info
        HStack(spacing: 12) {
            MusicArtwork(url: song?.url)
                .frame(width: box.height * 74 / 88, height: box.height)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 17, bottomLeadingRadius: 17))
            VStack(alignment: .leading, spacing: 2) {
                Text(info?.title ?? "Music link").font(Typo.ui(13.5, .semibold)).foregroundStyle(Tok.ink).lineLimit(1)
                let byline = info?.byline ?? ""
                if !byline.isEmpty { Text(byline).font(Typo.ui(12)).foregroundStyle(Tok.ink2).lineLimit(1) }
                if let song {
                    Button(song.info.source.name) { NSWorkspace.shared.open(song.url) }
                        .buttonStyle(.plain)
                        .font(Typo.ui(12, .medium)).foregroundStyle(Tok.music)
                        .help("Open in \(song.info.source.name)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 28)
        }
        .frame(width: box.width, height: box.height)
        .overlay(alignment: .bottomTrailing) {
            if let info, info.source != .unknown {
                Image(systemName: info.source.mark).font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 16, height: 16).background(info.source.color, in: .circle)
                    .padding(10)
                    .accessibilityHidden(true)
            }
        }
        .background(Tok.surface.opacity(0.92), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Tok.rim.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Tok.music.opacity(0.2)))
        .elevation(hover ? .overlay : .panel)
        .onHover { hover = $0 }
        .animation(Motion.small, value: hover)
    }
}

/// The song view (EntryViews.tsx MusicView): 200 pt artwork, the title on up to two lines, the byline, the source and
/// time in mono, then Open in … (the browser or the app takes it; Saro stays offline) and Copy link.
struct MusicDetail: View {
    @Environment(AppModel.self) private var model
    let entry: Entry

    var body: some View {
        let song = model.music(entry)
        VStack(spacing: 14) {
            MusicArtwork(url: song?.url)
                .frame(width: 200, height: 200)
                .clipShape(.rect(cornerRadius: Radius.panel))
                .elevation(.float)
            VStack(spacing: 6) {
                Text(song?.info.title ?? "Music link").font(Typo.ui(22, .semibold)).foregroundStyle(Tok.ink).lineLimit(2)
                let byline = song?.info.byline ?? ""
                if !byline.isEmpty { Text(byline).font(Typo.ui(14)).foregroundStyle(Tok.ink2) }
                Text(([song?.info.source == .unknown ? nil : song?.info.source.name, Self.when(entry)].compactMap { $0 }).joined(separator: " · "))
                    .monoCaps(10.5, tracking: 0.12).foregroundStyle(Tok.ink3)
            }
            .multilineTextAlignment(.center)
            if let song {
                HStack(spacing: 10) {
                    Button(song.info.source == .unknown ? "Open link ↗" : "Open in \(song.info.source.name) ↗") { NSWorkspace.shared.open(song.url) }
                        .buttonStyle(CaptureButtonStyle.primary)
                        .keyboardShortcut(.defaultAction)
                    Button("Copy link") {
                        NSPasteboard.general.clearContents()
                        let ok = NSPasteboard.general.setString(song.url.absoluteString, forType: .string)
                        model.show(Toast(ok ? "Link copied" : "Couldn’t copy the link", style: ok ? .info : .error))
                    }
                    .buttonStyle(CaptureButtonStyle.secondary)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                }
                .padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "TODAY · 4:16 PM".
    static func when(_ e: Entry) -> String {
        let day = e.localDay == LocalDay.today() ? "Today" : DayFormat.sidebar(e.localDay)
        return "\(day) · \(e.capturedAt.formatted(date: .omitted, time: .shortened))"
    }
}
