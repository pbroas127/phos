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
        /// How many more the closest trophy needs.
        var trophyLeft = 0
        /// Hour the reminder fires, so evening lines never go out at 6 AM.
        var hour = 20
        /// False when the reader set a custom morning reset, so "before midnight" would be wrong.
        var resetsAtMidnight = true
        var tone: ReminderTone = .gentle
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
        var hour = 20
        var resetsAtMidnight = true
        var tone: ReminderTone = .gentle
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
            c.trophyLeft = input.nextTrophy?.left ?? 0
            c.hour = input.hour
            c.resetsAtMidnight = input.resetsAtMidnight
            c.tone = input.tone
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
        let list = candidates(c.kind, tone: c.tone, hour: c.hour)
        let pick = list[abs(seed) % list.count]
        return Message(title: fill(pick.title, context), body: fill(pick.body, context))
    }

    /// Lines that fit the hour: evening lines from 5 PM, morning lines before noon, neutral lines any time.
    static func candidates(_ kind: Kind, tone: ReminderTone, hour: Int) -> [Template] {
        let all = templates(tone)[kind] ?? templates(tone)[.keepStreak]!
        let fit = all.filter { t in
            switch t.when {
            case .any: return true
            case .evening: return hour >= 17
            case .morning: return hour < 12
            }
        }
        return fit.isEmpty ? all.filter { $0.when == .any } : fit
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
            "{appsWaiting}": c.apps == 1 ? "1 app is waiting" : "\(c.apps) apps are waiting",
            "{trophy}": c.trophy,
            "{trophyLeft}": "\(c.trophyLeft)",
            "{total}": "\(c.total)",
            "{totalChapters}": plural(c.total, "chapter"),
            "{deadline}": c.resetsAtMidnight ? "before midnight" : "before your day resets"
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

    enum Slot { case any, evening, morning }

    struct Template {
        let title: String
        let body: String
        var when: Slot = .any
    }

    static func templates(_ tone: ReminderTone) -> [Kind: [Template]] {
        tone == .gentle ? gentle : playful
    }

    private static func t(_ title: String, _ body: String, _ when: Slot = .any) -> Template {
        Template(title: title, body: body, when: when)
    }

    /// No emoji, no streak pressure, no slang. Scripture is the invitation.
    static let gentle: [Kind: [Template]] = [
        .neverStarted: [
            t("Your first chapter is waiting", "Ten quiet minutes with {chapter} is a good way to begin."),
            t("A small start", "Every reader starts with one chapter. Yours is {chapter}."),
            t("Whenever you are ready", "{chapter} takes about ten minutes. There is no rush."),
            t("An evening chapter", "Open {chapter} before bed and see what stands out.", .evening),
            t("Begin the day with a chapter", "{chapter} is a calm place to start.", .morning)
        ],
        .keepStreak: [
            t("{chapter} is waiting", "A few quiet minutes today keeps your reading going."),
            t("Today's chapter", "{chapter} is ready when you have a moment."),
            t("A quiet minute", "You have not read today yet. {chapter} is short and worth it."),
            t("Still time today", "Read {chapter} and your streak reaches {next}."),
            t("Before you scroll tonight", "Give {chapter} a few minutes first.", .evening),
            t("An evening chapter", "{chapter} is waiting when the day slows down.", .evening),
            t("Start the day with {chapter}", "Ten minutes now sets the tone for the rest of it.", .morning)
        ],
        .milestone: [
            t("Day {next} is one chapter away", "Read {chapter} and reach {nextDays} in a row."),
            t("A milestone today", "{chapter} makes it {nextDays} of reading. Well done getting here."),
            t("{next} days of showing up", "Read {chapter} tonight and mark the milestone.", .evening)
        ],
        .bigStreak: [
            t("{streakDays} of faithfulness", "That is no accident. {chapter} is next."),
            t("Steady as ever", "{streakDays} in a row. Today's chapter is {chapter}."),
            t("Consistency looks good on you", "Day {next} starts with {chapter}.")
        ],
        .freshStart: [
            t("Grace for yesterday, a chapter for today", "Read {chapter} and begin again."),
            t("A new day", "Yesterday slipped by. Today is a good day to start again with {chapter}."),
            t("Begin again", "The best starts come right after a miss. {chapter} is ready."),
            t("Tonight is a fine time to restart", "{chapter} is waiting.", .evening)
        ],
        .comeBack: [
            t("We saved your spot", "You are still on {chapter}. Pick up right where you left off."),
            t("No guilt, just an open door", "{chapter} is waiting whenever you are ready."),
            t("It has been {daysWord}", "One chapter is a gentle way back. {chapter} is next."),
            t("An evening to return", "It has been {daysWord}. Ten minutes in {chapter} tonight is a good restart.", .evening)
        ],
        .longAway: [
            t("Whenever you are ready", "No pressure. Just one chapter, {chapter}, when you have a quiet minute."),
            t("A fresh start is always allowed", "It has been {daysWord}. Start small with {chapter}."),
            t("We kept the light on", "Come back to {chapter} and begin again."),
            t("Still here for you", "It has been a while. Ten minutes in {chapter} is a good way back.")
        ],
        .lastNudge: [
            t("One last note from us", "We will stop reminding you for now. Your place in {plan} will be waiting."),
            t("We will give you some space", "It has been {daysWord}. Come back any time, {chapter} is saved."),
            t("Last reminder for a while", "Whenever you are ready, {chapter} is where you left off.")
        ],
        .planAlmostDone: [
            t("So close to finishing {plan}", "Only {leftChapters} left. {chapter} is next."),
            t("{plan} is almost done", "{leftChapters} to go, starting with {chapter}."),
            t("The finish line is in sight", "Just {leftChapters} left in {plan}.")
        ],
        .chapterTeaser: [
            t("Today: {title}", "{chapter} is up next."),
            t("{title}", "That is what is waiting in {chapter}."),
            t("Next in your story: {title}", "Read {chapter} when you have a few minutes."),
            t("Tonight: {title}", "{chapter} is ready when the day slows down.", .evening),
            t("This morning: {title}", "Start the day with {chapter}.", .morning)
        ],
        .lockedApps: [
            t("{appsWaiting} on you", "Read {chapter} and they open."),
            t("Read first, scroll later", "One chapter opens your apps. {chapter} is next."),
            t("Your apps can wait", "{chapter} comes first today.")
        ],
        .trophyClose: [
            t("{trophy} is close", "Just {trophyLeft} more to earn it. {chapter} is next."),
            t("A trophy within reach", "{trophyLeft} more for {trophy}."),
            t("Almost there", "Keep reading and {trophy} is yours.")
        ],
        .sunday: [
            t("A Sunday chapter", "Rest, reflect, and read {chapter}."),
            t("The Lord's Day", "End the week with {chapter}."),
            t("A quiet Sunday", "{chapter} fits a slower day.")
        ]
    ]

    /// Emoji and fun, with at most one streak nudge per situation and nothing that shames.
    static let playful: [Kind: [Template]] = [
        .neverStarted: [
            t("Your first chapter is waiting 📖", "Ten quiet minutes today could start something good. {chapter} is ready when you are."),
            t("Day one starts with one chapter 🌱", "Read {chapter} tonight and light your first wick.", .evening),
            t("Hey, still thinking about it? 👀", "No pressure. {chapter} takes about ten minutes, and your streak starts the moment you finish."),
            t("Let's light the wick 🕯️", "One chapter, a few thoughts, a few questions. That's all it takes to begin."),
            t("Small start, big story ✨", "Every reader starts with one chapter. Yours is {chapter}."),
            t("Tonight could be day one 🌙", "Open {chapter} before bed and see what stands out.", .evening),
            t("Morning, reader ☀️", "Start the day with {chapter}. Ten minutes, that's it.", .morning)
        ],
        .keepStreak: [
            t("Keep your {streak} day streak alive 🔥", "Read {chapter} {deadline} to make it {next}."),
            t("🔥 {streakDays} strong", "{chapter} is ready for you."),
            t("Quick check in ✋", "You have not read today yet. {chapter} keeps your {streak} day streak burning."),
            t("Still time today ⏳", "Read {chapter} and your streak climbs to {next}."),
            t("The wick is still lit 🕯️", "Keep it that way with ten minutes in {chapter}."),
            t("Before you scroll tonight 📱", "Give {chapter} a few minutes and keep your {streak} day streak.", .evening),
            t("Day {next} is one chapter away 🚀", "Open {chapter} and make it official."),
            t("Your future self says thanks 🙌", "Read {chapter} tonight and keep the streak at {next}.", .evening),
            t("Tiny habit, big deal ✨", "{streakDays} of showing up. Let's make it one more."),
            t("Coffee and a chapter ☕", "{chapter} goes well with the morning.", .morning)
        ],
        .milestone: [
            t("Day {next} is right there 🏁", "Read {chapter} tonight and hit a {next} day streak.", .evening),
            t("Milestone alert 🎉", "One chapter today gets you to {nextDays} in a row."),
            t("You're about to hit {next} 🔥", "{chapter} is ready. Go claim it."),
            t("Big night tonight 🌟", "Finish {chapter} and your streak reaches {next}. Let's go!", .evening),
            t("A new record could be minutes away 🏆", "Read {chapter} to reach a {next} day streak.")
        ],
        .bigStreak: [
            t("{streakDays} of faithfulness 🙏", "That's no accident. Keep it going with {chapter}."),
            t("Legendary streak alert 🔥🔥", "{streakDays} in a row. Day {next} is one chapter away."),
            t("You're on fire, in the best way 🕯️", "{streakDays} straight. Read {chapter} and keep the light burning."),
            t("Consistency looks good on you ✨", "Day {next} starts with {chapter}.")
        ],
        .freshStart: [
            t("Missed a day? It happens 💛", "Start a fresh streak today with {chapter}."),
            t("New day, new streak 🌅", "Yesterday slipped by. Today is a great day to begin again.", .morning),
            t("Grace for yesterday, a chapter for today 🙏", "Read {chapter} and start day 1 of your next streak."),
            t("Let's get back on track 🛤️", "One chapter tonight and you're rolling again.", .evening),
            t("The wick can be relit 🕯️", "Your streak reset, but your story didn't. {chapter} is ready."),
            t("Bounce back 💪", "The best streaks start right after a miss. Read {chapter}.")
        ],
        .comeBack: [
            t("It's been {daysWord} 👋", "Come back and start a new streak with {chapter}."),
            t("We saved your spot 📍", "You're still on {chapter}. Pick up right where you left off."),
            t("No guilt, just an open door 🚪", "{chapter} is waiting whenever you're ready."),
            t("Ready for a comeback? 💪", "It's been {daysWord}. One chapter starts a brand new streak."),
            t("Hey, stranger 😄", "Your place in {plan} is saved. Come back to {chapter} tonight.", .evening),
            t("Let's relight the wick 🕯️", "{daysWord} away. Today could be day 1 again.")
        ],
        .longAway: [
            t("Long time no read 👀", "It's been {daysWord}. Your spot in {plan} is still saved."),
            t("Whenever you're ready 💛", "No streak pressure. Just one chapter, {chapter}, when you have a quiet minute."),
            t("A fresh start is always allowed 🌱", "It's been {daysWord}. Start small today."),
            t("We kept the light on 🕯️", "Come back to {chapter} and begin again."),
            t("Still here for you 🙏", "It's been a while. Ten minutes in {chapter} is a great way back.")
        ],
        .lastNudge: [
            t("One last nudge from us 💛", "We'll stop reminding you for now. Your place in {plan} will be waiting."),
            t("We'll give you some space 🌙", "It's been {daysWord}. Come back any time, {chapter} is saved."),
            t("Last reminder for a while 🕯️", "Whenever you're ready, one chapter starts a new streak.")
        ],
        .planAlmostDone: [
            t("So close to finishing {plan} 🏁", "Only {leftChapters} left. {chapter} is next."),
            t("{plan} is almost done 🎉", "{leftChapters} to go. Keep your {streak} day streak going too."),
            t("The finish line is in sight 👀", "Just {leftChapters} left in {plan}.")
        ],
        .chapterTeaser: [
            t("Tonight: {title} 📖", "{chapter} is up next. Keep your {streak} day streak going.", .evening),
            t("{title} 👀", "That's what's waiting in {chapter}."),
            t("Next up in your story: {title} ✨", "Read {chapter} and make it {nextDays} in a row."),
            t("Curious how {chapter} goes? 🤔", "{title}. Find out today and keep the streak alive."),
            t("Your chapter today has a name 📜", "{title}. Open {chapter} and keep your streak at {next}.")
        ],
        .lockedApps: [
            t("{appsWaiting} on you 🔒", "Read {chapter} and keep your {streak} day streak too."),
            t("Your apps are patient 😄", "{streakDays} in a row. Read {chapter} and they open."),
            t("Read first, scroll later 📱", "One chapter keeps the {streak} day streak and opens your apps.")
        ],
        .trophyClose: [
            t("{trophy} is so close 🏆", "Just {trophyLeft} more to earn it. {chapter} is next."),
            t("A trophy is within reach ✨", "{trophyLeft} more for {trophy}. Keep your {streak} day streak going."),
            t("Almost there 🥇", "Keep reading and {trophy} is yours.")
        ],
        .sunday: [
            t("A Sunday chapter 🙏", "Rest, reflect, and read {chapter}. Your streak will thank you."),
            t("Sunday reset ☀️", "End the week with {chapter} and keep your {streak} day streak."),
            t("The Lord's Day and a streak 🕯️", "{streakDays} in a row. Make it {next} with {chapter}.")
        ]
    ]
}
