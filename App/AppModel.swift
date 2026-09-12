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
    var selection: FamilyActivitySelection
    var authorized = false
    var route: Route?
    var now = Date()

    init(store: SharedStore = .shared, demo: Bool = ProcessInfo.processInfo.arguments.contains("-demoData")) {
        self.store = store
        self.demo = demo
        if demo { DemoData.seed(store) }
        settings = store.settings
        today = store.today()
        records = store.records
        selection = Blocker.selection(store)
        authorized = demo || AuthorizationCenter.shared.authorizationStatus == .approved
        refresh()
    }

    // MARK: Derived

    var plan: ReadingPlan { ReadingPlans.plan(settings.planID) }

    var planPosition: Int { settings.planPositions[settings.planID] ?? 0 }

    var planFinished: Bool { planPosition >= plan.chapters.count }

    /// The chapter for today: what was read today, otherwise the next one in the plan.
    var todaysChapter: ChapterRef {
        if let c = today.chapter { return c }
        return plan.chapters[min(planPosition, plan.chapters.count - 1)]
    }

    var todaysTitle: String { BookNames.title(todaysChapter) }

    var planDay: Int { today.readingDone && today.chapter != nil ? planPosition : min(planPosition + 1, plan.chapters.count) }

    var doneKeys: Set<String> { Set(records.filter(\.fromPlan).map(\.dayKey)) }

    var streak: Int { Streaks.current(doneKeys: doneKeys, todayKey: today.dayKey) }

    var lockReason: LockReason { today.lockReason(at: now) }

    var passesLeft: Int { settings.passesLeft(now: now) }

    var lockedCount: Int { Blocker.lockedCount(selection) }

    var todaysRecord: DayRecord? { records.first { $0.dayKey == today.dayKey } }

    var greeting: String {
        let h = Calendar.current.component(.hour, from: now)
        return h < 12 ? "Good morning" : (h < 17 ? "Good afternoon" : "Good evening")
    }

    // MARK: Lifecycle

    func refresh() {
        now = Date()
        let resolved = RuleLogic.resolve(current: settings.rules, pending: settings.pendingRules, now: now)
        if resolved.rules != settings.rules || resolved.pending != settings.pendingRules {
            settings.rules = resolved.rules
            settings.pendingRules = resolved.pending
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
        snap.reason = today.lockReason(at: now)
        snap.streak = streak
        snap.chapterTitle = todaysTitle
        snap.readingDone = today.readingDone
        snap.lockedCount = lockedCount
        snap.planName = plan.name
        snap.planDay = planDay
        snap.planLength = plan.chapters.count
        snap.unlockedUntil = today.unlockedUntil
        let (ref, verse) = DailyVerses.pick(for: today.dayKey)
        let text = Bible.shared.verse(ref, verse)
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

    func saveSettings() {
        store.settings = settings
        writeSnapshot()
        if settings.onboarded && !demo { Blocker.registerDaily(settings: settings) }
    }

    /// Opens the right screen after the lock sends someone here.
    func routeFromLock() {
        guard settings.onboarded, route == nil else { return }
        switch lockReason {
        case .reading: break
        case .recall, .midday: route = .recall
        case .evening: route = .emergency
        case .none: break
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

    func updateSelection(_ sel: FamilyActivitySelection) {
        selection = sel
        Blocker.save(selection: sel, store: store)
        writeSnapshot()
        if settings.onboarded && !demo { LockEngine.sync(store: store, now: Date()) }
    }

    func finishOnboarding() {
        settings.onboarded = true
        saveSettings()
        if !demo {
            Blocker.registerDaily(settings: settings)
            LockEngine.sync(store: store, now: Date())
        }
    }

    // MARK: Reading

    func beginReading(_ ref: ChapterRef) {
        if today.readingStartedAt == nil || today.chapter != ref {
            today.readingStartedAt = Date()
        }
        today.chapter = ref
        saveToday()
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

    /// Records a missed check and returns when new questions are allowed.
    @discardableResult
    func registerMiss() -> Date {
        today.missesToday += 1
        let next = Date().addingTimeInterval(QuizEngine.waitAfterMiss(missCount: today.missesToday))
        today.nextAttemptAt = next
        saveToday()
        return next
    }

    func completeReading(ref: ChapterRef, readMode: ReadMode, reflectMode: ReflectMode, reflection: String, score: Int, total: Int) {
        let fromPlan = !planFinished && ref == plan.chapters[min(planPosition, plan.chapters.count - 1)]
        let seconds = Int(Date().timeIntervalSince(today.readingStartedAt ?? Date()))
        let record = DayRecord(dayKey: today.dayKey, ref: ref, title: BookNames.title(ref), readMode: readMode,
                               reflectMode: reflectMode, reflection: reflection, score: score, total: total,
                               completedAt: Date(), readingSeconds: max(0, seconds), fromPlan: fromPlan)
        var all = store.records.filter { $0.dayKey != today.dayKey || !$0.fromPlan || !fromPlan }
        if let i = all.firstIndex(where: { $0.dayKey == today.dayKey && $0.fromPlan == fromPlan }) { all.remove(at: i) }
        all.append(record)
        store.records = all
        records = all
        if fromPlan && !today.readingDone {
            settings.planPositions[settings.planID] = planPosition + 1
            store.settings = settings
        }
        today.readingDone = true
        today.chapter = ref
        today.missesToday = 0
        today.nextAttemptAt = nil
        settings.preferredRead = readMode
        settings.preferredReflect = reflectMode
        store.settings = settings
        saveToday()
    }

    func unlock(minutes: Int) {
        let now = Date()
        let end = minutes >= Rules.restOfDay
            ? LockEngine.restOfDayEnd(settings: settings, now: now)
            : now.addingTimeInterval(TimeInterval(minutes * 60))
        today.unlockedUntil = end
        today.middayPending = false
        today.recallCount += 1
        saveToday()
        self.now = now
        if !demo {
            Blocker.unshield()
            Blocker.scheduleRelock(at: end, now: now)
            LockEngine.sync(store: store, now: now)
        }
    }

    func lockNow() {
        today.unlockedUntil = nil
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
        unlock(minutes: minutes)
    }

    /// Unlock choices up to the current limit.
    var unlockChoices: [Int] {
        let limit = settings.rules.unlockMinutes
        var base = [5, 15, 30, 60, 120].filter { $0 < limit }
        base.append(limit)
        return Array(base.suffix(4))
    }

    // MARK: Rules and plans

    func proposeRules(_ proposed: Rules) {
        let result = RuleLogic.propose(current: settings.rules, proposed: proposed, now: Date())
        settings.rules = result.effective
        settings.pendingRules = result.pending
        saveSettings()
    }

    func cancelPendingRules() {
        settings.pendingRules = nil
        saveSettings()
    }

    func choosePlan(_ id: String) {
        settings.planID = id
        if !today.readingDone { today.chapter = nil; saveToday() }
        saveSettings()
    }

    func restartPlan() {
        settings.planPositions[settings.planID] = 0
        if !today.readingDone { today.chapter = nil; saveToday() }
        saveSettings()
    }
}
