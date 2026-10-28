import SaroKit
import SwiftUI

/// The date picker above the bar (DatePickerPanel.tsx): a month of days in 7 columns from the Mac's first weekday, each day
/// with entries marked underneath in its mood's colour, the day on screen selected, no days after today and no months
/// after this one, and Go to today. Hovering a day reads it ahead, so picking it only has to slide; a key's pick is instant.
struct DatePickerPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var month = ""
    @State private var cursor = ""
    @State private var moods: [String: Mood] = [:]
    @FocusState private var focused: Bool

    private var today: String { LocalDay.today() }
    private var counts: [String: Int] { Dictionary(model.days.map { ($0.day, $0.count) }, uniquingKeysWith: { a, _ in a }) }

    /// The month's days in their columns, nil for the cells before the 1st.
    private var cells: [String?] {
        let cal = Calendar(identifier: .gregorian)
        guard let first = LocalDay.date(month) else { return [] }
        let lead = (cal.component(.weekday, from: first) - Calendar.current.firstWeekday + 7) % 7
        let n = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        return Array(repeating: nil, count: lead) + (0..<n).map { LocalDay.adding($0, to: month) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(LocalDay.date(month)?.formatted(.dateTime.month(.wide).year()) ?? "").font(Typo.ui(14, .medium)).foregroundStyle(Tok.ink)
                Spacer()
                step("chevron.left", "Previous month", -1)
                let last = month >= String(today.prefix(7)) + "-01"
                step("chevron.right", "Next month", 1).disabled(last).opacity(last ? 0.4 : 1)
            }
            .padding(.leading, 4)
            let columns = Array(repeating: GridItem(.fixed(36), spacing: 2), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<7, id: \.self) { Text(weekdays[$0]).font(Typo.mono(10)).foregroundStyle(Tok.ink3).frame(height: 20).accessibilityHidden(true) }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { cell(day) } else { Color.clear.frame(width: 36, height: 36) }
                }
            }
            Button { pick(today) } label: {
                Text("Go to today").font(Typo.ui(13, .medium)).foregroundStyle(Tok.sageDark)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Color.white.opacity(0.5), in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tok.sageDark.opacity(0.2)))
                    .contentShape(.rect(cornerRadius: 12))
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .onHover { if $0 { model.arm(today) } }
        }
        .padding(16)
        .fixedSize()
        .background(Tok.paper, in: .rect(cornerRadius: Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Color.white.opacity(0.2)))
        .elevation(.float)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return]) { press in
            if press.key == .return { pick(cursor); return .handled }
            let by = [KeyEquivalent.leftArrow: -1, .rightArrow: 1, .upArrow: -7, .downArrow: 7][press.key] ?? 0
            let next = LocalDay.adding(by, to: cursor)
            guard next <= today else { return .handled }
            cursor = next
            month = String(next.prefix(7)) + "-01"
            return .handled
        }
        .onExitCommand { model.datePickerOpen = false }
        .onAppear {
            cursor = model.day
            month = String(model.day.prefix(7)) + "-01"
            focused = true
        }
        .task(id: month) { await loadMoods() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Date picker")
    }

    private var weekdays: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7] }
    }

    private func step(_ symbol: String, _ label: String, _ by: Int) -> some View {
        Button {
            guard let d = LocalDay.date(month), let next = Calendar(identifier: .gregorian).date(byAdding: .month, value: by, to: d) else { return }
            month = String(LocalDay.string(for: next).prefix(7)) + "-01"
        } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(Tok.sageDark).frame(width: 28, height: 28).contentShape(.circle)
        }
        .buttonStyle(PressStyle(hoverFill: true, radius: 14))
        .accessibilityLabel(label)
    }

    private func cell(_ day: String) -> some View {
        let future = day > today, selected = day == model.day, isToday = day == today
        let n = counts[day] ?? 0
        let mark: Color? = n == 0 ? nil : moods[day].map(MoodPalette.color) ?? Tok.ink3
        let d = LocalDay.date(day) ?? .now
        return Button { pick(day) } label: {
            VStack(spacing: 2) {
                Text("\(Calendar(identifier: .gregorian).component(.day, from: d))")
                    .font(Typo.ui(13, isToday || selected ? .semibold : .regular)).monospacedDigit()
                    .foregroundStyle(selected ? Tok.onPrimary : future ? Tok.ink4 : isToday ? Tok.sage : Tok.ink)
                Capsule().fill(mark ?? .clear).frame(width: 10, height: 3)
                    .opacity(selected && mark != nil ? 0.9 : 1)
            }
            .frame(width: 36, height: 36)
            .background(selected ? Tok.sage : day == cursor && focused ? Tok.ink.opacity(0.06) : .clear, in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(PressStyle(hoverFill: !selected && !future, radius: 10))
        .disabled(future)
        .onHover { if $0 && !future { model.arm(day) } }
        .accessibilityLabel([d.formatted(.dateTime.weekday(.wide).month(.wide).day()), isToday ? "today" : nil, n > 0 ? "has entries" : nil,
                             selected ? "selected" : nil].compactMap { $0 }.joined(separator: ", "))
    }

    private func pick(_ day: String) {
        guard day <= today else { return }
        let byKey = Motion.byKey
        model.datePickerOpen = false
        if byKey { model.go(to: day) } else { model.slide(to: day) }
    }

    /// The month's days with entries, each with its reading's mood (none on a held day).
    private func loadMoods() async {
        var out: [String: Mood] = [:]
        for day in cells.compactMap({ $0 }) where (counts[day] ?? 0) > 0 {
            if let m = await model.pipeline.dayMood(day) { out[day] = m }
        }
        moods = out
    }
}
