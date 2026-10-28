import SaroKit
import SwiftUI

/// The evening letter (EveningLetter.tsx): the verified day reading, typeset in Newsreader. Non-generative (B-11): every
/// sentence is the reading's or a template around the person's own quoted words, and each quote links back to its
/// entry, flying into it from where it was read. A kept letter reads as it was kept.
struct LetterView: View {
    @Environment(AppModel.self) private var model
    @State private var shown = false
    @State private var writing = false
    @State private var draft = ""
    @State private var saving = false
    @State private var hovered: Int?
    @State private var frames: [Int: CGRect] = [:]
    @FocusState private var focus: Field?

    private enum Field: Hashable { case letter, draft }
    private var r: ReflectionModel { model.reflection }

    /// The kept copy when there is one, else the letter as the reading stands; nothing while entries are unchecked.
    private var letter: Letter? {
        guard model.dayStatus == .ready, let p = model.dayReading?.payload else { return nil }
        return r.kept ?? Letter(reading: p.reading, candidates: p.quotes, narrative: p.narrative, mood: r.state.lockedMood)
    }

    /// When the words come in after the surface: after the arrival's ease, after a morph, or at once.
    private var base: Double? {
        switch r.how {
        case .instant: nil
        case .arrive: 0.32
        case .morph: 0.14
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    salutation.rise(0, shown, base: base)
                    content
                }
                .padding(.horizontal, 36).padding(.top, 10).padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .letter)
            if let letter { footer(letter) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(r.kept != nil ? "Kept letter" : "Evening letter")
        .onAppear {
            if base == nil { shown = true; focus = .letter } else { withAnimation { shown = true } }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(r.kept != nil && letter != nil ? "Kept letter" : "Evening letter")
                .font(Typo.ui(10.5, .semibold)).tracking(1.3).textCase(.uppercase).foregroundStyle(Tok.ink3)
            Text(DayNarrative.label(model.day).uppercased()).font(Typo.mono(11)).tracking(0.7).foregroundStyle(Tok.ink3)
            Spacer()
            Button { model.insight = .spine } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .medium)).foregroundStyle(Tok.ink2)
                    .frame(width: 36, height: 36).contentShape(.circle)
            }
            .buttonStyle(PressStyle(hoverFill: true, radius: 18))
            .help("Close the letter  esc")
            .accessibilityLabel("Close the letter")
        }
        .padding(.leading, 36).padding(.trailing, 14).padding(.top, 14).padding(.bottom, 2)
    }

    /// 'Dear {name},' cut at 39 characters, isolated so a right-to-left name keeps its ellipsis at its own end; 'Hello,'
    /// with no name.
    private var salutation: some View {
        let name = model.profile?.address
        let cut = name.map { $0.count > 40 ? $0.prefix(39).trimmingCharacters(in: .whitespaces) + "…" : $0 }
        return Text(cut.map { "Dear \u{2068}\($0)\u{2069}," } ?? "Hello,")
            .font(Typo.serif(28, italic: true)).foregroundStyle(Tok.ink)
            .lineLimit(2)
            .help(name ?? "")
    }

    @ViewBuilder private var content: some View {
        switch model.dayStatus {
        case .held:
            VStack(alignment: .leading, spacing: 14) {
                prose("Saro isn’t writing about this day. Everything you saved is kept.")
                SafetyCardView(compact: true)
            }
            .padding(.top, 18)
        case .awaitingCheck:
            prose("Saro writes your letter once every entry has been checked. An entry whose transcript isn’t ready yet holds it.")
                .padding(.top, 18).rise(1, shown, base: base)
        case .empty:
            prose("Saro writes the letter once there’s something to read.").padding(.top, 18).rise(1, shown, base: base)
        case .working:
            writingShimmer
        case .ready:
            if let letter { page(letter) } else if model.dayReading == nil { writingShimmer } else { unavailable }
        }
    }

    private var writingShimmer: some View {
        ShimmerLines(widths: [0.92, 1, 0.8, 1, 0.6], height: 12, spacing: 14)
            .padding(.top, 22)
            .accessibilityElement()
            .accessibilityLabel("Saro is writing your letter")
            .rise(1, shown, base: base)
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 18) {
            prose("Saro couldn’t write your letter just now. Your entries are safe.")
            Button(r.busy.contains(.insights) ? "Trying again…" : "Retry") { Task { await r.refreshInsights() } }
                .buttonStyle(Pill(primary: true))
                .disabled(r.busy.contains(.insights))
        }
        .padding(.top, 18)
        .rise(1, shown, base: base)
    }

    private func prose(_ text: String) -> some View {
        Text(text).font(Typo.serif(18)).lineSpacing(7).foregroundStyle(Tok.ink).fixedSize(horizontal: false, vertical: true)
    }

    private func page(_ letter: Letter) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(letter.paragraphs.enumerated()), id: \.offset) { i, p in
                    paragraph(p, quotes: letter.quotes, slot: i).rise(i + 1, shown, base: base)
                }
            }
            .opacity(r.busy.contains(.letter) ? 0.4 : 1)
            .animation(Motion.easeOut(0.25), value: r.busy.contains(.letter))
            .padding(.top, 16)

            let unplaced = letter.unplacedQuotes
            if !unplaced.isEmpty {
                section("In your words", 4) {
                    ForEach(Array(unplaced.enumerated()), id: \.offset) { i, q in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(model.entry(q.entryId).map { KindStyle.tint($0.kind) } ?? Tok.ink4).frame(width: 6, height: 6)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                            paragraph("“\(q.text)”", quotes: [q], slot: 100 + i, size: 17, italic: true)
                        }
                    }
                }
            }
            section("The day’s mood", 5) {
                Text("\(Text("\(letter.mood.rawValue).").font(Typo.serif(18, italic: true))) \(Letter.typeset(letter.mood.summary))")
                    .font(Typo.serif(18)).lineSpacing(7).foregroundStyle(Tok.ink).fixedSize(horizontal: false, vertical: true)
            }
            if let q = letter.question {
                section("For you to wonder", 6) {
                    Text(Letter.typeset(q)).font(Typo.serif(21, italic: true)).lineSpacing(5).foregroundStyle(Tok.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    writeBack(letter)
                }
            }
            Text(letter.signOff).font(Typo.serif(18, italic: true)).foregroundStyle(Tok.ink2).padding(.top, 30).rise(7, shown, base: base)
        }
    }

    private func section<Content: View>(_ title: String, _ i: Int, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Typo.ui(10.5, .semibold)).tracking(1.3).textCase(.uppercase).foregroundStyle(Tok.ink3).accessibilityHidden(true)
            content()
        }
        .padding(.top, 26)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .rise(i, shown, base: base)
    }

    /// One paragraph, the person's quoted words voice-coloured links whose underline firms on hover. A click folds the
    /// letter to the spine and flies into the entry from the paragraph's place.
    // ponytail: the flight starts from the paragraph's frame; per-quote frames need TextLayout runs.
    private func paragraph(_ text: String, quotes: [Candidate], slot: Int, size: CGFloat = 18, italic: Bool = false) -> some View {
        Text(attributed(text, quotes: quotes, firm: hovered == slot))
            .font(Typo.serif(size, italic: italic)).lineSpacing(size * 0.4).foregroundStyle(Tok.ink)
            .fixedSize(horizontal: false, vertical: true)
            .onHover { hovered = $0 ? slot : hovered == slot ? nil : hovered }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DayView.space)) } action: { frames[slot] = $0 }
            .environment(\.openURL, OpenURLAction { url in follow(url, from: frames[slot]) })
            .accessibilityActions {
                ForEach(quotes, id: \.index) { q in
                    Button("Open the \(model.entry(q.entryId).map { KindStyle.noun($0.kind) } ?? "entry") “\(q.text)” is from") {
                        _ = follow(URL(string: "saro://entry/\(q.entryId)")!, from: frames[slot])
                    }
                }
            }
    }

    private func follow(_ url: URL, from frame: CGRect?) -> OpenURLAction.Result {
        guard url.scheme == "saro", url.host == "entry" else { return .systemAction }
        let id = url.lastPathComponent
        guard model.entry(id) != nil else { return .handled }
        r.flightSource = frame
        model.insight = .spine
        model.openEntryID = id
        return .handled
    }

    private func attributed(_ text: String, quotes: [Candidate], firm: Bool) -> AttributedString {
        var out = AttributedString()
        for seg in Letter.segments(Letter.typeset(text), quotes: quotes) {
            var part = AttributedString(seg.text)
            if let q = seg.quote {
                part.link = URL(string: "saro://entry/\(q.entryId)")
                part.foregroundColor = Tok.voice
                part.underlineStyle = Text.LineStyle(pattern: .solid, color: Tok.voice.opacity(firm ? 1 : 0.35))
            }
            out += part
        }
        return out
    }

    // MARK: Write back

    /// The letter's question is still the day's, so an answer can go to it; the same answer as the panel's.
    private func canWriteBack(_ letter: Letter) -> Bool {
        letter.question != nil && letter.question == model.dayReading?.payload.reading.question
    }

    @ViewBuilder private func writeBack(_ letter: Letter) -> some View {
        if writing {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Write back…").font(Typo.ui(14)).foregroundStyle(Tok.ink3).padding(.horizontal, 5).padding(.top, 1).allowsHitTesting(false)
                    }
                    TextEditor(text: $draft)
                        .font(Typo.ui(14)).foregroundStyle(Tok.ink)
                        .scrollContentBackground(.hidden)
                        .focused($focus, equals: .draft)
                        .writingToolsFollowPref()
                        .disabled(saving)
                        .accessibilityLabel("Write back")
                }
                .frame(height: 72)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Tok.surface.opacity(0.8), in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Tok.line))
                HStack(spacing: 8) {
                    Text("⌘↵").font(Typo.mono(11)).foregroundStyle(Tok.ink3).accessibilityHidden(true)
                    Spacer()
                    Button("Cancel") { writing = false }.keyboardShortcut(.cancelAction).buttonStyle(Pill(primary: false)).disabled(saving)
                    Button(saving ? "Saving…" : "Send") { send() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(Pill(primary: true))
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
            .padding(.top, 16)
        } else if let answer = r.answer, canWriteBack(letter) {
            VStack(alignment: .leading, spacing: 4) {
                Text("You wrote back").font(Typo.ui(10.5, .semibold)).tracking(1.3).textCase(.uppercase).foregroundStyle(Tok.ink3)
                Text(answer).font(Typo.serif(17)).lineSpacing(5).foregroundStyle(Tok.ink).fixedSize(horizontal: false, vertical: true)
                Button("Edit") { startWriting() }.buttonStyle(.plain).font(Typo.ui(13)).foregroundStyle(Tok.ink2).frame(minHeight: 32)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tok.surface.opacity(0.7), in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Tok.line.opacity(0.8)))
            .padding(.top, 16)
        }
    }

    private func startWriting() {
        draft = r.answer ?? ""
        writing = true
        focus = .draft
    }

    private func send() {
        guard !saving else { return }
        saving = true
        Task {
            if await r.saveAnswer(draft) { writing = false }
            saving = false
        }
    }

    // MARK: Footer

    private func footer(_ letter: Letter) -> some View {
        let rewriting = r.busy.contains(.letter)
        return HStack(spacing: 8) {
            if canWriteBack(letter), r.answer == nil, !writing {
                Button { startWriting() } label: { Label("Write back", systemImage: "pencil.line") }.buttonStyle(Pill(primary: false))
            }
            Button(rewriting ? "Writing a new one…" : "Write a new letter") { Task { await r.rewriteLetter() } }
                .buttonStyle(.plain)
                .font(Typo.ui(13)).foregroundStyle(Tok.ink3).underline(true, color: Tok.ink3.opacity(0.5))
                .padding(.horizontal, 8).frame(minHeight: 36)
                .disabled(rewriting)
            Spacer(minLength: 8)
            if r.kept != nil {
                Label { Text("Kept with this day") } icon: { Image(systemName: "checkmark").foregroundStyle(Tok.sage) }
                    .font(Typo.ui(13)).foregroundStyle(Tok.ink2).padding(.horizontal, 8)
            } else {
                Button {
                    Task {
                        await r.keep(letter)
                        model.insight = .spine
                    }
                } label: { Label("Keep", systemImage: "bookmark") }
                .buttonStyle(Pill(primary: true))
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Tok.line.opacity(0.7)).frame(height: 1) }
    }
}

extension View {
    /// The letter's lines rise 6 pt over 350 ms, 50 ms apart, from `base` after the surface (EveningLetter.tsx); nil shows
    /// them at once (from the keyboard). Reduce Motion keeps the fade only.
    func rise(_ index: Int, _ shown: Bool, base: Double? = 0) -> some View {
        modifier(Rise(index: index, shown: shown, base: base))
    }
}

private struct Rise: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    let shown: Bool
    let base: Double?

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion || base == nil ? 0 : 6)
            .animation(base.map { Motion.easeOut(0.35).delay($0 + Double(index) * 0.05) }, value: shown)
    }
}
