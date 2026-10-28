import Foundation
import SaroKit

extension AppModel {
    /// Onboarding shows while the profile isn't done. A demo or snapshot run skips it unless `-SaroOnboarding YES`
    /// asks for it, even in the moment before its seed marks it done.
    var showsOnboarding: Bool {
        let d = UserDefaults.standard
        return profile?.onboardingDoneAt == nil && !((isDemo || d.string(forKey: "SaroSnapshot") != nil) && !d.bool(forKey: "SaroOnboarding"))
    }

    enum FirstMode { case moment, voice, write }

    var firstQuestion: String { FirstPrompt.opening(starter?.firstPrompt, tone: profile?.tone, name: profile?.address) }

    /// The first reflection on today, once onboarding is done: the moment recorder or the voice pill under the question,
    /// or a writing page whose prompt row is the question. A replay from a past day comes back to today first.
    func startFirstReflection(_ mode: FirstMode) async {
        let prompt = handoffPrompt ?? firstQuestion
        await land(on: LocalDay.today())
        switch mode {
        case .moment, .voice:
            handoffPrompt = prompt
            recorderKind = mode == .moment ? .moment : .voice
        case .write:
            // The page reads its prompt row; the question is held only until the page is open.
            defer { handoffPrompt = nil }
            guard let e = await newWriting(day: LocalDay.today()) else { return }
            await keepPrompt(prompt, entryId: e.id, day: e.localDay)
            openEntryID = e.id
        }
    }

    /// A prompted entry's prompt row: the question it answered, for the page's header and the Book.
    func keepPrompt(_ question: String, entryId: String, day: String) async {
        let generator = question == starter?.firstPrompt ? "heuristic" : "curated"
        do {
            try await ledger.insertTurn(ReflectionTurn(kind: .prompt, question: question, generator: generator, localDay: day, entryId: entryId))
            // The day's prompts were read when the new page's entry landed, before this row: read them again for its header.
            await CaptureUI.shared.loadPrompts(self)
        } catch {
            show(.failed("Couldn’t keep today’s prompt with your page", error))
        }
    }
}
