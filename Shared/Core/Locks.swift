import CryptoKit
import Foundation

enum LockLogic {
    enum State: Equatable {
        /// Open.
        case open
        /// Locked, and reading or one question opens it.
        case gate
        /// Locked during strict hours. Only an emergency pass opens it.
        case strict
    }

    static func minutes(_ date: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// True inside a scheduled window on a chosen day. A window that crosses midnight belongs to the day it started.
    static func inWindow(_ set: LockSet, now: Date, calendar: Calendar = .current) -> Bool {
        let m = minutes(now, calendar)
        let s = set.start.minutesFromMidnight, e = set.end.minutesFromMidnight
        let weekday = calendar.component(.weekday, from: now)
        if s == e { return set.days.contains(weekday) }
        if s < e { return m >= s && m < e && set.days.contains(weekday) }
        if m >= s { return set.days.contains(weekday) }
        if m < e {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return set.days.contains(calendar.component(.weekday, from: yesterday))
        }
        return false
    }

    /// The end of the current strict window, for "locked until" text.
    static func windowEnd(_ set: LockSet, now: Date, calendar: Calendar = .current) -> Date {
        var end = set.end.date(on: now, calendar: calendar)
        if end <= now { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
        return end
    }

    static func isLockDay(_ set: LockSet, dayKey: String, calendar: Calendar = .current) -> Bool {
        guard let d = DayKey.localDate(from: dayKey, calendar: calendar) else { return true }
        return set.days.contains(calendar.component(.weekday, from: d))
    }

    static func state(_ set: LockSet, today: TodayState, now: Date, calendar: Calendar = .current) -> State {
        guard set.enabled, set.appCount > 0 else { return .open }
        let unlocked = today.isUnlocked(at: now)
        switch set.mode {
        case .scheduled:
            guard inWindow(set, now: now, calendar: calendar) else { return .open }
            if !set.allowEarning { return today.passOpen(at: now) ? .open : .strict }
            return unlocked ? .open : .gate
        case .untilRead:
            guard isLockDay(set, dayKey: today.dayKey, calendar: calendar), !unlocked else { return .open }
            return (!today.readingDone || today.middayPending) ? .gate : .open
        case .allDay:
            guard isLockDay(set, dayKey: today.dayKey, calendar: calendar) else { return .open }
            return unlocked ? .open : .gate
        }
    }

    static func reason(today: TodayState, settings: AppSettings, now: Date, calendar: Calendar = .current) -> LockReason {
        let states = settings.lockSets.map { state($0, today: today, now: now, calendar: calendar) }
        if states.contains(.gate) {
            if !today.readingDone { return .reading }
            if today.middayPending { return .midday }
            return .recall
        }
        if states.contains(.strict) { return .evening }
        return .none
    }

    static func strictUntil(settings: AppSettings, today: TodayState, now: Date, calendar: Calendar = .current) -> Date? {
        settings.lockSets
            .filter { state($0, today: today, now: now, calendar: calendar) == .strict }
            .map { windowEnd($0, now: now, calendar: calendar) }
            .min()
    }
}

enum SaveOutcome: Equatable {
    case applied
    case pending(Date)
    case blocked(String)
    case needsPasscode
    case needsCooldown(Int)
}

enum ConfigLogic {
    static func looserRules(_ current: Rules, _ proposed: Rules) -> Bool {
        RuleField.allCases.contains { f in
            let c = f.get(current), p = f.get(proposed)
            return c != p && !f.isStricter(p, than: c)
        }
    }

    static func coveredMinutes(_ set: LockSet) -> Set<Int> {
        let s = set.start.minutesFromMidnight
        return Set((0..<set.windowMinutes).map { (s + $0) % 1440 })
    }

    /// Rank of how much a mode locks, for spotting easier changes.
    static func modeStrength(_ set: LockSet) -> Int {
        switch set.mode {
        case .allDay: return 3
        case .untilRead: return 2
        case .scheduled: return set.allowEarning ? 1 : 2
        }
    }

    /// True when the proposal makes Phos easier to get past in any way.
    static func isEasier(current: LockConfig, proposed: LockConfig,
                         appsRemoved: (LockSet, LockSet) -> Bool = { $1.appCount < $0.appCount }) -> Bool {
        if looserRules(current.rules, proposed.rules) { return true }
        if proposed.schedule.morning.minutesFromMidnight > current.schedule.morning.minutesFromMidnight { return true }

        for c in current.lockSets where c.enabled {
            guard let p = proposed.lockSets.first(where: { $0.id == c.id }), p.enabled else { return true }
            if appsRemoved(c, p) { return true }
            if !c.days.isSubset(of: p.days) { return true }
            if c.mode != p.mode {
                if p.mode == .scheduled || modeStrength(p) < modeStrength(c) { return true }
            } else if c.mode == .scheduled {
                if !coveredMinutes(c).isSubset(of: coveredMinutes(p)) { return true }
                if !c.allowEarning && p.allowEarning { return true }
            }
        }

        let c = current.protection, p = proposed.protection
        if p.delayHours < c.delayHours || p.cooldownMinutes < c.cooldownMinutes { return true }
        if c.hasPasscode && p.passcodeHash != c.passcodeHash { return true }
        if c.onlyAfterReading && !p.onlyAfterReading { return true }
        if c.preventAppRemoval && !p.preventAppRemoval { return true }
        if let cu = c.commitUntil, (p.commitUntil ?? .distantPast) < cu { return true }
        return false
    }

    /// Runs an easier change through every protection the person turned on, in order.
    static func evaluate(settings: AppSettings, proposed: LockConfig, readingDone: Bool, now: Date,
                         passcodeOK: Bool, cooldownDone: Bool,
                         appsRemoved: (LockSet, LockSet) -> Bool = { $1.appCount < $0.appCount }) -> SaveOutcome {
        guard isEasier(current: settings.config, proposed: proposed, appsRemoved: appsRemoved) else { return .applied }
        let p = settings.protection
        if let until = p.commitUntil, until > now {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return .blocked("You committed to these settings until \(f.string(from: until)). Until then only emergency passes can open apps.")
        }
        if p.onlyAfterReading && !readingDone {
            return .blocked("Settings can only get easier after today's reading. Read first, then come back.")
        }
        if p.hasPasscode && !passcodeOK { return .needsPasscode }
        let setupDay = (settings.setupWindowEnds ?? .distantPast) > now
        if !setupDay && p.cooldownMinutes > 0 && !cooldownDone { return .needsCooldown(p.cooldownMinutes) }
        if !setupDay && p.delayHours > 0 { return .pending(now.addingTimeInterval(TimeInterval(p.delayHours * 3600))) }
        return .applied
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

    static func verify(_ code: String, _ p: Protection) -> Bool {
        guard let h = p.passcodeHash, let s = p.passcodeSalt else { return true }
        return hash(code, salt: s) == h
    }

    static func isValid(_ code: String) -> Bool {
        (4...8).contains(code.count) && code.allSatisfy(\.isNumber)
    }
}
