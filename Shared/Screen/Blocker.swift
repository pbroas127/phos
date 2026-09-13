import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import UserNotifications

extension ManagedSettingsStore.Name {
    /// Store used by the first build, cleared on sync.
    static let legacy = Self("phos")
    static let protection = Self("phos.protection")
    static func lock(_ id: String) -> Self { Self("phos.lock.\(id)") }
}

extension DeviceActivityName {
    static let day = Self("phos.morning")
    static func window(_ id: String) -> Self { Self("phos.lock.\(id)") }
    static func unlock(_ id: String) -> Self { Self("phos.unlock.\(id)") }
    var unlockLockID: String? {
        rawValue.hasPrefix("phos.unlock.") ? String(rawValue.dropFirst("phos.unlock.".count)) : nil
    }
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

    static func union(_ a: FamilyActivitySelection, _ b: FamilyActivitySelection) -> FamilyActivitySelection {
        var out = a
        out.applicationTokens.formUnion(b.applicationTokens)
        out.categoryTokens.formUnion(b.categoryTokens)
        out.webDomainTokens.formUnion(b.webDomainTokens)
        return out
    }

    /// Everything locked by any lock, for the usage report.
    static func union(_ sets: [LockSet]) -> FamilyActivitySelection {
        sets.reduce(FamilyActivitySelection()) { union($0, selection(from: $1.selection)) }
    }

    static func apply(_ lock: LockSet, shield: Bool) {
        let store = ManagedSettingsStore(named: .lock(lock.id))
        guard shield else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            store.shield.webDomainCategories = nil
            return
        }
        let sel = selection(from: lock.selection)
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

    static let usageThresholds = [15, 30, 60, 120]

    /// Registers the day boundary and every scheduled lock window.
    static func registerDaily(settings: AppSettings) {
        let center = DeviceActivityCenter()
        center.stopMonitoring(center.activities.filter { $0.unlockLockID == nil })
        // Usage thresholds on everything locked feed the Time Redeemed trophies.
        // ponytail: re-registering mid day restarts the count for that day; lock edits are protected, so this stays rare.
        let sel = union(settings.lockSets.filter(\.enabled))
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        if lockedCount(sel) > 0 {
            for minutes in usageThresholds {
                events[DeviceActivityEvent.Name("phos.use.\(minutes)")] = DeviceActivityEvent(
                    applications: sel.applicationTokens, categories: sel.categoryTokens, webDomains: sel.webDomainTokens,
                    threshold: DateComponents(minute: minutes))
            }
        }
        try? center.startMonitoring(.day, during: daily(TimeOfDay(hour: 0, minute: 0), TimeOfDay(hour: 23, minute: 59)), events: events)
        for lock in settings.lockSets where lock.enabled && !lock.allDay && lock.windowMinutes >= 15 && lock.windowMinutes < 1440 {
            try? center.startMonitoring(.window(lock.id), during: daily(lock.start, lock.end))
        }
    }

    /// Relocks a lock when its open time ends. Schedules must span 15 minutes, so short windows start in the past.
    static func scheduleRelock(lockID: String, at end: Date, now: Date = Date()) {
        let center = DeviceActivityCenter()
        center.stopMonitoring([.unlock(lockID)])
        let start = min(now, end.addingTimeInterval(-15 * 60))
        let cal = Calendar.current
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(intervalStart: cal.dateComponents(parts, from: start),
                                              intervalEnd: cal.dateComponents(parts, from: end),
                                              repeats: false)
        try? center.startMonitoring(.unlock(lockID), during: schedule)
    }

    static func cancelRelock(lockID: String) {
        DeviceActivityCenter().stopMonitoring([.unlock(lockID)])
    }
}

/// Lock decisions shared by the app and the activity monitor extension.
enum LockEngine {
    static func sync(store: SharedStore = .shared, now: Date = Date(), today override: TodayState? = nil) {
        let settings = store.settings
        let today = override ?? store.today(now: now, morning: settings.schedule.morning)
        var deletionBlocked = false
        var lockedCount = 0
        for lock in settings.lockSets {
            let locked = LockLogic.state(lock, today: today, now: now).isLocked
            Blocker.apply(lock, shield: locked)
            if locked {
                lockedCount += lock.appCount
                if lock.protection.blockDeletion { deletionBlocked = true }
            }
        }
        let ids = Set(settings.lockSets.map(\.id))
        for old in store.knownLockIDs where !ids.contains(old) { Blocker.clear(id: old) }
        store.knownLockIDs = Array(ids)
        ManagedSettingsStore(named: .legacy).clearAllSettings()
        ManagedSettingsStore(named: .protection).application.denyAppRemoval = deletionBlocked ? true : nil

        var snap = store.snapshot
        snap.reason = LockLogic.reason(today: today, locks: settings.lockSets, now: now)
        snap.readingDone = today.readingDone
        snap.lockedCount = lockedCount
        store.snapshot = snap
    }

    static func handleIntervalStart(_ activity: DeviceActivityName, store: SharedStore = .shared, now: Date = Date()) {
        // An unlock starting needs no work, and syncing here could reapply a shield from data older than the unlock.
        guard activity.unlockLockID == nil else { return }
        if activity == .day {
            var watched = store.watchedDays
            watched.insert(DayKey.key(for: now, morning: store.settings.schedule.morning))
            store.watchedDays = watched
        }
        sync(store: store, now: now)
    }

    static func handleIntervalEnd(_ activity: DeviceActivityName, store: SharedStore = .shared, now: Date = Date()) {
        var today = store.today(now: now, morning: store.settings.schedule.morning)
        if let id = activity.unlockLockID {
            // iOS can end the interval a little before the unlock time, so treat the last minute as over. Kept in memory only.
            var day = today.day(id)
            if let u = day.until, u <= now.addingTimeInterval(60) { day.until = nil }
            if let p = day.passUntil, p <= now.addingTimeInterval(60) { day.passUntil = nil }
            today.unlocks[id] = day
        }
        sync(store: store, now: now, today: today)
    }
}

extension LockEngine {
    /// Saves the highest screen time threshold reached today. Only touches the usage key, never today's lock state.
    static func recordUsage(_ event: DeviceActivityEvent.Name, store: SharedStore = .shared, now: Date = Date()) {
        guard let minutes = Int(event.rawValue.replacingOccurrences(of: "phos.use.", with: "")) else { return }
        let key = DayKey.key(for: now, morning: store.settings.schedule.morning)
        var usage = store.usage
        usage[key] = max(usage[key] ?? 0, minutes)
        store.usage = usage
    }
}

enum Notifier {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}
