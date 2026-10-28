#if DOGFOOD
import AppKit
import SaroKit
import SwiftUI

/// `-SaroSnapshot <dir>` renders key surfaces to PNG with ImageRenderer and quits, so the UI can be checked without
/// bringing the window forward. AppKit-backed pieces (player, text editor, lists) render blank. Use with -SaroDemo.
@MainActor
enum Snapshots {
    /// ponytail: renderers that hosted an AppKit view crash on deinit, so they live until the app quits.
    private static var keep: [AnyObject] = []

    static func runIfRequested(_ model: AppModel) {
        guard let dir = UserDefaults.standard.string(forKey: "SaroSnapshot") else { return }
        let delay = UserDefaults.standard.double(forKey: "SaroSnapshotDelay")
        Task {
            try? await Task.sleep(for: .seconds(delay > 0 ? delay : 20))
            await model.reload()
            let size = CGSize(width: 1280, height: 820)
            for dark in [true, false] {
                let suffix = dark ? "dark" : "light"
                shot("\(dir)/canvas-\(suffix).png", dark: dark, size: size, DayView())
                shot("\(dir)/noticed-\(suffix).png", dark: dark, size: CGSize(width: 360, height: 820), NoticedView())
                shot("\(dir)/letter-\(suffix).png", dark: dark, size: CGSize(width: 640, height: 720), LetterView())
                if let e = model.entries.first(where: { $0.kind == .reflection }) {
                    shot("\(dir)/detail-\(suffix).png", dark: dark, size: CGSize(width: 1040, height: 720), DetailView(entry: e))
                }
                shot("\(dir)/safety-\(suffix).png", dark: dark, size: CGSize(width: 440, height: 520), SafetyCardView())
            }
            NSApp.terminate(nil)
        }
    }

    private static func shot(_ path: String, dark: Bool, size: CGSize, _ view: some View) {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let r = ImageRenderer(content: view.environment(AppModelBox.model!).frame(width: size.width, height: size.height)
            .background(Tok.bg).environment(\.colorScheme, dark ? .dark : .light))
        r.scale = 2
        keep.append(r)
        guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

/// ImageRenderer content needs the model in its environment; this hands it over without capturing in a generic closure.
@MainActor
enum AppModelBox {
    static var model: AppModel?
}
#endif
