import AppKit
import SaroKit
import UserNotifications

/// Local notifications, no server (FR-ONB-04): one repeating ritual reminder per chosen weekday, with Voice and Write
/// actions, and the evening letter. Every one is content-free, so nothing of the journal shows on a locked screen or
/// a shared one. A click opens a `saro://` link.
@MainActor
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminders()

    static let title = "A minute for today?"
    static let body = "Your minute is here whenever you are."
    static let letterTitle = "Your evening letter is here."
    static let letterBody = "It’s ready whenever you are."

    private static let ritualCategory = "ritual"
    private static let letterCategory = "letter"
    private var center: UNUserNotificationCenter { .current() }

    /// Where a clicked notification's link goes; one that arrives before the window is up waits for it.
    var route: ((URL) -> Void)? {
        didSet {
            guard let route, let pending else { return }
            self.pending = nil
            route(pending)
        }
    }
    private var pending: URL?

    /// At launch: the delegate, the Voice and Write actions, and (for the real journal) the schedule as the prefs say.
    func install() {
        center.delegate = self
        let voice = UNNotificationAction(identifier: "voice", title: "Voice", options: [.foreground])
        let write = UNNotificationAction(identifier: "write", title: "Write", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.ritualCategory, actions: [voice, write], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.letterCategory, actions: [], intentIdentifiers: []),
        ])
        scheduleRitual()
    }

    func status() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }

    /// Asks once, from the click that turns a reminder on; afterwards the standing answer.
    func request() async -> Bool {
        let now = await status()
        guard now == .notDetermined else { return now == .authorized || now == .provisional }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// The ritual reminder, word for word, in a second.
    func sendTest() async {
        try? await center.add(UNNotificationRequest(identifier: "saro-ritual-test", content: ritualContent(),
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    /// Replaces every ritual reminder with the ones the prefs ask for (none while the reminder is off). Synchronous, so
    /// two calls can't interleave and leave a reminder on a weekday just turned off.
    func scheduleRitual(_ prefs: Prefs = PrefsStore.shared.prefs) {
        // ponytail: a demo journal shares the bundle id, so it leaves the real schedule alone; sendTest still works there.
        guard !PrefsStore.isDemo else { return }
        center.removePendingNotificationRequests(withIdentifiers: (1...7).map { "saro-ritual-\($0)" })
        for r in Self.requests(for: prefs) {
            center.add(UNNotificationRequest(identifier: r.id, content: ritualContent(),
                                             trigger: UNCalendarNotificationTrigger(dateMatching: r.components, repeats: true)),
                       withCompletionHandler: nil)
        }
    }

    static func requests(for prefs: Prefs) -> [(id: String, components: DateComponents)] { prefs.ritualRequests }

    /// The evening letter's notification for `day`, at `date` (straight away if that has passed). The caller checks the
    /// day may have one: never on a held day or one awaiting a check (SR-13, SR-14).
    func scheduleLetter(day: String, at date: Date) async {
        guard !PrefsStore.isDemo else { return }
        let content = UNMutableNotificationContent()
        content.title = Self.letterTitle
        content.body = Self.letterBody
        content.categoryIdentifier = Self.letterCategory
        content.userInfo = ["url": DeepLink.letter(day).url.absoluteString]
        let trigger: UNNotificationTrigger = date > .now.addingTimeInterval(1)
            ? UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date), repeats: false)
            : UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "saro-letter-\(day)", content: content, trigger: trigger))
    }

    func cancelLetter(day: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["saro-letter-\(day)"])
        center.removeDeliveredNotifications(withIdentifiers: ["saro-letter-\(day)"])
    }

    /// Erase (DR-16): nothing pending, nothing left in Notification Center.
    func removeAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private func ritualContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = Self.title
        content.body = Self.body
        content.categoryIdentifier = Self.ritualCategory
        return content
    }

    /// Voice and Write open the recorder or a page on today; the notification itself opens today, or its letter.
    nonisolated static func url(action: String, userInfo: [AnyHashable: Any]) -> URL {
        switch action {
        case "voice": DeepLink.capture(.voice).url
        case "write": DeepLink.capture(.reflection).url
        default: (userInfo["url"] as? String).flatMap(URL.init(string:)) ?? DeepLink.day(LocalDay.today()).url
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// A banner even while Saro is frontmost.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .list] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let url = Self.url(action: response.actionIdentifier, userInfo: response.notification.request.content.userInfo)
        await MainActor.run { open(url) }
    }

    private func open(_ url: URL) {
        NSApp.activate()
        if let route { route(url) } else { pending = url }
    }
}
