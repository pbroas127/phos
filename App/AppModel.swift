import DeviceActivity
import FamilyControls
import Foundation
import Observation
import SwiftUI
import UserNotifications
import WidgetKit

enum Route: String, Identifiable {
    case reading, recall, focus, recite, emergency
    var id: String { rawValue }
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
            var set = LockSet()
            set.selection = legacy
            set.appCount = Blocker.lockedCount(Blocker.selection(from: legacy))
            s.lockSets = [set]
            store.selectionData = nil
        }
        if s.schedule.eveningOn {
            var evening = LockSet()
            evening.name = "Evening"
            evening.mode = .scheduled
            evening.start = s.schedule.evening
            evening.end = s.schedule.morning
            evening.allowEarning = false
            evening.selection = s.lockSets.first?.selection
            evening.appCount = s.lockSets.first?.appCount ?? 0
            s.lockSets.append(evening)
            s.schedule.eveningOn = false
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

    /// Paths started but not finished, most recent first, not counting the active one.
    var otherPathsInProgress: [ReadingPlan] {
        ReadingPlans.all
            .filter { $0.id != plan.id && position($0) > 0 && position($0) < $0.chapters.count }
            .sorted { (lastRead($0) ?? .distantPast) > (lastRead($1) ?? .distantPast) }
    }

    /// The chapter for today: the one chosen or read today, otherwise the next one in the active path.
    var todaysChapter: ChapterRef {
        if let c = today.chapter { return c }
        return plan.chapters[min(planPosition, plan.chapters.count - 1)]
    }

    var todaysTitle: String { BookNames.title(todaysChapter) }

    /// True when the chapter on the Today card has already been read today.
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

    /// Picks a chapter from any path. The path becomes active and its place is kept for later.
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

    /// Switches the active path and shows its next chapter.
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

    // MARK: Lock state

    var lockReason: LockReason { LockLogic.reason(today: today, settings: settings, now: now) }

    var strictUntil: Date? { LockLogic.strictUntil(settings: settings, today: today, now: now) }

    var passesLeft: Int { settings.passesLeft(now: now) }

    var lockedCount: Int { demo ? 4 : settings.lockSets.filter(\.enabled).map(\.appCount).reduce(0, +) }

    var greeting: String {
        let h = Calendar.current.component(.hour, from: now)
        return h < 12 ? "Good morning" : (h < 17 ? "Good afternoon" : "Good evening")
    }

    // MARK: Lifecycle

    func refresh() {
        now = Date()
        var changed = false
        if let pending = settings.pendingConfig, now >= pending.effectiveAt {
            settings.config = pending.config
            settings.pendingConfig = nil
            changed = true
        }
        if let reset = settings.protection.passcodeResetAt, now >= reset {
            settings.protection.passcodeHash = nil
            settings.protection.passcodeSalt = nil
            settings.protection.passcodeResetAt = nil
            changed = true
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
        snap.unlockedUntil = today.unlockedUntil
        snap.strictUntil = strictUntil
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

    /// Saves settings that do not affect how hard Phos is to get past.
    func savePreferences() {
        store.settings = settings
        writeSnapshot()
    }

    /// Opens the right screen after the lock sends someone here.
    func routeFromLock() {
        guard settings.onboarded, route == nil else { return }
        switch lockReason {
        case .recall, .midday: route = .recall
        case .evening: route = .emergency
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

    /// Setup writes locks directly. After setup, changes go through protection.
    func setupLock(_ set: LockSet) {
        if let i = settings.lockSets.firstIndex(where: { $0.id == set.id }) {
            settings.lockSets[i] = set
        } else {
            settings.lockSets.append(set)
        }
        store.settings = settings
        writeSnapshot()
    }

    func finishOnboarding() {
        settings.onboarded = true
        settings.onboardedAt = Date()
        store.settings = settings
        writeSnapshot()
        if !demo {
            Blocker.registerDaily(settings: settings)
            LockEngine.sync(store: store, now: Date())
        }
    }

    // MARK: Protected changes

    /// Saves a change to rules, locks, times, or protection, running easier changes through every protection.
    func save(_ proposed: LockConfig, passcodeOK: Bool = false, cooldownDone: Bool = false) -> SaveOutcome {
        var p = proposed
        p.rules = p.rules.normalized()
        let byCount: (LockSet, LockSet) -> Bool = { $1.appCount < $0.appCount }
        let removed: (LockSet, LockSet) -> Bool = demo ? byCount : Blocker.appsRemoved
        let outcome = ConfigLogic.evaluate(settings: settings, proposed: p, readingDone: today.readingDone, now: Date(),
                                           passcodeOK: passcodeOK, cooldownDone: cooldownDone, appsRemoved: removed)
        switch outcome {
        case .applied:
            settings.config = p
            settings.pendingConfig = nil
            store.settings = settings
            writeSnapshot()
            if settings.onboarded && !demo {
                Blocker.registerDaily(settings: settings)
                LockEngine.sync(store: store, now: Date())
            }
        case .pending(let date):
            settings.pendingConfig = PendingConfig(config: p, effectiveAt: date)
            store.settings = settings
        case .blocked, .needsPasscode, .needsCooldown:
            break
        }
        return outcome
    }

    func cancelPending() {
        settings.pendingConfig = nil
        store.settings = settings
    }

    func checkPasscode(_ code: String) -> Bool { Passcode.verify(code, settings.protection) }

    /// Recovery for a forgotten passcode: it clears after a full day.
    func forgotPasscode() {
        settings.protection.passcodeResetAt = Date().addingTimeInterval(86_400)
        store.settings = settings
    }

    // MARK: Reading

    var nextAttemptAt: Date? {
        guard let d = today.nextAttemptAt, d > Date() else { return nil }
        return d
    }

    func markAsked(_ items: [QuizItem]) {
        let ids = items.map(\.id).filter { !today.askedQuestionIDs.contains($0) }
        today.askedQuestionIDs += ids
        saveToday()
    }

    /// Records a missed check and returns when new questions are allowed.
    @discardableResult
    func registerMiss() -> Date {
        today.missesToday += 1
        let next = Date().addingTimeInterval(QuizEngine.waitAfterMiss(missCount: today.missesToday))
        today.nextAttemptAt = next
        saveToday()
        return next
    }

    /// Saves the reading, moves the path, and returns where the path picks up.
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
        lastAfter = after
        return after
    }

    func unlock(minutes: Int) {
        let now = Date()
        let end = minutes >= Rules.restOfDay
            ? LockEngine.restOfDayEnd(settings: settings, now: now)
            : now.addingTimeInterval(TimeInterval(minutes * 60))
        today.unlockedUntil = max(end, today.unlockedUntil ?? end)
        today.middayPending = false
        today.recallCount += 1
        saveToday()
        self.now = now
        if !demo {
            Blocker.scheduleRelock(at: today.unlockedUntil ?? end, now: now)
            LockEngine.sync(store: store, now: now)
        }
    }

    func lockNow() {
        today.unlockedUntil = nil
        today.passUntil = nil
        saveToday()
        now = Date()
        if !demo {
            Blocker.cancelRelock()
            LockEngine.sync(store: store, now: now)
        }
    }

    func useEmergencyPass() {
        let minutes = min(settings.rules.unlockMinutes, 30)
        settings.passUses.append(PassUse(date: Date(), minutes: minutes))
        store.settings = settings
        today.passUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        unlock(minutes: minutes)
    }

    /// Unlock choices up to the current limit.
    var unlockChoices: [Int] {
        let limit = settings.rules.unlockMinutes
        var base = [5, 15, 30, 60, 120].filter { $0 < limit }
        base.append(limit)
        return Array(base.suffix(4))
    }
}
