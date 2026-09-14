import Foundation
import UserNotifications

/// Books the next week of daily reminders. Reruns whenever Wick opens or a reading finishes,
/// so messages always match the reader's real streak and chapter.
enum ReminderScheduler {
    static let prefix = "wick.reminder."

    static func reschedule(_ model: AppModel) {
        guard !model.demo else { return }
        let requests = model.settings.reminderOn ? build(model) : []
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
            for r in requests { center.add(r) }
        }
    }

    /// Sends one message right away, so the tone can be previewed from Settings.
    static func sendSample(_ model: AppModel) {
        let input = input(model)
        let plan = Reminders.plan(Reminders.Input(todayKey: input.todayKey, readToday: false, streak: input.streak, lastReadKey: input.lastReadKey,
                                                  totalChapters: input.totalChapters, chapter: input.chapter, title: input.title, plan: input.plan,
                                                  planLeft: input.planLeft, lockedApps: input.lockedApps, nextTrophy: input.nextTrophy,
                                                  weekday: input.weekday), days: 1)
        guard let first = plan.first else { return }
        let message = Reminders.message(first.context, seed: Int(Date().timeIntervalSince1970))
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "wick.sample", content: content, trigger: trigger))
    }

    private static func build(_ model: AppModel) -> [UNNotificationRequest] {
        let input = input(model)
        let cal = Calendar.current
        let now = Date()
        let minutes = model.settings.reminderMinutes
        let trophy = input.nextTrophy?.name ?? ""
        return Reminders.plan(input).compactMap { item in
            guard let day = cal.date(byAdding: .day, value: item.offset, to: cal.startOfDay(for: now)),
                  let fire = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  fire > now else { return nil }
            let key = DayKey.adding(item.offset, to: input.todayKey)
            let message = Reminders.message(item.context, trophy: trophy, seed: Reminders.seed(key + item.context.kind.rawValue))
            let content = UNMutableNotificationContent()
            content.title = message.title
            content.body = message.body
            content.sound = .default
            content.userInfo = ["route": "reading"]
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            return UNNotificationRequest(identifier: prefix + key, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        }
    }

    private static func input(_ model: AppModel) -> Reminders.Input {
        let readToday = model.today.readingDone
        let next: ChapterRef? = readToday
            ? (model.planFinished ? nil : model.plan.chapters[model.planPosition])
            : model.todaysChapter
        let stats = model.stats
        let close = (Achievements.streaks + Achievements.milestones)
            .filter { model.earned[$0.id] == nil }
            .map { ($0.name, $0.goal - $0.progress(stats)) }
            .filter { $0.1 > 0 }
            .min { $0.1 < $1.1 }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let weekday = DayKey.date(from: model.today.dayKey).map { utc.component(.weekday, from: $0) } ?? 2
        return Reminders.Input(
            todayKey: model.today.dayKey,
            readToday: readToday,
            streak: model.streak,
            lastReadKey: model.records.map(\.dayKey).max(),
            totalChapters: stats.chapters.count,
            chapter: next.map(BookNames.title) ?? "a new chapter",
            title: next.flatMap(ChapterTitles.title) ?? "",
            plan: model.plan.name,
            planLeft: max(0, model.plan.chapters.count - model.readCount(model.plan)),
            lockedApps: model.settings.lockSets.filter(\.enabled).map(\.appCount).reduce(0, +),
            nextTrophy: close.map { (name: $0.0, left: $0.1) },
            weekday: weekday
        )
    }
}
