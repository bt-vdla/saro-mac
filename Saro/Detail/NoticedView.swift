import SaroKit
import SwiftUI

/// "What Saro noticed": the day reading in the inspector, or the honest state that stands in for it (§13.2).
struct NoticedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What Saro noticed").monoCaps(11, tracking: 0.12).foregroundStyle(Tok.ink3)
                        Text(DayFormat.title(model.day)).font(Typo.serif(22, .medium)).foregroundStyle(Tok.ink)
                    }
                    Spacer()
                    Button { model.insight = .spine } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tok.ink2)
                            .frame(width: 28, height: 28).background(Tok.ink.opacity(0.06), in: .circle)
                    }
                    .buttonStyle(PressStyle())
                    .help("Fold  esc")
                }
                content
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tourAnchor(.inspector)
        .onAppear { Task { await model.ai.prewarm() } }
        .task(id: "\(model.day)\(model.dayStatus)") { model.refreshDayReading() }
    }

    @ViewBuilder private var content: some View {
        switch model.dayStatus {
        case .empty:
            note("Saro reads your day once you've saved a moment, a voice note or some writing.")
        case .working:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading your day on this Mac…").font(Typo.ui(13)).foregroundStyle(Tok.ink3)
            }
        case .held:
            note("Saro isn't writing about today. Everything you saved is kept, and you can play or read it any time.")
            SafetyCardView(compact: true)
        case .awaitingCheck:
            note("Saro will read today once every entry has been checked. An entry whose transcript isn't ready yet holds the day.")
        case .ready:
            if let r = model.dayReading { reading(r.payload, generator: r.generator) } else { note("Reading…") }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Typo.ui(13)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func reading(_ p: DayPayload, generator: String) -> some View {
        let r = p.reading
        VStack(alignment: .leading, spacing: 6) {
            Text(r.mood.rawValue.uppercased()).font(Typo.mono(10.5)).foregroundStyle(Tok.sageTeal)
            Text(r.mood.summary).font(Typo.serif(17)).foregroundStyle(Tok.ink)
            if let basis = r.moodBasis, !basis.isEmpty {
                Text("From: \(basis)").font(Typo.ui(12)).foregroundStyle(Tok.ink3)
            }
        }
        if generator == "heuristic" {
            Text("IN YOUR WORDS").font(Typo.mono(9.5)).foregroundStyle(Tok.voice)
        } else if let n = r.narrative, !n.isEmpty {
            Text(n).font(Typo.serif(16)).foregroundStyle(Tok.voice).fixedSize(horizontal: false, vertical: true)
        }
        if !p.quotes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(p.quotes, id: \.index) { q in
                    Button { if model.entry(q.entryId) != nil { model.openEntryID = q.entryId } } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Rectangle().fill(Tok.sageSoft).frame(width: 2)
                            Text("“\(q.text)”").font(Typo.serif(14.5, italic: true)).foregroundStyle(Tok.ink2)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Open the entry")
                }
            }
        }
        if let q = r.question, !q.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("A QUESTION").font(Typo.mono(10)).foregroundStyle(Tok.ink3)
                Text(q).font(Typo.serif(15, italic: true)).foregroundStyle(Tok.ink)
            }
        }
        Button {
            model.insight = .letter
        } label: {
            Label("Open the evening letter", systemImage: "envelope.open").font(Typo.ui(13, .medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(Tok.onPrimary).background(Tok.sage, in: .capsule)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("l", modifiers: [.command, .option])
        Text(generator == "heuristic" ? "HEURISTIC · NO MODEL" : "ON-DEVICE · \(model.ai.variant.uppercased())")
            .font(Typo.mono(9)).foregroundStyle(Tok.ink4)
    }
}
