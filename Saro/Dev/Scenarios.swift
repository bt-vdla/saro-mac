#if DOGFOOD
import AppKit
import AVFoundation
import ImageIO
import SaroKit
import SwiftUI
import UniformTypeIdentifiers

/// `-SaroScenario <dir>` (with -SaroDemo, in an unsandboxed build) drives the model as a user would: write, edit mid-reading,
/// hold and unhold, trash and undo, restore, a still and its note, recorded turns, try again, stacks, yesterday and back,
/// midnight, export. After each step it checks the ledger and the model and rewrites `<dir>/report.json`
/// (`[{step, ok, details}]`); it quits at the end. It makes the writing editor's calls without opening it: a live editor
/// would write its own, older text back when it closed.
@MainActor
final class Scenarios {
    struct Step: Encodable {
        let step: String
        let ok: Bool
        let details: [String]
    }

    static func runIfRequested(_ model: AppModel) {
        guard let dir = UserDefaults.standard.string(forKey: "SaroScenario"), model.isDemo else { return }
        let run = Scenarios(model: model, out: URL(fileURLWithPath: dir))
        Task {
            // ponytail: one watchdog for the whole run; a hung step reports as a timeout rather than per step.
            try? await Task.sleep(for: .seconds(UserDefaults.standard.double(forKey: "SaroScenarioTimeout").nonZero ?? 1200))
            run.record("watchdog", ["the run didn't finish in time"])
            NSApp.terminate(nil)
        }
        Task {
            await run.all()
            NSApp.terminate(nil)
        }
    }

    private let model: AppModel
    private let out: URL
    private var steps: [Step] = []
    private var ledger: Ledger { model.ledger }

    private init(model: AppModel, out: URL) {
        self.model = model
        self.out = out
    }

    // Synthetic text only (SR-28).
    static let page1 = "Went for a run before work. The river path was quiet and cold."
    static let page2 = page1 + "\nCalled Meera after lunch and we laughed about the old flat with the broken heater."
    static let page3 = page2 + "\nCooked dal for dinner and read two chapters before bed."
    static let held = "Rough week at the studio.\nSome nights I feel there is no reason to live.\nI stayed in bed most of Sunday."
    static let spoken = "I took the long way home past the lake. The water was still and I felt calm for the first time this week."

    private func all() async {
        await boot()
        guard let page = await writePage() else { return }
        await editWhileProcessing(page)
        await editAgain(page)
        await trashAndUndo(page)
        await trashWhileQueued()
        await restoreFromTrash()
        let held = await holdDay()
        if let held {
            await trashAndRestoreHeld(held)
            await unholdByEditing(held)
        }
        await emptyHeldPage()
        await still()
        await recordedTurns()
        await retranscribe()
        await stackAndGrid()
        await emptyPage()
        await yesterdayAndBack()
        await midnight()
        await export()
    }

    // MARK: Steps

    private func boot() async {
        var notes = ["ai: \(model.ai.status == .available ? "available" : "unavailable") \(model.ai.variant)"]
        let seeded = await wait(90) { [model] in model.entries.count >= 5 }
        if !seeded { notes.append("demo seed shows \(model.entries.count) entries after 90 s") }
        await settle(&notes)
        record("boot", await check() + (seeded ? [] : ["demo seed didn't load"]), notes)
    }

    private func writePage() async -> String? {
        var notes: [String] = []
        guard let e = await model.newWriting() else {
            record("write-page", ["newWriting returned nil"])
            return nil
        }
        await type(e.id, Self.page1)
        await close(e.id)
        let caught = await wait(30, every: .milliseconds(20)) { [ledger] in
            [ProcessingStatus.gating, ProcessingStatus.reading].contains((try? await ledger.entry(e.id))?.processingStatus ?? "")
        }
        notes.append(caught ? "caught the page mid-pass" : "the pass finished before it could be caught")
        record("write-page", [], notes)
        return e.id
    }

    private func editWhileProcessing(_ id: String) async {
        var notes: [String] = []
        await type(id, Self.page2)
        await close(id)
        await settle(&notes)
        record("edit-while-processing", await expectRead(id, Self.page2) + check(), notes)
    }

    private func editAgain(_ id: String) async {
        var notes: [String] = []
        await type(id, Self.page3)
        // A second autosave with the same text, as the editor's 800 ms debounce does when typing pauses twice.
        await type(id, Self.page3)
        await close(id)
        await settle(&notes)
        record("edit-again", await expectRead(id, Self.page3) + check(), notes)
    }

    private func trashAndUndo(_ id: String) async {
        var problems: [String] = []
        var notes: [String] = []
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        model.selection = [id]
        await model.trash([id], undoManager: undo)
        undo.endUndoGrouping()
        if model.entry(id) != nil { problems.append("trashed page still on the canvas") }
        if model.toast?.undo == nil { problems.append("no Undo on the trash toast") }
        if !model.selection.isEmpty { problems.append("selection kept a trashed card") }
        await settle(&notes)
        if let r = model.dayReading, r.payload.entryIds.contains(id) || r.payload.quotes.contains(where: { $0.entryId == id }) {
            problems.append("the day reading still draws on the trashed page")
        }
        problems += await check()
        undo.undo()
        let back = await wait(10) { [model] in model.entry(id) != nil }
        if !back { problems.append("undo didn't bring the page back") }
        await settle(&notes)
        problems += await expectRead(id, Self.page3) + check()
        if model.dayStatus == .ready, model.dayReading.map({ !$0.payload.entryIds.contains(id) }) ?? true {
            problems.append("the day reading wasn't read again with the restored page")
        }
        record("trash-undo", problems, notes)
    }

    /// A page trashed while it waits behind another in the queue, then put back with Undo, must still be read.
    private func trashWhileQueued() async {
        var notes: [String] = []
        guard let a = await model.newWriting(), let b = await model.newWriting() else { return record("trash-while-queued", ["newWriting failed"]) }
        await type(a.id, "Long walk to the market for mangoes. The vendor remembered my name.")
        await close(a.id)
        await type(b.id, "Fixed the wobbly shelf in the hallway with a folded coaster.")
        await close(b.id)
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        await model.trash([b.id], undoManager: undo)
        undo.endUndoGrouping()
        await settle(&notes)
        undo.undo()
        _ = await wait(10) { [model] in model.entry(b.id) != nil }
        await settle(&notes)
        record("trash-while-queued", await expectRead(b.id, "Fixed the wobbly shelf in the hallway with a folded coaster.") + check(), notes)
    }

    /// Trash, then the Trash pane's Restore.
    private func restoreFromTrash() async {
        var problems: [String] = []
        var notes: [String] = []
        guard let e = await model.newWriting() else { return record("restore-from-trash", ["newWriting failed"]) }
        let text = "Repotted the basil and the mint. The mint is already taking over."
        await type(e.id, text)
        await close(e.id)
        // Trashed before its pass runs, then restored from the Trash pane.
        await model.trash([e.id])
        await settle(&notes)
        model.pane = .trash
        let trashed = ((try? await ledger.trashed()) ?? []).map(\.id)
        if !trashed.contains(e.id) { problems.append("the page isn't in Trash") }
        await restoreAsTrashPaneDoes(e.id)
        model.pane = .day
        await settle(&notes)
        if model.entry(e.id) == nil { problems.append("restored page isn't on the canvas") }
        problems += await expectRead(e.id, text) + check()
        if model.dayStatus == .ready, model.dayReading.map({ !$0.payload.entryIds.contains(e.id) }) ?? true {
            problems.append("the day reading wasn't read again with the restored page")
        }
        record("restore-from-trash", problems, notes)
    }

    private func holdDay() async -> String? {
        var problems: [String] = []
        var notes: [String] = []
        guard let e = await model.newWriting() else {
            record("hold", ["newWriting failed"])
            return nil
        }
        await type(e.id, Self.held)
        await close(e.id)
        await settle(&notes)
        let v = (try? await ledger.verdicts(day: e.localDay))?[e.id]
        if v?.verdict != "safety_hold" { problems.append("held text got verdict \(v?.verdict ?? "none")") }
        if !model.isDayHeld { problems.append("the day isn't held") }
        if model.dayStatus != .held { problems.append("dayStatus is \(model.dayStatus), not held") }
        problems += await check()
        record("hold", problems, notes)
        return e.id
    }

    /// Trashing the held page frees the day; restoring it holds the day again, and nothing read meanwhile may stay stored.
    private func trashAndRestoreHeld(_ id: String) async {
        var problems: [String] = []
        var notes: [String] = []
        await model.trash([id])
        await settle(&notes)
        if model.isDayHeld { problems.append("the day is still held with its held page in Trash") }
        notes.append("day after trashing the held page: \(model.dayStatus)\(model.dayReading == nil ? "" : ", with a reading")")
        problems += await check()
        await restoreAsTrashPaneDoes(id)
        await settle(&notes)
        if !model.isDayHeld { problems.append("the day isn't held after the held page came back") }
        problems += await check()
        record("hold-trash-restore", problems, notes)
    }

    /// Rewriting the held page re-gates it; clear text frees the day.
    private func unholdByEditing(_ id: String) async {
        var notes: [String] = []
        let text = "Rough week at the studio, but the new kiln finally fired evenly."
        await type(id, text)
        await close(id)
        await settle(&notes)
        var problems = await expectRead(id, text) + check()
        if model.isDayHeld { problems.append("the day is still held after the held page was rewritten") }
        notes.append("day after the rewrite: \(model.dayStatus)\(model.dayReading == nil ? "" : ", with a reading")")
        record("unhold-by-editing", problems, notes)
    }

    /// A held page emptied of its words frees the day, as the pipeline already counts it.
    private func emptyHeldPage() async {
        var notes: [String] = []
        guard let e = await model.newWriting() else { return record("empty-held-page", ["newWriting failed"]) }
        await type(e.id, Self.held)
        await close(e.id)
        await settle(&notes)
        var problems = model.isDayHeld ? [] : ["the held page didn't hold the day"]
        await type(e.id, "")
        await close(e.id)
        await settle(&notes)
        problems += await check()
        if model.isDayHeld { problems.append("the day stays held by a page with no words left") }
        notes.append("day after emptying: \(model.dayStatus)\(model.dayReading == nil ? "" : ", with a reading")")
        record("empty-held-page", problems, notes)
    }

    private func still() async {
        var problems: [String] = []
        var notes: [String] = []
        guard let jpeg = Self.jpegWithGPS() else { return record("still", ["couldn't make the test JPEG"]) }
        let before = Set(model.entries.map(\.id))
        await model.importStill(jpeg, origin: "scenario", at: nil)
        guard let e = model.entries.first(where: { !before.contains($0.id) && $0.kind == .still }) else {
            return record("still", await check() + ["the still didn't land on the canvas"])
        }
        if let url = model.mediaURL(for: e), let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            if props[kCGImagePropertyGPSDictionary] != nil { problems.append("the still kept its GPS (DR-11)") }
            if (props[kCGImagePropertyOrientation] as? Int) != 6 { problems.append("the still lost its orientation") }
            if CGImageSourceGetType(src) as String? != UTType.heic.identifier { problems.append("the still isn't HEIC") }
        } else {
            problems.append("the still's file can't be read")
        }
        let note = "Morning light on the balcony tiles."
        await caption(e.id, note)
        await settle(&notes)
        problems += await expectCaption(e.id, note) + check()
        record("still", problems, notes)

        // A note can hold the still and its day (SR-11); a clear note frees them again.
        var held: [String] = []
        await caption(e.id, "Her old chair. Some nights I feel there is no reason to live without her.")
        await settle(&notes)
        if (try? await ledger.verdicts(day: e.localDay))?[e.id]?.verdict != "safety_hold" { held.append("the held note didn't hold the still") }
        if !model.isDayHeld { held.append("the held note didn't hold the day") }
        held += await check()
        await caption(e.id, note)
        await settle(&notes)
        held += await expectCaption(e.id, note) + check()
        if model.isDayHeld { held.append("the day stayed held after the note was rewritten") }
        record("still-held-note", held)
    }

    /// A voice note and a two-turn moment, written as files between beginTurn and finishTurn, as the recorder does.
    private func recordedTurns() async {
        var problems: [String] = []
        var notes: [String] = []
        let source = URL.temporaryDirectory.appending(path: "scenario-\(UUID().uuidString).caf")
        guard await DemoSpeech.write(Self.spoken, to: source) else { return record("recorded-turn", ["couldn't synthesise speech"]) }
        do {
            let voice = try await model.beginTurn(kind: .voice, sessionId: UUID().uuidString, turn: 1)
            if (try? await ledger.entry(voice.entryId))?.processingStatus != ProcessingStatus.recording {
                problems.append("the voice turn isn't 'recording' before its first frame (DR-12)")
            }
            try await Self.movie(from: source, to: voice.url)
            await model.finishTurn(voice, durationMs: 6000, error: nil)

            let session = UUID().uuidString
            var tickets: [TurnTicket] = []
            for n in 1...2 {
                let t = try await model.beginTurn(kind: .moment, sessionId: session, turn: n)
                try await Self.movie(from: source, to: t.url)
                await model.finishTurn(t, durationMs: 6000, error: nil)
                tickets.append(t)
            }
            await settle(&notes)
            for t in [voice] + tickets {
                let words = (try? await ledger.transcript(mediaId: t.mediaId)) ?? []
                let status = (try? await ledger.entry(t.entryId))?.processingStatus ?? "missing"
                notes.append("\(Self.short(t.entryId)): \(status), \(words.count) words")
                if let m = try? await ledger.media(t.mediaId), m.state != "ready" || (m.bytes ?? 0) == 0 {
                    problems.append("\(Self.short(t.entryId)) media is \(m.state), \(m.bytes ?? 0) bytes")
                }
            }
            let stacks = model.items.filter { $0.isStack && Set($0.entries.map(\.id)) == Set(tickets.map(\.entryId)) }
            if stacks.count != 1 { problems.append("the moment's two turns aren't one stack") }
        } catch {
            problems.append("recording failed: \(error.localizedDescription)")
        }
        problems += await check()
        record("recorded-turn", problems, notes)
    }

    /// Try again on a voice note: the transcript comes back and the note is gated and read as before.
    private func retranscribe() async {
        var notes: [String] = []
        guard let e = model.entries.first(where: { $0.kind == .voice && $0.processingStatus == ProcessingStatus.done }), let mid = e.mediaId else {
            return record("retranscribe", ["no voice note to transcribe again"])
        }
        model.retranscribe(e)
        try? await Task.sleep(for: .milliseconds(300))
        await settle(&notes)
        var problems = await check()
        if ((try? await ledger.transcript(mediaId: mid)) ?? []).isEmpty { problems.append("transcribing again lost the transcript") }
        record("retranscribe", problems, notes)
    }

    /// Stack two cards, fan them back out, grid them: the canvas and the ledger agree after each.
    private func stackAndGrid() async {
        var problems: [String] = []
        let ids = Set(model.entries.filter { model.layouts[$0.id]?.stackId == nil }.prefix(2).map(\.id))
        guard ids.count == 2 else { return record("stack-grid", ["not two loose cards to stack"]) }
        model.stack(ids)
        try? await Task.sleep(for: .milliseconds(500))
        var stored = (try? await ledger.layouts(day: model.day)) ?? [:]
        let sids = Set(ids.map { stored[$0]?.stackId })
        if sids.count != 1 || sids.first.flatMap({ $0 }) == nil { problems.append("the stack wasn't saved") }
        guard let stack = model.items.first(where: { $0.isStack && Set($0.entries.map(\.id)) == ids }), let sid = stack.stackID else {
            return record("stack-grid", problems + ["the two cards don't show as one stack"])
        }
        model.unstack(sid)
        model.grid(ids)
        try? await Task.sleep(for: .milliseconds(500))
        stored = (try? await ledger.layouts(day: model.day)) ?? [:]
        for id in ids where stored[id] != model.layouts[id] { problems.append("\(Self.short(id))'s place on the canvas wasn't saved") }
        if ids.contains(where: { stored[$0]?.stackId != nil }) { problems.append("unstacked cards kept their stack") }
        problems += await check()
        record("stack-grid", problems)
    }

    /// A page closed without a word leaves nothing behind.
    private func emptyPage() async {
        var notes: [String] = []
        guard let e = await model.newWriting() else { return record("empty-page", ["newWriting failed"]) }
        await close(e.id)
        await settle(&notes)
        var problems = await check()
        if (try? await ledger.entry(e.id)) != nil { problems.append("an empty page was kept") }
        let rows = (try? await ledger.run("SELECT COUNT(*) AS n FROM card_layout WHERE entry_id=?", [.text(e.id)]))?.first?["n"]?.int ?? 0
        if rows > 0 { problems.append("an empty page left its place on the canvas") }
        record("empty-page", problems, notes)
    }

    private func yesterdayAndBack() async {
        var problems: [String] = []
        var notes: [String] = []
        let today = LocalDay.today()
        let yesterday = LocalDay.adding(-1, to: today)
        model.selection = Set(model.entries.prefix(1).map(\.id))
        model.goPrevious()
        if await !wait(10, until: { [model] in model.day == yesterday }) { problems.append("⌘[ didn't reach yesterday") }
        if !model.selection.isEmpty { problems.append("selection crossed days") }
        if model.isToday { problems.append("isToday on yesterday") }
        // Writing on a past day backdates (DR-10).
        if let e = await model.newWriting() {
            await type(e.id, "Backfilled: the plumber came at nine and fixed the kitchen tap.")
            await close(e.id)
            if let row = try? await ledger.entry(e.id), row.localDay != yesterday || !row.backdated {
                problems.append("a page written on yesterday is filed \(row.localDay), backdated \(row.backdated)")
            }
        }
        // The floating panel's Write files under today, whatever the window shows.
        if let q = await model.newWriting(body: "Quick note from the menu bar: buy oat milk.", day: today) {
            model.process(q.id)
            if q.localDay != today || q.backdated { problems.append("a quick capture is filed \(q.localDay)") }
            if model.entry(q.id) != nil { problems.append("a quick capture for today shows on yesterday") }
        }
        if let t = try? await model.beginTurn(kind: .voice, sessionId: UUID().uuidString, turn: 1) {
            let source = URL.temporaryDirectory.appending(path: "scenario-\(UUID().uuidString).caf")
            if await DemoSpeech.write("Short note about yesterday.", to: source) { try? await Self.movie(from: source, to: t.url) }
            await model.finishTurn(t, durationMs: 2000, error: nil)
            if let row = try? await ledger.entry(t.entryId), row.localDay != yesterday || !row.backdated {
                problems.append("a turn recorded on yesterday is filed \(row.localDay), backdated \(row.backdated)")
            }
        }
        await settle(&notes)
        problems += await check()
        model.goNext()
        if await !wait(10, until: { [model] in model.day == today }) { problems.append("⌘] didn't come back to today") }
        model.goNext()
        try? await Task.sleep(for: .milliseconds(600))
        if model.day != today { problems.append("⌘] went past today to \(model.day)") }
        // Quick ⌘[ then ⌘T: the later change wins.
        model.goPrevious()
        model.goToday()
        try? await Task.sleep(for: .seconds(2))
        if model.day != today { problems.append("⌘[ ⌘T landed on \(model.day)") }
        await settle(&notes)
        problems += await check()
        record("yesterday-and-back", problems, notes)
    }

    /// Stands the model on yesterday as if it were still today, then lets midnight pass.
    private func midnight() async {
        var problems: [String] = []
        var notes: [String] = []
        let today = LocalDay.today()
        let yesterday = LocalDay.adding(-1, to: today)
        model.go(to: yesterday)
        _ = await wait(10) { [model] in model.day == yesterday }
        model.today = yesterday
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        if await !wait(10, until: { [model] in model.day == today }) { problems.append("midnight left the canvas on \(model.day)") }

        model.go(to: yesterday)
        _ = await wait(10) { [model] in model.day == yesterday }
        model.today = yesterday
        let open = model.entries.first?.id
        model.openEntryID = open
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        try? await Task.sleep(for: .seconds(1))
        if open != nil, model.day != yesterday || model.openEntryID != open { problems.append("midnight moved the day under an open entry") }
        model.openEntryID = nil
        if await !wait(10, until: { [model] in model.day == today }) { problems.append("closing the entry after midnight left \(model.day)") }
        if model.today != today { problems.append("the model's today is \(model.today)") }
        if let e = await model.newWriting() {
            if e.localDay != today || e.backdated { problems.append("a page written after midnight is filed \(e.localDay)") }
            try? await ledger.discardIfEmpty(e.id)
        }
        await model.reload()
        await settle(&notes)
        problems += await check()
        record("midnight", problems, notes)
    }

    private func export() async {
        var problems: [String] = []
        var notes: [String] = []
        let dir = URL.temporaryDirectory.appending(path: "scenario-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appending(path: "Saro.saroexport", directoryHint: .isDirectory)
            try await ledger.exportEverything(to: dest, prefs: PrefsStore.shared.export())
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: dest.appending(path: "saro.json"))) as? [String: Any] ?? [:]
            let rows = { (t: String) in json[t] as? [[String: Any]] ?? [] }
            let all = (try? await ledger.allEntries(includeTrashed: true)) ?? []
            if rows("entry").count != all.count { problems.append("export has \(rows("entry").count) entries, the ledger \(all.count)") }
            // Rows come in insertion order, so the last verdict per entry is its newest.
            var newest: [String: String] = [:]
            for r in rows("safety_verdict") { if let id = r["entry_id"] as? String { newest[id] = r["verdict"] as? String } }
            let held = Set(newest.filter { $0.value == "safety_hold" }.keys)
            let leaked = rows("entry_annotation").filter { held.contains($0["entry_id"] as? String ?? "") }
            if !leaked.isEmpty { problems.append("export carries \(leaked.count) readings of held entries (SR-15)") }
            let media = (try? await ledger.allMedia()) ?? []
            let missing = media.filter { $0.state == "ready" && !FileManager.default.fileExists(atPath: dest.appending(path: "Media/\($0.fileName)").path) }
            if !missing.isEmpty { problems.append("export is missing \(missing.count) media files") }
            notes.append("\(rows("entry").count) entries, \(media.count) media, \(rows("insight_snapshot").count) snapshots")
        } catch {
            problems.append("export failed: \(error.localizedDescription)")
        }
        problems += await check()
        record("export", problems, notes)
    }

    // MARK: The editor's calls

    /// What the writing editor's autosave does, for a page the run treats as open.
    private func type(_ id: String, _ text: String) async {
        let e = try? await ledger.entry(id)
        try? await ledger.updateEntryText(id: id, body: text, titleUser: e?.titleUser)
        await model.edited(id)
    }

    /// What closing the writing editor does.
    private func close(_ id: String) async {
        if (try? await ledger.entry(id))?.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            try? await ledger.discardIfEmpty(id)
        }
        await model.reload()
        model.process(id)
    }

    /// What the still's note field does when it loses focus or the detail closes.
    private func caption(_ id: String, _ text: String) async {
        guard let e = try? await ledger.entry(id) else { return }
        try? await ledger.updateEntryText(id: id, body: e.body, titleUser: e.titleUser, captionUser: text.isEmpty ? nil : text)
        await model.reload()
        if !text.isEmpty { model.process(id) }
    }

    /// The Trash pane's Restore button.
    private func restoreAsTrashPaneDoes(_ id: String) async {
        await model.restore(ids: [id])
    }

    // MARK: Checks

    /// The read an entry should end with: its current text gated and, when clear on a day that isn't held, read.
    private func expectRead(_ id: String, _ text: String) async -> [String] {
        guard let e = try? await ledger.entry(id) else { return ["\(Self.short(id)) is gone"] }
        var p: [String] = []
        if e.body != text { p.append("\(Self.short(id)) body isn't the last edit") }
        let v = (try? await ledger.verdicts(day: e.localDay))?[id]
        if v?.textSha256 != sha256(text) { p.append("\(Self.short(id)) wasn't gated on its last edit (status \(e.processingStatus))") }
        if v?.verdict == "clear" || v?.verdict == "unavailable_clear" {
            if (try? await ledger.hasAnnotation(entryId: id, inputHash: sha256(text))) != true { p.append("\(Self.short(id)) wasn't read on its last edit") }
            if e.localDay == model.day, !model.isDayHeld, model.annotations[id] == nil { p.append("\(Self.short(id)) reading doesn't show") }
        }
        return p
    }

    private func expectCaption(_ id: String, _ text: String) async -> [String] {
        guard let e = try? await ledger.entry(id) else { return ["\(Self.short(id)) is gone"] }
        let v = (try? await ledger.verdicts(day: e.localDay))?[id]
        var p: [String] = []
        if v?.textSha256 != sha256(text) { p.append("the still's note wasn't gated (status \(e.processingStatus))") }
        if v?.verdict == "clear", (try? await ledger.hasAnnotation(entryId: id, inputHash: sha256(text))) != true { p.append("the still's note wasn't read") }
        return p
    }

    /// Ledger invariants (SR-13, SR-15, DR-12) and the model's view of the day on screen.
    private func check() async -> [String] {
        var p: [String] = []
        let all = (try? await ledger.allEntries()) ?? []
        let byDay = Dictionary(grouping: all, by: \.localDay)
        var heldDays: Set<String> = []
        var texts: [String: String] = [:]
        for (day, entries) in byDay {
            let verdicts = (try? await ledger.verdicts(day: day)) ?? [:]
            for e in entries {
                let tag = "\(Self.short(e.id)) (\(e.kind.rawValue), \(day))"
                if [ProcessingStatus.recording, ProcessingStatus.pending, ProcessingStatus.transcribing, ProcessingStatus.gating,
                    ProcessingStatus.reading].contains(e.processingStatus) {
                    p.append("\(tag) stuck \(e.processingStatus)")
                }
                if let mid = e.mediaId {
                    if let m = try? await ledger.media(mid) {
                        if m.state == "ready", !FileManager.default.fileExists(atPath: ledger.url(for: m).path) { p.append("\(tag) media file is missing") }
                    } else {
                        p.append("\(tag) points at no media row")
                    }
                }
                let text = await self.text(e)
                texts[e.id] = text
                let v = verdicts[e.id]
                if v?.verdict == "safety_hold" {
                    // Emptied text has nothing left to hold (Pipeline.dayStatus).
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { heldDays.insert(day) }
                    let n = (try? await ledger.run("SELECT COUNT(*) AS n FROM entry_annotation WHERE entry_id=?", [.text(e.id)]))?.first?["n"]?.int ?? 0
                    if n > 0 { p.append("\(tag) is held but stores \(n) readings (SR-15)") }
                }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, e.processingStatus != ProcessingStatus.failed else { continue }
                if v == nil || v?.textSha256 != sha256(text) {
                    if e.processingStatus != ProcessingStatus.transcriptUnavailable { p.append("\(tag) isn't gated on its current text") }
                } else if v?.verdict == "clear" || v?.verdict == "unavailable_clear",
                          (try? await ledger.hasAnnotation(entryId: e.id, inputHash: sha256(text))) != true {
                    p.append("\(tag) is clear but has no reading of its current text")
                }
            }
        }
        for day in heldDays {
            let n = (try? await ledger.run("SELECT COUNT(*) AS n FROM insight_snapshot WHERE kind IN ('day_reading','letter') AND from_day=?",
                                           [.text(day)]))?.first?["n"]?.int ?? 0
            if n > 0 { p.append("held day \(day) still stores \(n) day readings or letters (SR-13, SR-15)") }
        }

        // The model, for the day on screen.
        guard model.pane == .day else { return p }
        let onDay = Set((byDay[model.day] ?? []).map(\.id))
        if Set(model.entries.map(\.id)) != onDay { p.append("the canvas shows \(model.entries.count) entries, the ledger has \(onDay.count) for \(model.day)") }
        for e in model.entries where model.layouts[e.id] == nil { p.append("\(Self.short(e.id)) has no place on the canvas") }
        let status = await model.pipeline.dayStatus(model.day)
        if model.dayStatus != status { p.append("the model says \(model.dayStatus), the pipeline \(status)") }
        if model.isDayHeld != heldDays.contains(model.day) { p.append("isDayHeld is \(model.isDayHeld) but the ledger says \(heldDays.contains(model.day))") }
        if model.isDayHeld {
            if model.dayReading != nil { p.append("a held day shows a day reading (SR-13)") }
            if let w = model.week.first(where: { $0.day == model.day }), w.mood != nil { p.append("a held day shows a mood in the week (SR-13)") }
            var titled = 0
            for e in model.entries {
                let tag = "\(Self.short(e.id)) (\(e.kind.rawValue))"
                if model.mood(for: e) != nil { p.append("\(tag) shows a mood on a held day (SR-13)") }
                if model.summary(for: e) != nil { p.append("\(tag) shows a summary on a held day (SR-13)") }
                if let t = model.annotations[e.id]?.title, !t.isEmpty, model.title(for: e).caseInsensitiveCompare(t) == .orderedSame { titled += 1 }
            }
            if titled > 0 { p.append("\(titled) cards show Saro's title on a held day (SR-13)") }
        }
        for id in model.annotations.keys {
            guard let v = model.verdicts[id] else { p.append("\(Self.short(id)) shows a reading with no verdict"); continue }
            if let t = texts[id], v.textSha256 != sha256(t) { p.append("\(Self.short(id)) shows a reading of older text") }
            if v.verdict == "safety_hold" { p.append("\(Self.short(id)) shows a reading while held") }
        }
        if let r = model.dayReading {
            for q in r.payload.quotes {
                guard let t = texts[q.entryId], onDay.contains(q.entryId) else { p.append("the day reading quotes an entry that isn't on the day"); continue }
                if !t.contains(q.text) { p.append("the day reading quotes \(Self.short(q.entryId)) words it no longer has") }
            }
        }
        return p
    }

    /// The text the gate reads, as `Pipeline.text(for:)` builds it.
    private func text(_ e: Entry) async -> String {
        switch e.kind {
        case .reflection, .music: return e.body ?? ""
        case .still: return e.captionUser ?? ""
        case .moment, .voice:
            guard let id = e.mediaId else { return "" }
            let words = (try? await ledger.transcript(mediaId: id)) ?? []
            return words.map(\.text).joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }

    // MARK: Plumbing

    /// Waits for the queue to drain and stay drained, then for the reload that follows.
    private func settle(_ notes: inout [String], timeout: Double = 300) async {
        let start = ContinuousClock.now
        var quiet = 0
        while quiet < 4, ContinuousClock.now - start < .seconds(timeout) {
            quiet = model.working ? 0 : quiet + 1
            try? await Task.sleep(for: .milliseconds(400))
        }
        if quiet < 4 { notes.append("still working after \(Int(timeout)) s") }
        await model.reload()
    }

    private func wait(_ seconds: Double, every: Duration = .milliseconds(200), until condition: @MainActor () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: every)
        }
        return await condition()
    }

    private func record(_ step: String, _ problems: [String], _ notes: [String] = []) {
        steps.append(Step(step: step, ok: problems.isEmpty, details: problems + notes.map { "note: \($0)" }))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? encoder.encode(steps).write(to: out.appending(path: "report.json"), options: .atomic)
    }

    private static func short(_ id: String) -> String { String(id.prefix(8)) }

    /// A 3:2 JPEG that carries GPS and an EXIF orientation, as a phone photo does.
    private static func jpegWithGPS() -> Data? {
        guard let ctx = CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 0.3, green: 0.5, blue: 0.7, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        guard let image = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 12.9716, kCGImagePropertyGPSLatitudeRef: "N",
                                    kCGImagePropertyGPSLongitude: 77.5946, kCGImagePropertyGPSLongitudeRef: "E"]
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyGPSDictionary: gps, kCGImagePropertyOrientation: 6] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// Rewraps synthesised audio as the QuickTime movie the recorder writes.
    private nonisolated static func movie(from source: URL, to url: URL) async throws {
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try await session.export(to: url, as: .mov)
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
#endif
