import SwiftUI

/// Sample data for App Store screenshots. Only used with the -demoData launch argument.
enum DemoData {
    static let reflection = "Nicodemus came at night, which tells me he was afraid of what the other Pharisees would think. Jesus does not shame him for it. He tells him plainly that he must be born anew, and that God so loved the world. I keep my own questions hidden too, and I want to bring them into the light."

    static let pastReflections: [(String, String)] = [
        ("JHN.2", "The water became wine only after the servants filled the jars to the brim. They obeyed before they saw anything happen."),
        ("JHN.1", "The Word was with God and was God. I never noticed that John starts the same way Genesis does, in the beginning."),
        ("PRO.31", "The worthy woman gets up while it is still night. Strength and dignity are her clothing, and she laughs at the time to come."),
        ("PRO.30", "Give me neither poverty nor riches. Agur asks for just enough so he does not forget God or dishonor him."),
        ("PRO.29", "Where there is no revelation, the people cast off restraint. That is exactly what my phone does to my mornings."),
        ("PRO.28", "The wicked flee when no one pursues, but the righteous are as bold as a lion."),
        ("PRO.27", "As iron sharpens iron, so a man sharpens his friend's countenance. I need people like that."),
        ("PRO.26", "Like a dog that returns to his vomit is a fool who repeats his folly. Hard to read, but true about scrolling."),
        ("PRO.25", "It is the glory of God to conceal a thing, but the glory of kings to search out a matter."),
        ("PRO.24", "A little sleep, a little slumber, a little folding of the hands to sleep, and poverty comes like a robber."),
        ("PRO.23", "Do not wear yourself out to be rich. Riches sprout wings like an eagle and fly away.")
    ]

    static func seed(_ store: SharedStore) {
        var settings = AppSettings()
        settings.onboarded = true
        settings.onboardedAt = Date().addingTimeInterval(-30 * 86_400)
        settings.planID = "book.JHN"
        settings.planPositions = ["book.JHN": 2, "book.PRO": 31, "book.MRK": 5, "gospels": 12]

        var social = LockSet()
        social.id = "social"
        social.name = "Social media"
        social.appCount = 4
        social.policy = .questionEach
        social.rewardSeconds = 1800
        let code = Passcode.make("2468")
        social.protection.kind = .passcode
        social.protection.passcodeHash = code.hash
        social.protection.passcodeSalt = code.salt
        social.protection.blockDeletion = true

        var games = LockSet()
        games.id = "games"
        games.name = "Games and video"
        games.appCount = 3
        games.days = [2, 3, 4, 5, 6]
        games.policy = .limited
        games.limit = 3
        games.rewardSeconds = 900
        games.protection.kind = .countdown
        games.protection.countdownMinutes = 5

        var night = LockSet()
        night.id = "bedtime"
        night.name = "Bedtime"
        night.appCount = 7
        night.allDay = false
        night.start = TimeOfDay(hour: 22, minute: 0)
        night.end = TimeOfDay(hour: 6, minute: 0)
        night.policy = .strict
        night.protection.kind = .commitment
        night.protection.commitUntil = Date().addingTimeInterval(21 * 86_400)

        settings.lockSets = [social, games, night]
        settings.passUses = [PassUse(date: Date().addingTimeInterval(-8 * 86_400), minutes: 15, lockID: "social")]
        store.settings = settings

        let todayKey = DayKey.key(for: Date(), morning: settings.schedule.morning)
        var records: [DayRecord] = []
        for (i, entry) in pastReflections.enumerated() {
            let key = DayKey.adding(-(i + 1), to: todayKey)
            let parts = entry.0.split(separator: ".")
            let ref = ChapterRef(book: String(parts[0]), chapter: Int(parts[1]) ?? 1)
            let date = (DayKey.localDate(from: key) ?? Date()).addingTimeInterval(-4 * 3600 + Double(i * 600))
            records.append(DayRecord(dayKey: key, ref: ref, title: BookNames.title(ref), readMode: i % 3 == 0 ? .inApp : .paper,
                                     reflectMode: i % 2 == 0 ? .spoken : .typed, reflection: entry.1, score: 4 + (i % 2),
                                     total: 5, completedAt: date, readingSeconds: 300 + i * 37, fromPlan: true))
        }
        store.records = records

        var today = TodayState(dayKey: todayKey)
        today.readingStartedAt = Date().addingTimeInterval(-200)
        if DemoScreen.requested == .recall || DemoScreen.requested == .unlocked {
            today.readingDone = true
            today.chapter = ChapterRef(book: "JHN", chapter: 3)
            store.records = records + [DayRecord(dayKey: todayKey, ref: ChapterRef(book: "JHN", chapter: 3), title: "John 3",
                                                 readMode: .paper, reflectMode: .spoken, reflection: reflection, score: 5, total: 5,
                                                 completedAt: Calendar.current.date(bySettingHour: 7, minute: 48, second: 0, of: Date()) ?? Date(),
                                                 readingSeconds: 390, fromPlan: true)]
            settings.planPositions["book.JHN"] = 3
            store.settings = settings
            var gamesDay = LockDay()
            gamesDay.count = 1
            today.unlocks["games"] = gamesDay
            if DemoScreen.requested == .unlocked {
                var socialDay = LockDay()
                socialDay.until = Date().addingTimeInterval(22 * 60)
                socialDay.count = 1
                today.unlocks["social"] = socialDay
            }
        }
        store.storedToday = today

        var snap = SharedSnapshot()
        snap.streak = 11
        snap.chapterTitle = "John 3"
        snap.lockedCount = 4
        snap.verseText = "Your word is a lamp to my feet, and a light for my path."
        snap.verseRef = "Psalm 119:105"
        store.snapshot = snap
    }

    static var usage: WeeklyUsage {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let thisWeek: [Double] = [96, 84, 71, 66, 52, 41, 34]
        let lastWeek: [Double] = [118, 132, 104, 97, 121, 88, 92]
        var totals: [Date: TimeInterval] = [:]
        var all: [Date: TimeInterval] = [:]
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: i - 6, to: today) ?? today
            let prior = cal.date(byAdding: .day, value: -7, to: d) ?? d
            totals[d] = thisWeek[i] * 60
            totals[prior] = lastWeek[i] * 60
            all[d] = (thisWeek[i] + 150 + Double(i * 9)) * 60
            all[prior] = (lastWeek[i] + 170) * 60
        }
        let split: [(String, Double, Double)] = [("Instagram", 0.34, 0.41), ("TikTok", 0.27, 0.30), ("YouTube", 0.21, 0.16), ("X", 0.10, 0.09), ("Snapchat", 0.08, 0.04)]
        var appDays: [String: [Date: TimeInterval]] = [:]
        for (name, share, lastShare) in split {
            for i in 0..<7 {
                let d = cal.date(byAdding: .day, value: i - 6, to: today) ?? today
                let prior = cal.date(byAdding: .day, value: -7, to: d) ?? d
                appDays[name, default: [:]][d] = thisWeek[i] * 60 * share
                appDays[name, default: [:]][prior] = lastWeek[i] * 60 * lastShare
            }
        }
        return WeeklyUsage.build(dayTotals: totals, allDayTotals: all, appDays: appDays, now: Date(), calendar: cal)
    }
}

/// Screens the screenshot workflow can open directly with -screen name.
enum DemoScreen: String {
    case today, path, calendar, reading, reflect, speak, quizChoice, quizBlank, quizOrder, pass, missed, recall, unlocked
    case streak, time, journal, settings, shield
    case library, book, locks, lockEditor, protection, trophies, readAloud, listen

    static var requested: DemoScreen? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return nil }
        return DemoScreen(rawValue: args[i + 1])
    }

    static var startTab: Int {
        switch requested {
        case .streak, .time, .journal: return 1
        case .settings, .lockEditor: return 2
        case .trophies: return 3
        default: return 0
        }
    }

    static var todayView: TodayScreen.Mode {
        switch requested {
        case .path: return .path
        case .calendar: return .calendar
        default: return .plan
        }
    }

    static var progressTab: ProgressScreen.Tab {
        switch requested {
        case .time: return .time
        case .journal: return .journal
        default: return .streak
        }
    }
}

struct DemoRouter: View {
    @Environment(AppModel.self) private var model
    let screen: DemoScreen
    private let john3 = ChapterRef(book: "JHN", chapter: 3)

    var body: some View {
        switch screen {
        case .today, .path, .calendar, .streak, .time, .journal, .settings, .unlocked, .library, .lockEditor, .trophies:
            MainTabs()
        case .book:
            NavigationStack { PathDetailView(planID: "book.MRK") { _ in } }
        case .locks:
            NavigationStack { LockDetailView(lockID: "social") }
        case .protection:
            NavigationStack { LockDetailView(lockID: "games") }
        case .reading:
            flow { InAppRead(ref: john3, remaining: 0) {} }
        case .readAloud:
            flow { SpeakRead(ref: john3) {} }
        case .listen:
            flow { ListenRead(ref: john3, remaining: 0) {} }
        case .reflect:
            flow { ReflectStep(ref: john3, mode: .constant(.typed), text: .constant(DemoData.reflection)) {} }
        case .speak:
            flow { ReflectStep(ref: john3, mode: .constant(.spoken), text: .constant("")) {} }
        case .quizChoice:
            flow { QuizRunner(items: demoItems(.choice)) { _, _ in } }
        case .quizBlank:
            flow { QuizRunner(items: demoItems(.blank)) { _, _ in } }
        case .quizOrder:
            flow { QuizRunner(items: demoItems(.order)) { _, _ in } }
        case .pass:
            flow { UnlockSummary(title: "5 of 5 correct") {} }
                .onAppear { model.lastUnlocked = model.locks.filter { $0.policy != .strict } }
        case .missed:
            let missed = (QuestionBank.shared.questions(for: john3)?.questions ?? []).filter { $0.v == 14 || $0.v == 23 }
            flow { MissedView(ref: john3, score: 2, total: 5, missed: Array(missed.prefix(2)), onRetry: {}, onReread: {}) }
        case .recall:
            UnlockCenter()
        case .shield:
            ShieldPreview(style: .verse, large: true).ignoresSafeArea()
        }
    }

    private func flow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            FlowHeader(title: "John 3", subtitle: "Today's reading") {}
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
            content()
        }
        .background(Theme.paper.ignoresSafeArea())
    }

    private func demoItems(_ first: Question.Kind) -> [QuizItem] {
        var g = SeededGenerator(seed: 7)
        let bank = QuestionBank.shared.questions(for: john3)?.questions ?? []
        let lead = bank.filter { $0.t == first }.prefix(1)
        let rest = bank.filter { $0.t != first }.prefix(4)
        return (Array(lead) + Array(rest)).map { QuizEngine.item(for: $0, using: &g) }
    }
}
