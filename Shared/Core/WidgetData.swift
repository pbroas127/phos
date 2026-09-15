import Foundation

/// Everything the widgets show, written by the app and read by the widget extension.
/// Widgets never load the whole Bible or the achievement engine, so they stay fast and light.
struct WidgetData: Codable, Equatable {
    struct Verse: Codable, Equatable {
        var text: String
        var ref: String
    }

    struct Lock: Codable, Equatable {
        var id: String = ""
        var name: String
        var locked: Bool
        var status: String
        var left: Int?
        var limit: Int?
    }

    struct Trophy: Codable, Equatable {
        var name: String
        var detail: String
        var art: String
        var progress: Int
        var goal: Int
        var earned: Bool
    }

    var updated = Date()
    /// The day this data describes, and when a day starts, so widgets can tell a new day has begun without the app.
    var dayKey = ""
    var morningHour = 0
    var morningMinute = 0
    /// The most recent day with a reading.
    var lastDoneKey: String?
    /// What to read next once today's chapter is done.
    var nextChapter = ""
    var nextTitle = ""
    var nextKeyVerse: Verse?
    var streak = 0
    var longestStreak = 0
    var readToday = false
    /// The last 7 days, oldest first, today last.
    var week: [Bool] = Array(repeating: false, count: 7)
    var totalChapters = 0
    var chapter = "John 1"
    var chapterTitle = "The Word Became Flesh"
    var verses: [Verse] = [Verse(text: "Your word is a lamp to my feet, and a light for my path.", ref: "Psalm 119:105")]
    var keyVerse = Verse(text: "In the beginning was the Word, and the Word was with God, and the Word was God.", ref: "John 1:1")
    var planName = "John"
    var planRead = 0
    var planTotal = 21
    /// Coming chapters as "John 4" and their titles.
    var upcoming: [Verse] = []
    var locks: [Lock] = []
    var lockedApps = 0
    /// Pinned trophies first, then the closest.
    var trophies: [Trophy] = []
    /// Closest to earning, ignoring pins.
    var closest: [Trophy] = []
    var lastEarned: Trophy?
    var earnedCount = 0
    var trophyTotal = 127

    static let placeholder: WidgetData = {
        var d = WidgetData()
        d.streak = 12
        d.longestStreak = 21
        d.week = [true, true, false, true, true, true, false]
        d.totalChapters = 48
        d.chapter = "John 3"
        d.chapterTitle = "Nicodemus Comes by Night"
        d.planRead = 2
        d.upcoming = [Verse(text: "Nicodemus Comes by Night", ref: "John 3"), Verse(text: "Living Water at the Well", ref: "John 4")]
        d.locks = [Lock(name: "Social media", locked: true, status: "Locked until today's reading", left: nil, limit: nil),
                   Lock(name: "Games", locked: true, status: "3 of 5 unlocks left", left: 3, limit: 5)]
        d.lockedApps = 7
        d.trophies = [Trophy(name: "Fortnight Faithful", detail: "Read 14 days in a row.", art: "flame_gold", progress: 12, goal: 14, earned: false)]
        d.earnedCount = 9
        return d
    }()

    /// The data as it should look right now. When a new day has started since the app last wrote it,
    /// today's reading is not done yet, the week moves along, a broken streak shows zero, and the next chapter is up.
    func current(now: Date = Date(), calendar: Calendar = .current) -> WidgetData {
        guard !dayKey.isEmpty else { return self }
        let key = DayKey.key(for: now, morning: TimeOfDay(hour: morningHour, minute: morningMinute), calendar: calendar)
        guard let a = DayKey.date(from: dayKey), let b = DayKey.date(from: key) else { return self }
        let days = Int((b.timeIntervalSince(a) / 86_400).rounded())
        guard days > 0 else { return self }
        var d = self
        d.dayKey = key
        d.week = Array((week + Array(repeating: false, count: min(days, 7))).suffix(7))
        if let last = lastDoneKey, last >= DayKey.adding(-1, to: key) {} else { d.streak = 0 }
        if readToday && !nextChapter.isEmpty {
            d.chapter = nextChapter
            d.chapterTitle = nextTitle
            if let v = nextKeyVerse { d.keyVerse = v }
        }
        d.readToday = false
        if !verses.isEmpty {
            let shift = days % verses.count
            d.verses = Array(verses[shift...] + verses[..<shift])
        }
        return d
    }

    /// The start of the next day, so widgets can redraw right when it begins.
    func nextDayStart(after date: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(after: date, matching: DateComponents(hour: morningHour, minute: morningMinute), matchingPolicy: .nextTime)
    }

    /// Shuffles and reveals are for one day. A new day starts back at the day's own verse, hidden.
    static func resetDailyState(for key: String) {
        guard let defaults = UserDefaults(suiteName: AppGroup.id), !key.isEmpty, defaults.string(forKey: "widget.day") != key else { return }
        defaults.set(key, forKey: "widget.day")
        defaults.set(0, forKey: "widget.verseOffset")
        defaults.set(0, forKey: "widget.trophyOffset")
        defaults.set(false, forKey: "widget.memoryRevealed")
    }

    // MARK: Widget only state

    /// Which verse a shuffle widget is showing, changed by its button.
    static var verseOffset: Int {
        get { UserDefaults(suiteName: AppGroup.id)?.integer(forKey: "widget.verseOffset") ?? 0 }
        set { UserDefaults(suiteName: AppGroup.id)?.set(newValue, forKey: "widget.verseOffset") }
    }

    static var trophyOffset: Int {
        get { UserDefaults(suiteName: AppGroup.id)?.integer(forKey: "widget.trophyOffset") ?? 0 }
        set { UserDefaults(suiteName: AppGroup.id)?.set(newValue, forKey: "widget.trophyOffset") }
    }

    static var memoryRevealed: Bool {
        get { UserDefaults(suiteName: AppGroup.id)?.bool(forKey: "widget.memoryRevealed") ?? false }
        set { UserDefaults(suiteName: AppGroup.id)?.set(newValue, forKey: "widget.memoryRevealed") }
    }

    /// Small trophy pictures copied into the shared container, since widgets cannot use the app's assets.
    static func imageURL(_ art: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)?
            .appendingPathComponent("widget_trophy_\(art).png")
    }
}

extension SharedStore {
    var hasWidgetData: Bool { defaults.data(forKey: "widgetData") != nil }

    var widgetData: WidgetData {
        get {
            guard let data = defaults.data(forKey: "widgetData"), let d = try? JSONDecoder().decode(WidgetData.self, from: data) else { return WidgetData() }
            return d
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: "widgetData") }
        }
    }
}
