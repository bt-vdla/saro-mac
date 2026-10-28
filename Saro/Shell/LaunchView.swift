import Observation
import SaroKit
import SwiftUI

/// How far the demo journal's seeding has got (0–1), nil when nothing is being seeded.
@Observable @MainActor
final class LaunchProgress {
    static let shared = LaunchProgress()
    var demo: Double?
}

/// While the journal opens: the lit ground, and a breathing sage dot only once opening has taken 150 ms, so a quick
/// launch doesn't flash. A demo journal being seeded says so, with how far it has got.
struct LaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var slow = false
    private var progress: Double? { LaunchProgress.shared.demo }

    var body: some View {
        ZStack {
            LitGround().ignoresSafeArea()
            if let progress {
                VStack(spacing: 14) {
                    Text("Preparing your demo journal…").font(Typo.serif(20)).foregroundStyle(Tok.ink)
                    ProgressView(value: progress).progressViewStyle(.linear).tint(Tok.sage).frame(width: 220)
                    Text("Two weeks of sample entries, made up and kept only for this launch.").font(Typo.ui(12)).foregroundStyle(Tok.ink3)
                }
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityValue("\(Int(progress * 100)) percent")
            } else if slow {
                Circle().fill(Tok.sage).frame(width: 10, height: 10)
                    .breathing(!reduceMotion)
                    .transition(.opacity)
                    .accessibilityLabel("Opening your journal")
            }
        }
        .animation(Motion.fade, value: slow)
        .overlay { ToastHost() }
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            slow = true
        }
    }
}
