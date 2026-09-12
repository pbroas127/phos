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
        settings.planID = "john"
        settings.planPositions = ["john": 2]
        settings.passUses = [PassUse(date: Date().addingTimeInterval(-8 * 86_400), minutes: 20)]
        settings.rules.middayQuestions = 1
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
                                                 completedAt: Date().addingTimeInterval(-5 * 3600), readingSeconds: 390, fromPlan: true)]
            settings.planPositions = ["john": 3]
            store.settings = settings
            if DemoScreen.requested == .recall { today.middayPending = true }
            if DemoScreen.requested == .unlocked { today.unlockedUntil = Date().addingTimeInterval(22 * 60) }
        }
        store.storedToday = today

        var snap = SharedSnapshot()
        snap.streak = 11
        snap.chapterTitle = "John 3"
        snap.lockedCount = 4
        store.snapshot = snap
    }

    static var usage: WeeklyUsage {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let minutes: [Double] = [96, 84, 71, 66, 52, 41, 34]
        let days = (0..<7).map { i in
            WeeklyUsage.Day(date: cal.date(byAdding: .day, value: i - 6, to: today) ?? today, seconds: minutes[i] * 60)
        }
        return WeeklyUsage(
            thisWeek: days,
            thisWeekTotal: minutes.reduce(0, +) * 60,
            lastWeekTotal: 12.4 * 3600,
            topApps: [.init(name: "Instagram", seconds: 2.2 * 3600), .init(name: "TikTok", seconds: 1.6 * 3600),
                      .init(name: "YouTube", seconds: 58 * 60), .init(name: "X", seconds: 24 * 60)]
        )
    }
}

/// Screens the screenshot workflow can open directly with -screen name.
enum DemoScreen: String {
    case today, path, calendar, reading, reflect, speak, quizChoice, quizBlank, quizOrder, pass, missed, recall, unlocked
    case streak, time, journal, settings, shield, focus, recite

    static var requested: DemoScreen? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return nil }
        return DemoScreen(rawValue: args[i + 1])
    }

    static var startTab: Int {
        switch requested {
        case .streak, .time, .journal: return 1
        case .settings: return 2
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
        case .today, .path, .calendar, .streak, .time, .journal, .settings, .unlocked:
            MainTabs()
        case .reading:
            flow { InAppRead(ref: john3, remaining: 0) {} }
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
            flow { PickTimeView(title: "5 of 5 correct", subtitle: "Your apps open for") {} }
        case .missed:
            let missed = (QuestionBank.shared.questions(for: john3)?.questions ?? []).filter { $0.v == 14 || $0.v == 23 }
            flow { MissedView(ref: john3, score: 2, total: 5, missed: Array(missed.prefix(2)), onRetry: {}, onReread: {}) }
        case .recall:
            RecallFlow()
        case .shield:
            ShieldPreview(style: .verse, large: true).ignoresSafeArea()
        case .focus:
            FocusSessionView()
        case .recite:
            ReciteView()
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
