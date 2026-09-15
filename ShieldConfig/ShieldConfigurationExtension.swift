import FamilyControls
import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Draws the screen people see when they open a locked app.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
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
        let morning = settings.schedule.morning
        let today = store.today(now: TrustedClock.now(), morning: morning)
        let yesterday = store.previousDay(before: today.dayKey)
        let candidates = settings.lockSets.filter { set in
            guard let data = set.selection, let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return false }
            return matches(sel)
        }
        return candidates.first { LockLogic.state($0, today: today, yesterday: yesterday, now: TrustedClock.now(), morning: morning).isLocked } ?? candidates.first
    }

    private func make(name: String?, lock: LockSet?) -> ShieldConfiguration {
        let store = SharedStore.shared
        let snap = store.snapshot
        let morning = store.settings.schedule.morning
        let today = store.today(now: TrustedClock.now(), morning: morning)
        let yesterday = store.previousDay(before: today.dayKey)
        let state = lock.map { LockLogic.state($0, today: today, yesterday: yesterday, now: TrustedClock.now(), morning: morning) } ?? .needsReading
        let copy = ShieldArt.copy(state: state, lock: lock, app: name ?? "This app", snap: snap, today: today,
                                  yesterday: yesterday, morning: morning)
        // Bedtime style locks always stay dark. Appearance cannot be read reliably inside a shield.
        let theme: ShieldTheme = state == .strict ? .dark : snap.theme
        let p = ShieldArt.palette(theme)
        // Title must be set, or iOS shows its own "Restricted" text. The light button keeps its label readable if iOS dims it.
        return ShieldConfiguration(
            backgroundBlurStyle: theme == .dark ? .dark : .extraLight,
            backgroundColor: p.background,
            icon: ShieldArt.emblem(theme),
            title: ShieldConfiguration.Label(text: copy.title, color: p.title),
            subtitle: ShieldConfiguration.Label(text: ShieldArt.subtitle(copy), color: p.body),
            primaryButtonLabel: ShieldConfiguration.Label(text: copy.button, color: p.buttonLabel),
            primaryButtonBackgroundColor: p.buttonFill,
            secondaryButtonLabel: nil
        )
    }
}
