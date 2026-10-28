import SaroKit
import SwiftUI

/// The evening letter: the verified day reading, typeset in New York. Non-generative (B-11): every sentence is the
/// reading's or a template around the user's own quoted words, and each quote links back to its entry.
struct LetterView: View {
    @Environment(AppModel.self) private var model
    @State private var kept = false
    @State private var shown = false

    var body: some View {
        Group {
            if let r = model.dayReading, model.dayStatus == .ready, let letter = Letter(reading: r.payload.reading, candidates: r.payload.quotes) {
                ScrollView { page(letter, payload: r.payload) }
            } else {
                ContentUnavailableView("No letter tonight", systemImage: "envelope",
                                       description: Text("Saro writes the letter once the day has been read."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "saro", url.host == "entry" else { return .systemAction }
            model.insight = .spine
            model.openEntryID = url.lastPathComponent
            return .handled
        })
        .task(id: model.day) { kept = (try? await model.ledger.latestSnapshot(kind: "letter", day: model.day)) != nil }
    }

    /// EveningLetter.tsx: an italic salutation, the reading, then "In your words", "The day's mood" and
    /// "For you to wonder", lines rising in on a 50 ms stagger.
    private func page(_ letter: Letter, payload: DayPayload) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(LocalDay.date(model.day)?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? model.day)
                .monoCaps(10.5, tracking: 0.12).foregroundStyle(Tok.ink3)
            Text("This evening,").font(Typo.serif(28, italic: true)).foregroundStyle(Tok.ink)
                .rise(0, shown)
            ForEach(Array(letter.paragraphs.enumerated()), id: \.offset) { i, p in
                Text(attributed(p, quotes: letter.quotes))
                    .font(Typo.serif(18)).lineSpacing(6).foregroundStyle(Tok.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .rise(i + 1, shown)
            }
            if !letter.quotes.isEmpty {
                section("In your words", 3) {
                    ForEach(letter.quotes, id: \.index) { q in
                        Text(attributed("“\(q.text)”", quotes: [q])).font(Typo.serif(17, italic: true)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            section("The day's mood", 4) {
                Text(letter.mood.rawValue).font(Typo.serif(18, .medium)).foregroundStyle(MoodPalette.color(letter.mood))
                Text(Letter.typeset(letter.mood.summary)).font(Typo.serif(17, italic: true)).foregroundStyle(Tok.ink2)
            }
            if let q = letter.question {
                section("For you to wonder", 5) {
                    Text(Letter.typeset(q)).font(Typo.serif(21, italic: true)).foregroundStyle(Tok.voice).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(letter.signOff).font(Typo.serif(17)).foregroundStyle(Tok.ink2).rise(6, shown)
            HStack {
                Button(kept ? "Kept" : "Keep this letter") { Task { await keep(payload) } }
                    .disabled(kept)
                Spacer()
                Button("Back") { model.insight = .panel }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 48).padding(.vertical, 44)
        .onAppear { withAnimation { shown = true } }
    }

    private func section<Content: View>(_ title: String, _ i: Int, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).monoCaps(10.5, tracking: 0.12).foregroundStyle(Tok.ink3)
            content()
        }
        .rise(i, shown)
    }

    /// The user's quoted words become links to the entry they came from.
    private func attributed(_ text: String, quotes: [Candidate]) -> AttributedString {
        var out = AttributedString()
        for seg in Letter.segments(Letter.typeset(text), quotes: quotes) {
            var part = AttributedString(seg.text)
            if let q = seg.quote {
                part.link = URL(string: "saro://entry/\(q.entryId)")
                part.foregroundColor = Tok.voice
                part.underlineStyle = Text.LineStyle(pattern: .solid, color: Tok.voice.opacity(0.35))
            }
            out += part
        }
        return out
    }

    private func keep(_ payload: DayPayload) async {
        guard let json = try? JSONEncoder().encode(payload), let text = String(data: json, encoding: .utf8) else { return }
        try? await model.ledger.insertSnapshot(InsightSnapshot(kind: "letter", day: model.day, aiRunId: model.dayReading?.runId,
                                                               generator: model.dayReading?.generator ?? "heuristic", inputHash: nil, payload: text))
        kept = true
        model.show(Toast("Letter kept"))
    }
}

extension View {
    /// The letter's lines rise 6 pt over 350 ms, 50 ms apart (EveningLetter.tsx). Reduce Motion keeps the fade only.
    func rise(_ index: Int, _ shown: Bool) -> some View {
        modifier(Rise(index: index, shown: shown))
    }
}

private struct Rise: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .animation(Motion.easeOut(0.35).delay(Double(index) * 0.05), value: shown)
    }
}
