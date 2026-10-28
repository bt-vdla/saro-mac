import AppKit
import SaroKit
import SwiftUI

/// An About you answer: an NSTextView that marks what Saro picks up with layout-manager temporary attributes (an
/// underline and a faint wash per kind, HighlightedAnswer.tsx), so marking never moves the text. Return commits (not
/// a held Return, not while composing), Shift-Return is a new line except on Q1, ⌥← at the very start goes back.
struct AnswerField: NSViewRepresentable {
    @Binding var text: String
    var marks: [Pick]
    var maxLength: Int
    var singleLine: Bool
    var label: String
    var onCommit: () -> Void
    var onBack: () -> Void
    /// The caret after each edit, or nil once composition (marked text) ends without one.
    var onEdit: (Int) -> Void
    var onComposing: (Int?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Read as the parent draws, so Text size and the Writing Tools switch reach a field that's already open.
    private let font = NSFont(name: "Geist-Regular", size: 28 * PrefsStore.shared.textScale) ?? .systemFont(ofSize: 28 * PrefsStore.shared.textScale)
    private let writingTools: NSWritingToolsBehavior = PrefsStore.shared.writingTools ? .default : .none

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> AnswerTextView {
        let tv = AnswerTextView(usingTextLayoutManager: false)
        tv.delegate = context.coordinator
        tv.coordinator = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.drawsBackground = false
        tv.allowsUndo = true
        tv.isContinuousSpellCheckingEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.writingToolsBehavior = writingTools
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.font = font
        tv.textColor = NSColor(Tok.ink)
        tv.insertionPointColor = NSColor(Tok.sage)
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.18
        tv.defaultParagraphStyle = style
        tv.typingAttributes = [.font: font, .foregroundColor: NSColor(Tok.ink), .paragraphStyle: style, .kern: -0.28]
        tv.string = text
        tv.setAccessibilityLabel(label)
        return tv
    }

    func updateNSView(_ tv: AnswerTextView, context: Context) {
        context.coordinator.parent = self
        if tv.font != font {
            tv.font = font
            tv.typingAttributes[.font] = font
        }
        if tv.writingToolsBehavior != writingTools { tv.writingToolsBehavior = writingTools }
        if tv.string != text, !tv.hasMarkedText() {
            tv.string = text
            tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        tv.setAccessibilityLabel(label)
        context.coordinator.paint(marks, in: tv, fade: !reduceMotion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: AnswerTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 600
        guard let container = tv.textContainer, let layout = tv.layoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let line = layout.defaultLineHeight(for: font) * 1.18
        return CGSize(width: width, height: max(line, ceil(layout.usedRect(for: container).height)))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AnswerField
        private var shown: [String: (range: NSRange, kind: Pick.Kind)] = [:]
        private var born: [String: ContinuousClock.Instant] = [:]
        private var fading: Task<Void, Never>?

        init(_ parent: AnswerField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            if tv.hasMarkedText() {
                parent.onComposing(tv.markedRange().location)
            } else {
                parent.onComposing(nil)
                parent.onEdit(tv.selectedRange().location)
            }
        }

        /// The limit (30 for a name, 280 for an answer, in UTF-16 like the web's maxLength), and no line breaks on Q1.
        func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange, replacementString string: String?) -> Bool {
            guard var s = string, !tv.hasMarkedText() else { return true }
            if parent.singleLine { s = s.replacingOccurrences(of: "\n", with: " ") }
            let room = parent.maxLength - ((tv.string as NSString).length - range.length)
            var fit = ""
            for c in s where (fit + String(c)).utf16.count <= max(0, room) { fit.append(c) }
            if fit == string { return true }
            if !fit.isEmpty { tv.insertText(fit, replacementRange: range) } else { NSSound.beep() }
            return false
        }

        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.moveWordLeft(_:)), tv.selectedRange() == NSRange(location: 0, length: 0) {
                parent.onBack()
                return true
            }
            return false
        }

        /// New marks fade in over 160 ms; dropped or moved ones go at once.
        func paint(_ marks: [Pick], in tv: NSTextView, fade: Bool) {
            let length = (tv.string as NSString).length
            var next: [String: (range: NSRange, kind: Pick.Kind)] = [:]
            for m in marks where m.end <= length && m.start < m.end {
                next["\(m.kind.rawValue)|\(m.start)|\(m.end)"] = (NSRange(location: m.start, length: m.end - m.start), m.kind)
            }
            let now = ContinuousClock.now
            for key in next.keys where shown[key] == nil { born[key] = fade ? now : now - .seconds(1) }
            born = born.filter { next[$0.key] != nil }
            let changed = next.keys.sorted() != shown.keys.sorted()
            shown = next
            draw(tv)
            guard changed else { return }
            fading?.cancel()
            fading = Task { [weak tv] in
                while !Task.isCancelled, let tv {
                    try? await Task.sleep(for: .milliseconds(16))
                    self.draw(tv)
                    if self.born.values.allSatisfy({ $0.duration(to: .now) > .milliseconds(160) }) { break }
                }
            }
        }

        private func draw(_ tv: NSTextView) {
            guard let lm = tv.layoutManager else { return }
            let all = NSRange(location: 0, length: (tv.string as NSString).length)
            for key in [NSAttributedString.Key.underlineStyle, .underlineColor, .backgroundColor] { lm.removeTemporaryAttribute(key, forCharacterRange: all) }
            for (key, mark) in shown where NSMaxRange(mark.range) <= all.length {
                let age = born[key].map { $0.duration(to: .now) } ?? .seconds(1)
                let seconds = Double(age.components.seconds) + Double(age.components.attoseconds) / 1e18
                let alpha = CGFloat(min(1, seconds / 0.16))
                let style = PickStyle(mark.kind)
                lm.addTemporaryAttributes([
                    .underlineStyle: style.underline.rawValue,
                    .underlineColor: style.nsColor(alpha: alpha),
                    .backgroundColor: style.nsColor(alpha: alpha * 0.08),
                ], forCharacterRange: mark.range)
            }
        }
    }
}

/// The NSTextView behind AnswerField: Return commits, focus lands with the caret at the end.
final class AnswerTextView: NSTextView {
    weak var coordinator: AnswerField.Coordinator?

    override func keyDown(with event: NSEvent) {
        guard [36, 76].contains(event.keyCode), !hasMarkedText(), let c = coordinator else { return super.keyDown(with: event) }
        // Held Return repeats; one press moves one question.
        if event.isARepeat { return }
        if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) {
            if !c.parent.singleLine { insertNewline(nil) }
            return
        }
        c.parent.onCommit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
            self.setSelectedRange(NSRange(location: (self.string as NSString).length, length: 0))
        }
    }
}

/// How each kind is marked (HighlightedAnswer.tsx PICK_UNDERLINE): text stays ink; no two solid kinds share a question.
struct PickStyle {
    let underline: NSUnderlineStyle
    let color: Color
    let pattern: Text.LineStyle.Pattern
    let double: Bool

    init(_ kind: Pick.Kind) {
        switch kind {
        case .name: (underline, color, pattern, double) = (.single, Tok.sageTeal, .solid, false)
        case .person: (underline, color, pattern, double) = (.double, Tok.echoInk, .solid, true)
        case .theme: (underline, color, pattern, double) = ([.thick, .patternDot], Tok.reflectionInk, .dot, false)
        case .time: (underline, color, pattern, double) = ([.single, .patternDash], Tok.music, .dash, false)
        case .goal: (underline, color, pattern, double) = (.single, Tok.stillInk, .solid, false)
        case .tone: (underline, color, pattern, double) = (.single, Tok.voice, .solid, false)
        }
    }

    /// The kind's colour at `alpha`, resolved for the light or dark appearance it's drawn in.
    func nsColor(alpha: CGFloat) -> NSColor {
        let base = NSColor(color)
        return NSColor(name: nil) { appearance in
            var resolved = base
            appearance.performAsCurrentDrawingAppearance { resolved = base.usingColorSpace(.sRGB) ?? base }
            return resolved.withAlphaComponent(alpha)
        }
    }

    /// The same mark on SwiftUI text: the chips and the first question.
    func apply(to s: inout AttributedSubstring, wash: Bool = true) {
        s.underlineStyle = Text.LineStyle(pattern: pattern, color: color)
        if wash { s.backgroundColor = color.opacity(0.08) }
    }
}
