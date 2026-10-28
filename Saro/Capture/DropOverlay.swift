import SaroKit
import SwiftUI

/// While a file Saro can keep is dragged over the canvas (Canvas.tsx): a dashed sage frame inset 12 over paper/40 and a
/// light blur, with a card naming the file's kind and the day it lands on. Fades in over 160 ms; the card grows from 0.96.
struct DropOverlay: View {
    let kind: EntryKind?
    let day: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let kind {
                ZStack {
                    Rectangle().fill(.frosted(.ultraThinMaterial, solid: Tok.paper.opacity(0.4))).overlay(Tok.paper.opacity(0.4))
                    RoundedRectangle(cornerRadius: Radius.sheet)
                        .strokeBorder(Tok.sage.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .padding(12)
                    card(kind)
                        .transition(reduceMotion ? .identity : .scale(scale: 0.96))
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.easeOut(0.16), value: kind)
        .allowsHitTesting(false)
    }

    private func card(_ kind: EntryKind) -> some View {
        VStack(spacing: 8) {
            Image(systemName: kind == .still ? "photo.badge.plus" : kind == .voice ? "waveform" : "movieclapper")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(kind.tint)
                .frame(width: 52, height: 52)
                .background(kind.tint.opacity(0.12), in: .circle)
            Text("Drop to add to \(DayFormat.sidebar(day))").font(Typo.ui(15, .medium)).foregroundStyle(Tok.ink)
            Text("It lands where you let go.").font(Typo.ui(13)).foregroundStyle(Tok.ink2)
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
        .background(Tok.surfaceAlt.opacity(0.9), in: .rect(cornerRadius: Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Tok.rim.opacity(0.6)))
        .elevation(.float)
        .accessibilityElement(children: .combine)
    }
}
