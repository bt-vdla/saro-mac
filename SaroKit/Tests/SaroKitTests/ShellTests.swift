import Foundation
import Testing
@testable import SaroKit

// Synthetic text only (SR-28).

private func count(_ l: Ledger, _ table: String, _ whereSQL: String = "1", _ args: [SQLValue] = []) async throws -> Int {
    try await l.run("SELECT COUNT(*) AS n FROM \(table) WHERE \(whereSQL)", args).first?.int("n") ?? -1
}

/// A moment with a file, a transcript, a verdict, a reading, a memory with its retraction, a question asked of it, a
/// commitment made from it and the day reading that quotes it.
private func richMoment(_ l: Ledger, day: String = LocalDay.today()) async throws -> (entry: Entry, file: URL) {
    let asset = MediaAsset(fileName: "\(day)/s/part-1.mov", kind: .video, origin: "recorded", state: "ready")
    let file = l.url(for: asset)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("movie".utf8).write(to: file)
    try await l.insertMedia(asset)
    let e = Entry(kind: .moment, localDay: day, mediaId: asset.id, processingStatus: ProcessingStatus.done)
    try await l.insertEntry(e)
    try await l.setTranscript(mediaId: asset.id, words: [TranscriptWord(text: "Tea", startMs: 0, durMs: 300, confidence: 0.9)], extractorVersion: "x")
    try await l.insertVerdict(SafetyVerdictRow(entryId: e.id, textSha256: sha256("Tea"), safetyVersion: SafetyGate.version, layer: 1,
                                               verdict: "clear", reasonCode: "ok"))
    let run = AIRun(feature: "entry", executor: "heuristic", status: "ok")
    try await l.insertRun(run, inputs: [AIRunInput(entryId: e.id, field: "transcript", text: "Tea")])
    try await l.insertAnnotation(EntryAnnotation(entryId: e.id, aiRunId: run.id, generator: "heuristic"))
    try await l.setLayouts([CardLayout(entryId: e.id, x: 0, y: 0)])
    let obs = UUID().uuidString
    try await l.run("""
        INSERT INTO observation (id, entry_id, source, kind, key, key_sha256, label, quote, local_day, created_at)
        VALUES (?, ?, 'extractor', 'line', 'theme:tea', 'h', 'Tea', 'Tea', ?, '2026-01-01T00:00:00Z')
        """, [.text(obs), .text(e.id), .text(day)])
    try await l.run("INSERT INTO observation_retraction (observation_id, reason, created_at) VALUES (?, 'edited', '2026-01-01T00:00:00Z')", [.text(obs)])
    try await l.run("""
        INSERT INTO reflection_turn (id, kind, entry_id, question, generator, local_day, created_at, updated_at)
        VALUES (?, 'prompt', ?, 'What stayed with you?', 'curated', ?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
        """, [.text(UUID().uuidString), .text(e.id), .text(day)])
    _ = try await l.addCommitment("Make tea for Ravi", day: day, sourceEntryId: e.id)
    try await l.insertSnapshot(InsightSnapshot(kind: "day_reading", day: day, aiRunId: nil, generator: "heuristic", inputHash: nil,
                                               payload: "{\"entryIds\":[\"\(e.id)\"]}"))
    return (e, file)
}

@Suite struct HousekeepingTests {
    @Test func deleteForeverTakesEverythingDerivedAndRespectsForeignKeys() async throws {
        let l = try tempLedger()
        let (e, file) = try await richMoment(l)
        let other = Entry(kind: .reflection, body: "Walked to the lake.")
        try await l.insertEntry(other)
        try await l.trash([e.id])

        #expect(try await l.hardDelete(ids: [e.id]) == 1)
        #expect(try await l.entry(e.id) == nil)
        for table in ["ai_run_input", "entry_annotation", "safety_verdict", "card_layout", "reflection_turn", "observation"] {
            #expect(try await count(l, table, "entry_id=?", [.text(e.id)]) == 0, "\(table)")
        }
        #expect(try await count(l, "observation_retraction") == 0)
        #expect(try await count(l, "insight_snapshot") == 0)
        #expect(try await count(l, "media_asset") == 0)
        #expect(try await count(l, "transcript_word") == 0)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        // The person's commitment stays, unlinked; the other entry is untouched.
        #expect(try await count(l, "commitment", "source_entry_id IS NULL") == 1)
        #expect(try await l.entry(other.id) != nil)
        #expect(try await l.run("PRAGMA foreign_key_check").isEmpty)
    }

    @Test func aSharedFileStaysUntilItsLastEntryGoes() async throws {
        let l = try tempLedger()
        let (e, file) = try await richMoment(l, day: LocalDay.adding(-1, to: LocalDay.today()))
        let copy = try await l.duplicate(id: e.id, toDay: LocalDay.today())
        try await l.trash([copy.id])

        try await l.hardDelete(ids: [e.id])
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try await count(l, "media_asset") == 1)
        // Its source gone, the copy is an original now.
        #expect(try await l.duplicatedFrom(id: copy.id) == nil)

        try await l.hardDelete(ids: [copy.id])
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try await count(l, "media_asset") == 0)
        #expect(try await l.run("PRAGMA foreign_key_check").isEmpty)
    }

    @Test func trashIsPurgedAfterThirtyDays() async throws {
        let l = try tempLedger()
        let old = Entry(kind: .reflection, body: "An old page.")
        let recent = Entry(kind: .reflection, body: "A recent page.")
        let live = Entry(kind: .reflection, body: "A page still on its day.")
        for e in [old, recent, live] { try await l.insertEntry(e) }
        try await l.trash([old.id, recent.id])
        let now = Date.now
        try await l.run("UPDATE entry SET trashed_at=? WHERE id=?", [.text(now.addingTimeInterval(-31 * 86_400).iso), .text(old.id)])
        try await l.run("UPDATE entry SET trashed_at=? WHERE id=?", [.text(now.addingTimeInterval(-29 * 86_400).iso), .text(recent.id)])

        #expect(try await l.purgeTrash(now: now) == 1)
        #expect(try await l.entry(old.id) == nil)
        #expect(try await l.entry(recent.id) != nil)
        #expect(try await l.entry(live.id) != nil)
        // Two days later the recent one goes too.
        #expect(try await l.purgeTrash(now: now.addingTimeInterval(2 * 86_400)) == 1)
        #expect(try await l.trashed().isEmpty)
    }

    @Test func expiryCountsDownInHoursOnTheLastDay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(TrashClock.left(until: now.addingTimeInterval(12 * 86_400 + 600), now: now) == "12 days left")
        #expect(TrashClock.left(until: now.addingTimeInterval(86_400 * 1.4), now: now) == "1 day left")
        #expect(TrashClock.left(until: now.addingTimeInterval(3 * 3600 - 60), now: now) == "3 hours left")
        #expect(TrashClock.left(until: now.addingTimeInterval(60), now: now) == "1 hour left")
        #expect(Ledger.expiry(trashedAt: now) == now.addingTimeInterval(30 * 86_400))
    }

    @Test func oneSnapshotADaySevenKept() async throws {
        let l = try tempLedger()
        try await l.insertEntry(Entry(kind: .reflection, body: "Chai on the balcony."))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for d in 0..<9 { #expect(try await l.dailySnapshot(now: start.addingTimeInterval(Double(d) * 86_400)) != nil) }
        #expect(try await l.dailySnapshot(now: start.addingTimeInterval(8 * 86_400 + 60)) == nil)
        let kept = l.snapshots()
        #expect(kept.count == Ledger.snapshotsKept)
        #expect(kept.first?.day == LocalDay.string(for: start.addingTimeInterval(8 * 86_400)))
        #expect(kept.allSatisfy { $0.bytes > 0 })
        #expect(Ledger.snapshots(root: l.rootURL) == kept)
    }

    @Test func aSnapshotRestoresInPlaceKeepingWhatItReplaced() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "saro-test-\(UUID().uuidString)")
        var l: Ledger? = try Ledger(rootURL: root)
        let kept = Entry(kind: .reflection, body: "Before the snapshot.")
        try await l!.insertEntry(kept)
        let snap = try #require(try await l!.dailySnapshot(now: .now))
        try await l!.insertEntry(Entry(kind: .reflection, body: "After the snapshot."))
        l = nil

        try Ledger.restore(snapshot: snap, root: root)
        let back = try Ledger(rootURL: root)
        #expect(try await back.allEntries().map(\.id) == [kept.id])
        let aside = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Backups").path).filter { $0.hasPrefix("replaced-") }
        #expect(aside.count == 1)
        #expect(Ledger.snapshots(root: root).count == 1)
    }

    @Test func eraseStillLeavesNothing() async throws {
        let l = try tempLedger()
        let (e, _) = try await richMoment(l)
        _ = try await l.duplicate(id: e.id, toDay: e.localDay)
        try await l.dailySnapshot(now: .now)
        try await l.eraseAll()
        let tables = try await l.run("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").compactMap { $0.str("name") }
        for t in tables { #expect(try await count(l, t) == 0, "\(t)") }
        #expect(!FileManager.default.fileExists(atPath: l.backupsURL.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: l.mediaURL.path).isEmpty)
    }
}

@Suite struct DuplicateTests {
    @Test func aCopySharesTheMediaInheritsTheVerdictAndIsBackdated() async throws {
        let l = try tempLedger()
        let (e, _) = try await richMoment(l)
        let yesterday = LocalDay.adding(-1, to: LocalDay.today())
        let copy = try await l.duplicate(id: e.id, toDay: yesterday)
        #expect(copy.localDay == yesterday)
        #expect(copy.backdated)
        #expect(copy.mediaId == e.mediaId)
        #expect(copy.sessionId == nil)
        #expect(copy.capturedAt <= .now)
        #expect(try await l.duplicatedFrom(id: copy.id) == e.id)
        #expect(try await l.verdicts(day: yesterday)[copy.id]?.verdict == "clear")
        // A copy of a copy points at the original, and nothing new reads as an engine count.
        let again = try await l.duplicate(id: copy.id, toDay: yesterday)
        #expect(try await l.duplicatedFrom(id: again.id) == e.id)
        #expect(try await count(l, "active_observation", "entry_id IN (?, ?)", [.text(copy.id), .text(again.id)]) == 0)
    }

    @Test func aHeldCopyHoldsItsNewDayAtOnce() async throws {
        let l = try tempLedger()
        let yesterday = LocalDay.adding(-1, to: LocalDay.today())
        let held = Entry(kind: .reflection, body: "A heavy night.", localDay: yesterday)
        try await l.insertEntry(held)
        try await l.insertVerdict(SafetyVerdictRow(entryId: held.id, textSha256: sha256(held.body!), safetyVersion: SafetyGate.version, layer: 2,
                                                   verdict: "safety_hold", reasonCode: "test"))
        let today = LocalDay.today()
        try await l.insertEntry(Entry(kind: .reflection, body: "Tea with Ravi."))
        try await l.insertSnapshot(InsightSnapshot(kind: "day_reading", day: today, aiRunId: nil, generator: "heuristic", inputHash: nil, payload: "{}"))

        let copy = try await l.duplicate(id: held.id, toDay: today)
        #expect(try await l.verdicts(day: today)[copy.id]?.verdict == "safety_hold")
        #expect(try await count(l, "insight_snapshot", "from_day=?", [.text(today)]) == 0)
    }

    @Test func tomorrowIsRefused() async throws {
        let l = try tempLedger()
        let e = Entry(kind: .reflection, body: "Plans.")
        try await l.insertEntry(e)
        await #expect(throws: DuplicateError.futureDay) { try await l.duplicate(id: e.id, toDay: LocalDay.adding(1, to: LocalDay.today())) }
        await #expect(throws: DuplicateError.missing) { try await l.duplicate(id: "gone", toDay: LocalDay.today()) }
    }

    @Test func todaysCopyIsNeverLaterThanNow() async throws {
        let l = try tempLedger()
        let late = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: .now.addingTimeInterval(-86_400))!
        let e = Entry(kind: .reflection, body: "Late page.", capturedAt: late)
        try await l.insertEntry(e)
        let now = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        let copy = try await l.duplicate(id: e.id, toDay: LocalDay.string(for: now), now: now)
        #expect(abs(copy.capturedAt.timeIntervalSince(now)) < 1)
        let earlier = try await l.duplicate(id: e.id, toDay: LocalDay.adding(-3, to: LocalDay.string(for: now)), now: now)
        #expect(Calendar.current.component(.hour, from: earlier.capturedAt) == 23)
    }

    @Test func summaryIsThePersonsOwn() async throws {
        let l = try tempLedger()
        let e = Entry(kind: .voice)
        try await l.insertEntry(e)
        try await l.updateSummary(id: e.id, "About the move.")
        #expect(try await l.summaryUser(id: e.id) == "About the move.")
        try await l.updateSummary(id: e.id, nil)
        #expect(try await l.summaryUser(id: e.id) == nil)
    }
}

@Suite struct ShellRulesTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func sameTitleWithinASecondFolds() {
        let shown = [ToastRules.Shown(title: "Moved to Trash", destructive: false, at: t0, hasAction: true, count: 2)]
        let r = ToastRules.arrive(.init(title: "Moved to Trash", destructive: false, at: t0.addingTimeInterval(0.5), hasAction: true), over: shown)
        #expect(r.twins == [0])
        #expect(r.count == 3)
        #expect(ToastRules.title("Moved to Trash", count: r.count) == "Moved to Trash (3)")
        let later = ToastRules.arrive(.init(title: "Moved to Trash", destructive: false, at: t0.addingTimeInterval(1.5), hasAction: true), over: shown)
        #expect(later.twins.isEmpty && later.count == 1)
        let otherStyle = ToastRules.arrive(.init(title: "Moved to Trash", destructive: true, at: t0, hasAction: false), over: shown)
        #expect(otherStyle.twins.isEmpty)
    }

    @Test func pastThreeTheOldestWithoutAnActionClose() {
        let shown = [
            ToastRules.Shown(title: "c", destructive: false, at: t0.addingTimeInterval(-1), hasAction: false),
            ToastRules.Shown(title: "b", destructive: false, at: t0.addingTimeInterval(-2), hasAction: true),
            ToastRules.Shown(title: "a", destructive: false, at: t0.addingTimeInterval(-3), hasAction: false),
        ]
        #expect(ToastRules.arrive(.init(title: "d", destructive: false, at: t0, hasAction: false), over: shown).closing == [2])
        let actions = shown.map { var s = $0; s.hasAction = true; return s }
        #expect(ToastRules.arrive(.init(title: "d", destructive: false, at: t0, hasAction: false), over: actions).closing.isEmpty)
        #expect(ToastRules.arrive(.init(title: "d", destructive: false, at: t0, hasAction: false), over: Array(shown.prefix(2))).closing.isEmpty)
    }

    @Test func failuresAreKeyedPerEntry() {
        var t = SaveTally()
        t.begin(); t.begin()
        #expect(t.label == "Saving…")
        t.end("a", saved: false)
        t.end("b", saved: true)
        #expect(t.label == "Not saved")
        t.begin()
        t.end("b", saved: true)
        #expect(t.failed == ["a"])
        t.forget("a")
        #expect(t.label == "Saved")
        t.end("x", saved: true)
        #expect(t.pending == 0)
    }

    @Test func initialsAndNames() {
        #expect(ShellText.initials("Bharat Tandon") == "BT")
        #expect(ShellText.initials("  maya  ") == "M")
        #expect(ShellText.initials("Anna Maria Lopez") == "AL")
        #expect(ShellText.initials("") == "")
        #expect(ShellText.exportName(.moment, day: "2026-10-27", ext: "mov") == "Saro moment, 27 Oct 2026.mov")
        #expect(ShellText.exportName(.voice, day: "2026-01-02", ext: "m4a") == "Saro voice note, 2 Jan 2026.m4a")
        #expect(ShellText.exportName(.moment, day: "2026-10-27", ext: "") == "Saro moment, 27 Oct 2026")
        #expect(ShellText.dayImageName("2026-09-26") == "saro-2026-09-26.png")
    }

    @Test func directionFollowsTheFirstStrongCharacter() {
        #expect(ShellText.isRightToLeft("שלום, Ravi"))
        #expect(ShellText.isRightToLeft("12. مرحبا"))
        #expect(ShellText.isRightToLeft("آج بہت تھکاوٹ"))
        #expect(!ShellText.isRightToLeft("Ravi said שלום"))
        #expect(!ShellText.isRightToLeft("2026 — "))
        #expect(!ShellText.isRightToLeft(""))
    }

    @Test func theDayImageIsAtMost4096() {
        #expect(DayImageMath.scale(for: CGSize(width: 800, height: 600)) == 2)
        #expect(DayImageMath.scale(for: CGSize(width: 8192, height: 1000)) == 0.5)
        #expect(DayImageMath.scale(for: .zero) == 2)
    }

    @Test func lockWaitsAsLongAsChosen() {
        #expect(Prefs.LockAfter.immediately.seconds == 0)
        #expect(Prefs.LockAfter.fiveMinutes.seconds == 300)
        #expect(Prefs.LockAfter.hour.seconds == 3600)
        #expect(Prefs.LockAfter.never.seconds == nil)
    }

    @Test func failureCopyNamesARemedyNeverTheError() {
        #expect(FailureCopy.remedy(for: CocoaError(.fileWriteOutOfSpace)) == "Your Mac may be out of space.")
        #expect(FailureCopy.remedy(for: POSIXError(.ENOSPC)) == "Your Mac may be out of space.")
        #expect(FailureCopy.remedy(for: SQLiteError(description: "database or disk is full in: INSERT")) == "Your Mac may be out of space.")
        #expect(FailureCopy.remedy(for: CocoaError(.fileWriteNoPermission)) == "Try again in a moment.")
        #expect(FailureCopy.code(CocoaError(.fileWriteNoPermission)) == "NSCocoaErrorDomain 513")
    }

    @Test func theMenusKeysComeFromTheTable() {
        #expect(Shortcut.today.chord == Shortcut.Chord(modifiers: [.command], key: "t"))
        #expect(Shortcut.exportCopy.chord == Shortcut.Chord(modifiers: [.shift, .command], key: "s"))
        #expect(Shortcut.lock.chord == Shortcut.Chord(modifiers: [.control, .command], key: "l"))
        #expect(Shortcut.moveToTrash.chord == Shortcut.Chord(modifiers: [.command], key: "delete"))
        #expect(Shortcut.previousDay.chord?.key == "[")
        // What a menu item carries is one chord; the replay's arrows and ⇧F10 are listed but not menu keys.
        let menuKeys: [Shortcut] = [.recordMoment, .voiceNote, .write, .captureAnywhere, .today, .previousDay, .nextDay, .showDays, .noticed,
                                    .letter, .fitDay, .zoomIn, .zoomOut, .editDetails, .exportCopy, .showInFinder, .copyText, .stack,
                                    .grid, .moveToTrash, .search, .whatSaroKnows, .settings, .shortcuts, .lock]
        #expect(menuKeys.allSatisfy { $0.chord != nil && Shortcut.all.contains($0) })
        #expect(Shortcut.all.first { $0.keys == "⇧F10" }?.chord == nil)
        #expect(Shortcut.all.first { $0.keys == "← →" }?.chord == nil)
    }

    @Test func noTwoShortcutsShareKeysInOneScope() {
        let keyed = Dictionary(grouping: Shortcut.all) { "\($0.scope ?? "app")|\($0.keys)" }
        #expect(keyed.values.allSatisfy { $0.count == 1 }, "\(keyed.filter { $0.value.count > 1 }.keys)")
        #expect(Set(Shortcut.all.map(\.group)) == Set(Shortcut.Group.allCases))
    }
}
