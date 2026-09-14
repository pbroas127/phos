import ManagedSettings
import UserNotifications

/// A shield cannot open another app, so the button posts a notification that opens Phos.
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
        case .strict, .usedUp:
            content.title = "Emergency passes"
            content.body = "Tap to open Wick if you really need in."
        case .recall:
            content.title = "One question"
            content.body = "Tap to answer a question about \(snap.chapterTitle)."
        case .tap:
            content.title = "Ready to unlock"
            content.body = "Tap to open Wick and unlock."
        case .reading, .none:
            content.title = "Today: \(snap.chapterTitle)"
            content.body = "Tap to read, reflect, and unlock your apps."
        }
        content.sound = .default
        content.userInfo = ["route": snap.reason.rawValue]
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: ["phos.shield"])
        center.add(UNNotificationRequest(identifier: "phos.shield", content: content, trigger: nil)) { _ in
            done(.close)
        }
    }
}
