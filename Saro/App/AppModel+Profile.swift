import SaroKit

extension AppModel {
    /// Reads the profile and the current starter context. Saves that land meanwhile win: an older read never replaces them.
    func loadProfile() async {
        do {
            let p = try await ledger.profile()
            if profile.map({ p.updatedAt >= $0.updatedAt }) ?? true { profile = p }
            starter = try await ledger.latestStarter()
        } catch {
            show(Toast("Couldn't read your profile: \(error.localizedDescription)", style: .error))
        }
    }

    /// Changes the profile row and saves it; on a failed write the change is dropped and says so.
    func saveProfile(_ change: (inout Profile) -> Void) async {
        do {
            var p = if let profile { profile } else { try await ledger.profile() }
            change(&p)
            try await ledger.saveProfile(p)
            profile = try await ledger.profile()
        } catch {
            show(Toast("Couldn't save your profile: \(error.localizedDescription)", style: .error))
        }
    }

    /// Saves this onboarding pass's starter context. `starter` becomes what was stored, so nothing derived from a held
    /// answer (its picks, or a personal first prompt) stays in memory either.
    func saveStarter(_ s: StarterContext) async {
        do {
            try await ledger.saveStarter(s)
            starter = try await ledger.latestStarter()
        } catch {
            starter = s.storable
            show(Toast("Couldn't save your answers on this Mac. They hold for this visit.", style: .error))
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
