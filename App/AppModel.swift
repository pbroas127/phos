import DeviceActivity
import FamilyControls
import Foundation
import Observation
import SwiftUI
import UserNotifications
import WidgetKit

enum Route: String, Identifiable {
    case reading, unlock
    var id: String { rawValue }
}

enum UnlockMethod {
    case reading, question, tap, pass
}

@Observable
final class AppModel {
    let store: SharedStore
    let demo: Bool

    var settings: AppSettings
    var today: TodayState
    var records: [DayRecord]
    /// Quizzes taken on their own after reading. They never open apps.
    var reviews: [ReviewRecord] = []
    var authorized = false
    var route: Route?
    var now = TrustedClock.now()
    /// Set after a reading so the result screen can offer where the path picks up.
    var lastAfter: PathLogic.After?
    /// Locks the last reading or other unlock opened, for the result screen.
    var lastUnlocked: [LockSet] = []
    /// Locks a finished reading can open. The result screen asks whether to open them now or save them for later.
    var readyToUnlock: [LockSet] = []
    var tab = DemoScreen.startTab
    /// Notifications are turned off, so the lock screen button cannot open Wick.
    var notificationsDenied = false
    /// A widget or link asked to start reading in a particular way.
    var startMode: ReadMode?
    /// Trophy history, recomputed after readings and on refresh.
    private(set) var stats: AchievementStats
    private(set) var earned: [String: Date] = [:]
    /// Newly earned trophies waiting to be celebrated.
    var celebrating: [Achievement] = []

    init(store: SharedStore = .shared, demo: Bool = ProcessInfo.processInfo.arguments.contains("-demoData")) {
        self.store = store
        self.demo = demo
        if demo { DemoData.seed(store) }
        settings = store.settings
        today = store.today()
        records = store.records
        stats = AchievementStats(records: [], passUses: [], usage: [:], watchedDays: [], todayKey: "")
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

    // MARK: Reviews

    /// Puts the model back to a first launch after every stored value was removed.
    func resetAfterDelete() {
        settings = AppSettings()
        today = TodayState(dayKey: DayKey.key(for: TrustedClock.now(), morning: settings.schedule.morning))
        records = []
        reviews = []
        earned = [:]
        celebrating = []
        readyToUnlock = []
        lastUnlocked = []
        lastAfter = nil
        route = nil
        tab = 0
        stats = AchievementStats(records: [], passUses: [], usage: [:], watchedDays: [], todayKey: today.dayKey)
    }

    /// The most recently read chapters, newest first, without repeats.
    func recentReadChapters(limit: Int) -> [ChapterRef] {
        var seen = Set<String>()
        var out: [ChapterRef] = []
        for r in records.sorted(by: { $0.completedAt > $1.completedAt }) where !seen.contains(r.ref.id) {
            seen.insert(r.ref.id)
            out.append(r.ref)
            if out.count == limit { break }
        }
        return out
    }

    struct BookProgress { let id: String; let name: String; let read: Int; let total: Int }

    /// Books with at least one chapter read, in Bible order.
    func booksWithReadings() -> [BookProgress] {
        let ids = readIDs
        return BookNames.order.compactMap { book in
            let total = ReadingPlans.chapterCounts[book] ?? 0
            let read = (1...max(1, total)).filter { ids.contains("\(book).\($0)") }.count
            return read == 0 ? nil : BookProgress(id: book, name: BookNames.name(book), read: read, total: total)
        }
    }

    func canReview(_ ref: ChapterRef) -> Bool { settings.allowReviewUnread || readIDs.contains(ref.id) }

    func reviews(for ref: ChapterRef) -> [ReviewRecord] { reviews.filter { $0.scope == ref.id } }

    func reviewItems(_ r: ReviewRequest) -> [QuizItem] {
        let banks = r.chapters.map { ($0.id, QuestionBank.shared.questions(for: $0)?.questions ?? []) }
        let picked = QuizEngine.review(banks: banks, total: r.total, asked: store.reviewAsked)
        if !demo { store.reviewAsked = picked.asked }
        return picked.items
    }

    func completeReview(_ r: ReviewRequest, score: Int, total: Int) {
        guard total > 0 else { return }
        var all = store.reviews
        all.append(ReviewRecord(scope: r.scope, chapterIDs: r.chapters.map(\.id), score: score, total: total, completedAt: TrustedClock.now()))
        store.reviews = all
        reviews = all
        checkAchievements()
        if settings.onboarded && !demo { CloudBackup.save(self) }
        WidgetWriter.write(self)
    }

    func choose(planID: String, index: Int, makeActive: Bool = true) {
        rollover()
        let p = ReadingPlans.plan(planID)
        guard p.chapters.indices.contains(index) else { return }
        let ref = p.chapters[index]
        if makeActive && settings.planID != p.id {
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
        rollover()
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
        rollover()
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
        rollover()
        if today.chapter != ref {
            today.chapter = ref
            if let i = plan.chapters.firstIndex(of: ref) {
                today.contextPlanID = plan.id
                today.contextIndex = i
            }
            today.readingStartedAt = nil
        }
        if today.readingStartedAt == nil { today.readingStartedAt = TrustedClock.now() }
        saveToday()
    }

    // MARK: Locks

    var locks: [LockSet] { settings.lockSets }

    func lock(_ id: String) -> LockSet? { settings.lockSets.first { $0.id == id } }

    /// The day before today, for overnight locks whose window started last evening.
    var yesterdayState: TodayState? { demo ? nil : store.previousDay(before: today.dayKey) }

    func state(_ lock: LockSet) -> LockLogic.State {
        LockLogic.state(lock, today: today, yesterday: yesterdayState, now: now, morning: settings.schedule.morning)
    }

    var lockReason: LockReason {
        LockLogic.reason(today: today, yesterday: yesterdayState, locks: settings.lockSets, now: now, morning: settings.schedule.morning)
    }

    var lockedLocks: [LockSet] { settings.lockSets.filter { state($0).isLocked } }

    var readingCheck: ReadingCheck {
        LockLogic.readingCheck(today: today, yesterday: yesterdayState, locks: settings.lockSets, now: now, morning: settings.schedule.morning)
    }

    var lockedCount: Int { demo ? 4 : lockedLocks.map(\.appCount).reduce(0, +) }

    /// A lock's unlocks right now, from the day its window started.
    func lockDay(_ lock: LockSet) -> LockDay {
        LockLogic.day(for: lock, today: today, yesterday: demo ? nil : store.previousDay(before: today.dayKey), now: now,
                      morning: settings.schedule.morning).day(lock.id)
    }

    /// "4 apps locked" or "4 apps and categories locked".
    var lockedLabel: String {
        let n = lockedCount
        if lockedLocks.contains(where: { $0.categoryCount > 0 }) { return n == 1 ? "1 category" : "\(n) apps and categories" }
        return n == 1 ? "1 app" : "\(n) apps"
    }

    func passesLeft(_ lock: LockSet) -> Int { settings.passesLeft(lock, now: now) }

    var pendingByLock: [String: PendingLock] {
        Dictionary(uniqueKeysWithValues: settings.pendingLocks.map { ($0.id, $0) })
    }

    var greeting: String {
        let h = Calendar.current.component(.hour, from: now)
        return h < 12 ? "Good morning" : (h < 17 ? "Good afternoon" : "Good evening")
    }

    func unlock(_ lock: LockSet, method: UnlockMethod) {
        rollover()
        let now = TrustedClock.now()
        // An overnight window after midnight keeps its unlocks on the day it started.
        let previous = demo ? nil : store.previousDay(before: today.dayKey)
        let onPrevious = LockLogic.usesPreviousDay(lock, today: today, yesterday: previous, now: now, morning: settings.schedule.morning)
        var target = onPrevious ? (previous ?? today) : today
        var day = target.day(lock.id)
        let end: Date
        if method == .pass {
            end = now.addingTimeInterval(15 * 60)
            day.passUntil = end
        } else {
            end = LockLogic.rewardEnd(lock, now: now)
            // The reading itself opens a limited lock without using one of its unlocks.
            day = LockLogic.opened(day, until: end, spendsUnlock: method != .reading)
        }
        if method == .question { today.recallCount += 1 }
        target.unlocks[lock.id] = day
        if onPrevious { store.yesterday = target } else { today.unlocks[lock.id] = day }
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
        rollover()
        var day = today.day(lock.id)
        day.until = nil
        day.passUntil = nil
        today.unlocks[lock.id] = day
        now = TrustedClock.now()
        saveToday()
        if !demo {
            Blocker.cancelRelock(lockID: lock.id)
            LockEngine.sync(store: store, now: now)
        }
    }

    func useEmergencyPass(_ lock: LockSet) {
        settings.passUses.append(PassUse(date: TrustedClock.now(), minutes: 15, lockID: lock.id))
        store.settings = settings
        unlock(lock, method: .pass)
    }

    private func applyLocks() {
        store.settings = settings
        writeSnapshot()
        if settings.onboarded && !demo {
            Blocker.registerDaily(settings: settings)
            LockEngine.sync(store: store, now: TrustedClock.now())
        }
    }

    func createLock(_ lock: LockSet) {
        var l = lock
        l.createdAt = TrustedClock.now()
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
        let when = TrustedClock.now().addingTimeInterval(TimeInterval(hours * 3600))
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
        Blocker.set(Blocker.union(Blocker.selection(from: settings.lockSets[i].selection), picked), on: &settings.lockSets[i])
        // A delayed change waiting to start gets the new apps too, so it does not remove them when it lands.
        if let p = settings.pendingLocks.firstIndex(where: { $0.id == id && !$0.deleted }) {
            let pending = Blocker.selection(from: settings.pendingLocks[p].lock.selection)
            Blocker.set(Blocker.union(pending, picked), on: &settings.pendingLocks[p].lock)
        }
        applyLocks()
    }

    /// Wrong tries in a row make the passcode wait a while. The right passcode also cancels a pending reset.
    func checkPasscode(_ code: String, for lock: LockSet) -> Bool {
        guard let i = settings.lockSets.firstIndex(where: { $0.id == lock.id }) else { return false }
        var p = settings.lockSets[i].protection
        if let until = p.lockedOutUntil, until > TrustedClock.now() { return false }
        let ok = Passcode.verify(code, p)
        if ok {
            p.failedAttempts = 0
            p.lockedOutUntil = nil
            p.passcodeResetAt = nil
        } else {
            p.failedAttempts += 1
            let wait = Passcode.wait(afterFailures: p.failedAttempts)
            if wait > 0 { p.lockedOutUntil = TrustedClock.now().addingTimeInterval(wait) }
        }
        settings.lockSets[i].protection = p
        store.settings = settings
        return ok
    }

    func forgotPasscode(_ id: String) {
        guard let i = settings.lockSets.firstIndex(where: { $0.id == id }) else { return }
        settings.lockSets[i].protection.passcodeResetAt = TrustedClock.now().addingTimeInterval(86_400)
        store.settings = settings
    }

    /// Keeping the passcode only makes the lock stronger, so anyone can cancel a reset.
    func cancelPasscodeReset(_ id: String) {
        guard let i = settings.lockSets.firstIndex(where: { $0.id == id }) else { return }
        settings.lockSets[i].protection.passcodeResetAt = nil
        store.settings = settings
    }

    // MARK: Lifecycle

    func refresh() {
        now = TrustedClock.now()
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
                settings.lockSets[i].protection.failedAttempts = 0
                settings.lockSets[i].protection.lockedOutUntil = nil
                settings.lockSets[i].protection.kind = .none
                changed = true
            }
        }
        if changed {
            store.settings = settings
            if !demo { Blocker.registerDaily(settings: settings) }
        }
        move(to: store.today(now: now, morning: settings.schedule.morning))
        records = store.records
        reviews = store.reviews
        if !demo { authorized = AuthorizationCenter.shared.authorizationStatus == .approved }
        let keys = Array(doneKeys).sorted()
        if store.doneKeys != keys { store.doneKeys = keys }
        checkNotificationPermission()
        writeSnapshot()
        if settings.onboarded && !demo { LockEngine.sync(store: store, now: now) }
        checkAchievements()
        ReminderScheduler.reschedule(self)
        if settings.onboarded { CloudBackup.save(self) }
        WidgetWriter.write(self)
    }

    /// Recomputes trophy progress and queues a celebration for anything newly earned.
    func checkAchievements() {
        stats = AchievementStats(records: records, passUses: settings.passUses, usage: store.usage, watchedDays: store.watchedDays,
                                 todayKey: today.dayKey, reviews: reviews, morning: settings.schedule.morning)
        var saved = store.earned
        let firstLook = saved.isEmpty && records.count > 1
        let new = Achievements.all.filter { saved[$0.id] == nil && $0.done(stats) }
        guard !new.isEmpty else {
            earned = saved
            return
        }
        for a in new { saved[a.id] = demo ? TrustedClock.now().addingTimeInterval(-86_400) : TrustedClock.now() }
        store.earned = saved
        earned = saved
        // History from before trophies existed is awarded quietly, so the first launch is not a parade.
        if !firstLook && !demo { celebrating += new }
    }

    func togglePin(_ a: Achievement) {
        if let i = settings.pinnedTrophies.firstIndex(of: a.id) {
            settings.pinnedTrophies.remove(at: i)
        } else {
            settings.pinnedTrophies.append(a.id)
        }
        store.settings = settings
        WidgetWriter.write(self)
    }


    func writeSnapshot() {
        var snap = store.snapshot
        snap.style = settings.shieldStyle
        snap.theme = settings.shieldTheme
        snap.reason = lockReason
        snap.streak = streak
        snap.chapterTitle = todaysTitle
        let read = readChapters(on: today.dayKey)
        snap.questionTopic = read.count == 1 ? BookNames.title(read[0]) : ""
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

    /// Moves to the new day if midnight passed while Phos was open, so an unlock is saved to the day it belongs to.
    private func rollover(_ date: Date = TrustedClock.now()) {
        let key = DayKey.key(for: date, morning: settings.schedule.morning)
        if today.dayKey != key { move(to: store.today(now: date, morning: settings.schedule.morning)) }
    }

    /// Switches to another day's state. The day that just ended is kept, so an overnight lock still sees the reading
    /// and unlocks from the evening its window started.
    private func move(to fresh: TodayState) {
        if fresh.dayKey != today.dayKey, today.dayKey == DayKey.adding(-1, to: fresh.dayKey), !demo {
            store.yesterday = today
        }
        today = fresh
    }

    private func checkNotificationPermission() {
        guard !demo else { return }
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let denied = s.authorizationStatus == .denied
            DispatchQueue.main.async {
                guard denied != self.notificationsDenied || self.store.snapshot.notificationsDenied != denied else { return }
                self.notificationsDenied = denied
                var snap = self.store.snapshot
                snap.notificationsDenied = denied
                self.store.snapshot = snap
            }
        }
    }

    private func saveToday() {
        rollover()
        store.storedToday = today
        writeSnapshot()
        WidgetWriter.write(self)
    }

    func savePreferences() {
        store.settings = settings
        writeSnapshot()
    }

    /// Opens the unlock screen after the lock sends someone here.
    /// Opens the part of Wick a widget or notification points to.
    func open(_ url: URL) {
        refresh()
        guard settings.onboarded, !demo else { return }
        switch url.host {
        case "read":
            tab = 0
            if !today.readingDone && route == nil { route = .reading }
        case "listen":
            tab = 0
            if route == nil {
                startMode = .listen
                route = .reading
            }
        case "progress", "journal", "streak": tab = 1
        case "locks", "settings": tab = 2
        case "trophies": tab = 3
        default: tab = 0
        }
        routeFromLock()
    }

    /// A tapped notification says where it wants to go: "read" opens today's reading, "unlock" opens the unlock screen.
    func routeFromNotification(_ target: String?) {
        refresh()
        guard settings.onboarded, !demo, route == nil else { return }
        switch target {
        case "read":
            tab = 0
            route = today.readingDone ? (lockReason == .none ? nil : .unlock) : .reading
        case "unlock":
            route = .unlock
        default:
            routeFromLock()
        }
    }

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
        settings.onboardedAt = TrustedClock.now()
        applyLocks()
    }

    // MARK: Reading

    /// Saved progress for this chapter today, if any.
    func draft(for ref: ChapterRef) -> ReadingDraft? {
        // A draft left open over midnight still resumes, unless it ended in a failed quiz on an earlier day.
        guard let d = store.readingDraft, d.ref == ref, d.dayKey == today.dayKey || !d.failed else { return nil }
        return d
    }

    func saveDraft(_ draft: ReadingDraft) {
        store.readingDraft = draft
    }

    func clearDraft() {
        store.readingDraft = nil
    }

    var nextAttemptAt: Date? {
        guard let d = today.nextAttemptAt, d > TrustedClock.now() else { return nil }
        return d
    }

    func markAsked(_ items: [QuizItem]) {
        rollover()
        let ids = items.map(\.id).filter { !today.askedQuestionIDs.contains($0) }
        today.askedQuestionIDs += ids
        saveToday()
    }

    /// Chapters finished on a day, in the order they were read.
    func readChapters(on dayKey: String) -> [ChapterRef] {
        var seen = Set<String>()
        return records.filter { $0.dayKey == dayKey }.sorted { $0.completedAt < $1.completedAt }
            .compactMap { seen.insert($0.ref.id).inserted ? $0.ref : nil }
    }

    /// What a lock's question can ask about: only chapters read on the day that lock is counting, never what comes next.
    func questionChapters(for lock: LockSet) -> [ChapterRef] {
        let day = LockLogic.day(for: lock, today: today, yesterday: yesterdayState, now: now, morning: settings.schedule.morning)
        let read = readChapters(on: day.dayKey)
        return read.isEmpty ? readChapters(on: today.dayKey) : read
    }

    /// Shows a question for a lock, or the one already showing. Nil while a miss wait is running.
    func unlockQuestion(for lock: LockSet) -> QuizItem? {
        rollover()
        let chapters = questionChapters(for: lock)
        let banks = chapters.flatMap { QuestionBank.shared.questions(for: $0)?.questions ?? [] }
        if let id = today.pendingQuestions[lock.id], let q = banks.first(where: { $0.id == id }) {
            return QuizEngine.pick(from: [q], count: 1, avoiding: []).first
        }
        guard nextAttemptAt == nil, let item = QuizEngine.pick(from: banks, count: 1, avoiding: Set(today.askedQuestionIDs)).first else { return nil }
        today.pendingQuestions[lock.id] = item.id
        today.askedQuestionIDs.append(item.id)
        saveToday()
        return item
    }

    /// Records an answer to a lock's question. A wrong answer, or leaving without answering, starts the wait.
    func answerUnlockQuestion(for lock: LockSet, right: Bool) {
        rollover()
        guard today.pendingQuestions[lock.id] != nil else { return }
        today.pendingQuestions[lock.id] = nil
        saveToday()
        if right { unlock(lock, method: .question) } else { registerMiss() }
    }

    @discardableResult
    func registerMiss() -> Date {
        rollover()
        today.missesToday += 1
        let next = TrustedClock.now().addingTimeInterval(QuizEngine.waitAfterMiss(missCount: today.missesToday))
        today.nextAttemptAt = next
        saveToday()
        return next
    }

    /// Saves the reading, moves the path, unlocks waiting locks, and returns where the path picks up.
    @discardableResult
    /// Opens every lock the reading made ready.
    func unlockReady() {
        let targets = readyToUnlock.compactMap { ready in settings.lockSets.first { $0.id == ready.id } }
        for lock in targets { unlock(lock, method: .reading) }
        lastUnlocked = targets
        readyToUnlock = []
    }

    func completeReading(ref: ChapterRef, readMode: ReadMode, reflectMode: ReflectMode, reflection: String, score: Int, total: Int,
                         audioFile: String? = nil) -> PathLogic.After? {
        rollover()
        // A chapter started before the day ended and finished soon after counts for the day it started,
        // so reading past midnight never breaks a streak.
        var grace: TodayState?
        if let prev = store.previousDay(before: today.dayKey), !prev.readingDone, prev.chapter == ref,
           let started = prev.readingStartedAt, TrustedClock.now().timeIntervalSince(started) < 3 * 3600,
           today.readingStartedAt == nil || today.readingStartedAt! >= started {
            grace = prev
        }
        var contextPlan: ReadingPlan?
        var contextIndex: Int?
        let context = grace ?? today
        if let id = context.contextPlanID, let i = context.contextIndex, ReadingPlans.plan(id).chapters.indices.contains(i),
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

        let seconds = Int(TrustedClock.now().timeIntervalSince(context.readingStartedAt ?? today.readingStartedAt ?? TrustedClock.now()))
        let record = DayRecord(dayKey: context.dayKey, ref: ref, title: BookNames.title(ref), readMode: readMode,
                               reflectMode: reflectMode, reflection: reflection, score: score, total: total,
                               completedAt: TrustedClock.now(), readingSeconds: max(0, seconds), fromPlan: contextPlan != nil,
                               misses: context.missesToday, audioFile: audioFile)
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
        if var y = grace {
            // The reading belongs to yesterday. Today still has its own chapter to read.
            y.readingDone = true
            y.readingStartedAt = nil
            if !demo { store.yesterday = y }
            if today.chapter == ref { today.chapter = nil }
        } else {
            today.readingDone = true
            today.chapter = ref
        }
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
        checkAchievements()
        ReminderScheduler.reschedule(self)
        CloudBackup.save(self)
        WidgetWriter.write(self)
        // Reading counts for every lock today. Opening them is the reader's choice on the result screen.
        readyToUnlock = waiting
        lastUnlocked = []
        lastAfter = after
        return after
    }
}
