import DeviceActivity
import FamilyControls
import Foundation
import Observation
import SwiftUI
import UserNotifications
import WidgetKit

enum Route: String, Identifiable {
    case reading, unlock, focus, recite
    var id: String { rawValue }
}

enum UnlockMethod {
    case reading, question, tap, otherWay, pass
}

@Observable
final class AppModel {
    let store: SharedStore
    let demo: Bool

    var settings: AppSettings
    var today: TodayState
    var records: [DayRecord]
    var authorized = false
    var route: Route?
    var now = Date()
    /// Set after a reading so the result screen can offer where the path picks up.
    var lastAfter: PathLogic.After?
    /// Locks the last reading or other unlock opened, for the result screen.
    var lastUnlocked: [LockSet] = []

    init(store: SharedStore = .shared, demo: Bool = ProcessInfo.processInfo.arguments.contains("-demoData")) {
        self.store = store
        self.demo = demo
        if demo { DemoData.seed(store) }
        settings = store.settings
        today = store.today()
        records = store.records
        authorized = demo || AuthorizationCenter.shared.authorizationStatus == .approved
        migrate()
        refresh()
    }

    private func migrate() {
        var s = settings
        s.planID = ReadingPlans.canonical(s.planID)
        var positions: [String: Int] = [:]
        for (k, v) in s.planPositions { positions[ReadingPlans.canonical(k)] = max(positions[ReadingPlans.canonical(k)] ?? 0, v) }
        s.planPositions = positions
        if s.lockSets.isEmpty, let legacy = store.selectionData {
            var lock = LockSet()
            lock.name = "Distractions"
            lock.selection = legacy
            lock.appCount = Blocker.lockedCount(Blocker.selection(from: legacy))
            s.lockSets = [lock]
            store.selectionData = nil
        }
        if s != settings {
            settings = s
            store.settings = s
        }
    }

    // MARK: Paths

    var plan: ReadingPlan { ReadingPlans.plan(settings.planID) }

    func position(_ p: ReadingPlan) -> Int { min(settings.planPositions[p.id] ?? 0, p.chapters.count) }

    var planPosition: Int { position(plan) }

    var planFinished: Bool { planPosition >= plan.chapters.count }

    var readIDs: Set<String> { Set(records.map(\.ref.id)) }

    func readCount(_ p: ReadingPlan) -> Int {
        let ids = readIDs
        return p.chapters.filter { ids.contains($0.id) }.count
    }

    func lastRead(_ p: ReadingPlan) -> Date? {
        let ids = Set(p.chapters.map(\.id))
        return records.filter { ids.contains($0.ref.id) }.map(\.completedAt).max()
    }

    func lastRead(_ ref: ChapterRef) -> Date? {
        records.filter { $0.ref == ref }.map(\.completedAt).max()
    }

    var otherPathsInProgress: [ReadingPlan] {
        ReadingPlans.all
            .filter { $0.id != plan.id && position($0) > 0 && position($0) < $0.chapters.count }
            .sorted { (lastRead($0) ?? .distantPast) > (lastRead($1) ?? .distantPast) }
    }

    var todaysChapter: ChapterRef {
        if let c = today.chapter { return c }
        return plan.chapters[min(planPosition, plan.chapters.count - 1)]
    }

    var todaysTitle: String { BookNames.title(todaysChapter) }

    var currentChapterDoneToday: Bool {
        records.contains { $0.dayKey == today.dayKey && $0.ref == todaysChapter }
    }

    var planDay: Int { min(planPosition + (currentChapterDoneToday ? 0 : 1), plan.chapters.count) }

    var doneKeys: Set<String> { Set(records.map(\.dayKey)) }

    var streak: Int { Streaks.current(doneKeys: doneKeys, todayKey: today.dayKey) }

    var todaysRecord: DayRecord? {
        records.filter { $0.dayKey == today.dayKey }.min { $0.completedAt < $1.completedAt }
    }

    func record(for ref: ChapterRef) -> DayRecord? {
        records.filter { $0.dayKey == today.dayKey && $0.ref == ref }.max { $0.completedAt < $1.completedAt }
    }

    func choose(planID: String, index: Int) {
        let p = ReadingPlans.plan(planID)
        guard p.chapters.indices.contains(index) else { return }
        let ref = p.chapters[index]
        if settings.planID != p.id {
            settings.planID = p.id
            store.settings = settings
        }
        if today.chapter != ref { today.readingStartedAt = nil }
        today.chapter = ref
        today.contextPlanID = p.id
        today.contextIndex = index
        saveToday()
    }

    func makeActive(_ planID: String) {
        let p = ReadingPlans.plan(planID)
        settings.planID = p.id
        store.settings = settings
        today.chapter = nil
        today.contextPlanID = nil
        today.contextIndex = nil
        today.readingStartedAt = nil
        saveToday()
    }

    func setPosition(_ planID: String, _ index: Int) {
        let p = ReadingPlans.plan(planID)
        settings.planPositions[p.id] = min(max(0, index), p.chapters.count)
        store.settings = settings
        if settings.planID == p.id && !currentChapterDoneToday {
            today.chapter = nil
            today.contextPlanID = nil
            today.contextIndex = nil
            today.readingStartedAt = nil
        }
        saveToday()
    }

    func restart(_ planID: String) { setPosition(planID, 0) }

    func beginReading(_ ref: ChapterRef) {
        if today.chapter != ref {
            today.chapter = ref
            if let i = plan.chapters.firstIndex(of: ref) {
                today.contextPlanID = plan.id
                today.contextIndex = i
            }
            today.readingStartedAt = nil
        }
        if today.readingStartedAt == nil { today.readingStartedAt = Date() }
        saveToday()
    }

    // MARK: Locks

    var locks: [LockSet] { settings.lockSets }

    func lock(_ id: String) -> LockSet? { settings.lockSets.first { $0.id == id } }

    func state(_ lock: LockSet) -> LockLogic.State { LockLogic.state(lock, today: today, now: now) }

    var lockReason: LockReason { LockLogic.reason(today: today, locks: settings.lockSets, now: now) }

    var lockedLocks: [LockSet] { settings.lockSets.filter { state($0).isLocked } }

    var readingCheck: ReadingCheck { LockLogic.readingCheck(today: today, locks: settings.lockSets, now: now) }

    var lockedCount: Int { demo ? 4 : lockedLocks.map(\.appCount).reduce(0, +) }

    func passesLeft(_ lock: LockSet) -> Int { settings.passesLeft(lock, now: now) }

    var pendingByLock: [String: PendingLock] {
        Dictionary(uniqueKeysWithValues: settings.pendingLocks.map { ($0.id, $0) })
    }

    var greeting: String {
        let h = Calendar.current.component(.hour, from: now)
        return h < 12 ? "Good morning" : (h < 17 ? "Good afternoon" : "Good evening")
    }

    func unlock(_ lock: LockSet, method: UnlockMethod) {
        let now = Date()
        var day = today.day(lock.id)
        let end: Date
        if method == .pass {
            end = now.addingTimeInterval(15 * 60)
            day.passUntil = end
        } else {
            end = LockLogic.rewardEnd(lock, now: now)
            day.until = max(end, day.until ?? end)
            day.count += 1
        }
        if method == .question { today.recallCount += 1 }
        today.unlocks[lock.id] = day
        self.now = now
        saveToday()
        if !demo {
            Blocker.scheduleRelock(lockID: lock.id, at: end, now: now)
            LockEngine.sync(store: store, now: now)
        }
    }

    /// Unlocks every lock that is waiting on one of these states. Returns the ones opened.
    @discardableResult
    func unlockAll(in states: Set<LockLogic.State>, method: UnlockMethod) -> [LockSet] {
        let targets = settings.lockSets.filter { states.contains(state($0)) }
        for lock in targets { unlock(lock, method: method) }
        lastUnlocked = targets
        return targets
    }

    func lockNow(_ lock: LockSet) {
        var day = today.day(lock.id)
        day.until = nil
        day.passUntil = nil
        today.unlocks[lock.id] = day
        now = Date()
        saveToday()
        if !demo {
            Blocker.cancelRelock(lockID: lock.id)
            LockEngine.sync(store: store, now: now)
        }
    }

    func useEmergencyPass(_ lock: LockSet) {
        settings.passUses.append(PassUse(date: Date(), minutes: 15, lockID: lock.id))
        store.settings = settings
        unlock(lock, method: .pass)
    }

    private func applyLocks() {
        store.settings = settings
        writeSnapshot()
        if settings.onboarded && !demo {
            Blocker.registerDaily(settings: settings)
            LockEngine.sync(store: store, now: Date())
        }
    }

    func createLock(_ lock: LockSet) {
        var l = lock
        l.createdAt = Date()
        settings.lockSets.append(l)
        applyLocks()
    }

    func saveLock(_ lock: LockSet) {
        guard let i = settings.lockSets.firstIndex(where: { $0.id == lock.id }) else { return }
        settings.lockSets[i] = lock
        settings.pendingLocks.removeAll { $0.id == lock.id }
        applyLocks()
    }

    func deleteLock(_ id: String) {
        settings.lockSets.removeAll { $0.id == id }
        settings.pendingLocks.removeAll { $0.id == id }
        applyLocks()
    }

    /// Saves a change that starts after the lock's delay.
    func scheduleChange(_ lock: LockSet, deleted: Bool, hours: Int) -> Date {
        let when = Date().addingTimeInterval(TimeInterval(hours * 3600))
        settings.pendingLocks.removeAll { $0.id == lock.id }
        settings.pendingLocks.append(PendingLock(lock: lock, deleted: deleted, effectiveAt: when))
        store.settings = settings
        return when
    }

    func cancelPending(_ id: String) {
        settings.pendingLocks.removeAll { $0.id == id }
        store.settings = settings
    }

    /// Adding apps only makes a lock stronger, so it never needs protection.
    func addApps(to id: String, picked: FamilyActivitySelection) {
        guard let i = settings.lockSets.firstIndex(where: { $0.id == id }) else { return }
        let merged = Blocker.union(Blocker.selection(from: settings.lockSets[i].selection), picked)
        settings.lockSets[i].selection = Blocker.encode(merged)
        settings.lockSets[i].appCount = Blocker.lockedCount(merged)
        applyLocks()
    }

    func checkPasscode(_ code: String, for lock: LockSet) -> Bool { Passcode.verify(code, lock.protection) }

    func forgotPasscode(_ id: String) {
        guard let i = settings.lockSets.firstIndex(where: { $0.id == id }) else { return }
        settings.lockSets[i].protection.passcodeResetAt = Date().addingTimeInterval(86_400)
        store.settings = settings
    }

    // MARK: Lifecycle

    func refresh() {
        now = Date()
        var changed = false
        for pending in settings.pendingLocks where now >= pending.effectiveAt {
            if pending.deleted {
                settings.lockSets.removeAll { $0.id == pending.id }
            } else if let i = settings.lockSets.firstIndex(where: { $0.id == pending.id }) {
                settings.lockSets[i] = pending.lock
            }
            changed = true
        }
        settings.pendingLocks.removeAll { now >= $0.effectiveAt }
        for i in settings.lockSets.indices {
            if let reset = settings.lockSets[i].protection.passcodeResetAt, now >= reset {
                settings.lockSets[i].protection.passcodeHash = nil
                settings.lockSets[i].protection.passcodeSalt = nil
                settings.lockSets[i].protection.passcodeResetAt = nil
                settings.lockSets[i].protection.kind = .none
                changed = true
            }
        }
        if changed {
            store.settings = settings
            if !demo { Blocker.registerDaily(settings: settings) }
        }
        today = store.today(now: now, morning: settings.schedule.morning)
        records = store.records
        writeSnapshot()
        if settings.onboarded && !demo { LockEngine.sync(store: store, now: now) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func writeSnapshot() {
        var snap = store.snapshot
        snap.style = settings.shieldStyle
        snap.reason = lockReason
        snap.streak = streak
        snap.chapterTitle = todaysTitle
        snap.readingDone = today.readingDone
        snap.lockedCount = lockedCount
        snap.planName = plan.name
        snap.planDay = planDay
        snap.planLength = plan.chapters.count
        let (ref, verse) = demo ? (ChapterRef(book: "PSA", chapter: 119), 105) : DailyVerses.pick(for: today.dayKey)
        let text = Bible.shared.verse(ref, verse).trimmingCharacters(in: CharacterSet(charactersIn: "“”‘’\"' "))
        if !text.isEmpty {
            snap.verseText = text
            snap.verseRef = BookNames.verseTitle(ref, verse)
        }
        store.snapshot = snap
    }

    private func saveToday() {
        store.storedToday = today
        writeSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func savePreferences() {
        store.settings = settings
        writeSnapshot()
    }

    /// Opens the unlock screen after the lock sends someone here.
    func routeFromLock() {
        guard settings.onboarded, route == nil else { return }
        switch lockReason {
        case .recall, .tap, .usedUp, .strict: route = .unlock
        case .reading, .none: break
        }
    }

    // MARK: Screen Time

    func requestAuthorization() async {
        if demo { authorized = true; return }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {}
        await MainActor.run { authorized = AuthorizationCenter.shared.authorizationStatus == .approved }
    }

    var reportSelection: FamilyActivitySelection { Blocker.union(settings.lockSets) }

    func finishOnboarding() {
        settings.onboarded = true
        settings.onboardedAt = Date()
        applyLocks()
    }

    // MARK: Reading

    /// Saved progress for this chapter today, if any.
    func draft(for ref: ChapterRef) -> ReadingDraft? {
        guard let d = store.readingDraft, d.dayKey == today.dayKey, d.ref == ref else { return nil }
        return d
    }

    func saveDraft(_ draft: ReadingDraft) {
        store.readingDraft = draft
    }

    func clearDraft() {
        store.readingDraft = nil
    }

    var nextAttemptAt: Date? {
        guard let d = today.nextAttemptAt, d > Date() else { return nil }
        return d
    }

    func markAsked(_ items: [QuizItem]) {
        let ids = items.map(\.id).filter { !today.askedQuestionIDs.contains($0) }
        today.askedQuestionIDs += ids
        saveToday()
    }

    @discardableResult
    func registerMiss() -> Date {
        today.missesToday += 1
        let next = Date().addingTimeInterval(QuizEngine.waitAfterMiss(missCount: today.missesToday))
        today.nextAttemptAt = next
        saveToday()
        return next
    }

    /// Saves the reading, moves the path, unlocks waiting locks, and returns where the path picks up.
    @discardableResult
    func completeReading(ref: ChapterRef, readMode: ReadMode, reflectMode: ReflectMode, reflection: String, score: Int, total: Int) -> PathLogic.After? {
        var contextPlan: ReadingPlan?
        var contextIndex: Int?
        if let id = today.contextPlanID, let i = today.contextIndex, ReadingPlans.plan(id).chapters.indices.contains(i),
           ReadingPlans.plan(id).chapters[i] == ref {
            contextPlan = ReadingPlans.plan(id)
            contextIndex = i
        } else if let i = plan.chapters.firstIndex(of: ref) {
            contextPlan = plan
            contextIndex = i
        } else if let bp = ReadingPlans.bookPlan(ref.book), let i = bp.chapters.firstIndex(of: ref) {
            contextPlan = bp
            contextIndex = i
        }

        let seconds = Int(Date().timeIntervalSince(today.readingStartedAt ?? Date()))
        let record = DayRecord(dayKey: today.dayKey, ref: ref, title: BookNames.title(ref), readMode: readMode,
                               reflectMode: reflectMode, reflection: reflection, score: score, total: total,
                               completedAt: Date(), readingSeconds: max(0, seconds), fromPlan: contextPlan != nil)
        var all = store.records
        all.append(record)
        store.records = all
        records = all

        var after: PathLogic.After?
        if let p = contextPlan, let i = contextIndex {
            let result = PathLogic.after(planID: p.id, index: i, position: position(p), count: p.chapters.count)
            settings.planPositions[p.id] = result.position
            settings.planID = p.id
            after = result
        }
        let waiting = settings.lockSets.filter { [.needsReading, .needsQuestion, .needsTap].contains(state($0)) }
        today.readingDone = true
        today.chapter = ref
        today.contextPlanID = nil
        today.contextIndex = nil
        today.readingStartedAt = nil
        today.missesToday = 0
        today.nextAttemptAt = nil
        settings.preferredRead = readMode
        settings.preferredReflect = reflectMode
        store.settings = settings
        saveToday()
        clearDraft()
        for lock in waiting { unlock(lock, method: .reading) }
        lastUnlocked = waiting
        lastAfter = after
        return after
    }
}
