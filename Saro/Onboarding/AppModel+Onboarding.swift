import Foundation
import SaroKit

extension AppModel {
    /// Onboarding shows while the profile isn't done. A demo or snapshot journal skips it unless `-SaroOnboarding YES`
    /// asks for it, even in the moment before its seed marks it done.
    var showsOnboarding: Bool {
        profile?.onboardingDoneAt == nil && !(isDemo && !UserDefaults.standard.bool(forKey: "SaroOnboarding"))
    }

    enum FirstMode { case moment, voice, write }

    /// The first reflection, once onboarding is done: the moment recorder, the voice pill, or a writing page whose
    /// prompt row is the question. The prompt is read first: the new page itself makes it a journal with entries.
    func startFirstReflection(_ mode: FirstMode) async {
        let prompt = todaysPrompt
        pane = .day
        switch mode {
        case .moment: recorderKind = .moment
        case .voice: recorderKind = .voice
        case .write:
            guard let e = await newWriting(day: LocalDay.today()) else { return }
            let generator = prompt == starter?.firstPrompt ? "heuristic" : "curated"
            do {
                try await ledger.insertTurn(ReflectionTurn(kind: .prompt, question: prompt, generator: generator, localDay: e.localDay, entryId: e.id))
            } catch {
                show(Toast("Couldn’t keep today’s prompt with your page: \(error.localizedDescription)", style: .error))
            }
            openEntryID = e.id
        }
    }
}
