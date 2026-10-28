import AppKit
import Observation
import SaroKit
import SwiftUI
import UserNotifications

/// The reflection side of the day on screen (FR-REF-*): the person's mood, answer, commitments and letter record, the
/// first week's notes, and the actions that change them. Held as `model.reflection`; `load(day:model:)` runs after every
/// day load. Every model call goes through the app's one queue (§11.7).
@Observable @MainActor
final class ReflectionModel {
    /// How the insight surface moves next (the frequency rule): a spring from the pointer, at once from the keyboard, or
    /// the evening arrival's ease.
    enum How { case morph, instant, arrive }
    enum Busy: Hashable { case insights, narrative, question, letter }

    private(set) var day: String?
    private(set) var state = DayState(day: "")
    private(set) var commitments: [Commitment] = []
    /// Yesterday's open commitments still to ask about, on today only (D9).
    private(set) var carryOvers: [Commitment] = []
    private(set) var kept: Letter?
    /// The answer to the day's question, while it is still the day's question.
    private(set) var answer: String?
    private(set) var note: WeekNote?
    var how: How = .morph
    /// Set when a keyboard close should hand focus back to the spine.
    var refocusSpine = false
    var busy: Set<Busy> = []
    /// The sage check that says a new reading has landed, for 1.2 s.
    private(set) var updated = false
    var adjustingMood = false
    /// ⌘K's 'Answer today's question' opens the question's editor.
    var answerRequested = false
    /// Where a quote's flight into its card starts, in the day view's coordinates.
    var flightSource: CGRect?
    /// Re-read each minute, so the letter becomes available at its time.
    private(set) var minute = Date.now

    @ObservationIgnored private(set) weak var model: AppModel?
    @ObservationIgnored private var loads = 0
    @ObservationIgnored private var lastRun: (day: String, run: String?)?
    @ObservationIgnored private var arrivedFor: String?
    @ObservationIgnored private var pendingArrive = false
    @ObservationIgnored private var scheduled: String?
    @ObservationIgnored private var regated: Set<String> = []
    @ObservationIgnored private var fullAt = Date.distantPast
    @ObservationIgnored private var delivered: Set<String> = []

    init() {
        Task { [weak self] in
            while !Task.isCancelled {
                let next = Calendar.current.nextDate(after: .now, matching: DateComponents(second: 0), matchingPolicy: .nextTime) ?? .now
                try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
                guard let self else { return }
                minute = .now
                arriveIfDue()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.arriveIfDue() }
        }
    }

    // MARK: Letter state

    var isToday: Bool { day == LocalDay.today() }

    /// Today's letter after the letter time (or once opened or kept); a past day's always (prefs.ts letterDue).
    var letterAvailable: Bool {
        _ = minute
        return !isToday || PrefsStore.shared.letterDue(at: .now) || state.letterOpenedAt != nil || kept != nil
    }

    var letterUnread: Bool { letterAvailable && state.letterOpenedAt == nil && kept == nil }

    /// The day's mood: the person's own when they set one, else the reading's.
    func mood(_ reading: DayReading) -> Mood { state.lockedMood ?? reading.mood }

    // MARK: Loading

    /// Reads the day's own records, then the first week's note, the letter's notification and the evening arrival.
    func load(day: String, model: AppModel) {
        self.model = model
        if self.day != day { adjustingMood = false }
        loads += 1
        let ticket = loads
        Task {
            let ledger = model.ledger
            let today = LocalDay.today()
            let state = (try? await ledger.dayState(day)) ?? DayState(day: day)
            let commitments = (try? await ledger.commitments(day: day)) ?? []
            let open = day == today ? (try? await ledger.openCommitments(from: LocalDay.adding(-1, to: day))) ?? [] : []
            let kept = (try? await ledger.keptLetter(day: day)).flatMap { try? JSONDecoder().decode(Letter.self, from: Data($0.payload.utf8)) }
            let turns = (try? await ledger.turns(day: day, kind: .dailyQuestion)) ?? []
            let note = await firstWeekNote(day, model: model)
            guard ticket == loads, model.day == day else { return }
            self.day = day
            self.state = state
            self.commitments = commitments
            carryOvers = Commitment.pending(open, today: commitments)
            self.kept = kept
            answer = turns.last { $0.answer != nil && $0.question == model.dayReading?.payload.reading.question }?.answer
            self.note = note
            flashIfNewReading(model)
            if let p = model.profile {
                await model.ai.setPersonalization(name: p.address, tone: p.tone, focus: p.focusAreas, known: [p.name, p.called].compactMap { $0 })
            }
            await scheduleNotice(model)
            regateIfWaiting(day, turns: turns, model: model)
            arriveIfDue()
        }
    }

    private func flashIfNewReading(_ model: AppModel) {
        let run = model.dayReading?.runId
        defer { lastRun = (model.day, run) }
        guard let last = lastRun, last.day == model.day, last.run != nil, run != nil, last.run != run else { return }
        updated = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            updated = false
        }
    }

    /// An answer or note checked while the model couldn't run is checked again once it can, once a session per day.
    private func regateIfWaiting(_ day: String, turns: [ReflectionTurn], model: AppModel) {
        let waiting = (turns.compactMap(\.answerVerdict) + [state.moodNoteVerdict].compactMap { $0 }).contains { $0.hasPrefix("unavailable") }
        guard waiting, model.ai.status == .available, regated.insert(day).inserted else { return }
        Task {
            await model.exclusive { await model.pipeline.regateReflections(day) }
            await model.reload()
        }
    }

    // MARK: Insight surface

    /// Called as `model.insight` changes: how it moves, the letter's read mark, and where focus goes.
    func moved(to insight: AppModel.Insight) {
        how = pendingArrive ? .arrive : NSApp.currentEvent?.type == .keyDown ? .instant : .morph
        pendingArrive = false
        refocusSpine = insight == .spine && how == .instant
        guard insight == .letter, let model, let day, day == model.day, model.dayStatus == .ready, model.dayReading != nil,
              state.letterOpenedAt == nil else { return }
        state.letterOpenedAt = .now
        Reminders.shared.cancelLetter(day: day)
        Task { try? await model.ledger.markLetterOpened(day: day) }
    }

    /// The evening arrival (InsightBar's arrive): once a day, after the letter time, on today with a current reading that
    /// wasn't opened or kept, the window key and the canvas idle. Otherwise it waits for the next activation or minute.
    func arriveIfDue() {
        guard let model, let day, day == model.day, isToday, arrivedFor != day, PrefsStore.shared.letterArrives,
              PrefsStore.shared.letterDue(at: .now), model.dayStatus == .ready, model.dayReading != nil,
              state.letterOpenedAt == nil, kept == nil, NSApp.isActive, NSApp.keyWindow != nil, model.pane == .day,
              model.insight == .spine, model.openEntryID == nil, model.openStackID == nil, model.openVoiceID == nil,
              model.recorderKind == nil, !model.searchOpen, !model.replay.active, model.selection.isEmpty else { return }
        arrivedFor = day
        pendingArrive = true
        model.insight = .letter
    }

    /// Today's letter notification (FR-REF-09): waiting at the letter time once a ready reading exists, and gone once the
    /// letter is read or the day is held or awaiting a check (SR-13, SR-14). Content-free.
    private func scheduleNotice(_ model: AppModel) async {
        let today = LocalDay.today()
        let onScreen = model.day == today
        let status = onScreen ? model.dayStatus : await model.pipeline.dayStatus(today)
        let hasLetter = onScreen ? model.dayReading != nil : await model.pipeline.latestDayReading(today) != nil
        let opened = onScreen ? state.letterOpenedAt != nil || kept != nil : (try? await model.ledger.dayState(today).letterOpenedAt) != nil
        let minutes = PrefsStore.shared.letterMinutes
        guard let at = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) else { return }
        switch Letter.notice(status: status, hasLetter: hasLetter, opened: opened, letterAt: at) {
        case .schedule(let date):
            let key = "\(today)|\(date)"
            guard scheduled != key else { return }
            scheduled = key
            await Reminders.shared.scheduleLetter(day: today, at: date)
        case .cancel:
            scheduled = nil
            Reminders.shared.cancelLetter(day: today)
        case .none:
            break
        }
    }

    // MARK: First week

    /// The first week's note for `day`: one stored on that day ("A first pattern", "Your first weekly letter"), else, on
    /// today, the one due now (stored once, with a content-free notification), else the day 4–5 check-in.
    private func firstWeekNote(_ day: String, model: AppModel) async -> WeekNote? {
        let ledger = model.ledger
        for kind in ["pattern", "week_letter"] {
            guard let s = try? await ledger.latestSnapshot(kind: kind), let n = try? JSONDecoder().decode(WeekNote.self, from: Data(s.payload.utf8))
            else { continue }
            switch await model.pipeline.weekNoteStatus(n) {
            case .held:
                // Drawn from a day since held, or from a moment that's gone: dropped (SR-13, SR-15).
                try? await ledger.deleteSnapshot(id: s.id)
            case .ready:
                if s.fromDay == day { return n }
            default:
                // One of its days is waiting on a check or a read: it shows again once that day can.
                if s.fromDay == day { return nil }
            }
        }
        guard day == LocalDay.today(), let start = PrefsStore.shared.weekStartedOn,
              let weekDay = WeekMilestones.weekDay(startedOn: start, now: .now) else { return nil }
        let entries = await model.pipeline.weekEntries(from: start)
        if let due = WeekMilestones.dueNote(startedOn: start, entries: entries, now: .now, name: model.profile?.address) {
            let kind = due.kind == .letter ? "week_letter" : "pattern"
            // Overlapping loads (a reload storm while entries process) deliver it once.
            if (try? await ledger.latestSnapshot(kind: kind)) == nil, delivered.insert(kind).inserted, let json = try? JSONEncoder().encode(due) {
                try? await ledger.insertSnapshot(InsightSnapshot(kind: kind, day: day, aiRunId: nil, generator: "heuristic", inputHash: nil,
                                                                 payload: String(decoding: json, as: UTF8.self)))
                await notify(due.kind == .letter ? "Your first weekly letter is here." : "Saro noticed a first pattern.", day: day)
                return due
            }
        }
        guard (4...5).contains(weekDay) else { return nil }
        return WeekMilestones.checkIn(goal: model.starter?.picks.first { $0.kind == .goal }?.text)
    }

    /// A content-free notice that opens the day; only where notifications are already allowed.
    private func notify(_ title: String, day: String) async {
        let center = UNUserNotificationCenter.current()
        guard !PrefsStore.isDemo, [.authorized, .provisional].contains(await center.notificationSettings().authorizationStatus) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = Reminders.letterBody
        content.userInfo = ["url": DeepLink.day(day).url.absoluteString]
        try? await center.add(UNNotificationRequest(identifier: "saro-week-\(day)", content: content,
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    // MARK: Refresh

    /// Refresh insights: a new reading of the day, sampled.
    func refreshInsights() async {
        await refresh(.insights, avoid: nil, done: "Insights refreshed", failed: "Couldn’t refresh insights")
    }

    /// Refresh narrative: a new take that avoids the title it had.
    func refreshNarrative() async {
        await refresh(.narrative, avoid: model?.dayReading?.payload.narrative?.title, done: "Narrative refreshed", failed: "Couldn’t refresh narrative")
    }

    /// Write a new letter: a new take on the day, which also replaces a kept letter.
    func rewriteLetter() async {
        guard let model, let day else { return }
        guard await refresh(.letter, avoid: model.dayReading?.payload.narrative?.title, done: nil, failed: "Couldn’t write a new letter") else { return }
        try? await model.ledger.clearKept(day: day)
        kept = nil
    }

    @discardableResult
    private func refresh(_ what: Busy, avoid: String?, done: String?, failed: String) async -> Bool {
        guard let model, !busy.contains(what) else { return false }
        busy.insert(what)
        defer { busy.remove(what) }
        let payload = await model.refreshDayReading(force: true, avoid: avoid)
        // A refresh that came back held shows the SafetyCard; there is nothing to toast.
        guard model.dayStatus != .held else { return false }
        if let text = payload == nil ? failed : done { model.show(Toast(text, style: payload == nil ? .error : .info)) }
        return payload != nil
    }

    /// Refresh question: the answered pair is archived and a question not asked in the last week takes its place.
    func refreshQuestion() async {
        guard let model, let day, !busy.contains(.question) else { return }
        busy.insert(.question)
        defer { busy.remove(.question) }
        let payload = await model.exclusive { await model.pipeline.refreshQuestion(day) }
        if payload != nil { answer = nil }
        await model.reload()
        model.show(payload == nil ? Toast("Couldn’t refresh question", style: .error) : Toast("New question ready"))
    }

    // MARK: Answer and mood

    /// Saves the person's answer to the day's question, gated first (it is their words, outside an entry). False keeps the
    /// draft: no question to answer, or the gate couldn't say yet.
    func saveAnswer(_ text: String) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let model, let day, !text.isEmpty, let question = model.dayReading?.payload.reading.question, !question.isEmpty else { return false }
        guard let verdict = await model.exclusive({ await model.pipeline.check(text) }) else {
            model.show(Toast("Couldn’t save your answer. Your words are still in the box.", style: .error))
            return false
        }
        do {
            let open = try await model.ledger.turns(day: day, kind: .dailyQuestion).last { $0.question == question }
            let turn = open ?? ReflectionTurn(kind: .dailyQuestion, question: question, generator: model.dayReading?.generator ?? "heuristic",
                                              localDay: day, aiRunId: model.dayReading?.runId)
            if open == nil { try await model.ledger.insertTurn(turn) }
            try await model.ledger.setTurnAnswer(id: turn.id, answer: text, verdict: verdict.verdict)
        } catch {
            model.show(Toast("Couldn’t save your answer. Your words are still in the box.", style: .error))
            return false
        }
        answer = text
        // A held answer holds the day; one the gate couldn't check holds its reading (SR-13, SR-14).
        if verdict.verdict != "clear" { await model.reload() }
        return true
    }

    /// Adjust emotion: the person's own mood for the day, locked against re-reads, with a gated note.
    func adjustMood(_ mood: Mood, note: String) async -> Bool {
        guard let model, let day else { return false }
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var verdict: String?
        if !note.isEmpty {
            guard let r = await model.exclusive({ await model.pipeline.check(note) }) else {
                model.show(Toast("Couldn’t save that change. Try again in a moment.", style: .error))
                return false
            }
            verdict = r.verdict
        }
        do {
            try await model.ledger.setUserMood(day: day, label: mood, note: note.isEmpty ? nil : note, verdict: verdict)
        } catch {
            model.show(Toast("Couldn’t save that change. Try again in a moment.", style: .error))
            return false
        }
        state.moodUser = mood
        state.moodLocked = true
        state.moodNote = note.isEmpty ? nil : note
        state.moodNoteVerdict = verdict
        await model.reload()
        return true
    }

    // MARK: Letter

    func keep(_ letter: Letter) async {
        guard let model, let day, let json = try? JSONEncoder().encode(letter) else { return }
        let snapshot = InsightSnapshot(kind: "letter", day: day, aiRunId: model.dayReading?.runId, generator: model.dayReading?.generator ?? "heuristic",
                                       inputHash: nil, payload: String(decoding: json, as: UTF8.self))
        do {
            try await model.ledger.keepLetter(day: day, snapshot: snapshot)
            kept = letter
            if state.letterOpenedAt == nil { state.letterOpenedAt = .now }
            model.show(Toast("Kept with this day. You’ll find it here when you come back to it."))
        } catch {
            model.show(Toast("Couldn’t keep the letter. Try again in a moment.", style: .error))
        }
    }

    // MARK: Commitments

    func addCommitment(_ text: String) async {
        guard let model, let day else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard commitments.count < Commitment.maxCount else { return listFull() }
        await change { try await model.ledger.addCommitment(text, day: day) }
    }

    func toggle(_ c: Commitment) async {
        guard let model else { return }
        await change { try await model.ledger.setDone(c.id, !c.done) }
    }

    /// ⌘Z puts the old words back.
    func edit(_ c: Commitment, to text: String, undo: UndoManager?) async {
        guard let model else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != c.text else { return }
        await change { try await model.ledger.edit(c.id, text: text) }
        var now = c
        now.text = text
        undo?.registerUndo(withTarget: self) { me in _ = MainActor.assumeIsolated { Task { await me.edit(now, to: c.text, undo: undo) } } }
        undo?.setActionName("Edit Commitment")
    }

    /// ⌘Z brings it back.
    func delete(_ c: Commitment, undo: UndoManager?) async {
        guard let model else { return }
        await change { try await model.ledger.delete(c.id) }
        undo?.registerUndo(withTarget: self) { me in _ = MainActor.assumeIsolated { Task { await me.change { try await model.ledger.restoreCommitment(c.id) } } } }
        undo?.setActionName("Delete Commitment")
    }

    func carry(_ ids: [String]) async {
        guard let model, let day else { return }
        let room = Commitment.maxCount - commitments.count
        guard room > 0 else { return listFull() }
        await change { try await model.ledger.carry(Array(ids.prefix(room)), to: day) }
        if ids.count > room { listFull() }
    }

    /// Let it go: yesterday's stays unfinished there. Letting several go at once can be undone for 5 s.
    func letGo(_ ids: [String]) async {
        guard let model, let day else { return }
        await change { try await model.ledger.letGo(ids, day: day) }
        guard ids.count > 1 else { return }
        model.show(Toast("Let go of \(ids.count) from yesterday. They stay on yesterday, unfinished.", undo: { [weak self] in
            Task { await self?.change { for id in ids { try await model.ledger.restoreCommitment(id) } } }
        }))
    }

    func copy(_ c: Commitment) { Self.copy(c.text) }

    private func listFull() {
        guard Date.now.timeIntervalSince(fullAt) > 3, let model else { return }
        fullAt = .now
        model.show(Toast("Today’s list is full. A day holds up to \(Commitment.maxCount) commitments."))
    }

    /// One ledger write, then the day's list read back; a failed write says so and changes nothing.
    private func change(_ write: @escaping () async throws -> Void) async {
        guard let model, let day else { return }
        do {
            try await write()
            let list = try await model.ledger.commitments(day: day)
            commitments = list
            if isToday { carryOvers = Commitment.pending(try await model.ledger.openCommitments(from: LocalDay.adding(-1, to: day)), today: list) }
        } catch {
            model.show(Toast("Couldn’t save that commitment. Try again in a moment.", style: .error))
        }
    }

    // MARK: Copy

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
