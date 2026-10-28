import AppKit
import SaroKit
import SwiftUI
import UserNotifications

/// 03 Rhythm (RhythmSection.tsx): the daily reminder as a ritual, previewed as it arrives, the evening letter's time,
/// and a reminder that follows when you usually reflect. Every change reschedules (Reminders.scheduleRitual).
struct RhythmSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var save = Autosave()
    @State private var status = UNAuthorizationStatus.notDetermined
    @State private var times: [Rhythm.EntryTime]?
    #if DOGFOOD
    /// Snapshots only: open on the demo's steady fortnight.
    static var sampleFirst = false
    @State private var sample = Self.sampleFirst
    #else
    @State private var sample = false
    #endif
    @State private var moved: Moved?
    @AccessibilityFocusState private var focus: Focus?

    struct Moved: Equatable {
        var wasOn: Bool
        var wasMinutes: Int
        var to: Int
    }

    enum Focus { case undo, suggest, usual }

    private var prefs: PrefsStore { PrefsStore.shared }

    var body: some View {
        SettingsCard(label: "Rhythm", title: "When Saro reaches you", autosave: save) {
            SettingsRow("Daily reminder", caption: reminderNote) {
                HStack(spacing: 14) {
                    TimePill(label: "Reminder time", minutes: Binding(get: { prefs.ritualMinutes }, set: { setReminder(minutes: $0) }))
                    Toggle("Daily reminder", isOn: Binding(get: { prefs.reminderOn }, set: { setReminder(on: $0) }))
                        .toggleStyle(.sage).labelsHidden()
                }
            }
            if status == .denied {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")!)
                }
                .buttonStyle(.settingsQuiet)
                .padding(.bottom, 8)
            }
            Weekdays(mask: Binding(get: { prefs.ritualWeekdays }, set: { mask in
                prefs.ritualWeekdays = mask
                reschedule()
            }))
            .padding(.bottom, 14)
            HStack(alignment: .center, spacing: 16) {
                NotificationPreview(time: Rhythm.formatClock(prefs.ritualMinutes))
                    .opacity(prefs.reminderOn ? 1 : 0.6)
                    .animation(Motion.fade, value: prefs.reminderOn)
                Button("Send a test") {
                    Task {
                        if await Reminders.shared.request() { await Reminders.shared.sendTest() }
                        status = await Reminders.shared.status()
                    }
                }
                .buttonStyle(.settingsQuiet)
                .disabled(status == .denied)
            }
            .padding(.bottom, 16)

            RowRule()
            SettingsRow("Evening letter", caption: "Your letter arrives after \(Rhythm.formatClock(prefs.letterMinutes)) on days you wrote.") {
                TimePill(label: "Evening letter time", minutes: Binding(get: { prefs.letterMinutes }, set: { m in
                    prefs.letterMinutes = m
                    save.run { await Reminders.shared.moveTodaysLetter(to: m) }
                }))
            }
            if prefs.letterMinutes < 17 * 60 {
                Label("At \(Rhythm.formatClock(prefs.letterMinutes)) the letter opens before most of the day has happened.", systemImage: "exclamationmark.triangle")
                    .font(Typo.ui(12)).foregroundStyle(Tok.warning)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
            RowRule()
            SettingsRow("Quick capture", caption: "From anywhere on this Mac, or from Saro in the menu bar.") {
                Text("⌃⌘J").font(Typo.mono(12)).foregroundStyle(Tok.ink2)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tok.border))
            }
            RowRule()
            usual.padding(.top, 18)
        }
        .animation(Motion.fade, value: prefs.letterMinutes < 17 * 60)
        .task {
            status = await Reminders.shared.status()
            times = (try? await model.ledger.entryTimes()) ?? []
        }
    }

    private var reminderNote: String {
        switch status {
        case .denied: "Notifications are off for Saro."
        default: "Arrives even when Saro is closed, and never shows what you wrote."
        }
    }

    // MARK: When you usually reflect

    private var stats: Rhythm.Stats? { Rhythm.stats(sample ? Rhythm.sampleFortnight() : times ?? []) }

    @ViewBuilder
    private var usual: some View {
        let stats = stats
        let usual = Rhythm.usualTime(stats)
        let suggestion = times == nil ? nil : Rhythm.suggestReminder(stats, reminderOn: prefs.reminderOn, reminderMinutes: prefs.ritualMinutes,
                                                                     dismissedAt: prefs.rhythmDismissedAt)
        let near = usual.map { prefs.reminderOn && Rhythm.circularGap($0 - 15, prefs.ritualMinutes) < Rhythm.minGap } ?? false
        let quiet: String? = times == nil ? nil
            : stats == nil || stats!.entries < Rhythm.minEntries || stats!.days < Rhythm.minDays
            ? "After \(Rhythm.minEntries) entries on \(Rhythm.minDays) different days, Saro can suggest a reminder time."
            : stats!.r < Rhythm.minR ? "Your times vary, so there’s no one time to suggest yet." : nil

        VStack(alignment: .leading, spacing: 6) {
            Text(sample ? "A sample fortnight · demo" : "Your last two weeks").monoCaps(11, tracking: 0.12).foregroundStyle(Tok.ink3)
            if let usual {
                Text("You usually reflect around \(Rhythm.formatClock(usual)).").font(Typo.serif(20)).foregroundStyle(Tok.ink)
                    .accessibilityFocused($focus, equals: .usual)
            }
            if let quiet { Text(quiet).font(Typo.ui(14)).foregroundStyle(Tok.ink2).fixedSize(horizontal: false, vertical: true) }
            RhythmStrip(stats: stats).padding(.top, 10)
            ZStack(alignment: .leading) {
                if let moved {
                    HStack(spacing: 4) {
                        Text("Reminder set for \(Rhythm.formatClock(moved.to)) ·")
                        Button("Undo") { undo(moved) }.buttonStyle(.settingsLink).accessibilityFocused($focus, equals: .undo)
                    }
                    .font(Typo.ui(14)).foregroundStyle(Tok.ink2)
                    .transition(.opacity)
                    .task(id: moved) {
                        try? await Task.sleep(for: .seconds(8))
                        guard self.moved == moved else { return }
                        if focus == .undo { focus = .usual }
                        self.moved = nil
                    }
                } else if let suggestion {
                    HStack(spacing: 8) {
                        Button(prefs.reminderOn ? "Move reminder to \(Rhythm.formatClock(suggestion.target))"
                            : "Turn on a reminder at \(Rhythm.formatClock(suggestion.target))") { accept(suggestion) }
                            .buttonStyle(.settingsPrimary)
                            .accessibilityFocused($focus, equals: .suggest)
                        Button("Not now") {
                            prefs.rhythmDismissedAt = .now
                            save.saved()
                            focus = .usual
                        }
                        .buttonStyle(.settingsQuiet)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.top, moved != nil || suggestion != nil ? 10 : 0)
            .animation(Motion.pick(Motion.small, reduce: reduceMotion), value: moved)
            if near, moved == nil {
                Text("Your reminder already sits just before it.").font(Typo.ui(12)).foregroundStyle(Tok.ink3)
            }
            if model.isDemo, quiet != nil || sample {
                Button(sample ? "Back to your entries" : "See it with a steady fortnight") { sample.toggle() }
                    .buttonStyle(.settingsLink).font(Typo.ui(13)).padding(.top, 8)
            }
        }
    }

    // MARK: Writes

    private func setReminder(on: Bool? = nil, minutes: Int? = nil) {
        let wasOn = prefs.reminderOn
        if let minutes {
            prefs.ritualMinutes = minutes
            prefs.ritualSource = .user
        }
        if let on { prefs.reminderOn = on }
        // The click that turns it on is the one that asks macOS.
        if prefs.reminderOn, !wasOn {
            Task {
                _ = await Reminders.shared.request()
                status = await Reminders.shared.status()
            }
        }
        reschedule()
    }

    private func reschedule() {
        save.run { await Reminders.shared.scheduleRitual() }
    }

    private func accept(_ s: Rhythm.Suggestion) {
        moved = Moved(wasOn: prefs.reminderOn, wasMinutes: prefs.ritualMinutes, to: s.target)
        setReminder(on: true, minutes: s.target)
        focus = .undo
    }

    private func undo(_ m: Moved) {
        prefs.reminderOn = m.wasOn
        prefs.ritualMinutes = m.wasMinutes
        reschedule()
        moved = nil
        focus = .suggest
    }
}

/// A mono time pill in Saro's own clock ("9:30 pm"), as the web's `step=300` input: ↑ and ↓ or the stepper move it
/// 5 minutes onto the 5-minute grid, ⇧↑ and ⇧↓ an hour, wrapping past midnight.
struct TimePill: View {
    let label: String
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(Rhythm.formatClock(minutes)).font(Typo.mono(13)).monospacedDigit().foregroundStyle(Tok.ink)
                .frame(minWidth: 62)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Tok.surfaceAlt, in: .capsule)
                .overlay(Capsule().strokeBorder(Tok.border))
                .contentShape(.focusEffect, .capsule)
                .focusable()
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    step(press.key == .upArrow ? 1 : -1, hour: press.modifiers.contains(.shift))
                    return .handled
                }
            Stepper(label, onIncrement: { step(1) }, onDecrement: { step(-1) }).labelsHidden()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Rhythm.formatClock(minutes))
        .accessibilityAdjustableAction { step($0 == .increment ? 1 : -1) }
    }

    private func step(_ by: Int, hour: Bool = false) { minutes = Rhythm.step(minutes, by: by, hour: hour) }
}

/// M T W T F S S, Monday first; the mask keeps Sunday as bit 0.
struct Weekdays: View {
    @Binding var mask: Int
    private static let days: [(bit: Int, letter: String, name: String)] = [
        (1, "M", "Monday"), (2, "T", "Tuesday"), (3, "W", "Wednesday"), (4, "T", "Thursday"), (5, "F", "Friday"), (6, "S", "Saturday"), (0, "S", "Sunday"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.days, id: \.bit) { d in
                let on = mask & (1 << d.bit) != 0
                Button { mask ^= 1 << d.bit } label: {
                    Text(d.letter).font(Typo.mono(11.5, on ? .medium : .regular))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(on ? Tok.onPrimary : Tok.ink2)
                        .background(on ? Tok.sage : Tok.surfaceAlt, in: .circle)
                        .overlay(Circle().strokeBorder(on ? Tok.sage : Tok.border))
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d.name)
                .accessibilityValue(on ? "On" : "Off")
                .accessibilityAddTraits(.isToggle)
            }
            if mask == 0 { Text("No days, so no reminder.").font(Typo.ui(12)).foregroundStyle(Tok.ink3).padding(.leading, 6) }
        }
        .animation(Motion.fade, value: mask)
    }
}

/// One day, midnight to midnight: a dot per entry, and a voice-coloured tick at the time you usually reflect.
struct RhythmStrip: View {
    let stats: Rhythm.Stats?
    private static let marks: [(String, Int)] = [("12a", 0), ("6a", 360), ("12p", 720), ("6p", 1080), ("12a", 1440)]

    var body: some View {
        let usual = Rhythm.usualTime(stats)
        VStack(spacing: 6) {
            Canvas { ctx, size in
                let mid = size.height / 2
                ctx.fill(Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1)), with: .color(Tok.line))
                for p in stats?.points ?? [] {
                    let x = size.width * CGFloat(p.minutes) / 1440
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: mid - 3, width: 6, height: 6)), with: .color(Tok.ink3))
                }
                if let usual {
                    let x = size.width * CGFloat(usual) / 1440
                    ctx.fill(Path(roundedRect: CGRect(x: x - 1, y: 0, width: 2, height: size.height), cornerRadius: 1), with: .color(Tok.voice))
                }
            }
            .frame(height: 16)
            GeometryReader { geo in
                ForEach(Array(Self.marks.enumerated()), id: \.offset) { i, m in
                    let last = i == Self.marks.count - 1
                    Text(m.0).font(Typo.mono(10)).foregroundStyle(Tok.ink3)
                        .frame(width: 40, alignment: i == 0 ? .leading : last ? .trailing : .center)
                        .offset(x: geo.size.width * CGFloat(m.1) / 1440 - (i == 0 ? 0 : last ? 40 : 20))
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement()
        .accessibilityLabel(Rhythm.describe(stats))
    }
}

extension Reminders {
    /// A new letter time moves today's letter too, while it's still on its way.
    func moveTodaysLetter(to minutes: Int) async {
        let day = LocalDay.today()
        guard await UNUserNotificationCenter.current().pendingNotificationRequests().contains(where: { $0.identifier == "saro-letter-\(day)" }),
              let at = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) else { return }
        await scheduleLetter(day: day, at: at)
    }
}
