#if DOGFOOD
import SwiftUI

/// The guided internal tour. Each step spotlights the first of its targets that's on screen; a step with none is
/// skipped unless it `floats`, in which case its card shows centred.
enum Tour {
    struct Step {
        let targets: [TourTarget]
        let title: String
        let body: String
        var floats = false
    }

    static let steps: [Step] = [
        Step(targets: [.sidebar], title: "Your days",
             body: "Every day you've journaled, with its entry count. Trash keeps deleted entries for undo, and Decisions holds the register to review."),
        Step(targets: [.dayNav], title: "Move between days",
             body: "⌘[ and ⌘] step a day back or forward, and Today (⌘T) brings you home. Capturing while a past day is open files the entry under that day."),
        Step(targets: [.canvas], title: "The day's canvas",
             body: "Pan with two fingers. Pinch or ⌘-scroll to zoom. Press a card for a moment, then drag to move it. Drag on empty space to marquee-select."),
        Step(targets: [.captureBar], title: "Capture",
             body: "Video comes first. Voice and writing are one click away. Drop or paste a still anywhere on the canvas."),
        Step(targets: [.recordButton], title: "Record a moment",
             body: "Each pause ends a turn and resume starts the next. A session's turns stack together on the canvas."),
        Step(targets: [.toolbar], title: "Arrange a selection",
             body: "Select cards to raise the toolbar: Stack ⌘S, Grid ⌘G and Delete. Deleted cards go to Trash; ⌘Z brings them back."),
        Step(targets: [.noticedButton, .inspector], title: "What Saro noticed",
             body: "Saro's reading of the day, made on this Mac once each entry passes the safety gate. In the evening it becomes a typeset letter."),
        Step(targets: [.devNotes], title: "Dev notes",
             body: "⇧⌘D opens notes for whatever screen you're on: what's built, what's stubbed and its open decisions. Leave a note for Claude there; File → Export Decisions for Claude (⇧⌘E) hands everything back.",
             floats: true),
        Step(targets: [.helpMenu], title: "Help",
             body: "Help → Take the Tour runs this again. Help → If you're struggling is one click from every screen.",
             floats: true),
    ]
}

/// Dims the window, cuts a rounded hole around the step's target and places the callout beside it.
struct TourOverlay: View {
    let anchors: [TourTarget: Anchor<CGRect>]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let dev = DevMode.shared

    var body: some View {
        GeometryReader { geo in
            let bounds = CGRect(origin: .zero, size: geo.size)
            let steps = Tour.steps.compactMap { step -> (Tour.Step, CGRect?)? in
                if let rect = step.targets.lazy.compactMap({ t in anchors[t].map { geo[$0] } }).first { return (step, rect) }
                return step.floats ? (step, nil) : nil
            }
            if let index = dev.tourStep, !steps.isEmpty {
                let i = min(index, steps.count - 1)
                let step = steps[i].0, target = steps[i].1
                // A target outside the content (a window toolbar item) gets no hole; its card sits under it instead.
                let hole = target.map { $0.insetBy(dx: -8, dy: -8).intersection(bounds) }.flatMap { $0.isNull || $0.isEmpty ? nil : $0 }
                let shape = Cutout(hole: hole ?? CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0))
                ZStack(alignment: .topLeading) {
                    shape
                        .fill(Color.black.opacity(0.42), style: FillStyle(eoFill: true))
                        .contentShape(shape, eoFill: true)
                        .onTapGesture {}
                    if let hole {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Tok.mint, lineWidth: 2)
                            .frame(width: hole.width, height: hole.height)
                            .offset(x: hole.minX, y: hole.minY)
                            .allowsHitTesting(false)
                    }
                    callout(step, index: i, count: steps.count)
                        .position(Self.place(card: CGSize(width: 320, height: 190), beside: hole ?? target, in: bounds))
                        .id(i)
                        .transition(.opacity)
                }
                .animation(reduceMotion ? nil : Motion.open, value: hole)
                .animation(Motion.fade, value: i)
                .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: dev.tourStep == nil)
    }

    private func callout(_ step: Tour.Step, index: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DevHeading("Tour · \(index + 1) of \(count)")
            Text(step.title).font(Typo.serif(20, .medium)).foregroundStyle(Tok.ink)
            Text(step.body).font(Typo.ui(13)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Skip") { dev.endTour() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderless)
                Spacer()
                if index > 0 {
                    Button("Back") { dev.tourStep = index - 1 }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                }
                Button(index == count - 1 ? "Done" : "Next") {
                    if index == count - 1 { dev.endTour() } else { dev.tourStep = index + 1 }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Tok.sage)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(width: 320)
        .saroSurface(radius: 16, lifted: true)
    }

    /// Centre point for the callout: right of the target, else left, below, above; centred when there's no target.
    static func place(card: CGSize, beside target: CGRect?, in bounds: CGRect) -> CGPoint {
        let gap: CGFloat = 16, margin: CGFloat = 16
        guard let t = target else { return CGPoint(x: bounds.midX, y: bounds.midY) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, card.height / 2 + margin), bounds.maxY - card.height / 2 - margin) }
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, card.width / 2 + margin), bounds.maxX - card.width / 2 - margin) }
        if t.maxX + gap + card.width + margin <= bounds.maxX { return CGPoint(x: t.maxX + gap + card.width / 2, y: clampY(t.midY)) }
        if t.minX - gap - card.width - margin >= bounds.minX { return CGPoint(x: t.minX - gap - card.width / 2, y: clampY(t.midY)) }
        if t.maxY + gap + card.height + margin <= bounds.maxY { return CGPoint(x: clampX(t.midX), y: max(t.maxY, 0) + gap + card.height / 2) }
        if t.minY - gap - card.height - margin >= bounds.minY { return CGPoint(x: clampX(t.midX), y: t.minY - gap - card.height / 2) }
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

/// The dimmed window with one rounded hole; the hole animates between steps.
private struct Cutout: Shape {
    var hole: CGRect

    var animatableData: CGRect.AnimatableData {
        get { hole.animatableData }
        set { hole.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        p.addRoundedRect(in: hole, cornerSize: CGSize(width: 12, height: 12), style: .continuous)
        return p
    }
}
#endif
