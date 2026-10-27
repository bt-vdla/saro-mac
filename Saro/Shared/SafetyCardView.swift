import SaroKit
import SwiftUI

/// The SafetyCard (SR-19, SR-20): crisis resources for the Mac's region, never an AI reflection. Reachable from any
/// screen through Help → If you're struggling, the menu bar extra, and in place of a held entry's reading.
struct SafetyCardView: View {
    var compact = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            if !compact {
                Text("If you're struggling").font(Typo.serif(24, .medium)).foregroundStyle(Tok.ink)
                Text("You don't have to carry this alone. These lines are free and confidential, and someone will listen.")
                    .font(Typo.ui(13.5)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(CrisisResources.forRegion(), id: \.name) { r in
                Link(destination: r.url) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name).font(Typo.ui(14, .semibold)).foregroundStyle(Tok.ink)
                        Text(r.contact).font(Typo.ui(13)).foregroundStyle(Tok.sageTeal)
                        Text("\(r.region.uppercased()) · \(r.detail.uppercased())").font(Typo.mono(9.5)).foregroundStyle(Tok.ink3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Tok.bg, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            if !compact {
                Text("If you might act on thoughts of ending your life, call your local emergency number now.")
                    .font(Typo.ui(12)).foregroundStyle(Tok.ink3).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(compact ? 0 : 28)
        .frame(width: compact ? nil : 440)
        .background(compact ? Color.clear : Tok.surface)
    }
}
