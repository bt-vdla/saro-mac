import SaroKit
import SwiftUI

/// What the panel's Copy items put on the pasteboard, as Markdown (InsightBar.tsx handleCopy*): only what is on screen.
enum CopyText {
    static func narrative(_ n: Narrative, subtitle: String) -> String {
        (["# \(n.title)", "## \(subtitle)"] + n.body).joined(separator: "\n\n")
    }

    static func emotion(_ mood: Mood) -> String { "## \(mood.rawValue)\n\n\(mood.summary)" }

    static func question(_ q: String) -> String { "## \(q)" }

    /// The whole panel: the narrative, then each section, then the answer.
    static func summary(_ n: Narrative?, subtitle: String, mood: Mood, question: String?, answer: String?) -> String {
        var parts: [String] = []
        if let n { parts.append(narrative(n, subtitle: subtitle)) }
        parts.append(emotion(mood))
        if let question {
            parts.append("## For you to wonder\n\(question)" + (answer.map { "\n\n**Your answer:** \($0)" } ?? ""))
        }
        return parts.joined(separator: "\n\n")
    }
}

extension ReflectionModel {
    /// Copies and says so in one toast.
    func copy(_ text: String, toast: String?) {
        Self.copy(text)
        if let toast { model?.show(Toast(toast)) }
    }

    /// The panel's summary as Markdown, while the day's reading may show; nil on a held day or with nothing read.
    var summary: String? {
        guard let model, model.dayStatus == .ready, let p = model.dayReading?.payload else { return nil }
        let subtitle = p.reading.narrative ?? p.narrative?.subtitle ?? ""
        return CopyText.summary(p.narrative, subtitle: Letter.typeset(subtitle), mood: mood(p.reading), question: p.reading.question, answer: answer)
    }
}

/// Right-clicking anywhere on the panel (InsightBarContextMenu.tsx).
struct PanelMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let r = model.reflection
        Button("Refresh insights", systemImage: "arrow.clockwise") { Task { await r.refreshInsights() } }
            .disabled(!r.canRefresh)
        Button("Collapse to spine", systemImage: "sidebar.right") { model.insight = .spine }
        Button("Copy summary", systemImage: "doc.on.doc") {
            if let s = r.summary { r.copy(s, toast: "Copied to clipboard") }
        }
        .keyboardShortcut("c")
        .disabled(r.summary == nil)
    }
}
