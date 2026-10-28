import SaroKit
import SwiftUI

/// Week, Month and Year: an ink/6 % capsule of 68 pt segments whose surface thumb slides with the zoom itself, not only
/// when it settles (a segmented Picker can't follow a continuous zoom). A click springs there; a key jumps.
struct LensLevels: View {
    let lens: LensState
    private static let segment: CGFloat = 68

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Tok.surfaceAlt)
                .shadow(color: Tok.shadow.opacity(0.12), radius: 1.5, y: 1)
                .frame(width: Self.segment, height: 36)
                .offset(x: min(max(lens.z, 0), 2) * Self.segment)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                ForEach(LensMath.Level.allCases, id: \.self) { l in
                    Button {
                        lens.go(to: l, how: Motion.byKey ? .instant : .animated)
                    } label: {
                        Text(l.title).font(Typo.ui(13, .medium))
                            .foregroundStyle(lens.level == l ? Tok.ink : Tok.ink2)
                            .frame(width: Self.segment, height: 36)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(lens.level == l ? .isSelected : [])
                    .help("\(l.title)  ⌘\(l.rawValue + 1)")
                }
            }
        }
        .padding(4)
        .background(Tok.ink.opacity(0.06), in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zoom")
    }
}
