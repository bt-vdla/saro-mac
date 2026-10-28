import SaroKit
import SwiftUI

/// The narrative (InsightBar.tsx header): the title in Saro's serif, the subtitle (the model's narrative in its place when
/// it passed the drift check), and a body that opens on the chevron, with the day's quotes in the person's own words.
struct NarrativeSection: View {
    @Environment(AppModel.self) private var model
    let payload: DayPayload
    let narrative: Narrative
    let open: Bool
    let locked: Bool
    let toggle: () -> Void

    private var subtitle: String { Letter.typeset(payload.reading.narrative ?? narrative.subtitle) }

    var body: some View {
        let r = model.reflection
        let refreshing = r.busy.contains(.narrative) || r.busy.contains(.insights)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Letter.typeset(narrative.title)).font(Typo.serif(22, .medium)).foregroundStyle(Tok.momentInk)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(Typo.ui(13.5)).lineSpacing(2).foregroundStyle(Tok.momentInk)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button(action: toggle) { Chevron(open: open, tint: Tok.momentInk) }
                    .buttonStyle(.plain)
                    .opacity(locked ? 0.5 : 1)
                    .accessibilityLabel(open ? "Hide narrative" : "Show narrative")
            }
            if open {
                VStack(alignment: .leading, spacing: 12) {
                    if refreshing {
                        ShimmerLines(widths: [0.8, 1, 0.6, 1, 0.66])
                    } else {
                        ForEach(narrative.body, id: \.self) { p in
                            Text(Letter.typeset(p)).font(Typo.ui(13)).lineSpacing(3).foregroundStyle(Tok.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !payload.quotes.isEmpty { quotes }
                }
                .padding(.top, 12)
                .transition(.opacity)
            }
        }
        .contentShape(.rect)
        .contextMenu {
            Button("Refresh narrative", systemImage: "arrow.clockwise") { Task { await r.refreshNarrative() } }.disabled(refreshing)
            Button("Copy narrative", systemImage: "doc.on.doc") {
                r.copy(CopyText.narrative(narrative, subtitle: subtitle), toast: "Narrative copied")
            }
        }
    }

    /// "In your words": the reading's picked quotes, each opening the entry it came from.
    private var quotes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In your words").monoCaps(10, tracking: 0.12).foregroundStyle(Tok.ink3)
            ForEach(payload.quotes, id: \.index) { q in
                Button { if model.entry(q.entryId) != nil { model.openEntryID = q.entryId } } label: {
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 1).fill(model.entry(q.entryId).map { KindStyle.tint($0.kind) } ?? Tok.sageSoft).frame(width: 2)
                        Text("“\(Letter.typeset(q.text))”").font(Typo.serif(14.5, italic: true)).foregroundStyle(Tok.ink2)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Open the entry")
                .accessibilityHint("Opens the \(model.entry(q.entryId).map { KindStyle.noun($0.kind) } ?? "entry") this is from")
            }
        }
        .padding(.top, 4)
    }
}

/// The last-inferred line in the panel's sticky header: the newest entry's kind mark and one line about it, or, while a
/// new entry is still being read, that it was saved.
struct LastInferredLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let line: (kind: EntryKind, text: String)? = if model.dayStatus == .working, let e = model.entries.max(by: { $0.capturedAt < $1.capturedAt }) {
            (e.kind, KindStyle.pending(e.kind))
        } else if model.dayStatus == .ready, let l = model.dayReading?.payload.narrative?.lastInferred {
            (l.kind, Letter.typeset(l.message))
        } else {
            nil
        }
        if let line {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: KindStyle.symbol(line.kind)).font(.system(size: 13, weight: .semibold)).foregroundStyle(KindStyle.tint(line.kind))
                    .accessibilityHidden(true)
                Text(line.text).font(Typo.ui(13, .medium)).foregroundStyle(KindStyle.ink(line.kind))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .help(line.text)
            }
            .id(line.text)
            .transition(.asymmetric(insertion: .offset(y: 4).combined(with: .opacity), removal: .opacity))
        }
    }
}
