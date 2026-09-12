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

/// A reading day starts at the morning lock time, so 1 AM still belongs to yesterday.
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

    /// Local calendar date for a key, used for display.
    static func localDate(from key: String, calendar: Calendar = .current) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }
}

// MARK: - Rules

struct Rules: Codable, Equatable {
    var wordsToType: Int = 60
    var secondsOfTalking: Int = 45
    var minimumReadingMinutes: Int = 5
    var questionsPerCheck: Int = 5
    var correctToPass: Int = 3
    var unlockMinutes: Int = 30
    var middayQuestions: Int = 1
    var emergencyPasses: Int = 3
    var delayEasierChanges: Bool = true

    static let restOfDay = 1440
    static let unlockChoices = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, restOfDay]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Rules()
        wordsToType = (try? c.decode(Int.self, forKey: .wordsToType)) ?? d.wordsToType
        secondsOfTalking = (try? c.decode(Int.self, forKey: .secondsOfTalking)) ?? d.secondsOfTalking
        minimumReadingMinutes = (try? c.decode(Int.self, forKey: .minimumReadingMinutes)) ?? d.minimumReadingMinutes
        questionsPerCheck = (try? c.decode(Int.self, forKey: .questionsPerCheck)) ?? d.questionsPerCheck
        correctToPass = (try? c.decode(Int.self, forKey: .correctToPass)) ?? d.correctToPass
        unlockMinutes = (try? c.decode(Int.self, forKey: .unlockMinutes)) ?? d.unlockMinutes
        middayQuestions = (try? c.decode(Int.self, forKey: .middayQuestions)) ?? d.middayQuestions
        emergencyPasses = (try? c.decode(Int.self, forKey: .emergencyPasses)) ?? d.emergencyPasses
        delayEasierChanges = (try? c.decode(Bool.self, forKey: .delayEasierChanges)) ?? d.delayEasierChanges
    }

    func normalized() -> Rules {
        var r = self
        for f in RuleField.allCases where f != .unlock {
            f.set(&r, min(max(f.get(r), f.range.lowerBound), f.range.upperBound))
        }
        r.correctToPass = min(max(r.correctToPass, 1), r.questionsPerCheck)
        r.unlockMinutes = Rules.unlockChoices.min(by: { abs($0 - r.unlockMinutes) < abs($1 - r.unlockMinutes) }) ?? 30
        return r
    }

    static func unlockLabel(_ minutes: Int) -> String {
        if minutes >= restOfDay { return "Rest of the day" }
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? (h == 1 ? "1 hour" : "\(h) hours") : "\(h) hr \(m) min"
    }
}

enum RuleField: String, CaseIterable, Identifiable {
    case words, seconds, reading, questions, pass, unlock, midday, passes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .words: return "Words to type"
        case .seconds: return "Seconds of talking"
        case .reading: return "Minimum reading time"
        case .questions: return "Questions per check"
        case .pass: return "Correct to pass"
        case .unlock: return "Apps open for"
        case .midday: return "Midday questions"
        case .passes: return "Emergency passes"
        }
    }

    var detail: String {
        switch self {
        case .words: return "How much you write when you type your reflection."
        case .seconds: return "Only time you are actually talking counts."
        case .reading: return "The done button waits this long."
        case .questions: return "Asked after each reading."
        case .pass: return "Right answers needed to unlock."
        case .unlock: return "After this, apps lock again until you answer one question."
        case .midday: return "Each one locks your apps until you answer it."
        case .passes: return "Skips per month for real emergencies."
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .words: return 20...300
        case .seconds: return 15...300
        case .reading: return 0...30
        case .questions: return 1...10
        case .pass: return 1...10
        case .unlock: return 5...Rules.restOfDay
        case .midday: return 0...6
        case .passes: return 0...10
        }
    }

    var step: Int {
        switch self {
        case .words, .seconds: return 5
        default: return 1
        }
    }

    /// True when a bigger number makes the app harder to get past.
    var higherIsStricter: Bool {
        switch self {
        case .unlock, .passes: return false
        default: return true
        }
    }

    func isStricter(_ a: Int, than b: Int) -> Bool {
        higherIsStricter ? a > b : a < b
    }

    func get(_ r: Rules) -> Int {
        switch self {
        case .words: return r.wordsToType
        case .seconds: return r.secondsOfTalking
        case .reading: return r.minimumReadingMinutes
        case .questions: return r.questionsPerCheck
        case .pass: return r.correctToPass
        case .unlock: return r.unlockMinutes
        case .midday: return r.middayQuestions
        case .passes: return r.emergencyPasses
        }
    }

    func set(_ r: inout Rules, _ v: Int) {
        switch self {
        case .words: r.wordsToType = v
        case .seconds: r.secondsOfTalking = v
        case .reading: r.minimumReadingMinutes = v
        case .questions: r.questionsPerCheck = v
        case .pass: r.correctToPass = v
        case .unlock: r.unlockMinutes = v
        case .midday: r.middayQuestions = v
        case .passes: r.emergencyPasses = v
        }
    }

    func valueLabel(_ v: Int) -> String {
        switch self {
        case .words: return "\(v) words"
        case .seconds: return v >= 60 && v % 60 == 0 ? "\(v / 60) min" : "\(v) sec"
        case .reading: return v == 0 ? "Off" : "\(v) min"
        case .questions: return "\(v)"
        case .pass: return "\(v)"
        case .unlock: return Rules.unlockLabel(v)
        case .midday: return v == 0 ? "Off" : "\(v) a day"
        case .passes: return "\(v) a month"
        }
    }
}

struct PendingRules: Codable, Equatable {
    var rules: Rules
    var effectiveAt: Date
}

enum RuleLogic {
    /// Stricter changes apply right away. Easier changes wait a day when the delay is on.
    static func propose(current: Rules, proposed raw: Rules, now: Date, delay: TimeInterval = 86_400, setupUntil: Date? = nil) -> (effective: Rules, pending: PendingRules?) {
        let proposed = raw.normalized()
        // During the first day after setup every change applies right away, so people can find settings that fit.
        if let setupUntil, now < setupUntil { return (proposed, nil) }
        guard current.delayEasierChanges else { return (proposed, nil) }
        var effective = current
        var easier = false
        for f in RuleField.allCases {
            let c = f.get(current), p = f.get(proposed)
            if c == p { continue }
            if f.isStricter(p, than: c) { f.set(&effective, p) } else { easier = true }
        }
        if !proposed.delayEasierChanges { easier = true }
        effective = effective.normalized()
        return (effective, easier ? PendingRules(rules: proposed, effectiveAt: now.addingTimeInterval(delay)) : nil)
    }

    static func resolve(current: Rules, pending: PendingRules?, now: Date) -> (rules: Rules, pending: PendingRules?) {
        guard let p = pending else { return (current, nil) }
        return now >= p.effectiveAt ? (p.rules.normalized(), nil) : (current, p)
    }
}

// MARK: - Schedule

struct Schedule: Codable, Equatable {
    var morning = TimeOfDay(hour: 5, minute: 0)
    var midday = TimeOfDay(hour: 12, minute: 0)
    var eveningOn = false
    var evening = TimeOfDay(hour: 21, minute: 30)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Schedule()
        morning = (try? c.decode(TimeOfDay.self, forKey: .morning)) ?? d.morning
        midday = (try? c.decode(TimeOfDay.self, forKey: .midday)) ?? d.midday
        eveningOn = (try? c.decode(Bool.self, forKey: .eveningOn)) ?? d.eveningOn
        evening = (try? c.decode(TimeOfDay.self, forKey: .evening)) ?? d.evening
    }

    /// Midday questions start at the midday time, three hours apart (two when there are many), before 11 PM.
    func middayTimes(count: Int) -> [TimeOfDay] {
        guard count > 0 else { return [] }
        let spacing = count <= 3 ? 180 : 120
        return (0..<count).compactMap { i in
            let m = midday.minutesFromMidnight + i * spacing
            return m <= 23 * 60 ? TimeOfDay(minutes: m) : nil
        }
    }
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

enum ReadMode: String, Codable, CaseIterable, Identifiable {
    case paper, inApp, listen
    var id: String { rawValue }
    var title: String {
        switch self {
        case .paper: return "Paper Bible"
        case .inApp: return "Read in Phos"
        case .listen: return "Listen"
        }
    }
    var symbol: String {
        switch self {
        case .paper: return "book.closed"
        case .inApp: return "text.book.closed"
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
    case none, reading, recall, midday, evening
}

struct ChapterRef: Codable, Hashable, Identifiable {
    var book: String
    var chapter: Int
    var id: String { "\(book).\(chapter)" }
}

struct DayRecord: Codable, Identifiable, Hashable {
    var id: String { dayKey }
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
}

struct TodayState: Codable, Equatable {
    var dayKey: String
    var readingDone = false
    var chapter: ChapterRef?
    var readingStartedAt: Date?
    var missesToday = 0
    var nextAttemptAt: Date?
    var askedQuestionIDs: [String] = []
    var unlockedUntil: Date?
    var middayPending = false
    var eveningLocked = false
    var recallCount = 0

    init(dayKey: String) {
        self.dayKey = dayKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = (try? c.decode(String.self, forKey: .dayKey)) ?? ""
        readingDone = (try? c.decode(Bool.self, forKey: .readingDone)) ?? false
        chapter = try? c.decode(ChapterRef.self, forKey: .chapter)
        readingStartedAt = try? c.decode(Date.self, forKey: .readingStartedAt)
        missesToday = (try? c.decode(Int.self, forKey: .missesToday)) ?? 0
        nextAttemptAt = try? c.decode(Date.self, forKey: .nextAttemptAt)
        askedQuestionIDs = (try? c.decode([String].self, forKey: .askedQuestionIDs)) ?? []
        unlockedUntil = try? c.decode(Date.self, forKey: .unlockedUntil)
        middayPending = (try? c.decode(Bool.self, forKey: .middayPending)) ?? false
        eveningLocked = (try? c.decode(Bool.self, forKey: .eveningLocked)) ?? false
        recallCount = (try? c.decode(Int.self, forKey: .recallCount)) ?? 0
    }

    func isUnlocked(at now: Date) -> Bool {
        guard let u = unlockedUntil else { return false }
        return u > now
    }

    /// Why apps are locked right now, or none when they are open.
    func lockReason(at now: Date) -> LockReason {
        if isUnlocked(at: now) { return .none }
        if !readingDone { return .reading }
        if eveningLocked { return .evening }
        if middayPending { return .midday }
        return .recall
    }
}

struct PassUse: Codable, Hashable, Identifiable {
    var id: Date { date }
    var date: Date
    var minutes: Int
}

struct AppSettings: Codable, Equatable {
    var onboarded = false
    var onboardedAt: Date?
    var rules = Rules()
    var pendingRules: PendingRules?
    var schedule = Schedule()
    var shieldStyle: ShieldStyle = .verse
    var planID = "john"
    var planPositions: [String: Int] = [:]
    var passUses: [PassUse] = []
    var preferredRead: ReadMode = .paper
    var preferredReflect: ReflectMode = .typed

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        onboarded = (try? c.decode(Bool.self, forKey: .onboarded)) ?? d.onboarded
        onboardedAt = try? c.decode(Date.self, forKey: .onboardedAt)
        rules = (try? c.decode(Rules.self, forKey: .rules)) ?? d.rules
        pendingRules = try? c.decode(PendingRules.self, forKey: .pendingRules)
        schedule = (try? c.decode(Schedule.self, forKey: .schedule)) ?? d.schedule
        shieldStyle = (try? c.decode(ShieldStyle.self, forKey: .shieldStyle)) ?? d.shieldStyle
        planID = (try? c.decode(String.self, forKey: .planID)) ?? d.planID
        planPositions = (try? c.decode([String: Int].self, forKey: .planPositions)) ?? d.planPositions
        passUses = (try? c.decode([PassUse].self, forKey: .passUses)) ?? d.passUses
        preferredRead = (try? c.decode(ReadMode.self, forKey: .preferredRead)) ?? d.preferredRead
        preferredReflect = (try? c.decode(ReflectMode.self, forKey: .preferredReflect)) ?? d.preferredReflect
    }

    /// Rule changes apply instantly until this moment.
    var setupWindowEnds: Date? { onboardedAt?.addingTimeInterval(86_400) }

    func passesLeft(now: Date, calendar: Calendar = .current) -> Int {
        let used = passUses.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }.count
        return max(0, rules.emergencyPasses - used)
    }
}

/// What the lock screen, shield button, and widgets need, written by the app.
struct SharedSnapshot: Codable, Equatable {
    var style: ShieldStyle = .verse
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
    var unlockedUntil: Date?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SharedSnapshot()
        style = (try? c.decode(ShieldStyle.self, forKey: .style)) ?? d.style
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
        unlockedUntil = try? c.decode(Date.self, forKey: .unlockedUntil)
    }
}
