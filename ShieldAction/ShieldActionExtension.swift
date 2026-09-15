import FamilyControls
import ManagedSettings
import UserNotifications

/// A shield cannot open another app, so the button posts a notification that opens Wick.
class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(action, lock: lock { $0.applicationTokens.contains(application) }, completionHandler)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(action, lock: lock { $0.webDomainTokens.contains(webDomain) }, completionHandler)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(action, lock: lock { $0.categoryTokens.contains(category) }, completionHandler)
    }

    /// The lock that holds the tapped app, preferring one that is locked right now.
    private func lock(_ matches: (FamilyActivitySelection) -> Bool) -> LockSet? {
        let store = SharedStore.shared
        let settings = store.settings
        let today = store.today(morning: settings.schedule.morning)
        let yesterday = store.previousDay(before: today.dayKey)
        let candidates = settings.lockSets.filter { set in
            guard let data = set.selection, let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return false }
            return matches(sel)
        }
        return candidates.first {
            LockLogic.state($0, today: today, yesterday: yesterday, now: Date(), morning: settings.schedule.morning).isLocked
        } ?? candidates.first
    }

    private func respond(_ action: ShieldAction, lock: LockSet?, _ done: @escaping (ShieldActionResponse) -> Void) {
        guard action == .primaryButtonPressed else {
            done(.close)
            return
        }
        let store = SharedStore.shared
        let snap = store.snapshot
        let state: LockLogic.State
        if let lock {
            let morning = store.settings.schedule.morning
            let today = store.today(morning: morning)
            state = LockLogic.state(lock, today: today, yesterday: store.previousDay(before: today.dayKey), now: Date(), morning: morning)
        } else {
            state = Self.state(for: snap.reason)
        }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            // With notifications off the button cannot do anything, so the shield stays up and its text says to open Wick.
            guard settings.authorizationStatus != .denied else {
                done(.defer)
                return
            }
            let content = Self.content(state: state, lock: lock, chapter: snap.chapterTitle)
            center.removeDeliveredNotifications(withIdentifiers: ["phos.shield"])
            center.add(UNNotificationRequest(identifier: "phos.shield", content: content, trigger: nil)) { _ in
                done(.close)
            }
        }
    }

    private static func state(for reason: LockReason) -> LockLogic.State {
        switch reason {
        case .reading, .none: return .needsReading
        case .recall: return .needsQuestion
        case .tap: return .needsTap
        case .usedUp: return .usedUp
        case .strict: return .strict
        }
    }

    private static func content(state: LockLogic.State, lock: LockSet?, chapter: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let name = lock?.name ?? "your apps"
        var route = "read"
        switch state {
        case .strict:
            content.title = lock.map { "\($0.name) is resting" } ?? "Emergency passes"
            content.body = "Tap to open Wick and use a pass."
            route = "unlock"
        case .usedUp:
            content.title = "No unlocks left today"
            content.body = "Tap to open Wick and use a pass."
            route = "unlock"
        case .needsQuestion:
            content.title = "One question"
            content.body = "Tap to answer a question about \(chapter) and open \(name)."
        case .needsTap:
            content.title = "Ready to unlock"
            content.body = "You read today. Tap to open \(name)."
        case .needsReading, .open, .inactive:
            content.title = "Today: \(chapter)"
            content.body = "Tap to read, reflect, and open \(name). Emergency passes are in Wick too."
        }
        content.sound = .default
        content.userInfo = ["route": route]
        return content
    }
}
