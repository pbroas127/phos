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

    static func rewardEnd(_ lock: LockSet, now: Date, calendar: Calendar = .current) -> Date {
        lock.rewardSeconds == LockSet.untilEnd
            ? activeEnd(lock, now: now, calendar: calendar)
            : now.addingTimeInterval(TimeInterval(max(30, lock.rewardSeconds)))
    }

    /// One line that describes the most pressing lock, for the shield button and widgets.
    static func reason(today: TodayState, locks: [LockSet], now: Date, calendar: Calendar = .current) -> LockReason {
        let states = locks.map { state($0, today: today, now: now, calendar: calendar) }
        if states.contains(.needsReading) { return .reading }
        if states.contains(.needsQuestion) { return .recall }
        if states.contains(.needsTap) { return .tap }
        if states.contains(.usedUp) { return .usedUp }
        if states.contains(.strict) { return .strict }
        return .none
    }

    /// The strictest reading check among locks waiting on today's reading, or among all locks if none are.
    static func readingCheck(today: TodayState, locks: [LockSet], now: Date, calendar: Calendar = .current) -> ReadingCheck {
        let waiting = locks.filter { state($0, today: today, now: now, calendar: calendar) == .needsReading }
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
            return .blocked("You committed to \(lock.name) until \(until.formatted(date: .abbreviated, time: .shortened)). Until then only emergency passes can open it, and you can still add apps.")
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

    static func isValid(_ code: String) -> Bool {
        (4...8).contains(code.count) && code.allSatisfy(\.isNumber)
    }
}
