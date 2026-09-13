import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import UserNotifications

extension ManagedSettingsStore.Name {
    /// Store used by the first builds, cleared on sync.
    static let legacy = Self("phos")
    static let protection = Self("phos.protection")
    static func lock(_ id: String) -> Self { Self("phos.lock.\(id)") }
}

extension DeviceActivityName {
    static let morning = Self("phos.morning")
    static let unlock = Self("phos.unlock")
    static func midday(_ i: Int) -> Self { Self("phos.midday.\(i)") }
    static func lock(_ id: String) -> Self { Self("phos.lock.\(id)") }
    var isMidday: Bool { rawValue.hasPrefix("phos.midday.") }
}

/// Shields locked apps and keeps the schedules registered.
enum Blocker {
    static func selection(from data: Data?) -> FamilyActivitySelection {
        guard let data, let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return sel
    }

    static func encode(_ sel: FamilyActivitySelection) -> Data? {
        try? JSONEncoder().encode(sel)
    }

    static func lockedCount(_ sel: FamilyActivitySelection) -> Int {
        sel.applicationTokens.count + sel.categoryTokens.count + sel.webDomainTokens.count
    }

    /// Everything locked by any lock, for the usage report.
    static func union(_ sets: [LockSet]) -> FamilyActivitySelection {
        var out = FamilyActivitySelection()
        for set in sets {
            let sel = selection(from: set.selection)
            out.applicationTokens.formUnion(sel.applicationTokens)
            out.categoryTokens.formUnion(sel.categoryTokens)
            out.webDomainTokens.formUnion(sel.webDomainTokens)
        }
        return out
    }

    /// True when the proposed lock no longer covers something the current one did.
    static func appsRemoved(_ current: LockSet, _ proposed: LockSet) -> Bool {
        let c = selection(from: current.selection), p = selection(from: proposed.selection)
        return !c.applicationTokens.isSubset(of: p.applicationTokens)
            || !c.categoryTokens.isSubset(of: p.categoryTokens)
            || !c.webDomainTokens.isSubset(of: p.webDomainTokens)
    }

    static func apply(_ set: LockSet, shield: Bool) {
        let store = ManagedSettingsStore(named: .lock(set.id))
        guard shield else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            store.shield.webDomainCategories = nil
            return
        }
        let sel = selection(from: set.selection)
        store.shield.applications = sel.applicationTokens.isEmpty ? nil : sel.applicationTokens
        store.shield.applicationCategories = sel.categoryTokens.isEmpty ? nil : .specific(sel.categoryTokens)
        store.shield.webDomains = sel.webDomainTokens.isEmpty ? nil : sel.webDomainTokens
        store.shield.webDomainCategories = sel.categoryTokens.isEmpty ? nil : .specific(sel.categoryTokens)
    }

    static func clear(id: String) {
        ManagedSettingsStore(named: .lock(id)).clearAllSettings()
    }

    private static func daily(_ start: TimeOfDay, _ end: TimeOfDay) -> DeviceActivitySchedule {
        DeviceActivitySchedule(intervalStart: start.components, intervalEnd: end.components, repeats: true)
    }

    /// Registers the morning boundary, midday questions, and every scheduled lock window.
    static func registerDaily(settings: AppSettings) {
        let center = DeviceActivityCenter()
        center.stopMonitoring(center.activities.filter { $0 != .unlock })
        let morning = TimeOfDay(minutes: min(settings.schedule.morning.minutesFromMidnight, 23 * 60 + 30))
        try? center.startMonitoring(.morning, during: daily(morning, TimeOfDay(hour: 23, minute: 59)))
        for (i, t) in settings.schedule.middayTimes(count: settings.rules.middayQuestions).enumerated() {
            let end = TimeOfDay(minutes: min(t.minutesFromMidnight + 15, 23 * 60 + 59))
            guard end.minutesFromMidnight - t.minutesFromMidnight >= 15 else { continue }
            try? center.startMonitoring(.midday(i), during: daily(t, end))
        }
        for set in settings.lockSets where set.enabled && set.mode == .scheduled && set.windowMinutes >= 15 {
            let schedule = set.windowMinutes >= 1440
                ? daily(TimeOfDay(hour: 0, minute: 0), TimeOfDay(hour: 23, minute: 59))
                : daily(set.start, set.end)
            try? center.startMonitoring(.lock(set.id), during: schedule)
        }
    }

    /// Relocks when an unlock window ends. Schedules must span 15 minutes, so short windows start in the past.
    static func scheduleRelock(at end: Date, now: Date = Date()) {
        let center = DeviceActivityCenter()
        center.stopMonitoring([.unlock])
        let start = min(now, end.addingTimeInterval(-15 * 60))
        let cal = Calendar.current
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(intervalStart: cal.dateComponents(parts, from: start),
                                              intervalEnd: cal.dateComponents(parts, from: end),
                                              repeats: false)
        try? center.startMonitoring(.unlock, during: schedule)
    }

    static func cancelRelock() {
        DeviceActivityCenter().stopMonitoring([.unlock])
    }
}

/// Lock decisions shared by the app and the activity monitor extension.
enum LockEngine {
    static func sync(store: SharedStore = .shared, now: Date = Date()) {
        let settings = store.settings
        let today = store.today(now: now, morning: settings.schedule.morning)
        var anyLocked = false
        for set in settings.lockSets {
            let locked = LockLogic.state(set, today: today, now: now) != .open
            Blocker.apply(set, shield: locked)
            anyLocked = anyLocked || locked
        }
        let ids = Set(settings.lockSets.map(\.id))
        for old in store.knownLockIDs where !ids.contains(old) { Blocker.clear(id: old) }
        store.knownLockIDs = Array(ids)
        ManagedSettingsStore(named: .legacy).clearAllSettings()
        ManagedSettingsStore(named: .protection).application.denyAppRemoval =
            settings.protection.preventAppRemoval && anyLocked ? true : nil

        var snap = store.snapshot
        snap.reason = LockLogic.reason(today: today, settings: settings, now: now)
        snap.readingDone = today.readingDone
        snap.unlockedUntil = today.unlockedUntil
        snap.strictUntil = LockLogic.strictUntil(settings: settings, today: today, now: now)
        snap.lockedCount = settings.lockSets.filter(\.enabled).map(\.appCount).reduce(0, +)
        store.snapshot = snap
    }

    static func handleIntervalStart(_ activity: DeviceActivityName, store: SharedStore = .shared, now: Date = Date()) {
        var today = store.today(now: now)
        if activity == .morning {
            if !today.readingDone { today.unlockedUntil = nil }
            store.storedToday = today
        } else if activity.isMidday {
            if today.readingDone {
                today.middayPending = true
                today.unlockedUntil = nil
                store.storedToday = today
            }
        }
        sync(store: store, now: now)
    }

    static func handleIntervalEnd(_ activity: DeviceActivityName, store: SharedStore = .shared, now: Date = Date()) {
        if activity == .unlock {
            var today = store.today(now: now)
            if let until = today.unlockedUntil, until <= now.addingTimeInterval(60) { today.unlockedUntil = nil }
            if let pass = today.passUntil, pass <= now.addingTimeInterval(60) { today.passUntil = nil }
            store.storedToday = today
        }
        sync(store: store, now: now)
    }

    /// End of an unlock that lasts the rest of the day: the next morning.
    static func restOfDayEnd(settings: AppSettings, now: Date, calendar: Calendar = .current) -> Date {
        let d = settings.schedule.morning.date(on: now, calendar: calendar)
        return d > now ? d : calendar.date(byAdding: .day, value: 1, to: d) ?? now.addingTimeInterval(3600)
    }
}

enum Notifier {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}
