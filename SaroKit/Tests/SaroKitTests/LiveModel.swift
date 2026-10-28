import Testing

/// The on-device model turns away a request made while it is busy, and the ladder then falls to its heuristic rung.
/// Swift Testing runs tests in parallel across suites, so every live-model test takes a turn through this trait.
struct LiveModel: TestTrait, TestScoping {
    private actor Turns {
        private var busy = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func take() async {
            if busy { await withCheckedContinuation { waiting.append($0) } } else { busy = true }
        }

        /// Hands the turn straight to the next test in line, or frees it.
        func give() {
            if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
        }
    }

    private static let turns = Turns()

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        await Self.turns.take()
        do { try await function() } catch { await Self.turns.give(); throw error }
        await Self.turns.give()
    }
}

extension Trait where Self == LiveModel {
    /// One live-model test at a time (see `LiveModel`).
    static var liveModel: Self { LiveModel() }
}
