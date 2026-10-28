import Foundation
import SaroKit

extension AppModel {
    /// Reads the profile and the current starter context. Saves that land meanwhile win: an older read never replaces them.
    func loadProfile() async {
        do {
            let p = try await ledger.profile()
            if profile.map({ p.updatedAt >= $0.updatedAt }) ?? true { profile = p }
            starter = try await ledger.latestStarter()
        } catch {
            show(.failed("Couldn't read your profile", error))
        }
    }

    /// Changes the profile row and saves it; on a failed write the change is dropped and says so.
    func saveProfile(_ change: (inout Profile) -> Void) async {
        do {
            var p = if let profile { profile } else { try await ledger.profile() }
            change(&p)
            try await saves.track("profile") { [ledger, p] in try await ledger.saveProfile(p) }
            profile = try await ledger.profile()
        } catch {
            show(.failed("Couldn't save your profile", error))
        }
    }

    /// Saves this onboarding pass's starter context. `starter` becomes what was stored, so nothing derived from a held
    /// answer (its picks, or a personal first prompt) stays in memory either. Answers saved while the model is off go
    /// back through the gate once it can run.
    @discardableResult
    func saveStarter(_ s: StarterContext) async -> Bool {
        if ai.status != .available { UserDefaults.standard.removeObject(forKey: Self.gatedKey) }
        do {
            try await ledger.saveStarter(s)
            starter = try await ledger.latestStarter()
            return true
        } catch {
            starter = s.storable
            show(Toast("Couldn't save your answers on this Mac. They hold for this visit.", style: .error))
            return false
        }
    }

    /// The SAFETY_VERSION every answer, mood note and About you answer was last checked under, marked when that pass
    /// ran without the model.
    static let gatedKey = "reflectionsGatedAt"

    /// The person's own words outside entries go back through the gate (SR-17, SR-18): every one under a new
    /// SAFETY_VERSION, or once the model can run after a pass without it; otherwise just the answers and mood notes
    /// gated without the model, once it can. The pass is remembered once every one has its verdict.
    func regateOwnWords() async {
        let mark = ai.status == .available ? SafetyGate.version : SafetyGate.version + "|unavailable"
        func due() async -> Bool? {
            if ![SafetyGate.version, mark].contains(UserDefaults.standard.string(forKey: Self.gatedKey)) { return true }
            guard ai.status == .available, !((try? await ledger.reflectionDays(waiting: true)) ?? []).isEmpty else { return nil }
            return false
        }
        guard await due() != nil else { return }
        await exclusive { [self] in
            guard let all = await due() else { return }
            var done = await pipeline.regateReflections(all: all)
            // Onboarding gates its own answers while it's open.
            if all, profile?.onboardingDoneAt != nil, let old = try? await ledger.latestStarter() {
                let s = await pipeline.regate(starter: old, knownName: profile?.address ?? "")
                if let s, s != old, await saveStarter(s) {
                    // Pages that kept the old first prompt lose it too: it quotes an answer no longer clear.
                    if let gone = old.firstPrompt, gone != starter?.firstPrompt { try? await ledger.dropPrompts(question: gone) }
                    await saveProfile { $0.follow(picks: old.storable.picks, to: s.storable.picks) }
                } else if s != old {
                    done = false
                }
            }
            if all, done { UserDefaults.standard.set(mark, forKey: Self.gatedKey) }
        }
    }

    func completeOnboarding() async { await saveProfile { $0.onboardingDoneAt = .now } }

    /// Settings → Replay Onboarding: the window goes back to the welcome door; the journal is untouched.
    func replayOnboarding() async { await saveProfile { $0.onboardingDoneAt = nil } }

    /// Pausing opens a memory_pause window and resuming closes it, in the profile's own write.
    func setMemoryPaused(_ paused: Bool) async { await saveProfile { $0.memoryPaused = paused } }

    /// The question a recording or a page starts from: the person's own first prompt until there is an entry, then
    /// today's reading question (never on a held day), then their tone's line, then the web's fallback.
    var todaysPrompt: String {
        if days.isEmpty, let first = starter?.firstPrompt, !first.isEmpty { return first }
        if isToday, !isDayHeld, dayStatus == .ready, let q = dayReading?.payload.reading.question, !q.isEmpty { return q }
        return FirstPrompt.opening(nil, tone: profile?.tone, name: profile?.address)
    }
}
