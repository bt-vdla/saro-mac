import Foundation

/// What a music link says about itself, read offline from the URL alone (music.ts demoResolveMusic). Nothing is fetched;
/// an artist or album is named only when the link's own slug says it, never invented.
public struct MusicInfo: Sendable, Hashable {
    public enum Source: String, Sendable, CaseIterable {
        case spotify, apple, youtube, ytmusic, jiosaavn, soundcloud, tidal, unknown

        /// "Open in Spotify", "Spotify · Today".
        public var name: String {
            switch self {
            case .spotify: "Spotify"
            case .apple: "Apple Music"
            case .youtube: "YouTube"
            case .ytmusic: "YouTube Music"
            case .jiosaavn: "JioSaavn"
            case .soundcloud: "SoundCloud"
            case .tidal: "Tidal"
            case .unknown: "the web"
            }
        }

        /// The source's brand colour, which the artwork blends into.
        public var brand: UInt32 {
            switch self {
            case .spotify: 0x1DB954
            case .apple: 0xFA243C
            case .youtube, .ytmusic: 0xFF0033
            case .jiosaavn: 0x2BC5B4
            case .soundcloud: 0xFF5500
            case .tidal: 0x222222
            case .unknown: 0x4D91D1
            }
        }
    }

    public var source: Source
    /// track, album, playlist, episode, show, artist, music-video, video; nil when the link doesn't say.
    public var kind: String?
    public var title: String
    public var artist: String
    public var album: String
}

public enum Music {
    /// A typed or pasted link Saro will keep: http(s) with a host. The field takes any such link.
    public static func link(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(where: \.isWhitespace), let url = URL(string: t), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else { return nil }
        return url
    }

    /// A paste on the canvas becomes a song only from these services (Canvas.tsx looksLikeMusicUrl); Tidal isn't one.
    public static func isMusicLink(_ text: String) -> Bool {
        guard let url = link(text) else { return false }
        return ![.unknown, .tidal].contains(source(url.host?.lowercased() ?? ""))
    }

    public static func resolve(_ url: URL) -> MusicInfo {
        let host = url.host?.lowercased() ?? ""
        let source = source(host)
        let parts = url.path(percentEncoded: true).split(separator: "/").map(String.init)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var info = MusicInfo(source: source, kind: nil, title: "Music link", artist: "", album: "")
        func label(_ kind: String?) -> String { "\(kind.flatMap { kindLabel[$0] } ?? "Track") on \(source.name)" }
        switch source {
        case .spotify:
            info.kind = parts.first { ["track", "album", "playlist", "episode", "show", "artist"].contains($0) }
            info.title = info.kind.map { label($0) } ?? "Music on Spotify"
        case .apple:
            let k = parts.firstIndex { ["album", "song", "playlist", "artist", "music-video", "station"].contains($0) }
            let kind = k.map { parts[$0] }
            let slug = k.flatMap { $0 + 1 < parts.count ? parts[$0 + 1] : nil }
            info.kind = kind
            if let slug, isSlug(slug) {
                info.title = humanizeSlug(slug)
                // ?i= links point at a track inside an album; the slug names the track.
                if kind == "album", !query.contains(where: { $0.name == "i" && $0.value?.isEmpty == false }) { info.album = info.title }
                if kind == "artist" { info.artist = info.title }
            } else {
                info.title = label(kind)
            }
        case .youtube:
            info.kind = parts.first == "playlist" ? "playlist" : "video"
            info.title = label(info.kind)
        case .ytmusic:
            info.kind = parts.first == "playlist" ? "playlist" : parts.first == "browse" ? "album" : parts.first == "channel" ? "artist" : "track"
            info.title = label(info.kind)
        case .jiosaavn:
            let rest = parts.first == "s" ? Array(parts.dropFirst()) : parts
            let kind = rest.first
            info.kind = kind
            // Skips hex hashes (user playlists: /s/playlist/<hash>/<name>/<id>).
            if let slug = rest.dropFirst().first(where: { isSlug($0) && $0.range(of: "^[0-9a-f]{16,}$", options: [.regularExpression, .caseInsensitive]) == nil }) {
                info.title = humanizeSlug(kind == "artist" ? slug.replacingOccurrences(of: "-songs$", with: "", options: .regularExpression) : slug)
                if kind == "album" { info.album = info.title }
                if kind == "artist" { info.artist = info.title }
            } else {
                info.title = label(kind)
            }
        case .soundcloud:
            let reserved = ["sets", "likes", "tracks", "albums", "reposts", "popular-tracks", "following", "followers"]
            let at = { (i: Int) in i < parts.count ? parts[i] : nil }
            if host.hasPrefix("on.") || !(at(0).map(isSlug) ?? false) {
                (info.kind, info.title) = ("track", label("track"))
            } else if at(1) == "sets", let set = at(2), isSlug(set) {
                (info.kind, info.title, info.artist) = ("album", humanizeSlug(set), humanizeSlug(parts[0]))
                info.album = info.title
            } else if let track = at(1), isSlug(track), !reserved.contains(track) {
                (info.kind, info.title, info.artist) = ("track", humanizeSlug(track), humanizeSlug(parts[0]))
            } else {
                (info.kind, info.title) = ("artist", humanizeSlug(parts[0]))
                info.artist = info.title
            }
        case .tidal:
            info.kind = parts.first { ["track", "album", "playlist", "video", "artist"].contains($0) }
            info.title = label(info.kind)
        case .unknown:
            break
        }
        return info
    }

    /// What the artwork's hue is taken from: the source and the link's path and query, so one link always looks the same.
    public static func artworkSeed(_ url: URL) -> String {
        let query = url.query(percentEncoded: true).map { "?\($0)" } ?? ""
        return "\(source(url.host?.lowercased() ?? "").rawValue):\(url.path(percentEncoded: true))\(query)"
    }

    /// The artwork's two ends (musicArtwork): hsl(hue, 55%, 64%) from the seed, into the source's brand colour.
    public static func artwork(_ url: URL) -> (top: UInt32, bottom: UInt32) {
        let hue = Double(hash(artworkSeed(url)) % 360)
        return (hsl(hue, 0.55, 0.64), resolve(url).source.brand)
    }

    /// A slug as words: decoded, separators to spaces, title-cased but for small words after the first.
    public static func humanizeSlug(_ slug: String) -> String {
        let s = (slug.removingPercentEncoding ?? slug)
            .replacingOccurrences(of: "[-_+.]+", with: " ", options: .regularExpression)
            .split(separator: " ")
        return s.enumerated().map { i, w in
            i > 0 && smallWords.contains(w.lowercased()) ? w.lowercased() : w.prefix(1).uppercased() + w.dropFirst()
        }.joined(separator: " ")
    }

    static func source(_ host: String) -> MusicInfo.Source {
        func hostIs(_ domain: String) -> Bool { host == domain || host.hasSuffix(".\(domain)") }
        if hostIs("music.youtube.com") { return .ytmusic }
        if hostIs("youtube.com") || hostIs("youtu.be") || hostIs("youtube-nocookie.com") { return .youtube }
        if hostIs("spotify.com") || hostIs("spotify.link") { return .spotify }
        if hostIs("music.apple.com") { return .apple }
        if hostIs("jiosaavn.com") { return .jiosaavn }
        if hostIs("soundcloud.com") { return .soundcloud }
        if hostIs("tidal.com") { return .tidal }
        return .unknown
    }

    private static let kindLabel = ["track": "Track", "song": "Track", "album": "Album", "playlist": "Playlist", "featured": "Playlist",
                                    "episode": "Podcast episode", "show": "Podcast", "artist": "Artist", "music-video": "Music video",
                                    "video": "Video"]
    private static let smallWords: Set = ["a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "of", "on", "or", "the", "to", "vs", "with"]

    private static func isSlug(_ part: String) -> Bool {
        part.contains(where: \.isLetter) && !part.allSatisfy(\.isNumber)
            && part.range(of: #"^(pl|id)[.\d]"#, options: [.regularExpression, .caseInsensitive]) == nil
    }

    /// FNV-1a over UTF-16 units, as db.ts hashString.
    static func hash(_ s: String) -> UInt32 {
        s.utf16.reduce(0x811C_9DC5 as UInt32) { ($0 ^ UInt32($1)) &* 0x0100_0193 }
    }

    static func hsl(_ h: Double, _ s: Double, _ l: Double) -> UInt32 {
        let c = (1 - abs(2 * l - 1)) * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = l - c / 2
        let (r, g, b): (Double, Double, Double) = switch h {
        case ..<60: (c, x, 0)
        case ..<120: (x, c, 0)
        case ..<180: (0, c, x)
        case ..<240: (0, x, c)
        case ..<300: (x, 0, c)
        default: (c, 0, x)
        }
        let byte = { (v: Double) in UInt32(((v + m) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}
