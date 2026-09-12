import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Draws the screen people see when they open a locked app.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private let ink = UIColor(red: 0x22 / 255, green: 0x1D / 255, blue: 0x17 / 255, alpha: 1)
    private let dim = UIColor(red: 0x8A / 255, green: 0x7F / 255, blue: 0x71 / 255, alpha: 1)
    private let gold = UIColor(red: 0xA8 / 255, green: 0x7A / 255, blue: 0x22 / 255, alpha: 1)
    private let paper = UIColor(red: 0xFB / 255, green: 0xF9 / 255, blue: 0xF4 / 255, alpha: 1)

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        make(name: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        make(name: application.localizedDisplayName ?? category.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        make(name: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        make(name: webDomain.domain ?? category.localizedDisplayName)
    }

    private func make(name: String?) -> ShieldConfiguration {
        let snap = SharedStore.shared.snapshot
        let app = name ?? "This app"
        let title: String
        let subtitle: String
        let button: String
        let hint = "\n\nTap below, then tap the Phos notification."

        switch snap.reason {
        case .evening:
            title = "Evening lock is on"
            subtitle = "Your apps rest until morning. Emergency passes are in Phos." + hint
            button = "Open Phos"
        case .midday:
            title = "Midday question"
            subtitle = "One question about \(snap.chapterTitle) opens \(app)." + hint
            button = "Answer the question"
        case .recall:
            title = "\(app) is resting"
            subtitle = "Answer one question about \(snap.chapterTitle) to open it again." + hint
            button = "Answer a question"
        case .reading, .none:
            switch snap.style {
            case .verse:
                title = "\(app) is locked"
                subtitle = "“\(snap.verseText)”\n\(snap.verseRef)" + hint
                button = "Unlock with today's reading"
            case .streak:
                if snap.streak > 0 {
                    title = "Day \(snap.streak + 1) is waiting"
                    subtitle = "Read \(snap.chapterTitle) to keep your \(snap.streak) day streak and open \(app)." + hint
                } else {
                    title = "Start your streak"
                    subtitle = "Read \(snap.chapterTitle) to open \(app)." + hint
                }
                button = "Keep my streak"
            case .quiet:
                title = "Locked until you read"
                subtitle = "Phos opens your apps after today's chapter." + hint
                button = "Open Phos"
            }
        }

        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: paper,
            icon: UIImage(named: "ShieldIcon"),
            title: ShieldConfiguration.Label(text: title, color: ink),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: dim),
            primaryButtonLabel: ShieldConfiguration.Label(text: button, color: .white),
            primaryButtonBackgroundColor: gold,
            secondaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: gold)
        )
    }
}
