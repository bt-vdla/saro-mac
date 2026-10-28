import SaroKit
import SwiftUI

/// "What Saro noticed" (InsightBar.tsx's expanded bar): a sticky header with the last-inferred line, then the first
/// week's note, the narrative, the mood and the question as single-open sections, the way into the letter and the
/// commitments card, or the honest state that stands in for the reading (§13.2).
struct NoticedView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open: PanelSection? = .narrative
    @State private var editing = false
    @FocusState private var collapseFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                    LetterEntry().padding(.top, 10)
                    CommitmentsCard().padding(.top, 10)
                    provenance.padding(.top, 14)
                }
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
        .contextMenu { PanelMenu() }
        .tourAnchor(.inspector)
        .onAppear {
            Task { await model.ai.prewarm() }
            if model.reflection.how == .instant { collapseFocused = true }
        }
        // Read on open, before the first frame, so a reading that's coming never flashes as one that failed.
        .onChange(of: "\(model.day)\(model.dayStatus)", initial: true) { if model.dayStatus == .ready { model.rereadDay() } }
        .onDisappear { model.reflection.answerRequested = false }
        .onChange(of: model.day) {
            open = .narrative
            editing = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("What Saro noticed · \(DayNarrative.label(model.day))").monoCaps(10, tracking: 0.12).foregroundStyle(Tok.ink3)
                    .lineLimit(1)
                Spacer()
                Button { model.insight = .spine } label: {
                    Image(systemName: "sidebar.right").font(.system(size: 13, weight: .medium)).foregroundStyle(Tok.momentInk)
                        .frame(width: 32, height: 32)
                        .background(Tok.paper.opacity(0.9), in: .circle)
                        .overlay(Circle().strokeBorder(Tok.rim.opacity(0.7)))
                        .elevation(.raise)
                        .contentShape(.circle)
                }
                .buttonStyle(PressStyle())
                .focused($collapseFocused)
                .help("Collapse insights  esc")
                .accessibilityLabel("Collapse insights")
            }
            LastInferredLine()
                .animation(Motion.easeOut(0.2), value: model.dayReading?.payload.narrative?.lastInferred?.message)
        }
        .padding(.leading, 20).padding(.trailing, 16).padding(.top, 16).padding(.bottom, 10)
        .background(Tok.paper.opacity(0.8))
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [Tok.paper.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom).frame(height: 8).offset(y: 8)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.dayStatus {
        case .empty:
            emptyState
        case .working:
            loading
        case .held:
            VStack(alignment: .leading, spacing: 14) {
                note("Saro isn’t writing about this day. Everything you saved is kept, and you can play or read it any time.")
                SafetyCardView(compact: true)
            }
            .padding(.top, 8)
        case .awaitingCheck:
            note("Saro will read this day once every entry has been checked. An entry whose transcript isn’t ready yet holds the day.")
                .padding(.top, 8)
        case .ready:
            if let r = model.dayReading, let narrative = r.payload.narrative {
                reading(r.payload, narrative: narrative)
            } else if model.working {
                loading
            } else {
                unavailable
            }
        }
    }

    /// The day can be read but no reading came (InsightBar's 'unavailable'): say so, and offer to try again.
    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Insights aren’t ready yet").font(Typo.serif(22, .medium)).foregroundStyle(Tok.momentInk)
            Text(model.isToday ? "Saro couldn’t read today’s entries just now." : "Saro couldn’t read this day’s entries just now.")
                .font(Typo.ui(13.5)).foregroundStyle(Tok.momentInk)
            Button("Try again") { model.reflection.retryReading() }
                .buttonStyle(Pill(primary: true))
                .padding(.top, 10)
        }
        .padding(.top, 6)
    }

    /// Nothing to read yet: on the day itself, what to add; on another, that nothing was saved; and when there are
    /// entries without words (a bare still), what Saro reads.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "circle.dotted").font(.system(size: 22, weight: .light)).foregroundStyle(Tok.ink3).padding(.bottom, 4)
                .accessibilityHidden(true)
            if !model.entries.isEmpty {
                Text("Saro reads your day once you’ve saved a moment, a voice note or some writing.")
                    .font(Typo.ui(13, .medium)).foregroundStyle(Tok.ink2)
            } else if model.isToday {
                Text("Nothing yet today.").font(Typo.ui(13, .medium)).foregroundStyle(Tok.ink2)
                Text("Add a moment, an echo, or a still. Insights appear once there’s something to read.")
                    .font(Typo.ui(12)).foregroundStyle(Tok.ink3).frame(maxWidth: 220)
            } else {
                Text("Nothing saved on this day.").font(Typo.ui(13, .medium)).foregroundStyle(Tok.ink2)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.isToday ? "Reading today’s entries…" : "Reading this day’s entries…").font(Typo.serif(22, .medium)).foregroundStyle(Tok.momentInk)
            Text("This takes a few seconds.").font(Typo.ui(13.5)).foregroundStyle(Tok.momentInk)
            ShimmerLines(widths: [0.8, 1, 0.6, 1, 0.66]).padding(.top, 10)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Typo.ui(13)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func reading(_ p: DayPayload, narrative: Narrative) -> some View {
        if let n = model.reflection.note { FirstWeekNoteView(note: n).padding(.bottom, 14) }
        NarrativeSection(payload: p, narrative: narrative, open: open == .narrative, locked: editing) { set(.narrative) }
            .padding(.top, 4)
        rule
        MoodSection(reading: p.reading, open: open == .mood) { set(.mood) }
        rule
        QuestionSection(question: p.reading.question, open: open == .question, editing: $editing) { set(.question) }
    }

    private var rule: some View { Rectangle().fill(Tok.line.opacity(0.7)).frame(height: 1).padding(.vertical, 10) }

    /// Single-open, on the small spring (a fade under Reduce Motion); locked open while an answer is being written.
    private func set(_ s: PanelSection) {
        guard !editing else { return }
        withAnimation(Motion.pick(Motion.small, reduce: reduceMotion)) { open = open == s ? nil : s }
    }

    @ViewBuilder private var provenance: some View {
        if model.dayStatus == .ready, let r = model.dayReading {
            Text(r.generator == "heuristic" ? "In your words · no model" : "On-device · \(model.ai.variant)")
                .monoCaps(9, tracking: 0.12).foregroundStyle(Tok.ink4)
        }
    }
}

/// The panel's way into the letter (LetterEntry): "Close the day" before the letter time, the letter itself once it's
/// there. Hidden on a day with no reading; never on a held day or one awaiting a check.
private struct LetterEntry: View {
    @Environment(AppModel.self) private var model
    @State private var hover = false

    var body: some View {
        let r = model.reflection
        if model.dayStatus == .ready, model.dayReading != nil, r.letterAvailable || r.isToday {
            let available = r.letterAvailable
            Button { model.insight = .letter } label: {
                HStack(spacing: 12) {
                    Image(systemName: available ? "envelope" : "moon.stars").font(.system(size: 14)).foregroundStyle(Tok.voice)
                        .frame(width: 32, height: 32)
                        .background(Tok.voice.opacity(0.1), in: .circle)
                        .overlay(alignment: .topTrailing) {
                            if r.letterUnread {
                                Circle().fill(Tok.voice).frame(width: 8, height: 8).overlay(Circle().strokeBorder(Tok.surface, lineWidth: 2))
                                    .offset(x: -1, y: 1)
                            }
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(!available ? "Close the day" : r.isToday ? "Today’s letter" : "This day’s letter")
                            .font(Typo.serif(16)).foregroundStyle(Tok.ink)
                        Text(!available ? "Saro writes you a letter about today."
                             : r.kept != nil ? "Kept with this day." : r.letterUnread ? "Waiting for you." : "Read it again.")
                            .font(Typo.ui(12)).foregroundStyle(Tok.ink3)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Tok.ink3)
                        .offset(x: hover ? 2 : 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(minHeight: 48)
                .background(Tok.surface.opacity(hover ? 1 : 0.7), in: .rect(cornerRadius: Radius.panel))
                .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Tok.rim.opacity(0.8)))
                .elevation(.lift)
                .contentShape(.rect(cornerRadius: Radius.panel))
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .onHover { hover = $0 }
            .animation(Motion.small, value: hover)
            .help("Evening letter  ⌥⌘L")
        }
    }
}
