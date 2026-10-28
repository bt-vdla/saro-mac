import SaroKit
import SwiftUI

/// The evening letter: the verified day reading, typeset in New York. Non-generative (B-11): every sentence is the
/// reading's or a template around the user's own quoted words, and each quote links back to its entry.
struct LetterView: View {
    @Environment(AppModel.self) private var model
    @State private var kept = false

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

    private func page(_ letter: Letter, payload: DayPayload) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(LocalDay.date(model.day)?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased() ?? model.day)
                .font(Typo.mono(10.5)).foregroundStyle(Tok.ink3)
            ForEach(Array(letter.paragraphs.enumerated()), id: \.offset) { _, p in
                Text(attributed(p, quotes: letter.quotes))
                    .font(Typo.serif(19)).lineSpacing(6).foregroundStyle(Tok.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(letter.mood.rawValue.uppercased()).font(Typo.mono(10.5)).foregroundStyle(Tok.sageTeal)
                Text(Letter.typeset(letter.mood.summary)).font(Typo.serif(17, italic: true)).foregroundStyle(Tok.ink2)
            }
            if let q = letter.question {
                Text(Letter.typeset(q)).font(Typo.serif(19, italic: true)).foregroundStyle(Tok.voice)
            }
            Text(letter.signOff).font(Typo.serif(17)).foregroundStyle(Tok.ink2)
            HStack {
                Button(kept ? "Kept" : "Keep this letter") { Task { await keep(payload) } }
                    .disabled(kept)
                Spacer()
                Button("Back") { model.insight = .panel }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 48).padding(.vertical, 44)
    }

    /// The user's quoted words become links to the entry they came from.
    private func attributed(_ text: String, quotes: [Candidate]) -> AttributedString {
        var out = AttributedString()
        for seg in Letter.segments(Letter.typeset(text), quotes: quotes) {
            var part = AttributedString(seg.text)
            if let q = seg.quote {
                part.link = URL(string: "saro://entry/\(q.entryId)")
                part.foregroundColor = Tok.sageTeal
                part.underlineStyle = .single
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
