import Foundation

enum AppGroup {
    static let id = "group.com.peterbroas.phos"
}

// MARK: - Time

struct TimeOfDay: Codable, Hashable {
    var hour: Int
    var minute: Int

    var minutesFromMidnight: Int { hour * 60 + minute }

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(minutes: Int) {
        let m = ((minutes % 1440) + 1440) % 1440
        hour = m / 60
        minute = m % 60
    }

    func date(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    var components: DateComponents { DateComponents(hour: hour, minute: minute) }

    var label: String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date(on: Date()))
    }
}

/// A reading day starts at the day start time (midnight by default).
enum DayKey {
    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    static func key(for date: Date, morning: TimeOfDay, calendar: Calendar = .current) -> String {
        let shifted = date.addingTimeInterval(-Double(morning.minutesFromMidnight) * 60)
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    static func date(from key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    static func adding(_ days: Int, to key: String) -> String {
        guard let d = date(from: key), let n = utc.date(byAdding: .day, value: days, to: d) else { return key }
        let c = utc.dateComponents([.year, .month, .day], from: n)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Local calendar date for a key, used for display and weekdays.
    static func localDate(from key: String, calendar: Calendar = .current) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }
}

struct Schedule: Codable, Equatable {
    /// When a new reading day begins.
    var morning = TimeOfDay(hour: 0, minute: 0)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        morning = (try? c.decode(TimeOfDay.self, forKey: .morning)) ?? TimeOfDay(hour: 0, minute: 0)
    }
}

// MARK: - Reading check

/// What a reading must include before it unlocks anything.
struct ReadingCheck: Codable, Hashable {
    var words = 60
    var seconds = 45
    var minutes = 5
    var questions = 5
    var pass = 3

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReadingCheck()
        words = (try? c.decode(Int.self, forKey: .words)) ?? d.words
        seconds = (try? c.decode(Int.self, forKey: .seconds)) ?? d.seconds
        minutes = (try? c.decode(Int.self, forKey: .minutes)) ?? d.minutes
        questions = (try? c.decode(Int.self, forKey: .questions)) ?? d.questions
        pass = (try? c.decode(Int.self, forKey: .pass)) ?? d.pass
    }

    func normalized() -> ReadingCheck {
        var r = self
        r.words = min(max(r.words, 20), 300)
        r.seconds = min(max(r.seconds, 15), 300)
        r.minutes = min(max(r.minutes, 0), 30)
        r.questions = min(max(r.questions, 1), 10)
        r.pass = min(max(r.pass, 1), r.questions)
        return r
    }

    /// When several locks are waiting on the same reading, the strictest request wins.
    static func strictest(_ checks: [ReadingCheck]) -> ReadingCheck {
        guard var r = checks.first else { return ReadingCheck() }
        for c in checks.dropFirst() {
            r.words = max(r.words, c.words)
            r.seconds = max(r.seconds, c.seconds)
            r.minutes = max(r.minutes, c.minutes)
            r.questions = max(r.questions, c.questions)
            r.pass = max(r.pass, c.pass)
        }
        return r.normalized()
    }
}

// MARK: - Locks

enum UnlockPolicy: String, Codable, CaseIterable, Identifiable {
    case readOnce, questionEach, limited, strict
    var id: String { rawValue }

    var title: String {
        switch self {
        case .readOnce: return "Read once, then unlock freely"
        case .questionEach: return "A question every unlock"
        case .limited: return "Limited unlocks a day"
        case .strict: return "No unlocks"
        }
    }

    var detail: String {
        switch self {
        case .readOnce: return "After today's reading, open these apps any time with one tap."
        case .questionEach: return "After today's reading, each unlock takes one question about it."
        case .limited: return "After today's reading, only a set number of unlocks."
        case .strict: return "Nothing opens these apps while the lock is active except an emergency pass."
        }
    }

    var symbol: String {
        switch self {
        case .readOnce: return "book.closed"
        case .questionEach: return "questionmark.bubble"
        case .limited: return "number"
        case .strict: return "lock.fill"
        }
    }
}

enum ProtectionKind: String, Codable, CaseIterable, Identifiable {
    case none, passcode, countdown, delay, commitment, afterReading
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No protection"
        case .passcode: return "Passcode"
        case .countdown: return "Waiting timer"
        case .delay: return "Delayed changes"
        case .commitment: return "Commitment"
        case .afterReading: return "Only after reading"
        }
    }

    var detail: String {
        switch self {
        case .none: return "Change settings any time."
        case .passcode: return "Enter a passcode to change settings. Let a friend keep it for real accountability."
        case .countdown: return "Wait on a countdown screen before settings open."
        case .delay: return "Changes are saved but only start after a wait."
        case .commitment: return "Settings can't change at all until a date you pick."
        case .afterReading: return "Settings only open after today's reading is done."
        }
    }

    var symbol: String {
        switch self {
        case .none: return "lock.open"
        case .passcode: return "key"
        case .countdown: return "timer"
        case .delay: return "clock.arrow.circlepath"
        case .commitment: return "calendar.badge.clock"
        case .afterReading: return "book"
        }
    }
}

struct LockProtection: Codable, Hashable {
    var kind: ProtectionKind = .none
    var passcodeHash: String?
    var passcodeSalt: String?
    var passcodeResetAt: Date?
    var countdownMinutes = 5
    var delayHours = 24
    var commitUntil: Date?
    /// While this lock is on, iOS blocks deleting apps.
    var blockDeletion = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LockProtection()
        kind = (try? c.decode(ProtectionKind.self, forKey: .kind)) ?? d.kind
        passcodeHash = try? c.decode(String.self, forKey: .passcodeHash)
        passcodeSalt = try? c.decode(String.self, forKey: .passcodeSalt)
        passcodeResetAt = try? c.decode(Date.self, forKey: .passcodeResetAt)
        countdownMinutes = (try? c.decode(Int.self, forKey: .countdownMinutes)) ?? d.countdownMinutes
        delayHours = (try? c.decode(Int.self, forKey: .delayHours)) ?? d.delayHours
        commitUntil = try? c.decode(Date.self, forKey: .commitUntil)
        blockDeletion = (try? c.decode(Bool.self, forKey: .blockDeletion)) ?? d.blockDeletion
    }

    var hasPasscode: Bool { passcodeHash != nil }

    var summary: String {
        switch kind {
        case .none: return "No protection"
        case .passcode: return "Passcode"
        case .countdown: return "\(countdownMinutes) min timer"
        case .delay: return "\(delayHours) hour delay"
        case .commitment:
            guard let u = commitUntil else { return "Commitment" }
            return "Committed until \(u.formatted(.dateTime.month(.abbreviated).day()))"
        case .afterReading: return "After reading"
        }
    }
}

struct LockSet: Codable, Identifiable, Hashable {
    static let untilEnd = -1
    static let rewardChoices = [30, 60, 300, 600, 900, 1800, 3600, 7200, untilEnd]

    var id = UUID().uuidString
    var name = ""
    var enabled = true
    /// Encoded FamilyActivitySelection.
    var selection: Data?
    var appCount = 0
    /// Calendar weekday numbers, 1 is Sunday.
    var days: Set<Int> = Set(1...7)
    var allDay = true
    var start = TimeOfDay(hour: 21, minute: 0)
    var end = TimeOfDay(hour: 7, minute: 0)
    var policy: UnlockPolicy = .questionEach
    var limit = 5
    var limitNeedsQuestion = false
    /// Seconds each unlock opens the apps for, or untilEnd for the rest of the active time.
    var rewardSeconds = 1800
    var otherWays = true
    var reading = ReadingCheck()
    var emergencyPasses = 3
    var protection = LockProtection()
    var createdAt = Date()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LockSet()
        id = (try? c.decode(String.self, forKey: .id)) ?? d.id
        name = (try? c.decode(String.self, forKey: .name)) ?? "Lock"
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? d.enabled
        selection = try? c.decode(Data.self, forKey: .selection)
        appCount = (try? c.decode(Int.self, forKey: .appCount)) ?? d.appCount
        days = (try? c.decode(Set<Int>.self, forKey: .days)) ?? d.days
        start = (try? c.decode(TimeOfDay.self, forKey: .start)) ?? d.start
        end = (try? c.decode(TimeOfDay.self, forKey: .end)) ?? d.end
        limit = (try? c.decode(Int.self, forKey: .limit)) ?? d.limit
        limitNeedsQuestion = (try? c.decode(Bool.self, forKey: .limitNeedsQuestion)) ?? d.limitNeedsQuestion
        rewardSeconds = (try? c.decode(Int.self, forKey: .rewardSeconds)) ?? d.rewardSeconds
        otherWays = (try? c.decode(Bool.self, forKey: .otherWays)) ?? d.otherWays
        reading = (try? c.decode(ReadingCheck.self, forKey: .reading)) ?? d.reading
        emergencyPasses = (try? c.decode(Int.self, forKey: .emergencyPasses)) ?? d.emergencyPasses
        protection = (try? c.decode(LockProtection.self, forKey: .protection)) ?? d.protection
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? d.createdAt

        // Build 2 stored a mode instead of hours and a policy.
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        let legacyMode = try? legacy.decode(String.self, forKey: .mode)
        if let p = try? c.decode(UnlockPolicy.self, forKey: .policy) {
            policy = p
            allDay = (try? c.decode(Bool.self, forKey: .allDay)) ?? d.allDay
        } else {
            switch legacyMode {
            case "untilRead":
                policy = .readOnce
                rewardSeconds = LockSet.untilEnd
                allDay = true
            case "scheduled":
                allDay = false
                policy = ((try? legacy.decode(Bool.self, forKey: .allowEarning)) ?? true) ? .questionEach : .strict
            default:
                policy = .questionEach
                allDay = true
            }
        }
    }

    private enum LegacyKeys: String, CodingKey { case mode, allowEarning }

    static func rewardLabel(_ seconds: Int) -> String {
        if seconds == untilEnd { return "Until the lock ends" }
        if seconds < 60 { return "\(seconds) sec" }
        let m = seconds / 60
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? (m == 60 ? "1 hour" : "\(m / 60) hours") : "\(m / 60) hr \(m % 60) min"
    }

    var hoursLabel: String { allDay ? "All day" : "\(start.label) to \(end.label)" }

    var daysLabel: String {
        if days.count == 7 { return "Every day" }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
    }

    var policyLabel: String {
        switch policy {
        case .readOnce: return "Read once"
        case .questionEach: return "Question each unlock"
        case .limited: return "\(limit) unlocks a day"
        case .strict: return "No unlocks"
        }
    }

    var summary: String {
        let apps = appCount == 1 ? "1 app" : "\(appCount) apps"
        return "\(hoursLabel) · \(policyLabel) · \(apps)"
    }

    /// Length of the scheduled window in minutes. Equal start and end means all 24 hours.
    var windowMinutes: Int {
        if allDay { return 1440 }
        let s = start.minutesFromMidnight, e = end.minutesFromMidnight
        if s == e { return 1440 }
        return e > s ? e - s : 1440 - s + e
    }
}

/// A saved change to a lock that starts later because the lock uses delayed changes.
struct PendingLock: Codable, Equatable, Identifiable {
    var id: String { lock.id }
    var lock: LockSet
    var deleted: Bool
    var effectiveAt: Date
}

// MARK: - App state

enum ShieldStyle: String, Codable, CaseIterable, Identifiable {
    case verse, streak, quiet
    var id: String { rawValue }
    var title: String {
        switch self {
        case .verse: return "Verse of the day"
        case .streak: return "Streak on the line"
        case .quiet: return "Quiet"
        }
    }
}

enum ShieldTheme: String, Codable, CaseIterable, Identifiable {
    case dark, light
    var id: String { rawValue }
    var title: String { self == .dark ? "Night" : "Ivory" }
}

enum ReadMode: String, Codable, CaseIterable, Identifiable {
    case paper, inApp, speak, listen
    var id: String { rawValue }
    var title: String {
        switch self {
        case .paper: return "Paper Bible"
        case .inApp: return "Read in Phos"
        case .speak: return "Read it aloud"
        case .listen: return "Listen"
        }
    }
    var symbol: String {
        switch self {
        case .paper: return "book.closed"
        case .inApp: return "text.book.closed"
        case .speak: return "waveform"
        case .listen: return "headphones"
        }
    }
}

enum ReflectMode: String, Codable, CaseIterable, Identifiable {
    case typed, spoken, prompts
    var id: String { rawValue }
    var title: String {
        switch self {
        case .typed: return "Type it"
        case .spoken: return "Say it"
        case .prompts: return "Prompts"
        }
    }
    var symbol: String {
        switch self {
        case .typed: return "keyboard"
        case .spoken: return "mic"
        case .prompts: return "list.bullet"
        }
    }
}

enum LockReason: String, Codable {
    case none, reading, recall, tap, usedUp, strict
}

struct ChapterRef: Codable, Hashable, Identifiable {
    var book: String
    var chapter: Int
    var id: String { "\(book).\(chapter)" }
}

struct DayRecord: Codable, Identifiable, Hashable {
    var id: String { "\(dayKey).\(ref.id).\(Int(completedAt.timeIntervalSince1970))" }
    var dayKey: String
    var ref: ChapterRef
    var title: String
    var readMode: ReadMode
    var reflectMode: ReflectMode
    var reflection: String
    var score: Int
    var total: Int
    var completedAt: Date
    var readingSeconds: Int
    var fromPlan: Bool
    /// Quizzes missed that day before this one passed.
    var misses: Int? = nil
}

/// One lock's unlock state for the current day.
struct LockDay: Codable, Equatable {
    var until: Date?
    var passUntil: Date?
    var count = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        until = try? c.decode(Date.self, forKey: .until)
        passUntil = try? c.decode(Date.self, forKey: .passUntil)
        count = (try? c.decode(Int.self, forKey: .count)) ?? 0
    }
}

struct TodayState: Codable, Equatable {
    var dayKey: String
    var readingDone = false
    var chapter: ChapterRef?
    var contextPlanID: String?
    var contextIndex: Int?
    var readingStartedAt: Date?
    var missesToday = 0
    var nextAttemptAt: Date?
    var askedQuestionIDs: [String] = []
    var unlocks: [String: LockDay] = [:]
    var recallCount = 0

    init(dayKey: String) {
        self.dayKey = dayKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = (try? c.decode(String.self, forKey: .dayKey)) ?? ""
        readingDone = (try? c.decode(Bool.self, forKey: .readingDone)) ?? false
        chapter = try? c.decode(ChapterRef.self, forKey: .chapter)
        contextPlanID = try? c.decode(String.self, forKey: .contextPlanID)
        contextIndex = try? c.decode(Int.self, forKey: .contextIndex)
        readingStartedAt = try? c.decode(Date.self, forKey: .readingStartedAt)
        missesToday = (try? c.decode(Int.self, forKey: .missesToday)) ?? 0
        nextAttemptAt = try? c.decode(Date.self, forKey: .nextAttemptAt)
        askedQuestionIDs = (try? c.decode([String].self, forKey: .askedQuestionIDs)) ?? []
        unlocks = (try? c.decode([String: LockDay].self, forKey: .unlocks)) ?? [:]
        recallCount = (try? c.decode(Int.self, forKey: .recallCount)) ?? 0
    }

    func day(_ lockID: String) -> LockDay { unlocks[lockID] ?? LockDay() }
}

/// Where today's reading left off, so leaving the app never loses work.
struct ReadingDraft: Codable, Equatable {
    enum Step: String, Codable { case mode, read, reflect, quiz, result }

    var dayKey: String
    var ref: ChapterRef
    var step: Step = .mode
    var readMode: ReadMode = .paper
    var reflectMode: ReflectMode = .typed
    var reflection = ""
    var prompts = ["", "", ""]
    var speechSeconds: Double = 0
    /// Question ids for the current check, in order.
    var quizIDs: [String] = []
    var answered = 0
    var correct = 0
    var missedIDs: [String] = []
    /// True after a missed check, so the flow comes back to the result and new questions.
    var failed = false
    /// Read it aloud progress: words heard and the furthest word reached.
    var aloudHeard: [Int] = []
    var aloudCursor = 0

    init(dayKey: String, ref: ChapterRef) {
        self.dayKey = dayKey
        self.ref = ref
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = (try? c.decode(String.self, forKey: .dayKey)) ?? ""
        ref = (try? c.decode(ChapterRef.self, forKey: .ref)) ?? ChapterRef(book: "JHN", chapter: 1)
        step = (try? c.decode(Step.self, forKey: .step)) ?? .mode
        readMode = (try? c.decode(ReadMode.self, forKey: .readMode)) ?? .paper
        reflectMode = (try? c.decode(ReflectMode.self, forKey: .reflectMode)) ?? .typed
        reflection = (try? c.decode(String.self, forKey: .reflection)) ?? ""
        prompts = (try? c.decode([String].self, forKey: .prompts)) ?? ["", "", ""]
        speechSeconds = (try? c.decode(Double.self, forKey: .speechSeconds)) ?? 0
        quizIDs = (try? c.decode([String].self, forKey: .quizIDs)) ?? []
        answered = (try? c.decode(Int.self, forKey: .answered)) ?? 0
        correct = (try? c.decode(Int.self, forKey: .correct)) ?? 0
        missedIDs = (try? c.decode([String].self, forKey: .missedIDs)) ?? []
        failed = (try? c.decode(Bool.self, forKey: .failed)) ?? false
        aloudHeard = (try? c.decode([Int].self, forKey: .aloudHeard)) ?? []
        aloudCursor = (try? c.decode(Int.self, forKey: .aloudCursor)) ?? 0
    }

    /// The step to reopen at. Reading timers never resume, so a partly read chapter starts reading again.
    var resumeStep: Step {
        if failed && (step == .mode || step == .read || step == .result) { return .result }
        switch step {
        case .mode: return .mode
        // Reading out loud saves word by word, so it picks up right where it stopped.
        case .read: return readMode == .speak && aloudCursor > 0 ? .read : .mode
        default: return step
        }
    }
}

struct PassUse: Codable, Hashable, Identifiable {
    var id: Date { date }
    var date: Date
    var minutes: Int
    var lockID: String?
}

struct AppSettings: Codable, Equatable {
    var onboarded = false
    var onboardedAt: Date?
    var schedule = Schedule()
    var lockSets: [LockSet] = []
    var pendingLocks: [PendingLock] = []
    var shieldStyle: ShieldStyle = .verse
    var shieldTheme: ShieldTheme = .dark
    var planID = "book.JHN"
    var planPositions: [String: Int] = [:]
    var passUses: [PassUse] = []
    var preferredRead: ReadMode = .paper
    var preferredReflect: ReflectMode = .typed
    /// Read aloud voice: kokoro:<name>, system:<identifier>, or empty for the best iPhone voice.
    var voiceID = ""
    /// Trophies shown on the Today screen.
    var pinnedTrophies: [String] = []
    var schemaVersion = 3

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        onboarded = (try? c.decode(Bool.self, forKey: .onboarded)) ?? d.onboarded
        onboardedAt = try? c.decode(Date.self, forKey: .onboardedAt)
        schedule = (try? c.decode(Schedule.self, forKey: .schedule)) ?? d.schedule
        lockSets = (try? c.decode([LockSet].self, forKey: .lockSets)) ?? d.lockSets
        pendingLocks = (try? c.decode([PendingLock].self, forKey: .pendingLocks)) ?? d.pendingLocks
        shieldStyle = (try? c.decode(ShieldStyle.self, forKey: .shieldStyle)) ?? d.shieldStyle
        shieldTheme = (try? c.decode(ShieldTheme.self, forKey: .shieldTheme)) ?? d.shieldTheme
        planID = (try? c.decode(String.self, forKey: .planID)) ?? d.planID
        planPositions = (try? c.decode([String: Int].self, forKey: .planPositions)) ?? d.planPositions
        passUses = (try? c.decode([PassUse].self, forKey: .passUses)) ?? d.passUses
        preferredRead = (try? c.decode(ReadMode.self, forKey: .preferredRead)) ?? d.preferredRead
        preferredReflect = (try? c.decode(ReflectMode.self, forKey: .preferredReflect)) ?? d.preferredReflect
        voiceID = (try? c.decode(String.self, forKey: .voiceID)) ?? d.voiceID
        pinnedTrophies = (try? c.decode([String].self, forKey: .pinnedTrophies)) ?? d.pinnedTrophies
        let version = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 1
        schemaVersion = 3

        // Older builds kept reading rules globally and started days at a set morning time.
        if version < 3 {
            schedule.morning = TimeOfDay(hour: 0, minute: 0)
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            if let rules = try? legacy.decode(LegacyRules.self, forKey: .rules) {
                let d = ReadingCheck()
                for i in lockSets.indices {
                    lockSets[i].reading = ReadingCheck(words: rules.wordsToType ?? d.words, seconds: rules.secondsOfTalking ?? d.seconds,
                                                       minutes: rules.minimumReadingMinutes ?? d.minutes, questions: rules.questionsPerCheck ?? d.questions,
                                                       pass: rules.correctToPass ?? d.pass).normalized()
                    lockSets[i].emergencyPasses = rules.emergencyPasses ?? 3
                    if lockSets[i].rewardSeconds != LockSet.untilEnd, let minutes = rules.unlockMinutes {
                        lockSets[i].rewardSeconds = minutes >= 1440 ? LockSet.untilEnd : minutes * 60
                    }
                }
            }
        }
    }

    private enum LegacyKeys: String, CodingKey { case rules }

    private struct LegacyRules: Decodable {
        var wordsToType: Int?
        var secondsOfTalking: Int?
        var minimumReadingMinutes: Int?
        var questionsPerCheck: Int?
        var correctToPass: Int?
        var unlockMinutes: Int?
        var emergencyPasses: Int?
    }

    func passesLeft(_ lock: LockSet, now: Date, calendar: Calendar = .current) -> Int {
        let used = passUses.filter { $0.lockID == lock.id && calendar.isDate($0.date, equalTo: now, toGranularity: .month) }.count
        return max(0, lock.emergencyPasses - used)
    }
}

extension ReadingCheck {
    init(words: Int, seconds: Int, minutes: Int, questions: Int, pass: Int) {
        self.words = words
        self.seconds = seconds
        self.minutes = minutes
        self.questions = questions
        self.pass = pass
    }
}

/// What the lock screen, shield button, and widgets need, written by the app and monitor.
struct SharedSnapshot: Codable, Equatable {
    var style: ShieldStyle = .verse
    var theme: ShieldTheme = .dark
    var reason: LockReason = .reading
    var streak = 0
    var chapterTitle = "Today's chapter"
    var readingDone = false
    var verseText = "Your word is a lamp to my feet, and a light for my path."
    var verseRef = "Psalm 119:105"
    var lockedCount = 0
    var planName = ""
    var planDay = 0
    var planLength = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SharedSnapshot()
        style = (try? c.decode(ShieldStyle.self, forKey: .style)) ?? d.style
        theme = (try? c.decode(ShieldTheme.self, forKey: .theme)) ?? d.theme
        reason = (try? c.decode(LockReason.self, forKey: .reason)) ?? d.reason
        streak = (try? c.decode(Int.self, forKey: .streak)) ?? d.streak
        chapterTitle = (try? c.decode(String.self, forKey: .chapterTitle)) ?? d.chapterTitle
        readingDone = (try? c.decode(Bool.self, forKey: .readingDone)) ?? d.readingDone
        verseText = (try? c.decode(String.self, forKey: .verseText)) ?? d.verseText
        verseRef = (try? c.decode(String.self, forKey: .verseRef)) ?? d.verseRef
        lockedCount = (try? c.decode(Int.self, forKey: .lockedCount)) ?? d.lockedCount
        planName = (try? c.decode(String.self, forKey: .planName)) ?? d.planName
        planDay = (try? c.decode(Int.self, forKey: .planDay)) ?? d.planDay
        planLength = (try? c.decode(Int.self, forKey: .planLength)) ?? d.planLength
    }
}
