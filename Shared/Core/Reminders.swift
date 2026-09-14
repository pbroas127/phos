import Foundation

/// The one daily nudge: which situation applies on a given day, and a friendly message for it.
/// Only ever one a day, and none on days the chapter is already read.
enum Reminders {
    enum Kind: String, CaseIterable {
        case neverStarted, keepStreak, milestone, bigStreak, freshStart, comeBack, longAway, lastNudge
        case planAlmostDone, chapterTeaser, lockedApps, trophyClose, sunday
    }

    /// What we know about the reader when planning a day's message.
    struct Context: Equatable {
        var kind: Kind
        var streak = 0
        var next = 0
        var days = 0
        var chapter = ""
        var title = ""
        var plan = ""
        var left = 0
        var apps = 0
        var trophy = ""
        var total = 0
    }

    struct Message: Equatable {
        let title: String
        let body: String
    }

    static let milestones = [3, 7, 10, 14, 21, 30, 50, 60, 75, 100, 150, 200, 250, 300, 365, 500, 730, 1000]

    /// Plans the next week of reminders, one per day at most. Assumes no more reading happens, so a day
    /// without a reading turns the next days into "come back" messages. The planner reruns every time the app opens.
    struct Input {
        var todayKey: String
        var readToday: Bool
        /// Days in a row, counting today when read today, otherwise ending yesterday.
        var streak: Int
        var lastReadKey: String?
        var totalChapters: Int
        var chapter: String
        var title: String
        var plan: String
        var planLeft: Int
        var lockedApps: Int
        var nextTrophy: (name: String, left: Int)?
        /// Weekday of today's key, 1 is Sunday.
        var weekday: Int
    }

    static func plan(_ input: Input, days: Int = 7) -> [(offset: Int, context: Context)] {
        var out: [(Int, Context)] = []
        for k in 0..<days {
            if k == 0 && input.readToday { continue }
            let dayKey = DayKey.adding(k, to: input.todayKey)
            let lastRead = input.readToday ? input.todayKey : input.lastReadKey
            let weekday = (input.weekday - 1 + k) % 7 + 1
            var c = Context(kind: .keepStreak)
            c.chapter = input.chapter
            c.title = input.title
            c.plan = input.plan
            c.left = input.planLeft
            c.apps = input.lockedApps
            c.total = input.totalChapters
            guard let lastRead else {
                c.kind = .neverStarted
                out.append((k, c))
                continue
            }
            let away = daysBetween(lastRead, dayKey)
            if away <= 1 {
                // The streak is alive and only today's reading keeps it going.
                c.streak = input.streak
                c.next = input.streak + 1
                c.kind = pickAlive(c, input: input, seed: seed(dayKey), weekday: weekday)
            } else if away == 2 {
                c.days = 1
                c.kind = .freshStart
            } else if k == days - 1 {
                c.days = away
                c.kind = .lastNudge
            } else {
                c.days = away
                c.kind = away >= 7 ? .longAway : .comeBack
            }
            out.append((k, c))
        }
        return out
    }

    private static func pickAlive(_ c: Context, input: Input, seed: Int, weekday: Int) -> Kind {
        if milestones.contains(c.next) { return .milestone }
        var options: [Kind] = [c.streak >= 30 ? .bigStreak : .keepStreak, .keepStreak]
        if !c.title.isEmpty { options.append(.chapterTeaser) }
        if c.left > 0 && c.left <= 3 && !c.plan.isEmpty { options.append(.planAlmostDone) }
        if c.apps > 0 { options.append(.lockedApps) }
        if let t = input.nextTrophy, t.left > 0, t.left <= 3 { options.append(.trophyClose) }
        if weekday == 1 { options.append(.sunday) }
        return options[abs(seed) % options.count]
    }

    static func message(_ c: Context, trophy: String = "", seed: Int) -> Message {
        var context = c
        if !trophy.isEmpty { context.trophy = trophy }
        let list = templates[c.kind] ?? templates[.keepStreak]!
        let pick = list[abs(seed) % list.count]
        return Message(title: fill(pick.0, context), body: fill(pick.1, context))
    }

    static func fill(_ text: String, _ c: Context) -> String {
        var s = text
        let values: [String: String] = [
            "{streak}": "\(c.streak)",
            "{streakDays}": plural(c.streak, "day"),
            "{next}": "\(c.next)",
            "{nextDays}": plural(c.next, "day"),
            "{days}": "\(c.days)",
            "{daysWord}": plural(c.days, "day"),
            "{chapter}": c.chapter,
            "{title}": c.title,
            "{plan}": c.plan,
            "{left}": "\(c.left)",
            "{leftChapters}": plural(c.left, "chapter"),
            "{apps}": plural(c.apps, "app"),
            "{trophy}": c.trophy,
            "{total}": "\(c.total)",
            "{totalChapters}": plural(c.total, "chapter")
        ]
        for (k, v) in values { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }

    static func plural(_ n: Int, _ word: String) -> String { n == 1 ? "1 \(word)" : "\(n) \(word)s" }

    static func seed(_ key: String) -> Int {
        key.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0x7FFFFFFF }
    }

    static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let x = DayKey.date(from: a), let y = DayKey.date(from: b) else { return 0 }
        return Int((y.timeIntervalSince(x) / 86_400).rounded())
    }

    // MARK: Messages

    static let templates: [Kind: [(String, String)]] = [
        .neverStarted: [
            ("Your first chapter is waiting 📖", "Ten quiet minutes today could start something good. {chapter} is ready when you are."),
            ("Day one starts with one chapter 🌱", "Read {chapter} tonight and light your first wick."),
            ("Hey, still thinking about it? 👀", "No pressure. {chapter} takes about ten minutes, and your streak starts the moment you finish."),
            ("Let's light the wick 🕯️", "One chapter, a few thoughts, a few questions. That's all it takes to begin."),
            ("Small start, big story ✨", "Every reader starts with one chapter. Yours is {chapter}."),
            ("Tonight could be day one 🌙", "Open {chapter} before bed and see what stands out."),
            ("The Bible is not going anywhere 😄", "But tonight is a great night to begin. {chapter} is up first.")
        ],
        .keepStreak: [
            ("Keep your {streak} day streak alive 🔥", "Read {chapter} before midnight to make it {next}."),
            ("🔥 {streakDays} strong", "Don't let the flame go out. {chapter} is ready for you."),
            ("Your streak misses you already 🥺", "{streakDays} in a row. One chapter keeps it going."),
            ("Quick check in ✋", "You have not read today yet. {chapter} keeps your {streak} day streak burning."),
            ("Protect the streak 🛡️", "{streakDays} and counting. Tonight's chapter is {chapter}."),
            ("Still time today ⏳", "Read {chapter} and your streak climbs to {next}."),
            ("The wick is still lit 🕯️", "Keep it that way with ten minutes in {chapter}."),
            ("Don't break the chain ⛓️", "{streakDays} in a row is worth protecting. Read before the day ends."),
            ("Before you scroll tonight 📱", "Give {chapter} a few minutes and keep your {streak} day streak."),
            ("Day {next} is one chapter away 🚀", "Open {chapter} and make it official."),
            ("Your future self says thanks 🙌", "Read {chapter} tonight and keep the streak at {next}."),
            ("Tiny habit, big deal ✨", "{streakDays} of showing up. Let's make it one more."),
            ("Hey, it's reading o'clock 🕰️", "{chapter} is waiting and so is day {next}."),
            ("Streak status: at risk 😬", "Read before midnight to keep all {streakDays}.")
        ],
        .milestone: [
            ("Day {next} is right there 🏁", "Read {chapter} tonight and hit a {next} day streak."),
            ("Milestone alert 🎉", "One chapter tonight gets you to {nextDays} in a row."),
            ("You're about to hit {next} 🔥", "Don't stop one day short. {chapter} is ready."),
            ("Big night tonight 🌟", "Finish {chapter} and your streak reaches {next}. Let's go!"),
            ("{next} days in a row? Say less 😎", "Read tonight and claim it."),
            ("A new record could be minutes away 🏆", "Read {chapter} to reach a {next} day streak.")
        ],
        .bigStreak: [
            ("{streakDays} of faithfulness 🙏", "That's no accident. Keep it going with {chapter} tonight."),
            ("Legendary streak alert 🔥🔥", "{streakDays} in a row. Day {next} is one chapter away."),
            ("You're on fire, in the best way 🕯️", "{streakDays} straight. Read {chapter} and keep the light burning."),
            ("This streak has seen things 😄", "{streakDays} and still going. Tonight's chapter is {chapter}."),
            ("Consistency looks good on you ✨", "Day {next} starts with {chapter}.")
        ],
        .freshStart: [
            ("Missed a day? It happens 💛", "Start a fresh streak tonight with {chapter}."),
            ("New day, new streak 🌅", "Yesterday slipped by. Today is a great day to begin again."),
            ("Grace for yesterday, a chapter for today 🙏", "Read {chapter} and start day 1 of your next streak."),
            ("Let's get back on track 🛤️", "One chapter tonight and you're rolling again."),
            ("The wick can be relit 🕯️", "Your streak reset, but your story didn't. {chapter} is ready."),
            ("Bounce back tonight 💪", "The best streaks start right after a miss. Read {chapter}.")
        ],
        .comeBack: [
            ("It's been {daysWord} 👋", "Come back and start a new streak with {chapter}."),
            ("We saved your spot 📍", "You're still on {chapter}. Pick up right where you left off."),
            ("Your Bible misses you 🥹", "It's been {daysWord}. Ten minutes tonight is a perfect restart."),
            ("No guilt, just an open door 🚪", "{chapter} is waiting whenever you're ready."),
            ("Ready for a comeback? 💪", "It's been {daysWord}. One chapter starts a brand new streak."),
            ("Hey, stranger 😄", "Your place in {plan} is saved. Come back to {chapter} tonight."),
            ("Let's relight the wick 🕯️", "{daysWord} away. Tonight could be day 1 again.")
        ],
        .longAway: [
            ("Long time no read 👀", "It's been {daysWord}. Your spot in {plan} is still saved."),
            ("Whenever you're ready 💛", "No streak pressure. Just one chapter, {chapter}, when you have a quiet minute."),
            ("A fresh start is always allowed 🌱", "It's been {daysWord}. Start small tonight."),
            ("We kept the light on 🕯️", "Come back to {chapter} and begin again."),
            ("Still here for you 🙏", "It's been a while. Ten minutes in {chapter} is a great way back.")
        ],
        .lastNudge: [
            ("One last nudge from us 💛", "We'll stop reminding you for now. Your place in {plan} will be waiting."),
            ("We'll give you some space 🌙", "It's been {daysWord}. Come back any time, {chapter} is saved."),
            ("Last reminder for a while 🕯️", "Whenever you're ready, one chapter starts a new streak.")
        ],
        .planAlmostDone: [
            ("So close to finishing {plan} 🏁", "Only {leftChapters} left. {chapter} is next."),
            ("{plan} is almost done 🎉", "{leftChapters} to go. Keep your {streak} day streak going too."),
            ("The finish line is in sight 👀", "Just {leftChapters} left in {plan}.")
        ],
        .chapterTeaser: [
            ("Tonight: {title} 📖", "{chapter} is up next. Keep your {streak} day streak going."),
            ("{title} 👀", "That's what's waiting in {chapter}. Read it before the day ends."),
            ("Next up in your story: {title} ✨", "Read {chapter} and make it {nextDays} in a row."),
            ("Curious how {chapter} goes? 🤔", "{title}. Find out tonight and keep the streak alive."),
            ("Your chapter tonight has a name 📜", "{title}. Open {chapter} and keep your streak at {next}.")
        ],
        .lockedApps: [
            ("{apps} are waiting on you 🔒", "Read {chapter} and keep your {streak} day streak too."),
            ("Your apps are patient, your streak isn't 😄", "{streakDays} in a row. Read {chapter} tonight."),
            ("Read first, scroll later 📱", "One chapter keeps the {streak} day streak and opens your apps.")
        ],
        .trophyClose: [
            ("{trophy} is so close 🏆", "Just {left} more to earn it. Read {chapter} tonight."),
            ("A trophy is within reach ✨", "{left} more for {trophy}. Keep your {streak} day streak going."),
            ("Almost there 🥇", "Keep reading and {trophy} is yours.")
        ],
        .sunday: [
            ("A Sunday chapter 🙏", "Rest, reflect, and read {chapter}. Your streak will thank you."),
            ("Sunday reset ☀️", "End the week with {chapter} and keep your {streak} day streak."),
            ("Sabbath and a streak 🕯️", "{streakDays} in a row. Make it {next} with {chapter}.")
        ]
    ]
}
