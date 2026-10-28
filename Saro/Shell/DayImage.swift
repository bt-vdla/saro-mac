import AppKit
import Observation
import SaroKit
import SwiftUI
import UniformTypeIdentifiers

/// "Preparing your day…", shown only once an export has taken 150 ms.
@Observable @MainActor
final class DayImageProgress {
    static let shared = DayImageProgress()
    var preparing = false
}

extension AppModel {
    /// Export Day as Image (Canvas.tsx handleExportDayImage): every card of the day, fitted, 48 pt around, up to twice the
    /// points and at most 4096 px, on the hour's ground, with no chrome; saved as saro-YYYY-MM-DD.png.
    func exportDayImage() async {
        guard pane == .day, !stageCards.isEmpty else {
            return show(Toast(title: "Nothing to export yet", detail: "This day has no entries."))
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ShellText.dayImageName(day)
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.message = "Saro saves this day's canvas as a picture. Nothing leaves this Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let slow = Task {
            try await Task.sleep(for: .milliseconds(150))
            DayImageProgress.shared.preparing = true
        }
        defer {
            slow.cancel()
            DayImageProgress.shared.preparing = false
        }
        // The HUD gets a frame to show in before the render holds the main actor.
        try? await Task.sleep(for: .milliseconds(16))
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard let image = DayImage.render(self, dark: dark) else {
            return show(Toast(title: "Couldn't export this day", detail: "Try again in a moment.", style: .destructive))
        }
        do {
            try await Task.detached { try DayImage.writePNG(image, to: url) }.value
            show(Toast(title: "Day exported", detail: url.lastPathComponent))
        } catch {
            show(.failed("Couldn't export this day", error))
        }
    }
}

enum DayImage {
    /// The day's cards on a still stage at the fitted camera. The Metal ground can't be drawn offscreen, so a gradient
    /// from the same hour's colours with grain stands in for it.
    @MainActor static func render(_ model: AppModel, dark: Bool) -> CGImage? {
        let cards = model.stageCards
        guard let b = CanvasMath.bounds(cards.map { CGRect(center: $0.center, size: $0.size) }) else { return nil }
        let pad = DayImageMath.pad
        let size = CGSize(width: b.width + 2 * pad, height: b.height + 2 * pad)
        let hour = model.isToday ? Sky.localHour(.now) : 13
        let stage = ZStack(alignment: .topLeading) {
            StillGround(ground: Sky.ground(at: hour, dark: dark, followsDay: Daylight.shared.mode == .clock))
            ForEach(cards) { c in
                Group {
                    if c.item.isStack { StackFace(entries: c.item.entries) } else { CardFace(entry: c.item.top, size: c.size) }
                }
                .frame(width: c.size.width, height: c.size.height, alignment: .topLeading)
                .position(x: c.center.x - b.minX + pad, y: c.center.y - b.minY + pad)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .environment(model)
        .environment(\.colorScheme, dark ? .dark : .light)
        let r = ImageRenderer(content: stage)
        r.scale = DayImageMath.scale(for: size)
        return r.cgImage
    }

    nonisolated static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }
}

/// The lit ground without Metal: the hour's ground, its pool of light at the sun, the horizon band and still grain.
struct StillGround: View {
    let ground: Sky.Ground

    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height)
            ZStack {
                color(ground.ground)
                RadialGradient(colors: [color(ground.light).opacity(min(1, ground.power * 0.55)), .clear],
                               center: UnitPoint(x: ground.sun.x, y: ground.sun.y), startRadius: 0, endRadius: side * max(0.4, ground.spread))
                LinearGradient(colors: [.clear, color(ground.accent).opacity(min(0.6, ground.accentPower * 0.5))],
                               startPoint: .center, endPoint: .bottom)
                Canvas { ctx, size in
                    // A fixed seed, so the grain is the same every export.
                    var seed: UInt64 = 0x5A40
                    for _ in 0..<Int(size.width * size.height / 90) {
                        seed = seed &* 6364136223846793005 &+ 1442695040888963407
                        let x = Double(seed >> 33 & 0xFFFF) / 65535 * size.width
                        let y = Double(seed >> 17 & 0xFFFF) / 65535 * size.height
                        ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(seed & 1 == 0 ? .white.opacity(0.05) : .black.opacity(0.04)))
                    }
                }
            }
        }
    }

    private func color(_ v: SIMD3<Double>) -> Color { Color(.sRGBLinear, red: v.x, green: v.y, blue: v.z) }
}
