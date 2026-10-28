import SaroKit
import SwiftUI

/// The first week keeping its word (FirstWeekNote.tsx), above the narrative on the day it arrived: "A first pattern",
/// the day 4–5 check-in, or the first weekly letter, typeset like the evening letter and signed. It rises 8 pt.
struct FirstWeekNoteView: View {
    let note: WeekNote
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let letter = note.kind == .letter
        VStack(alignment: .leading, spacing: 0) {
            Text(letter ? "Your first weekly letter" : "Your first week").monoCaps(10.5, tracking: 0.12).foregroundStyle(Tok.ink3)
            Text(note.title).font(letter ? Typo.serif(24, italic: true) : Typo.serif(20, .medium))
                .foregroundStyle(letter ? Tok.voice : Tok.ink)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(note.lines, id: \.self) { line in
                    Text(line).font(letter ? Typo.serif(16) : Typo.ui(13.5)).lineSpacing(letter ? 4 : 2).foregroundStyle(Tok.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 10)
            if letter { Text("Saro").font(Typo.serif(16, italic: true)).foregroundStyle(Tok.ink).padding(.top, 12) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: Radius.panel)
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : 8)
        .onAppear { withAnimation(Motion.easeOut(0.35)) { shown = true } }
        .accessibilityElement(children: .combine)
    }
}
