import Foundation
import Testing
@testable import SaroKit

// Synthetic text only (SR-28). Run under `swift test --sanitize=thread` to check the SQLite connection
// (opened NOMUTEX) is only ever touched from its actor, whatever the callers do at once.

/// The app's pattern: the queue drains entries while the canvas reloads the day after every status change.
@Test func pipelineWhileTheDayReloads() async throws {
    let l = try tempLedger()
    let ai = SaroAI(stub: { _ in "NONE" }, status: .unavailable(reason: "test"))
    let p = Pipeline(ledger: l, ai: ai)
    let entries = (0..<12).map { Entry(kind: .reflection, body: "Walked to the market number \($0) and bought mangoes.") }
    for e in entries { try await l.insertEntry(e) }
    let ids = entries.map(\.id)
    let day = entries[0].localDay
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            for id in ids { await p.process(entryId: id) {} }
            await p.readDay(day)
        }
        for _ in 0..<4 {
            group.addTask {
                for _ in 0..<20 {
                    _ = await p.dayStatus(day)
                    _ = await p.latestDayReading(day)
                    _ = try? await l.entries(day: day)
                    _ = try? await l.verdicts(day: day)
                }
            }
        }
    }
    let verdicts = try await l.verdicts(day: day)
    #expect(verdicts.count == ids.count)
    #expect(verdicts.values.allSatisfy { $0.verdict == "unavailable_clear" })
    #expect(try await l.annotations(day: day).count == ids.count)
    #expect(await p.dayStatus(day) == .ready)
}

/// Layout writes (drags, stacks) race day reads from other tasks; every write lands once.
@Test func concurrentLedgerWritersAndReaders() async throws {
    let l = try tempLedger()
    let entries = (0..<40).map { Entry(kind: .reflection, body: "Note \($0) about the garden.") }
    await withThrowingTaskGroup(of: Void.self) { group in
        for e in entries {
            group.addTask {
                try await l.insertEntry(e)
                try await l.setLayouts([CardLayout(entryId: e.id, x: 1, y: 2, z: 3)])
            }
            group.addTask { _ = try await l.days() }
        }
    }
    let day = entries[0].localDay
    #expect(try await l.entries(day: day).count == entries.count)
    #expect(try await l.layouts(day: day).count == entries.count)
}

/// Two ledgers on one file (two Saro processes sharing the container): writes wait on the busy timeout instead of failing.
@Test func twoLedgersOnOneFileBothWrite() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "saro-test-\(UUID().uuidString)")
    let a = try Ledger(rootURL: root)
    let b = try Ledger(rootURL: root)
    let result = await withThrowingTaskGroup(of: Void.self) { group -> Result<Void, any Error> in
        for i in 0..<30 {
            let ledger = i.isMultiple(of: 2) ? a : b
            group.addTask {
                let e = Entry(kind: .reflection, body: "Shared file note \(i).")
                try await ledger.insertEntry(e)
                try await ledger.setLayouts([CardLayout(entryId: e.id, x: 0, y: 0, z: i)])
            }
        }
        do { try await group.waitForAll(); return .success(()) } catch { return .failure(error) }
    }
    #expect(throws: Never.self) { try result.get() }
    #expect(try await a.allEntries().count == 30)
}

/// Opens once; waiters before that wait.
actor Latch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async { if !isOpen { await withCheckedContinuation { waiters.append($0) } } }
    func open() {
        isOpen = true
        for w in waiters { w.resume() }
        waiters = []
    }
}

/// An autosave that lands while the model reads the old text: that pass ends without marking the entry done, the day
/// waits, and the next pass (AppModel.edited queues one) gates and reads the new text.
@Test func editDuringTheReadingWaitsForItsOwnPass() async throws {
    let l = try tempLedger()
    let (reading, release) = (Latch(), Latch())
    let p = Pipeline(ledger: l, ai: stubAI { ask in
        switch ask {
        case .classify: return "NONE"
        case .entry:
            await reading.open()
            await release.wait()
            return cleanEntry
        case .day: return cleanDay
        }
    })
    let e = Entry(kind: .reflection, body: chai)
    try await l.insertEntry(e)
    let pass = Task { await p.process(entryId: e.id) {} }
    await reading.wait()
    let edit = "Had chai with Ravi after work, then walked home in the rain."
    try await l.updateEntryText(id: e.id, body: edit, titleUser: nil)
    await release.open()
    await pass.value
    #expect(try await l.entry(e.id)?.processingStatus == ProcessingStatus.pending)
    #expect(await p.dayStatus(e.localDay) == .working)
    #expect(await p.readDay(e.localDay) == nil)

    await p.process(entryId: e.id) {}
    #expect(try await l.entry(e.id)?.processingStatus == ProcessingStatus.done)
    #expect(try await l.verdicts(day: e.localDay)[e.id]?.textSha256 == sha256(edit))
    #expect(try await l.hasAnnotation(entryId: e.id, inputHash: sha256(edit)))
    #expect(await p.dayStatus(e.localDay) == .ready)
}
