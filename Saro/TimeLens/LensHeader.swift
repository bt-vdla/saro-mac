import SaroKit
import SwiftUI

/// Top left, what the lens frames and how much is in it; top right, the zoom control and the way back (LensView.tsx).
struct LensHeader: View {
    let lens: LensState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Self.title(lens)).font(Typo.ui(17, .medium)).tracking(-0.17).foregroundStyle(Tok.ink).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 8) {
                    Text(meta).monoCaps(11, tracking: 0.05).foregroundStyle(Tok.ink3)
                        .accessibilityLabel(meta)
                    if lens.status == .failed {
                        Button("Retry") { Task { await lens.load() } }
                            .buttonStyle(.plain)
                            .font(Typo.ui(12)).underline().foregroundStyle(Tok.sage)
                            .pointerStyle(.link)
                    }
                }
                .onChange(of: meta) { _, m in if lens.status != .ready || !m.isEmpty { AccessibilityNotification.Announcement(m).post() } }
                if let from = lens.reachFrom {
                    Text("The lens reaches back to \(from).").font(Typo.ui(12.5)).foregroundStyle(Tok.ink2)
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                LensLevels(lens: lens)
                Button {
                    lens.close(how: Motion.byKey ? .instant : .animated)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).foregroundStyle(Tok.ink2)
                        .frame(width: 44, height: 44)
                        .background(Tok.surface, in: .circle)
                        .overlay(Circle().strokeBorder(Tok.line))
                        .elevation(.lift)
                        .contentShape(.circle)
                }
                .buttonStyle(PressStyle(radius: 22))
                .accessibilityLabel("Back to \(lens.back)")
                .help("Back to \(lens.back)  Esc")
            }
        }
        .padding(.horizontal, 32).padding(.top, 28)
    }

    /// "22 – 28 September" for a week, "September 2026" for a month, "Nov 2025 – Oct 2026" for the year, in the locale's
    /// own range format.
    static func title(_ lens: LensState) -> String {
        guard !lens.cal.days.isEmpty else { return "" }
        let r = lens.unit, from = lens.cal.days[r.lowerBound].date, to = lens.cal.days[r.upperBound].date
        switch lens.level {
        case .year:
            let sameYear = Calendar.current.component(.year, from: from) == Calendar.current.component(.year, from: to)
            return sameYear ? "\(from.formatted(.dateTime.month(.abbreviated))) – \(to.formatted(.dateTime.month(.abbreviated).year()))"
                : (from..<to).formatted(Date.IntervalFormatStyle().month(.abbreviated).year())
        case .month: return from.formatted(.dateTime.month(.wide).year())
        case .week:
            return r.lowerBound == r.upperBound ? from.formatted(.dateTime.day().month(.wide))
                : (from..<to).formatted(Date.IntervalFormatStyle().day().month(.wide))
        }
    }

    private var meta: String {
        switch lens.status {
        case .failed: return "Couldn’t load your days"
        case .loading: return lens.slow ? "Reading your days…" : ""
        case .ready:
            let r = lens.unit
            let totals = r.map { lens.summaries[$0]?.total ?? 0 }
            let entries = totals.reduce(0, +), days = totals.filter { $0 > 0 }.count
            return entries == 0 ? "No entries" : "\(entries) \(entries == 1 ? "entry" : "entries") · \(days) \(days == 1 ? "day" : "days")"
        }
    }
}
