import SaroKit
import SwiftUI

/// 06 What Saro knows. ponytail: holds the section until memory merges and swaps this for
/// `WhatSaroKnowsView(embedded: true)`; pausing already works, since it lives in the profile.
struct MemorySlot: View {
    @Environment(AppModel.self) private var model
    @State private var save = Autosave()

    var body: some View {
        let paused = model.profile?.memoryPaused ?? false
        SettingsCard(label: "Memory", title: "What Saro knows about you", autosave: save) {
            SettingsRow("Learn from my entries", caption: "Saro notices people, places and themes as you write, here on this Mac.") {
                Toggle("Learn from my entries", isOn: Binding(get: { !paused }, set: { on in
                    save.run { try await model.updateProfile { $0.memoryPaused = !on } }
                }))
                .toggleStyle(.sage).labelsHidden()
                .disabled(model.profile == nil)
            }
            if paused {
                Text("Paused. Saro won’t learn anything new. What’s here stays.").font(Typo.serif(17)).foregroundStyle(Tok.ink2)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
            RowRule()
            Label("The list of what Saro has noticed, with Edit and Forget for each, comes with the next build.", systemImage: "clock")
                .font(Typo.ui(12)).foregroundStyle(Tok.ink3)
                .padding(.top, 14)
        }
        .animation(Motion.fade, value: paused)
    }
}
