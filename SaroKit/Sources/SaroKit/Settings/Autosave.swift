import Observation

/// A card's saves, in order (PersonalizationSheet.tsx useAutosave): the ✓ Saved tick shows only once the latest write
/// has returned, and leaves after 2.2 s; Couldn't save · Retry shows only when a write throws. Only the writes queue:
/// the tick's 2.2 s never holds the next write back.
@MainActor @Observable
public final class Autosave {
    public enum State: Sendable { case idle, saved, failed }

    public private(set) var state = State.idle
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var last: (@MainActor () async throws -> Void)?

    public init() {}

    public func run(_ write: @escaping @MainActor () async throws -> Void) {
        seq += 1
        let id = seq
        state = .idle
        last = write
        let previous = queue
        queue = Task {
            await previous?.value
            do {
                try await write()
                guard id == seq else { return }
                state = .saved
                Task {
                    try? await Task.sleep(for: .seconds(2.2))
                    if id == seq, state == .saved { state = .idle }
                }
            } catch {
                if id == seq { state = .failed }
            }
        }
    }

    /// A write that can't fail (UserDefaults), so the tick still says it landed.
    public func saved() { run {} }

    public func retry() { if let last { run(last) } }
}
