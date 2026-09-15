import Foundation
import SwiftUI

/// Everything worth keeping if the phone is lost or Wick is reinstalled. Lock app choices are not included,
/// because Screen Time app tokens only work on the device that picked them.
struct BackupPayload: Codable {
    var version = 1
    var savedAt: Date
    var records: [DayRecord]
    var earned: [String: Date]
    var planID: String
    var planPositions: [String: Int]
    var pinnedTrophies: [String]
    var passUses: [PassUse]
    var preferredRead: ReadMode
    var preferredReflect: ReflectMode
    var voiceID: String
    var reminderOn: Bool
    var reminderMinutes: Int
    var allowAlreadyRead: Bool
    var shieldStyle: ShieldStyle
    var shieldTheme: ShieldTheme
    /// Added after the first backups shipped, so older ones decode without it.
    var reviews: [ReviewRecord]? = nil
    var allowReviewUnread: Bool? = nil
}

/// Automatic backup to the person's own iCloud through the key value store. No account and no servers of ours.
enum CloudBackup {
    private static let key = "wick.backup.v1"
    private static let savedKey = "wick.backup.savedAt"
    /// iCloud key value storage allows about 1 MB in total.
    private static let limit = 950_000

    static var available: Bool { FileManager.default.ubiquityIdentityToken != nil }

    static var lastSaved: Date? { UserDefaults.standard.object(forKey: savedKey) as? Date }

    private static let queue = DispatchQueue(label: "wick.backup", qos: .utility)
    private static let fingerprintKey = "wick.backup.fingerprint"

    /// Saves in the background after changes. Never shrinks the backup: whatever iCloud already holds is merged in first,
    /// so a new phone that skipped restore cannot wipe years of journal.
    static func save(_ model: AppModel) {
        guard let payload = payload(model) else { return }
        let print = fingerprint(payload)
        guard UserDefaults.standard.string(forKey: fingerprintKey) != print else { return }
        queue.async { if write(payload) { UserDefaults.standard.set(print, forKey: fingerprintKey) } }
    }

    /// Saves right away, for the Back up now button.
    static func saveNow(_ model: AppModel) -> Bool {
        guard let payload = payload(model) else { return false }
        let ok = queue.sync { write(payload) }
        if ok { UserDefaults.standard.set(fingerprint(payload), forKey: fingerprintKey) }
        return ok
    }

    /// Removes the backup from iCloud.
    static func erase() {
        let store = NSUbiquitousKeyValueStore.default
        store.removeObject(forKey: key)
        store.synchronize()
        UserDefaults.standard.removeObject(forKey: savedKey)
        UserDefaults.standard.removeObject(forKey: fingerprintKey)
    }

    private static func payload(_ model: AppModel) -> BackupPayload? {
        guard available, !model.demo, model.settings.backupOn, !model.records.isEmpty else { return nil }
        let s = model.settings
        return BackupPayload(savedAt: Date(), records: model.records, earned: model.earned, planID: s.planID,
                             planPositions: s.planPositions, pinnedTrophies: s.pinnedTrophies, passUses: s.passUses,
                             preferredRead: s.preferredRead, preferredReflect: s.preferredReflect, voiceID: s.voiceID,
                             reminderOn: s.reminderOn, reminderMinutes: s.reminderMinutes, allowAlreadyRead: s.allowAlreadyRead,
                             shieldStyle: s.shieldStyle, shieldTheme: s.shieldTheme,
                             reviews: model.reviews, allowReviewUnread: s.allowReviewUnread)
    }

    private static func fingerprint(_ p: BackupPayload) -> String {
        let last = p.records.map(\.completedAt.timeIntervalSince1970).max() ?? 0
        return "\(p.records.count).\(p.reviews?.count ?? 0).\(p.earned.count).\(Int(last)).\(p.planID).\(p.planPositions.values.reduce(0, +))"
    }

    /// Combines this iPhone's history with what iCloud already has. Settings come from this iPhone.
    static func merged(_ local: BackupPayload, with remote: BackupPayload?) -> BackupPayload {
        guard let remote else { return local }
        var out = local
        var byID = Dictionary(local.records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in remote.records {
            if let mine = byID[r.id] {
                if mine.reflection.isEmpty && !r.reflection.isEmpty { byID[r.id]?.reflection = r.reflection }
            } else {
                byID[r.id] = r
            }
        }
        out.records = byID.values.sorted { $0.completedAt < $1.completedAt }
        var reviews = Dictionary((local.reviews ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in remote.reviews ?? [] where reviews[r.id] == nil { reviews[r.id] = r }
        out.reviews = reviews.values.sorted { $0.completedAt < $1.completedAt }
        for (id, date) in remote.earned { out.earned[id] = min(out.earned[id] ?? date, date) }
        for (plan, pos) in remote.planPositions { out.planPositions[plan] = max(out.planPositions[plan] ?? 0, pos) }
        out.pinnedTrophies = Array(Set(local.pinnedTrophies + remote.pinnedTrophies))
        out.passUses = Array(Set(local.passUses + remote.passUses)).sorted { $0.date < $1.date }
        return out
    }

    private static func write(_ local: BackupPayload) -> Bool {
        var payload = merged(local, with: latest())
        var data = pack(payload)
        // ponytail: years of long reflections could pass iCloud's 1 MB; then the oldest reflection text is dropped first,
        // a tenth of the journal at a time. Upgrade path is a CloudKit record if people ever hit this.
        let sorted = payload.records.indices.sorted { payload.records[$0].completedAt < payload.records[$1].completedAt }
        var i = 0
        let step = max(1, sorted.count / 10)
        while let d = data, d.count > limit, i < sorted.count {
            for j in sorted[i..<min(sorted.count, i + step)] { payload.records[j].reflection = "" }
            i += step
            data = pack(payload)
        }
        guard let data, data.count <= limit else { return false }
        let store = NSUbiquitousKeyValueStore.default
        store.set(data, forKey: key)
        store.synchronize()
        UserDefaults.standard.set(Date(), forKey: savedKey)
        return true
    }

    static func latest() -> BackupPayload? {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        guard let data = store.data(forKey: key),
              let raw = try? (data as NSData).decompressed(using: .zlib) as Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(BackupPayload.self, from: raw)
    }

    private static func pack(_ payload: BackupPayload) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let json = try? encoder.encode(payload) else { return nil }
        return try? (json as NSData).compressed(using: .zlib) as Data
    }
}

extension AppModel {
    /// Brings a backup in without losing anything already on this phone.
    func restore(_ backup: BackupPayload) {
        var byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in backup.records where byID[r.id] == nil { byID[r.id] = r }
        let merged = byID.values.sorted { $0.completedAt < $1.completedAt }
        store.records = merged

        var earnedNow = store.earned
        for (id, date) in backup.earned { earnedNow[id] = min(earnedNow[id] ?? date, date) }
        store.earned = earnedNow

        settings.planID = backup.planID
        for (plan, pos) in backup.planPositions { settings.planPositions[plan] = max(settings.planPositions[plan] ?? 0, pos) }
        settings.pinnedTrophies = Array(Set(settings.pinnedTrophies + backup.pinnedTrophies))
        settings.passUses = Array(Set(settings.passUses + backup.passUses)).sorted { $0.date < $1.date }
        settings.preferredRead = backup.preferredRead
        settings.preferredReflect = backup.preferredReflect
        settings.voiceID = backup.voiceID
        settings.reminderOn = backup.reminderOn
        settings.reminderMinutes = backup.reminderMinutes
        settings.allowAlreadyRead = backup.allowAlreadyRead
        settings.shieldStyle = backup.shieldStyle
        settings.shieldTheme = backup.shieldTheme
        settings.allowReviewUnread = backup.allowReviewUnread ?? settings.allowReviewUnread
        var reviewsByID = Dictionary(store.reviews.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in backup.reviews ?? [] where reviewsByID[r.id] == nil { reviewsByID[r.id] = r }
        store.reviews = reviewsByID.values.sorted { $0.completedAt < $1.completedAt }
        store.settings = settings
        refresh()
    }
}

/// Backup status and actions in Settings.
struct BackupRow: View {
    @Environment(AppModel.self) private var model
    @State private var message: String?
    @State private var confirmRestore = false
    @State private var found: BackupPayload?

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            if CloudBackup.available {
                Toggle(isOn: $model.settings.backupOn) {
                    Label("Back up to iCloud", systemImage: model.settings.backupOn ? "checkmark.icloud" : "icloud.slash")
                        .foregroundStyle(Theme.ink)
                }
                .onChange(of: model.settings.backupOn) { _, on in
                    model.savePreferences()
                    if on { CloudBackup.save(model) }
                }
            } else {
                Label("iCloud is off on this iPhone", systemImage: "icloud.slash").foregroundStyle(Theme.dim)
            }
            Text(detail).font(.footnote).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            if CloudBackup.available && model.settings.backupOn {
                HStack(spacing: 16) {
                    Button("Back up now") {
                        message = CloudBackup.saveNow(model) ? "Backed up just now." : "Nothing to back up yet. Finish a chapter first."
                    }
                    .buttonStyle(.borderless)
                    Button("Restore") {
                        found = CloudBackup.latest()
                        if found == nil { message = "No backup found in iCloud yet." } else { confirmRestore = true }
                    }
                    .buttonStyle(.borderless)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.gold)
            }
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.dim) }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Restore from iCloud?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore") {
                if let found { model.restore(found); message = "Restored \(found.records.count) readings." }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Readings, journal entries, streaks, trophies, and places in each book are added to what is on this iPhone. Your reading and reflection style, reminder time, lock screen look, and active plan switch to the backup's.")
        }
    }

    private var detail: String {
        guard CloudBackup.available else {
            return "Sign in to iCloud in the Settings app to keep your journal, streaks, and trophies safe."
        }
        guard model.settings.backupOn else {
            return "Backup is off. Your journal, streaks, and trophies stay only on this iPhone. Your existing iCloud backup is kept until you delete your data."
        }
        if let saved = CloudBackup.lastSaved {
            return "Your journal, streaks, trophies, and reading places save to your iCloud automatically. Last saved \(saved.formatted(.relative(presentation: .named)))."
        }
        return "Your journal, streaks, trophies, and reading places save to your iCloud automatically after each reading."
    }
}

/// Offered on the first setup screen when this iPhone is new but iCloud has a backup.
struct RestoreOffer: View {
    @Environment(AppModel.self) private var model
    @State private var backup: BackupPayload?
    @State private var done = false

    var body: some View {
        Group {
            if let backup, !done, model.records.isEmpty {
                CardBox(padding: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Welcome back 👋").font(.headline).foregroundStyle(Theme.ink)
                        Text("We found your iCloud backup with \(backup.records.count) readings, your journal, and your trophies.")
                            .font(.subheadline).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                        Button("Restore my progress") {
                            model.restore(backup)
                            withAnimation { done = true }
                        }
                        .buttonStyle(.phos)
                    }
                }
            } else if done {
                Label("Progress restored. Set up your locks to finish.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.green)
            }
        }
        .onAppear { if CloudBackup.available && !model.demo { backup = CloudBackup.latest() } }
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
            DispatchQueue.main.async { if model.records.isEmpty { backup = CloudBackup.latest() } }
        }
    }
}
