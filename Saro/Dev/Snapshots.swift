#if DOGFOOD
import AppKit
import SaroKit
import SwiftUI

/// `-SaroSnapshot <dir>` (with -SaroDemo, in an unsandboxed build) hosts the real UI in an off-screen window, steps through
/// a few states and writes each as `<dir>/<state>.png`, so the UI can be checked without taking the user's focus.
@MainActor
enum Snapshots {
    private static var panel: NSPanel?
    /// Holds the day's first card a little off its place, so the drag grid can be seen.
    static let hold = Notification.Name("SaroSnapshotHold")
    /// Holds a trash flight this far along, so both its ends can be seen.
    static var trashFreeze: Double?

    static func runIfRequested(_ model: AppModel) {
        guard let dir = UserDefaults.standard.string(forKey: "SaroSnapshot") else { return }
        let p = NSPanel(contentRect: NSRect(x: -6000, y: 0, width: 1320, height: 860), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentView = NSHostingView(rootView: RootView().environment(model))
        panel = p
        let dark = UserDefaults.standard.bool(forKey: "SaroSnapshotDark")
        p.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        Task {
            try? await Task.sleep(for: .seconds(UserDefaults.standard.double(forKey: "SaroSnapshotDelay").clamped(to: 5...120)))
            let steps: [(String, @MainActor () -> Void)] = [
                ("canvas", { model.selection = [] }),
                ("selected", { model.selection = Set(model.entries.prefix(2).map(\.id)) }),
                ("noticed", { model.selection = []; model.showNoticed = true }),
                ("detail", { model.showNoticed = false; model.openEntryID = model.entries.first(where: { $0.kind == .reflection })?.id }),
                ("still", { model.openEntryID = model.entries.first(where: { $0.kind == .still })?.id }),
                ("letter", { model.openEntryID = nil; model.showLetter = true }),
                ("voice", { model.insight = .spine; model.openVoiceID = model.entries.first(where: { $0.kind == .voice })?.id }),
                // A writing and the still part way into the Undo toast, then part way back out of it (as a click on Undo
                // flies them), then home.
                ("trash", {
                    model.openVoiceID = nil
                    trashFreeze = 0.3
                    let ids = [EntryKind.reflection, .still].compactMap { k in model.entries.first { $0.kind == k }?.id }
                    Task { await model.trash(Set(ids), flies: true) }
                }),
                ("untrash", {
                    guard let t = model.toast else { return }
                    model.trashFlight = TrashFlight(cards: t.trashed, back: (t, CGRect(x: 24, y: 860 - 92 - 56, width: 360, height: 56)))
                    t.undo?()
                    model.toast = nil
                }),
                ("untrashed", {
                    trashFreeze = nil
                    model.trashFlight = nil
                }),
                ("replay", {
                    model.startReplay(animated: false)
                    let items = model.replay.items
                    model.replay.scrub(to: items.isEmpty ? 12 : items[items.count / 2].hour)
                    model.replay.tip = .key
                }),
                ("held", {
                    model.replay.exit(animated: false)
                    model.openVoiceID = nil
                    NotificationCenter.default.post(name: hold, object: nil)
                }),
                // Deep links, without bringing the app forward.
                ("link-day", {
                    WindowActions.openMain = {}
                    model.openVoiceID = nil
                    model.open(DeepLink.day(LocalDay.adding(-1, to: LocalDay.today())).url)
                }),
                ("link-missing", {
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        model.open(DeepLink.entry("gone").url)
                    }
                }),
                ("grow", { p.contentView = NSHostingView(rootView: GrowGallery()) }),
                ("foundation", { p.contentView = NSHostingView(rootView: FoundationGallery(profile: model.profile)) }),
            ]
            for (name, apply) in steps {
                apply()
                try? await Task.sleep(for: .seconds(2.5))
                if let v = p.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
                }
            }
            NSApp.terminate(nil)
        }
    }
}

/// Foundation's shared pieces, which no screen of their own shows yet: the reminder banner, the greeting, readiness and
/// the privacy copy.
private struct FoundationGallery: View {
    let profile: Profile?

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 16) {
                NotificationPreview(time: "9:30 PM")
                NotificationPreview(time: "7:15 AM").environment(\._accessibilityReduceTransparency, true)
                ForEach([0.0, 5, 8, 11, 13, 16, 18, 21, 23], id: \.self) { h in
                    Text("\(Greeting.eyebrow(hour: h).uppercased()) · \(Greeting.line(hour: h))").font(Typo.ui(12)).foregroundStyle(Tok.ink2)
                }
                Text(Readiness.model().line).font(Typo.ui(12)).foregroundStyle(Tok.ink2)
                Text("Prompt: \(profile.map { $0.tone.previewLine(name: $0.address) } ?? "no profile")").font(Typo.serif(15)).foregroundStyle(Tok.voice)
                Text("Onboarding done: \(profile?.onboardingDoneAt?.formatted() ?? "no")").font(Typo.mono(10)).foregroundStyle(Tok.ink3)
            }
            .frame(width: 380, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(PrivacyCopy.nfr02, id: \.self) { Text($0).font(Typo.serif(15)).foregroundStyle(Tok.ink) }
                ForEach(PrivacyCopy.promises) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.title).font(Typo.serif(18, .medium))
                        ForEach(p.body, id: \.self) { Text($0).font(Typo.ui(12)).foregroundStyle(Tok.ink2) }
                        Text(p.proofs.joined(separator: "  ·  ")).font(Typo.mono(10)).foregroundStyle(Tok.ink3)
                        Text(p.where).font(Typo.ui(11, .medium)).foregroundStyle(Tok.sageTeal)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tok.bg)
    }
}

/// The recorder's flight out of its bar button and back, frozen at a few points of the way (the real one never sits
/// still long enough to snapshot): the voice pill out, then back, then the moment frame out.
private struct GrowGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(.voice, out: true)
            row(.voice, out: false)
            row(.moment, out: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tok.bg)
    }

    private func row(_ kind: EntryKind, out: Bool) -> some View {
        let rest = kind == .voice ? CGRect(x: 30, y: 100, width: 380, height: 98) : CGRect(x: 20, y: 16, width: 400, height: 250)
        return HStack(spacing: 0) {
            ForEach([0.12, 0.3, 0.6], id: \.self) { v in
                surface(kind)
                    .modifier(GrowFlight(v: v, from: CGRect(x: 56, y: 214, width: 68, height: 52), to: rest, outbound: out, face: .of(kind)))
                    .offset(x: rest.minX, y: rest.minY)
                    .frame(width: 440, height: 286, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder private func surface(_ kind: EntryKind) -> some View {
        if kind == .voice {
            VoicePill(notice: nil, inSession: false, grows: true, toggle: {}, done: {}, close: {}).frame(width: 380)
        } else {
            Text("Getting your camera ready…").font(Typo.ui(13)).foregroundStyle(.white.opacity(0.8))
                .frame(width: 400, height: 250)
                .background(.black, in: .rect(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.1)))
        }
    }
}

private extension Double {
    func clamped(to r: ClosedRange<Double>) -> Double { self == 0 ? 20 : Swift.min(Swift.max(self, r.lowerBound), r.upperBound) }
}
#endif
