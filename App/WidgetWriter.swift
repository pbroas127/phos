import UIKit
import WidgetKit

/// Fills the shared widget data from the app's state and nudges WidgetKit to redraw.
enum WidgetWriter {
    static func write(_ model: AppModel) {
        var d = WidgetData()
        let todayKey = model.today.dayKey
        let doneKeys = Set(model.records.map(\.dayKey))
        d.streak = model.streak
        d.longestStreak = Streaks.longest(doneKeys: doneKeys)
        d.readToday = model.today.readingDone
        d.dayKey = todayKey
        d.morningHour = model.settings.schedule.morning.hour
        d.morningMinute = model.settings.schedule.morning.minute
        d.lastDoneKey = doneKeys.max()
        d.week = (0..<7).map { doneKeys.contains(DayKey.adding($0 - 6, to: todayKey)) }
        d.totalChapters = Set(model.records.map(\.ref.id)).count

        // The chapter shown is today's, read or not. Once it is read, the next one waits for tomorrow.
        let ref = model.todaysChapter
        d.chapter = BookNames.title(ref)
        d.chapterTitle = ChapterTitles.title(ref) ?? ""
        let next = model.planFinished ? ref : model.plan.chapters[min(model.planPosition, model.plan.chapters.count - 1)]
        d.nextChapter = BookNames.title(next)
        d.nextTitle = ChapterTitles.title(next) ?? ""
        if let key = QuestionBank.shared.questions(for: next)?.keyVerse {
            d.nextKeyVerse = .init(text: clean(Bible.shared.verse(next, key)), ref: BookNames.verseTitle(next, key))
        }
        if let key = QuestionBank.shared.questions(for: ref)?.keyVerse {
            d.keyVerse = .init(text: clean(Bible.shared.verse(ref, key)), ref: BookNames.verseTitle(ref, key))
        }
        let start = abs(Reminders.seed(todayKey)) % max(1, DailyVerses.refs.count)
        d.verses = (0..<DailyVerses.refs.count).map { i in
            let (r, v) = DailyVerses.refs[(start + i) % DailyVerses.refs.count]
            return WidgetData.Verse(text: clean(Bible.shared.verse(r, v)), ref: BookNames.verseTitle(r, v))
        }.filter { !$0.text.isEmpty }

        d.planName = model.plan.name
        d.planRead = model.readCount(model.plan)
        d.planTotal = model.plan.chapters.count
        let from = min(model.planPosition, model.plan.chapters.count)
        d.upcoming = model.plan.chapters[from...].prefix(5).map { .init(text: ChapterTitles.title($0) ?? "", ref: BookNames.title($0)) }

        d.locks = model.settings.lockSets.filter(\.enabled).map { lock in
            let state = model.state(lock)
            let day = model.lockDay(lock)
            let limited = lock.policy == .limited
            return WidgetData.Lock(id: lock.id, name: lock.name, locked: state.isLocked, status: status(state),
                                   left: limited ? max(0, lock.limit - day.count) : nil, limit: limited ? lock.limit : nil)
        }
        d.lockedApps = model.lockedCount

        let stats = model.stats
        let pinned = model.settings.pinnedTrophies.compactMap { id in Achievements.all.first { $0.id == id && model.earned[id] == nil } }
        let close = Achievements.almost(stats, earned: Set(model.earned.keys), limit: 6).filter { a in !pinned.contains { $0.id == a.id } }
        d.trophies = (pinned + close).prefix(6).map { info($0, stats: stats, earned: false) }
        d.closest = Achievements.almost(stats, earned: Set(model.earned.keys), limit: 6).map { info($0, stats: stats, earned: false) }
        if let last = Achievements.all.compactMap({ a in model.earned[a.id].map { (a, $0) } }).max(by: { $0.1 < $1.1 }) {
            d.lastEarned = info(last.0, stats: stats, earned: true)
        }
        d.earnedCount = model.earned.count
        d.trophyTotal = Achievements.all.count

        let old = model.store.widgetData
        d.updated = old.updated
        guard d != old else { return }
        d.updated = Date()
        model.store.widgetData = d
        for art in Set(d.trophies.map(\.art) + d.closest.map(\.art) + [d.lastEarned?.art].compactMap { $0 }) { saveImage(art) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func info(_ a: Achievement, stats: AchievementStats, earned: Bool) -> WidgetData.Trophy {
        .init(name: a.name, detail: a.detail, art: a.art, progress: a.progress(stats), goal: a.goal, earned: earned)
    }

    private static func status(_ state: LockLogic.State) -> String {
        switch state {
        case .inactive: return "Not active now"
        case .open: return "Open"
        case .needsReading: return "Locked until you read"
        case .needsQuestion: return "One question opens it"
        case .needsTap: return "Read today, tap to open"
        case .usedUp: return "No unlocks left today"
        case .strict: return "Strict hours"
        }
    }

    private static func clean(_ s: String) -> String {
        TextChecks.plain(s).trimmingCharacters(in: CharacterSet(charactersIn: "“”‘’\"' "))
    }

    /// Copies a small version of a trophy picture into the shared container once.
    private static func saveImage(_ art: String) {
        guard let url = WidgetData.imageURL(art), !FileManager.default.fileExists(atPath: url.path),
              let image = UIImage(named: "trophy_\(art)") else { return }
        let size = CGSize(width: 180, height: 180)
        let small = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        try? small.pngData()?.write(to: url)
    }
}
