import FamilyControls
import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Draws the screen people see when they open a locked app, in light and dark.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private var isDark: Bool { UITraitCollection.current.userInterfaceStyle == .dark }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        make(name: application.localizedDisplayName, lock: lock { sel in application.token.map { sel.applicationTokens.contains($0) } ?? false })
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        make(name: application.localizedDisplayName ?? category.localizedDisplayName,
             lock: lock { sel in category.token.map { sel.categoryTokens.contains($0) } ?? false })
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        make(name: webDomain.domain, lock: lock { sel in webDomain.token.map { sel.webDomainTokens.contains($0) } ?? false })
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        make(name: webDomain.domain ?? category.localizedDisplayName,
             lock: lock { sel in category.token.map { sel.categoryTokens.contains($0) } ?? false })
    }

    /// The lock that contains this app, preferring the one that is locked right now.
    private func lock(_ matches: (FamilyActivitySelection) -> Bool) -> LockSet? {
        let store = SharedStore.shared
        let settings = store.settings
        let today = store.today(morning: settings.schedule.morning)
        let candidates = settings.lockSets.filter { set in
            guard let data = set.selection, let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return false }
            return matches(sel)
        }
        return candidates.first { LockLogic.state($0, today: today, now: Date()).isLocked } ?? candidates.first
    }

    private func make(name: String?, lock: LockSet?) -> ShieldConfiguration {
        let store = SharedStore.shared
        let snap = store.snapshot
        let today = store.today(morning: store.settings.schedule.morning)
        let app = name ?? "This app"
        let state = lock.map { LockLogic.state($0, today: today, now: Date()) } ?? .needsReading
        let reward = lock.map { LockSet.rewardLabel($0.rewardSeconds).lowercased() } ?? "a while"

        let title: String
        let subtitle: String
        let button: String

        switch state {
        case .strict:
            let end = lock.map { LockLogic.activeEnd($0, now: Date()) }
            let f = DateFormatter()
            f.timeStyle = .short
            title = end.map { "Locked until \(f.string(from: $0))" } ?? "Locked for now"
            subtitle = "\(lock?.name ?? "This lock") is strict. Only an emergency pass opens \(app)."
            button = "Open Phos"
        case .usedUp:
            title = "No unlocks left today"
            subtitle = "\(lock?.name ?? "This lock") allows \(lock?.limit ?? 0) a day. Emergency passes are in Phos."
            button = "Open Phos"
        case .needsQuestion:
            title = "\(app) is resting"
            subtitle = "One question about \(snap.chapterTitle) opens it for \(reward)."
            button = "Answer a question"
        case .needsTap:
            title = "\(app) is resting"
            subtitle = "You read today. Unlock it for \(reward) from Phos."
            button = "Unlock"
        case .needsReading, .open, .inactive:
            switch snap.style {
            case .verse:
                title = "\(app) can wait"
                subtitle = "“\(snap.verseText)”\n\(snap.verseRef)"
            case .streak:
                title = snap.streak > 0 ? "Day \(snap.streak + 1) is waiting" : "Start your streak"
                subtitle = "Read \(snap.chapterTitle) to open \(app)."
            case .quiet:
                title = "Read first"
                subtitle = "\(app) opens after today's chapter."
            }
            button = "Read today's chapter"
        }

        // Colors are picked for the current appearance directly. Dynamic colors and blur get washed out by the system.
        let dark = isDark
        let background = dark ? rgb(0x15120E) : rgb(0xFBF9F4)
        let ink = dark ? rgb(0xF4EEE3) : rgb(0x221D17)
        let dim = dark ? rgb(0xB9AD9B) : rgb(0x8A7F71)
        let gold = dark ? rgb(0xE0AE4B) : rgb(0xA87A22)
        let onGold = dark ? rgb(0x1B1307) : rgb(0xFFFFFF)
        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: background,
            icon: UIImage(named: dark ? "ShieldIconDark" : "ShieldIcon"),
            title: ShieldConfiguration.Label(text: title, color: ink),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: dim),
            primaryButtonLabel: ShieldConfiguration.Label(text: button, color: onGold),
            primaryButtonBackgroundColor: gold,
            secondaryButtonLabel: nil
        )
    }
}
