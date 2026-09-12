import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import UserNotifications

extension ManagedSettingsStore.Name {
    static let phos = Self("phos")
}

extension DeviceActivityName {
    static let morning = Self("phos.morning")
    static let evening = Self("phos.evening")
    static let unlock = Self("phos.unlock")
    static func midday(_ i: Int) -> Self { Self("phos.midday.\(i)") }
    var isMidday: Bool { rawValue.hasPrefix("phos.midday.") }
}

/// Applies and clears the shield on locked apps, and keeps the daily schedule registered.
enum Blocker {
    static var managed: ManagedSettingsStore { ManagedSettingsStore(named: .phos) }

    static func selection(_ store: SharedStore = .shared) -> FamilyActivitySelection {
        guard let data = store.selectionData,
              let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return sel
    }

    static func save(selection: FamilyActivitySelection, store: SharedStore = .shared) {
        store.selectionData = try? JSONEncoder().encode(selection)
    }

    static func lockedCount(_ sel: FamilyActivitySelection) -> Int {
        sel.applicationTokens.count + sel.categoryTokens.count + sel.webDomainTokens.count
    }

    static func shield(store: SharedStore = .shared) {
        let sel = selection(store)
        let m = managed
        m.shield.applications = sel.applicationTokens.isEmpty ? nil : sel.applicationTokens
        m.shield.applicationCategories = sel.categoryTokens.isEmpty ? nil : .specific(sel.categoryTokens)
        m.shield.webDomains = sel.webDomainTokens.isEmpty ? nil : sel.webDomainTokens
        m.shield.webDomainCategories = sel.categoryTokens.isEmpty ? nil : .specific(sel.categoryTokens)
    }

    static func unshield() {
        let m = managed
        m.shield.applications = nil
        m.shield.applicationCategories = nil
        m.shield.webDomains = nil
        m.shield.webDomainCategories = nil
    }

    private static func schedule(from start: TimeOfDay, to end: TimeOfDay) -> DeviceActivitySchedule {
        DeviceActivitySchedule(intervalStart: start.components, intervalEnd: end.components, repeats: true)
    }

    /// Registers the morning lock, midday questions, and evening lock.
    static func registerDaily(settings: AppSettings) {
        let center = DeviceActivityCenter()
        center.stopMonitoring(center.activities.filter { $0 != .unlock })
        let morning = TimeOfDay(minutes: min(settings.schedule.morning.minutesFromMidnight, 23 * 60 + 30))
        try? center.startMonitoring(.morning, during: schedule(from: morning, to: TimeOfDay(hour: 23, minute: 59)))
        for (i, t) in settings.schedule.middayTimes(count: settings.rules.middayQuestions).enumerated() {
            let end = TimeOfDay(minutes: min(t.minutesFromMidnight + 15, 23 * 60 + 59))
            guard end.minutesFromMidnight - t.minutesFromMidnight >= 15 else { continue }
            try? center.startMonitoring(.midday(i), during: schedule(from: t, to: end))
        }
        if settings.schedule.eveningOn {
            let start = TimeOfDay(minutes: min(settings.schedule.evening.minutesFromMidnight, 23 * 60 + 30))
            try? center.startMonitoring(.evening, during: schedule(from: start, to: TimeOfDay(hour: 23, minute: 59)))
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
        let today = store.today(now: now)
        var snap = store.snapshot
        snap.reason = today.lockReason(at: now)
        snap.readingDone = today.readingDone
        snap.unlockedUntil = today.unlockedUntil
        store.snapshot = snap
        if snap.reason == .none { Blocker.unshield() } else { Blocker.shield(store: store) }
    }

    static func handleIntervalStart(_ activity: DeviceActivityName, store: SharedStore = .shared, now: Date = Date()) {
        var today = store.today(now: now)
        if activity == .morning {
            today.eveningLocked = false
            if !today.readingDone { today.unlockedUntil = nil }
        } else if activity == .evening {
            today.eveningLocked = true
            today.unlockedUntil = nil
        } else if activity.isMidday {
            if today.readingDone && !today.eveningLocked {
                today.middayPending = true
                today.unlockedUntil = nil
            }
        } else {
            return
        }
        store.storedToday = today
        sync(store: store, now: now)
    }

    static func handleIntervalEnd(_ activity: DeviceActivityName, store: SharedStore = .shared, now: Date = Date()) {
        guard activity == .unlock else { return }
        var today = store.today(now: now)
        if let until = today.unlockedUntil, until <= now.addingTimeInterval(60) {
            today.unlockedUntil = nil
            store.storedToday = today
        }
        sync(store: store, now: now)
    }

    /// End of an unlock that lasts the rest of the day: the next evening lock or the next morning.
    static func restOfDayEnd(settings: AppSettings, now: Date, calendar: Calendar = .current) -> Date {
        func next(_ t: TimeOfDay) -> Date {
            let d = t.date(on: now, calendar: calendar)
            return d > now ? d : calendar.date(byAdding: .day, value: 1, to: d) ?? d
        }
        var candidates = [next(settings.schedule.morning)]
        if settings.schedule.eveningOn { candidates.append(next(settings.schedule.evening)) }
        return candidates.min() ?? now.addingTimeInterval(3600)
    }
}

enum Notifier {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}
