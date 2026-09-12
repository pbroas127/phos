import ManagedSettings
import UserNotifications

/// A shield cannot open another app, so the unlock button posts a notification that opens Phos.
class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(action, completionHandler)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(action, completionHandler)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(action, completionHandler)
    }

    private func respond(_ action: ShieldAction, _ done: @escaping (ShieldActionResponse) -> Void) {
        guard action == .primaryButtonPressed else {
            done(.close)
            return
        }
        let snap = SharedStore.shared.snapshot
        let content = UNMutableNotificationContent()
        switch snap.reason {
        case .evening:
            content.title = "Evening lock is on"
            content.body = "Tap to open Phos. Emergency passes are there if you really need one."
        case .midday:
            content.title = "Your midday question"
            content.body = "Tap to answer one question about \(snap.chapterTitle)."
        case .recall:
            content.title = "One question"
            content.body = "Tap to answer a question about \(snap.chapterTitle) and open your apps."
        case .reading, .none:
            content.title = "Today: \(snap.chapterTitle)"
            content.body = "Tap to read, reflect, and unlock your apps."
        }
        content.sound = .default
        content.userInfo = ["route": snap.reason.rawValue]
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: ["phos.shield"])
        let request = UNNotificationRequest(identifier: "phos.shield", content: content, trigger: nil)
        center.add(request) { _ in
            done(.close)
        }
    }
}
