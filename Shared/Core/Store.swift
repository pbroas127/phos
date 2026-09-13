import Foundation

/// App Group storage shared by the app and every extension.
final class SharedStore {
    static let shared = SharedStore()

    let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppGroup.id)) {
        self.defaults = defaults ?? .standard
    }

    private func load<T: Decodable>(_ key: String, as: T.Type) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    var settings: AppSettings {
        get { load("settings", as: AppSettings.self) ?? AppSettings() }
        set { save(newValue, "settings") }
    }

    var records: [DayRecord] {
        get { load("records", as: [DayRecord].self) ?? [] }
        set { save(newValue, "records") }
    }

    var snapshot: SharedSnapshot {
        get { load("snapshot", as: SharedSnapshot.self) ?? SharedSnapshot() }
        set { save(newValue, "snapshot") }
    }

    /// Lock ids that have a ManagedSettings store, so deleted locks can be cleared.
    var knownLockIDs: [String] {
        get { defaults.stringArray(forKey: "knownLockIDs") ?? [] }
        set { defaults.set(newValue, forKey: "knownLockIDs") }
    }

    /// Older builds kept a single app selection here.
    var selectionData: Data? {
        get { defaults.data(forKey: "selection") }
        set { defaults.set(newValue, forKey: "selection") }
    }

    var storedToday: TodayState? {
        get { load("today", as: TodayState.self) }
        set { save(newValue, "today") }
    }

    /// Today's state, starting a fresh day when the morning boundary has passed.
    func today(now: Date = Date(), morning: TimeOfDay? = nil) -> TodayState {
        let key = DayKey.key(for: now, morning: morning ?? settings.schedule.morning)
        if let t = storedToday, t.dayKey == key { return t }
        let fresh = TodayState(dayKey: key)
        storedToday = fresh
        return fresh
    }
}
