import Observation
import SaroKit
import SwiftUI

/// Is everything saved? (save-status.ts) Every user-content write goes through `track`, keyed by what it saves (an
/// entry's id), so the avatar's dot is honest: amber while a write is pending, green for 1.5 s after the last lands, red
/// until a failed one is retried. A failure keeps its retry; deleting what it saved forgets it.
@Observable @MainActor
final class SaveStatus {
    private(set) var tally = SaveTally()
    /// True for 1.5 s after the last pending write lands with nothing failed.
    private(set) var justSaved = false
    @ObservationIgnored private var retries: [String: @MainActor () async -> Void] = [:]
    @ObservationIgnored private var savedAt = 0

    var failures: Set<String> { tally.failed }
    var pending: Bool { tally.pending > 0 }
    var notSaved: Bool { !tally.failed.isEmpty && !pending }

    /// Runs a write, keyed by what it saves (an entry's id), and rethrows its failure, which marks that key not saved
    /// until a retry lands or what it saved is deleted. The write itself is kept as the retry, so it should be safe to
    /// run again, with whatever must follow it inside.
    func track(_ key: String, _ op: @escaping @MainActor () async throws -> Void) async throws {
        let wasFailing = !tally.failed.isEmpty
        tally.begin()
        do {
            #if DOGFOOD
            if DevFlags.simulateWriteFailures { throw CocoaError(.fileWriteUnknown) }
            #endif
            try await op()
            retries[key] = nil
            tally.end(key, saved: true)
            if !pending { settle() }
        } catch {
            retries[key] = { try? await self.track(key, op) }
            tally.end(key, saved: false)
            Log.shell.error("save \(FailureCopy.code(error), privacy: .public)")
            if !wasFailing { AccessibilityNotification.Announcement("Not saved").post() }
            throw error
        }
    }

    /// What these entries saved no longer matters (they were deleted): their failures go, layouts included.
    func forget(_ ids: some Collection<String>) {
        for key in tally.failed where ids.contains(where: key.contains) {
            retries[key] = nil
            tally.forget(key)
        }
    }

    func retry(_ key: String) async { await retries[key]?() }

    /// Retry in the avatar menu: every failed write again.
    func retryAll() async {
        for key in tally.failed { await retry(key) }
        if tally.failed.isEmpty { AccessibilityNotification.Announcement("Saved").post() }
    }

    private func settle() {
        guard tally.failed.isEmpty else { return }
        savedAt += 1
        let mark = savedAt
        justSaved = true
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            if mark == savedAt { justSaved = false }
        }
    }
}
