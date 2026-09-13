import UIKit

/// The words on a locked app's screen.
struct ShieldCopy {
    var eyebrow: String
    var title: String
    var body: String
    var isVerse: Bool
    var reference: String?
    var button: String
    /// For locks with a daily limit: unlocks remaining and the daily total.
    var unlocksLeft: Int? = nil
    var unlockLimit: Int? = nil
}

/// Words and colors for the locked app screen, shared by the real shield and the preview in Settings.
enum ShieldArt {
    struct Palette {
        let background: UIColor
        let eyebrow: UIColor
        let title: UIColor
        let body: UIColor
        let reference: UIColor
        let buttonFill: UIColor
        let buttonLabel: UIColor
    }

    static func hex(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    static func palette(_ theme: ShieldTheme) -> Palette {
        switch theme {
        case .dark:
            return Palette(background: hex(0x15120E), eyebrow: hex(0xD4A84B), title: hex(0xF6F1E7), body: hex(0xCFC6B6),
                           reference: hex(0xC9A04A), buttonFill: hex(0xF6F1E7), buttonLabel: hex(0x15120E))
        case .light:
            return Palette(background: hex(0xFBF9F4), eyebrow: hex(0x8A6318), title: hex(0x221D17), body: hex(0x4A4238),
                           reference: hex(0x8A6318), buttonFill: hex(0x221D17), buttonLabel: hex(0xFBF9F4))
        }
    }

    static func copy(state: LockLogic.State, lock: LockSet?, app: String, snap: SharedSnapshot, today: TodayState? = nil, now: Date = Date()) -> ShieldCopy {
        var c = baseCopy(state: state, lock: lock, app: app, snap: snap, now: now)
        if let lock, lock.policy == .limited, state != .strict, state != .inactive {
            c.unlockLimit = lock.limit
            c.unlocksLeft = max(0, lock.limit - (today?.day(lock.id).count ?? 0))
        }
        return c
    }

    /// Filled dots for unlocks left, empty dots for ones used today.
    static func dots(left: Int, total: Int) -> String {
        let shown = min(total, 10)
        let filled = min(left, shown)
        return (Array(repeating: "●", count: filled) + Array(repeating: "○", count: shown - filled)).joined(separator: " ")
    }

    static func unlocksLabel(_ left: Int) -> String {
        left == 0 ? "No unlocks left today" : left == 1 ? "1 unlock left" : "\(left) unlocks left"
    }

    private static func baseCopy(state: LockLogic.State, lock: LockSet?, app: String, snap: SharedSnapshot, now: Date) -> ShieldCopy {
        let chapter = snap.chapterTitle
        switch state {
        case .strict:
            let f = DateFormatter()
            f.timeStyle = .short
            let time = lock.map { f.string(from: LockLogic.activeEnd($0, now: now)) } ?? "later"
            return ShieldCopy(eyebrow: lock?.name ?? "Strict hours", title: "Rest now.",
                              body: "\(app) opens again at \(time).", isVerse: false, reference: nil, button: "Open Phos")
        case .usedUp:
            return ShieldCopy(eyebrow: "Daily limit reached", title: "Enough for today.",
                              body: "Unlocks reset at midnight. Rest in what you read.", isVerse: false, reference: nil, button: "Open Phos")
        case .needsQuestion:
            return ShieldCopy(eyebrow: "Almost there", title: "One question left.",
                              body: "Answer one question about \(chapter) to open \(app).", isVerse: false, reference: nil,
                              button: "Answer the question")
        case .needsTap:
            let reward = lock.map { LockSet.rewardLabel($0.rewardSeconds).lowercased() } ?? "a while"
            let forText = lock?.rewardSeconds == LockSet.untilEnd ? "until this lock ends" : "for \(reward)"
            return ShieldCopy(eyebrow: "Chapter read", title: "Well done.",
                              body: "You read \(chapter) today. \(app) opens \(forText).", isVerse: false, reference: nil,
                              button: app.count <= 14 ? "Unlock \(app)" : "Unlock")
        case .needsReading, .open, .inactive:
            switch snap.style {
            case .verse:
                return ShieldCopy(eyebrow: "Today · \(chapter)", title: "\(app) can wait.",
                                  body: snap.verseText, isVerse: true, reference: snap.verseRef, button: "Read \(chapter)")
            case .streak:
                return ShieldCopy(eyebrow: snap.streak > 0 ? "\(snap.streak) day streak" : "Today · \(chapter)",
                                  title: snap.streak > 0 ? "Keep it going." : "Start today.",
                                  body: "Read \(chapter) to keep your streak and open \(app).", isVerse: false, reference: nil,
                                  button: "Read \(chapter)")
            case .quiet:
                return ShieldCopy(eyebrow: "Today · \(chapter)", title: "Read first.",
                                  body: "\(app) opens after \(chapter).", isVerse: false, reference: nil, button: "Read \(chapter)")
            }
        }
    }

    /// The system shield draws the icon at up to about 80pt tall, so the emblem alone fills it.
    static func emblem(_ theme: ShieldTheme) -> UIImage? {
        UIImage(named: theme == .dark ? "EmblemDark" : "EmblemLight")
    }

    /// Subtitle text for the system shield: the verse with its reference, or the state message.
    static func subtitle(_ c: ShieldCopy) -> String {
        var text = c.isVerse ? "“\(c.body)”\n\(c.reference ?? "")" : c.body
        // iOS lays out the shield itself, so blank lines are the only way to set the dots apart from the verse.
        if let left = c.unlocksLeft, let total = c.unlockLimit {
            text += "\n\n\n\(dots(left: left, total: total))\n\(unlocksLabel(left))"
        }
        return text
    }
}
