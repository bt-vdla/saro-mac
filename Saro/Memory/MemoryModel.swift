import AppKit
import Observation
import SaroKit
import SwiftUI

/// What Saro knows, for the pane, Settings and prompts: the derived lines, the rows the graph draws, and every change
/// the person makes to them. Held as `model.memory`.
@Observable @MainActor
final class MemoryModel {
    enum Status { case loading, ready, failed }
    /// What a save of the person's own words came to.
    enum Saved { case saved, held, failed, unchanged }

    let ledger: Ledger
    let pipeline: Pipeline
    private(set) var memories: [Memory] = []
    /// `active_observation`, for the graph.
    private(set) var rows: [MemoryObservation] = []
    private(set) var status: Status = .loading
    /// Cleared entries so far, for the empty state's count (R-14).
    private(set) var clearedEntries = 0
    private(set) var called: String?
    var query = ""
    /// Keys showing "Deleted · Undo"; forgetting them waits for the window to close (FR-MEM-03).
    private(set) var pending: Set<String> = []
    /// A line the ⌘K palette asked for: the list scrolls to it and focuses it.
    var reveal: String?
    /// A write that failed, for AppModel's error toast.
    @ObservationIgnored var showError: (String) -> Void = { _ in }
    @ObservationIgnored private var timers: [String: Task<Void, Never>] = [:]
    /// Each pending delete's ⌘Z, so Undo or the window closing takes just that one off the Edit menu.
    @ObservationIgnored private var undoTokens: [String: UndoToken] = [:]
    /// A sighting opened from Why or the graph: the recording plays from here once its detail opens.
    @ObservationIgnored private var playFrom: (entryId: String, ms: Int)?
    @ObservationIgnored private var loads = 0

    static let undoSeconds = 6.0

    init(ledger: Ledger, pipeline: Pipeline) {
        self.ledger = ledger
        self.pipeline = pipeline
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.commitPendingBeforeQuit() }
        }
    }

    /// Lines that count: not waiting to be deleted.
    var live: [Memory] { memories.filter { !pending.contains($0.key) } }

    /// For prompts (FR-MEM feeding): labels only, never sentences; forgotten and held rows never get here.
    var knownLabels: [String] { MemoryList.knownLabels(live, called: called) }

    // MARK: Reading

    /// Re-derives everything from the ledger. A load that a newer one overtook drops its result.
    func load(animation: Animation? = nil) async {
        loads += 1
        let ticket = loads
        do {
            let rows = try await ledger.activeObservations()
            let derived = MemoryList.derive(rows, starter: try await ledger.latestStarter(), commitments: try await ledger.openCommitments(),
                                            tombstones: try await ledger.tombstoneHashes(), forgotAllAt: try await ledger.forgotAllAt(),
                                            pauses: try await ledger.pauses())
            let cleared = try await ledger.clearedEntryCount()
            let called = try await ledger.profile().address
            guard ticket == loads else { return }
            withAnimation(animation) {
                self.rows = rows
                // A line waiting on its Undo keeps its place until the window closes.
                memories = derived + memories.filter { pending.contains($0.key) && !derived.map(\.key).contains($0.key) }
                clearedEntries = cleared
                self.called = called
                status = .ready
            }
        } catch {
            guard ticket == loads else { return }
            status = .failed
        }
    }

    // MARK: Learning (the one hook in AppModel.drain, and the launch backfill)

    func learn(entryId: String) async {
        if await pipeline.learn(entryId: entryId) { await load() }
    }

    /// Cleared entries this extractor hasn't read, for the launch sweep to queue.
    func unlearned() async -> [String] {
        (try? await ledger.unlearnedEntryIDs(extractor: MemoryRules.extractorVersion)) ?? []
    }

    // MARK: Changes

    /// Delete: the line becomes "Deleted · Undo" for six seconds; ⌘Z or Undo brings it back with nothing written.
    func delete(_ m: Memory, undoManager: UndoManager?) {
        guard !pending.contains(m.key) else { return }
        pending.insert(m.key)
        announce("Deleted: \(Self.sentence(m.text)) Undo is there for a few seconds.")
        timers[m.key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoSeconds))
            guard !Task.isCancelled else { return }
            await self?.commit([m.key])
        }
        guard let undoManager else { return }
        let token = UndoToken(undoManager)
        undoTokens[m.key] = token
        undoManager.registerUndo(withTarget: token) { [weak self] _ in MainActor.assumeIsolated { self?.undo(m) } }
        undoManager.setActionName("Delete Memory")
    }

    /// Undo, from the row or ⌘Z; ⇧⌘Z then deletes it again.
    func undo(_ m: Memory) {
        guard pending.contains(m.key) else { return }
        timers.removeValue(forKey: m.key)?.cancel()
        pending.remove(m.key)
        if let token = undoTokens.removeValue(forKey: m.key), let um = token.manager {
            if um.isUndoing {
                um.registerUndo(withTarget: token) { [weak self] t in
                    MainActor.assumeIsolated { if let um = t.manager { self?.delete(m, undoManager: um) } }
                }
                um.setActionName("Delete Memory")
            } else {
                um.removeAllActions(withTarget: token)
            }
        }
        announce("Restored.")
    }

    private func dropUndo(_ keys: some Sequence<String>) {
        for k in keys {
            if let t = undoTokens.removeValue(forKey: k) { t.manager?.removeAllActions(withTarget: t) }
        }
    }

    /// The pane closing writes what's pending at once.
    func commitPending() async {
        let keys = Array(pending)
        guard !keys.isEmpty else { return }
        for k in keys { timers.removeValue(forKey: k)?.cancel() }
        await commit(keys)
    }

    private func commit(_ keys: [String]) async {
        for k in keys { timers[k] = nil }
        dropUndo(keys)
        do {
            try await ledger.forget(keys: keys)
            pending.subtract(keys)
            await load(animation: Motion.easeOut(0.12))
        } catch {
            pending.subtract(keys)
            fail("Couldn’t delete that. Try again.")
        }
    }

    /// Quitting inside an Undo window still forgets: the write runs off the main actor while the main thread waits.
    // ponytail: a semaphore wait capped at 2 s; an applicationShouldTerminate reply if forgetting ever grows slow.
    private func commitPendingBeforeQuit() {
        let keys = Array(pending)
        guard !keys.isEmpty else { return }
        let ledger = ledger
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            try? await ledger.forget(keys: keys)
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    /// An edit: the person's line for this key, which learning never overwrites.
    func edit(_ m: Memory, to text: String) async -> Saved {
        let clean = MemoryList.oneLine(text)
        guard !clean.isEmpty, clean != MemoryList.oneLine(m.text) else { return .unchanged }
        return await write(MemoryObservation(entryId: nil, source: .user, kind: .line, key: m.key, label: clean, localDay: LocalDay.today()),
                           done: "Saved.", failed: "Couldn’t save that change. Try again.")
    }

    /// Something Saro should know, at the top of About you. Only ever given to prompts as quoted data (FR-SET-10).
    func add(_ text: String) async -> Saved {
        let clean = MemoryList.oneLine(text)
        guard !clean.isEmpty else { return .unchanged }
        let saved = await write(MemoryObservation(entryId: nil, source: .user, kind: .line, key: "user:\(UUID().uuidString)", label: clean,
                                            localDay: LocalDay.today()), done: "Added.", failed: "Couldn’t add that. Try again.")
        if saved == .saved { query = "" }
        return saved
    }

    /// A corrected name in the graph.
    func rename(_ key: String, to text: String) async -> Saved {
        let clean = MemoryList.oneLine(text)
        guard !clean.isEmpty else { return .unchanged }
        return await write(MemoryObservation(entryId: nil, source: .user, kind: .label, key: key, label: clean, localDay: LocalDay.today()),
                           done: "Renamed.", failed: "Couldn’t save that change. Try again.")
    }

    /// The person's own words pass the phrase gate before they're kept (§13: user text stored outside an entry is gated
    /// at save); a hit keeps nothing.
    private func write(_ o: MemoryObservation, done: String, failed: String) async -> Saved {
        if SafetyGate.phraseHit(o.label) { return .held }
        do {
            try await ledger.addUserMemory(o)
            await load(animation: Motion.small)
            announce(done)
            return .saved
        } catch {
            fail(failed)
            return .failed
        }
    }

    /// Forget from the graph, after its confirmation: written at once.
    func forget(_ key: String, label: String) async {
        do {
            try await ledger.forget(keys: [key])
            await load(animation: Motion.small)
            announce("Forgot \(label).")
        } catch {
            fail("Couldn’t forget right now. Try again.")
        }
    }

    /// Forget everything (FR-MEM-04); nil when it couldn't.
    func forgetAll() async -> Int? {
        let n = live.count
        do {
            try await ledger.forgetAll(extra: memories.map(\.key))
            timers.values.forEach { $0.cancel() }
            timers = [:]
            dropUndo(Array(undoTokens.keys))
            pending = []
            query = ""
            await load()
            announce("Forgot \(n) \(n == 1 ? "memory" : "memories").")
            return n
        } catch {
            fail("Couldn’t forget right now. Try again.")
            return nil
        }
    }

    // MARK: Going to a sighting

    /// Flies to the sighting's day and opens its entry; a recording plays from the quote.
    func open(_ s: Sighting, in model: AppModel) async {
        guard let id = s.entryId else { return }
        if s.field == "transcript", let start = s.spanStart, let e = try? await ledger.entry(id), let mid = e.mediaId,
           let words = try? await ledger.transcript(mediaId: mid), let ms = Pipeline.startMs(atUTF16: start, in: words) {
            playFrom = (id, ms)
        }
        model.open(DeepLink.entry(id).url)
    }

    /// The detail asks once, when it opens: where to start playing, if a quote opened it.
    func takePlayFrom(_ entryId: String) -> Int? {
        guard let p = playFrom, p.entryId == entryId else { return nil }
        playFrom = nil
        return p.ms
    }

    // MARK: Helpers

    func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    /// Heard and seen: local writes rarely fail, so when one does it says so in a toast (no pending counter).
    private func fail(_ text: String) {
        announce(text)
        showError(text)
    }

    /// The line as a sentence, without doubling its full stop.
    static func sentence(_ text: String) -> String {
        text.last.map { ".!?…”’\"".contains($0) } == true ? text : text + "."
    }
}

/// The target of one pending delete's ⌘Z.
private final class UndoToken {
    weak var manager: UndoManager?
    init(_ manager: UndoManager) { self.manager = manager }
}
