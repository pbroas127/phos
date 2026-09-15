import CryptoKit
import Foundation

enum LockLogic {
    enum State: Equatable {
        /// Outside its days or hours, or turned off.
        case inactive
        /// Unlocked right now.
        case open
        case needsReading
        case needsQuestion
        case needsTap
        /// Limited lock with no unlocks left today.
        case usedUp
        /// No unlocks allowed. Only an emergency pass opens it.
        case strict

        var isLocked: Bool { self != .inactive && self != .open }
    }

    static func minutes(_ date: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// True inside the lock's days and hours. A window that crosses midnight belongs to the day it started.
    static func isActive(_ lock: LockSet, now: Date, calendar: Calendar = .current) -> Bool {
        guard lock.enabled, lock.appCount > 0 else { return false }
        let weekday = calendar.component(.weekday, from: now)
        if lock.allDay { return lock.days.contains(weekday) }
        let m = minutes(now, calendar)
        let s = lock.start.minutesFromMidnight, e = lock.end.minutesFromMidnight
        if s == e { return lock.days.contains(weekday) }
        if s < e { return m >= s && m < e && lock.days.contains(weekday) }
        if m >= s { return lock.days.contains(weekday) }
        if m < e {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return lock.days.contains(calendar.component(.weekday, from: yesterday))
        }
        return false
    }

    /// When the window running right now began, for scheduled locks. Nil for all day locks or when not active.
    static func windowStart(_ lock: LockSet, now: Date, calendar: Calendar = .current) -> Date? {
        guard !lock.allDay, lock.start != lock.end, isActive(lock, now: now, calendar: calendar) else { return nil }
        let s = lock.start.minutesFromMidnight, e = lock.end.minutesFromMidnight
        let startsYesterday = s > e && minutes(now, calendar) < e
        let day = startsYesterday ? (calendar.date(byAdding: .day, value: -1, to: now) ?? now) : now
        return lock.start.date(on: day, calendar: calendar)
    }

    /// The day a lock's unlocks and reading belong to. A window that crosses into a new day, like 9 PM to 7 AM,
    /// keeps using the day it started on until it ends, so midnight does not relock it or refill its unlocks.
    /// A reading done on either day counts.
    static func day(for lock: LockSet, today: TodayState, yesterday: TodayState?, now: Date,
                    morning: TimeOfDay = TimeOfDay(hour: 0, minute: 0), calendar: Calendar = .current) -> TodayState {
        guard let yesterday, yesterday.dayKey == DayKey.adding(-1, to: today.dayKey),
              let start = windowStart(lock, now: now, calendar: calendar),
              DayKey.key(for: start, morning: morning, calendar: calendar) == yesterday.dayKey else { return today }
        var d = yesterday
        d.readingDone = yesterday.readingDone || today.readingDone
        return d
    }

    /// True when this lock's unlocks right now are saved on the previous day.
    static func usesPreviousDay(_ lock: LockSet, today: TodayState, yesterday: TodayState?, now: Date,
                                morning: TimeOfDay = TimeOfDay(hour: 0, minute: 0), calendar: Calendar = .current) -> Bool {
        day(for: lock, today: today, yesterday: yesterday, now: now, morning: morning, calendar: calendar).dayKey != today.dayKey
    }

    static func state(_ lock: LockSet, today: TodayState, yesterday: TodayState?, now: Date,
                      morning: TimeOfDay = TimeOfDay(hour: 0, minute: 0), calendar: Calendar = .current) -> State {
        state(lock, today: day(for: lock, today: today, yesterday: yesterday, now: now, morning: morning, calendar: calendar),
              now: now, calendar: calendar)
    }

    static func state(_ lock: LockSet, today: TodayState, now: Date, calendar: Calendar = .current) -> State {
        guard isActive(lock, now: now, calendar: calendar) else { return .inactive }
        let day = today.day(lock.id)
        if let p = day.passUntil, p > now { return .open }
        if lock.policy == .strict { return .strict }
        if let u = day.until, u > now { return .open }
        if !today.readingDone { return .needsReading }
        switch lock.policy {
        case .readOnce: return .needsTap
        case .questionEach: return .needsQuestion
        case .limited:
            if day.count >= lock.limit { return .usedUp }
            return lock.limitNeedsQuestion ? .needsQuestion : .needsTap
        case .strict: return .strict
        }
    }

    /// When the current active time ends: midnight for all day locks, the end time for scheduled ones.
    static func activeEnd(_ lock: LockSet, now: Date, calendar: Calendar = .current) -> Date {
        if lock.allDay || lock.start == lock.end {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.startOfDay(for: tomorrow)
        }
        var end = lock.end.date(on: now, calendar: calendar)
        if end <= now { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
        return end
    }

    /// When a lock that is on stops being on, for "opens again" copy. Nil when it never switches off.
    static func reopens(_ lock: LockSet, now: Date, calendar: Calendar = .current) -> Date? {
        guard lock.allDay || lock.start == lock.end else { return activeEnd(lock, now: now, calendar: calendar) }
        let today = calendar.startOfDay(for: now)
        for i in 1...7 {
            guard let d = calendar.date(byAdding: .day, value: i, to: today) else { continue }
            if !lock.days.contains(calendar.component(.weekday, from: d)) { return d }
        }
        return nil
    }

    /// "at 7:00 AM", "tomorrow", "Monday", or nil when the lock is on all day, every day.
    static func reopenPhrase(_ lock: LockSet, now: Date, calendar: Calendar = .current) -> String? {
        guard let when = reopens(lock, now: now, calendar: calendar) else { return nil }
        if !(lock.allDay || lock.start == lock.end) {
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.timeStyle = .short
            f.dateStyle = .none
            return "at \(f.string(from: when))"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: when).day ?? 0
        if days <= 1 { return "tomorrow" }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEEE"
        return f.string(from: when)
    }

    /// A reading opens its locks without using one of a limited lock's unlocks. Every later unlock counts.
    static func opened(_ day: LockDay, until end: Date, spendsUnlock: Bool) -> LockDay {
        var d = day
        d.until = max(end, d.until ?? end)
        if spendsUnlock { d.count += 1 }
        return d
    }

    static func rewardEnd(_ lock: LockSet, now: Date, calendar: Calendar = .current) -> Date {
        lock.rewardSeconds == LockSet.untilEnd
            ? activeEnd(lock, now: now, calendar: calendar)
            : now.addingTimeInterval(TimeInterval(max(30, lock.rewardSeconds)))
    }

    /// One line that describes the most pressing lock, for the shield button and widgets.
    static func reason(today: TodayState, yesterday: TodayState? = nil, locks: [LockSet], now: Date,
                       morning: TimeOfDay = TimeOfDay(hour: 0, minute: 0), calendar: Calendar = .current) -> LockReason {
        let states = locks.map { state($0, today: today, yesterday: yesterday, now: now, morning: morning, calendar: calendar) }
        if states.contains(.needsReading) { return .reading }
        if states.contains(.needsQuestion) { return .recall }
        if states.contains(.needsTap) { return .tap }
        if states.contains(.usedUp) { return .usedUp }
        if states.contains(.strict) { return .strict }
        return .none
    }

    /// The strictest reading check among locks waiting on today's reading, or among all locks if none are.
    static func readingCheck(today: TodayState, yesterday: TodayState? = nil, locks: [LockSet], now: Date,
                             morning: TimeOfDay = TimeOfDay(hour: 0, minute: 0), calendar: Calendar = .current) -> ReadingCheck {
        let waiting = locks.filter { state($0, today: today, yesterday: yesterday, now: now, morning: morning, calendar: calendar) == .needsReading }
        let pool = waiting.isEmpty ? locks.filter(\.enabled) : waiting
        return ReadingCheck.strictest(pool.map(\.reading))
    }
}

enum ProtectionLogic {
    enum Access: Equatable {
        case open
        case needsPasscode
        case needsCountdown(Int)
        /// Editing works, but saving schedules the change after this many hours.
        case delayed(Int)
        case blocked(String)
    }

    static func access(_ lock: LockSet, readingDone: Bool, now: Date) -> Access {
        let p = lock.protection
        switch p.kind {
        case .none:
            return .open
        case .passcode:
            return p.hasPasscode ? .needsPasscode : .open
        case .countdown:
            return .needsCountdown(max(1, p.countdownMinutes))
        case .delay:
            return .delayed(max(1, p.delayHours))
        case .commitment:
            guard let until = p.commitUntil, until > now else { return .open }
            return .blocked("You committed to \(lock.name) until \(until.formatted(date: .abbreviated, time: .shortened)). Until then this lock's settings can't change. Reading still unlocks it, and you can still add apps.")
        case .afterReading:
            return readingDone ? .open : .blocked("\(lock.name) settings open after today's reading. Read first, then come back. You can still add apps.")
        }
    }
}

enum Passcode {
    static func hash(_ code: String, salt: String) -> String {
        SHA256.hash(data: Data((salt + ":" + code).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func make(_ code: String) -> (hash: String, salt: String) {
        let salt = UUID().uuidString
        return (hash(code, salt: salt), salt)
    }

    static func verify(_ code: String, _ p: LockProtection) -> Bool {
        guard let h = p.passcodeHash, let s = p.passcodeSalt else { return true }
        return hash(code, salt: s) == h
    }

    /// Seconds to wait after this many wrong tries in a row: 1 minute at 5, then 15 minutes at 10 and every 5 after.
    static func wait(afterFailures n: Int) -> TimeInterval {
        if n >= 10 && n % 5 == 0 { return 15 * 60 }
        return n == 5 ? 60 : 0
    }

    static func isValid(_ code: String) -> Bool {
        (4...8).contains(code.count) && code.allSatisfy(\.isNumber)
    }
}
