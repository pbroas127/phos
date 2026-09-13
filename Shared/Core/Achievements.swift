import Foundation

/// One trophy. Progress is always computed from saved history, so nothing can drift out of sync.
struct Achievement: Identifiable {
    enum Group: String, CaseIterable, Identifiable {
        case milestones, streaks, books, journeys, holyDays, mastery, reflection, ways, time, discipline, combos, hidden
        var id: String { rawValue }
        var title: String {
            switch self {
            case .milestones: return "Milestone Reader"
            case .streaks: return "Streaks"
            case .books: return "Books of the Bible"
            case .journeys: return "Journeys"
            case .holyDays: return "Holy Days"
            case .mastery: return "Sharp Mind"
            case .reflection: return "Reflection"
            case .ways: return "Ways to Read"
            case .time: return "Time Redeemed"
            case .discipline: return "Discipline"
            case .combos: return "Combos"
            case .hidden: return "Hidden"
            }
        }
        var subtitle: String {
            switch self {
            case .milestones: return "Chapters read, all time"
            case .streaks: return "Days in a row"
            case .books: return "Finish whole books"
            case .journeys: return "Themed readings in a set time"
            case .holyDays: return "Readings on special days"
            case .mastery: return "Quiz results"
            case .reflection: return "What you write and say"
            case .ways: return "Paper, screen, voice, and ears"
            case .time: return "Less time on locked apps"
            case .discipline: return "Habits that hold"
            case .combos: return "Reading and screen time together"
            case .hidden: return "Found by surprise"
            }
        }
    }

    let id: String
    let group: Group
    let name: String
    let detail: String
    let art: String
    let goal: Int
    var secret = false
    let measure: (AchievementStats) -> Int

    func progress(_ stats: AchievementStats) -> Int { min(goal, max(0, measure(stats))) }
    func fraction(_ stats: AchievementStats) -> Double { goal == 0 ? 1 : Double(progress(stats)) / Double(goal) }
    func done(_ stats: AchievementStats) -> Bool { progress(stats) >= goal }
}

/// Everything achievements look at, gathered once from history.
struct AchievementStats {
    let records: [DayRecord]
    let chapters: Set<String>
    let byBook: [String: Set<Int>]
    let daysByChapter: [String: Set<String>]
    let dayKeys: Set<String>
    let todayKey: String
    let perfectDays: Set<String>
    let perfectCount: Int
    let correctAnswers: Int
    let reflections: [String]
    let reflectModes: Set<ReflectMode>
    let spokenReflections: Int
    let readModes: [ReadMode: Int]
    let hours: [Int]
    let comebacks: Int
    let passDays: Set<String>
    /// Highest usage threshold, in minutes, that locked apps reached each day.
    let usage: [String: Int]
    /// Days Phos was watching screen time, so a missing usage entry means almost no use.
    let watchedDays: Set<String>

    init(records: [DayRecord], passUses: [PassUse], usage: [String: Int], watchedDays: Set<String>, todayKey: String,
         morning: TimeOfDay = TimeOfDay(hour: 0, minute: 0), calendar: Calendar = .current) {
        self.records = records
        self.todayKey = todayKey
        self.usage = usage
        self.watchedDays = watchedDays
        var chapters = Set<String>(), byBook: [String: Set<Int>] = [:], daysByChapter: [String: Set<String>] = [:]
        var perfect = Set<String>(), perfectCount = 0, correct = 0, modes: [ReadMode: Int] = [:]
        var reflectModes = Set<ReflectMode>(), spoken = 0, texts: [String] = [], hours: [Int] = []
        for r in records {
            chapters.insert(r.ref.id)
            byBook[r.ref.book, default: []].insert(r.ref.chapter)
            daysByChapter[r.ref.id, default: []].insert(r.dayKey)
            if r.total > 0 && r.score >= r.total { perfect.insert(r.dayKey); perfectCount += 1 }
            correct += r.score
            modes[r.readMode, default: 0] += 1
            let text = r.reflection.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                texts.append(text)
                reflectModes.insert(r.reflectMode)
                if r.reflectMode == .spoken { spoken += 1 }
            }
            hours.append(calendar.component(.hour, from: r.completedAt))
        }
        self.chapters = chapters
        self.byBook = byBook
        self.daysByChapter = daysByChapter
        self.dayKeys = Set(records.map(\.dayKey))
        self.perfectDays = perfect
        self.perfectCount = perfectCount
        self.correctAnswers = correct
        self.readModes = modes
        self.reflections = texts
        self.reflectModes = reflectModes
        self.spokenReflections = spoken
        self.hours = hours
        self.comebacks = records.filter { ($0.misses ?? 0) > 0 }.count
        self.passDays = Set(passUses.map { DayKey.key(for: $0.date, morning: morning, calendar: calendar) })
    }

    // MARK: Helpers used by the catalog

    func booksDone(_ ids: [String]) -> Int {
        ids.filter { (byBook[$0]?.count ?? 0) >= (ReadingPlans.chapterCounts[$0] ?? .max) }.count
    }

    func chaptersIn(_ ids: [String]) -> Int { ids.reduce(0) { $0 + (byBook[$1]?.count ?? 0) } }

    /// Most of these chapters read inside any window of this many days.
    func bestWindow(_ refs: [String], days: Int) -> Int {
        let starts = refs.flatMap { daysByChapter[$0] ?? [] }
        var best = 0
        for start in Set(starts) {
            let end = DayKey.adding(days - 1, to: start)
            let count = refs.filter { ref in (daysByChapter[ref] ?? []).contains { $0 >= start && $0 <= end } }.count
            best = max(best, count)
        }
        return best
    }

    func readOn(_ refs: [String], days: Set<String>) -> Bool {
        refs.contains { !(daysByChapter[$0] ?? []).isDisjoint(with: days) }
    }

    func longestRun(_ days: Set<String>) -> Int { Streaks.longest(doneKeys: days) }

    /// Finished days Phos watched where locked apps stayed under this many minutes.
    func daysUnder(_ minutes: Int) -> Set<String> {
        Set(watchedDays.filter { $0 < todayKey && (usage[$0] ?? 0) < minutes })
    }

    func weekday(_ key: String) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return DayKey.date(from: key).map { utc.component(.weekday, from: $0) } ?? 0
    }

    var sundays: Set<String> { dayKeys.filter { weekday($0) == 1 } }

    var wordsWritten: Int { reflections.reduce(0) { $0 + TextChecks.words($1).count } }

    /// Longest stretch of days, from the first reading until today, with no emergency pass.
    var passFreeDays: Int {
        guard let first = dayKeys.min() else { return 0 }
        var marks = passDays.filter { $0 >= first }.sorted()
        marks.insert(first, at: 0)
        marks.append(todayKey)
        var best = 0
        for i in 1..<marks.count { best = max(best, Self.daysBetween(marks[i - 1], marks[i])) }
        return best
    }

    /// Weeks in a row with a reading on both Saturday and Sunday.
    var weekendRun: Int {
        let sundaysDone = dayKeys.filter { weekday($0) == 1 && dayKeys.contains(DayKey.adding(-1, to: $0)) }
        var best = 0
        for s in sundaysDone where !sundaysDone.contains(DayKey.adding(-7, to: s)) {
            var run = 0, k = s
            while sundaysDone.contains(k) { run += 1; k = DayKey.adding(7, to: k) }
            best = max(best, run)
        }
        return best
    }

    static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let x = DayKey.date(from: a), let y = DayKey.date(from: b) else { return 0 }
        return Int((y.timeIntervalSince(x) / 86_400).rounded())
    }

    /// Easter Sunday for a year (Anonymous Gregorian algorithm), as a day key.
    static func easter(_ year: Int) -> String {
        let a = year % 19, b = year / 100, c = year % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31, day = (h + l - 7 * m + 114) % 31 + 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    var years: [Int] { Set(dayKeys.compactMap { Int($0.prefix(4)) }).sorted() }

    func holyDays(offset: Int) -> Set<String> { Set(years.map { DayKey.adding(offset, to: Self.easter($0)) }) }

    func daysMatching(_ suffix: String) -> Set<String> { dayKeys.filter { $0.hasSuffix(suffix) } }
}

enum Achievements {
    private static func refs(_ book: String, _ chapters: [Int]) -> [String] { chapters.map { "\(book).\($0)" } }
    private static func refs(_ book: String, _ range: ClosedRange<Int>) -> [String] { refs(book, Array(range)) }

    static let gospels = ["MAT", "MRK", "LUK", "JHN"]
    static let moses = ["GEN", "EXO", "LEV", "NUM", "DEU"]
    static let paul = ["ROM", "1CO", "2CO", "GAL", "EPH", "PHP", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM"]
    static let general = ["HEB", "JAS", "1PE", "2PE", "1JN", "2JN", "3JN", "JUD"]
    static let major = ["ISA", "JER", "LAM", "EZK", "DAN"]
    static let minor = ["HOS", "JOL", "AMO", "OBA", "JON", "MIC", "NAM", "HAB", "ZEP", "HAG", "ZEC", "MAL"]

    private static func book(_ id: String, _ name: String, _ detail: String, _ art: String, _ ids: [String]) -> Achievement {
        Achievement(id: "book.\(id)", group: .books, name: name, detail: detail, art: art, goal: ids.count) { $0.booksDone(ids) }
    }

    private static func journey(_ id: String, _ name: String, _ detail: String, _ art: String, _ list: [String], days: Int) -> Achievement {
        Achievement(id: "journey.\(id)", group: .journeys, name: name, detail: detail, art: art, goal: list.count) { $0.bestWindow(list, days: days) }
    }

    static let all: [Achievement] = milestones + streaks + books + journeys + holyDays + mastery + reflection + ways + time + discipline + combos + hidden

    static let milestones: [Achievement] = [
        (1, "first", "First Light", "Finish your first chapter.", "sunrise"),
        (10, "10", "Kindled Wick", "Read 10 chapters.", "lamp_bronze"),
        (25, "25", "Steady Glow", "Read 25 chapters.", "lamp_silver"),
        (50, "50", "Lamp to My Feet", "Read 50 chapters.", "lamp_gold"),
        (100, "100", "Hundredfold", "Read 100 chapters.", "lamp_radiant"),
        (250, "250", "Deep Roots", "Read 250 chapters.", "roots_tree"),
        (500, "500", "Hidden Treasure", "Read 500 chapters.", "treasure_chest"),
        (1000, "1000", "Keeper of the Scrolls", "Read 1,000 chapters.", "scroll_keeper")
    ].map { goal, id, name, detail, art in
        Achievement(id: "chapters.\(id)", group: .milestones, name: name, detail: detail, art: art, goal: goal) { $0.chapters.count }
    }

    static let streaks: [Achievement] = [
        (3, "Kindled", "Read 3 days in a row.", "flame_bronze"),
        (7, "One Full Week", "Read 7 days in a row.", "flame_silver"),
        (14, "Fortnight Faithful", "Read 14 days in a row.", "flame_gold"),
        (30, "Month of Light", "Read 30 days in a row.", "flame_radiant"),
        (60, "The Bush Still Burns", "Read 60 days in a row.", "burning_bush"),
        (100, "Evergreen", "Read 100 days in a row.", "evergreen_tree"),
        (200, "Pillar of Fire", "Read 200 days in a row.", "pillar_fire"),
        (365, "A Year of Light", "Read every day for a whole year.", "sun_crown")
    ].map { goal, name, detail, art in
        Achievement(id: "streak.\(goal)", group: .streaks, name: name, detail: detail, art: art, goal: goal) { $0.longestRun($0.dayKeys) }
    }

    static let books: [Achievement] = [
        book("GEN", "In the Beginning", "Read all of Genesis.", "creation", ["GEN"]),
        book("EXO", "Out of Egypt", "Read all of Exodus.", "parted_sea", ["EXO"]),
        book("law", "The Law Given", "Read Leviticus, Numbers, and Deuteronomy.", "stone_tablets", ["LEV", "NUM", "DEU"]),
        book("moses", "Books of Moses", "Read Genesis through Deuteronomy.", "moses_staff", moses),
        book("JOS", "The Promised Land", "Read all of Joshua.", "trumpet_walls", ["JOS"]),
        book("judges", "Days of the Judges", "Read Judges and Ruth.", "torch_jar", ["JDG", "RUT"]),
        book("samuel", "A King After God's Heart", "Read 1 and 2 Samuel.", "crown_harp", ["1SA", "2SA"]),
        book("kings", "Kings and Prophets", "Read 1 and 2 Kings.", "chariot_fire", ["1KI", "2KI"]),
        book("chronicles", "The Chronicler", "Read 1 and 2 Chronicles.", "temple", ["1CH", "2CH"]),
        book("return", "Return and Rebuild", "Read Ezra and Nehemiah.", "city_gate", ["EZR", "NEH"]),
        book("EST", "For Such a Time", "Read all of Esther.", "scepter", ["EST"]),
        book("JOB", "Out of the Whirlwind", "Read all of Job.", "whirlwind", ["JOB"]),
        book("PSA", "The Psalmist", "Read all 150 Psalms.", "lyre", ["PSA"]),
        book("PRO", "More Precious Than Rubies", "Read all of Proverbs.", "ruby", ["PRO"]),
        book("ECC", "A Time for Everything", "Read all of Ecclesiastes.", "seasons_tree", ["ECC"]),
        book("SNG", "Song of Songs", "Read all of Song of Songs.", "rose", ["SNG"]),
        book("major", "Major Prophets", "Read Isaiah, Jeremiah, Lamentations, Ezekiel, and Daniel.", "live_coal", major),
        book("minor", "The Twelve", "Read all twelve minor prophets, Hosea to Malachi.", "plumb_line", minor),
        book("DAN", "Dare to Be Daniel", "Read all of Daniel.", "lion", ["DAN"]),
        book("gospels", "The Good News", "Read all four Gospels.", "four_scrolls", gospels),
        book("ACT", "To the Ends of the Earth", "Read all of Acts.", "ship_sail", ["ACT"]),
        book("paul", "Letters Home", "Read all 13 letters of Paul.", "quill_letter", paul),
        book("general", "Letters to All", "Read Hebrews through Jude.", "sealed_letters", general),
        book("REV", "Seven Seals", "Read all of Revelation.", "seven_seals", ["REV"]),
        book("short", "Short and Sweet", "Read every one chapter book: Obadiah, Philemon, 2 John, 3 John, and Jude.", "mustard_seed", ["OBA", "PHM", "2JN", "3JN", "JUD"]),
        book("ot", "The Old Covenant", "Read the whole Old Testament.", "ark_covenant", ReadingPlans.oldTestament),
        book("nt", "The New Covenant", "Read the whole New Testament.", "chalice_bread", ReadingPlans.newTestament),
        book("bible", "Genesis to Revelation", "Read every chapter of the Bible.", "bible_radiant", ReadingPlans.oldTestament + ReadingPlans.newTestament)
    ]

    static let journeys: [Achievement] = [
        journey("signs", "The Seven Signs", "Read John 2, 4, 5, 6, 9, and 11 within two weeks.", "water_jars", refs("JHN", [2, 4, 5, 6, 9, 11]), days: 14),
        journey("mountain", "On the Mountain", "Read Matthew 5, 6, and 7 within three days.", "mountain_sermon", refs("MAT", 5...7), days: 3),
        journey("passion", "Passion Week", "Read the last days of Jesus in all four Gospels within one week: Matthew 26 to 28, Mark 14 to 16, Luke 22 to 24, and John 18 to 21.", "crown_thorns",
                refs("MAT", 26...28) + refs("MRK", 14...16) + refs("LUK", 22...24) + refs("JHN", 18...21), days: 7),
        journey("shepherd", "The Good Shepherd", "Read Psalm 23, Ezekiel 34, Luke 15, and John 10 within one week.", "shepherd_staff", ["PSA.23", "EZK.34", "LUK.15", "JHN.10"], days: 7),
        journey("phos", "Phos", "Follow the light: Genesis 1, Psalm 27, Isaiah 60, John 1, John 8, and 1 John 1 within two weeks.", "phos_emblem", ["GEN.1", "PSA.27", "ISA.60", "JHN.1", "JHN.8", "1JN.1"], days: 14),
        journey("exodus", "The Exodus Road", "Read Exodus 12, 14, 16, and 20 within one week.", "manna_basket", refs("EXO", [12, 14, 16, 20]), days: 7),
        journey("giant", "Giant Slayer", "Read 1 Samuel 16 and 17 and Psalm 23 within one week.", "sling_stone", ["1SA.16", "1SA.17", "PSA.23"], days: 7),
        journey("babylon", "Faithful in Babylon", "Read Daniel 1 to 6 within one week.", "fiery_furnace", refs("DAN", 1...6), days: 7),
        journey("jonah", "Into the Deep", "Read all four chapters of Jonah in one day.", "whale", refs("JON", 1...4), days: 1),
        journey("love", "Love Never Fails", "Read 1 Corinthians 13, John 15, Romans 12, and 1 John 4 within one week.", "heart_flame", ["1CO.13", "JHN.15", "ROM.12", "1JN.4"], days: 7),
        journey("armor", "Armor of God", "Read Ephesians 6, Romans 13, 2 Corinthians 10, and 1 Thessalonians 5 within one week.", "shield_armor", ["EPH.6", "ROM.13", "2CO.10", "1TH.5"], days: 7),
        journey("faith", "Hall of Faith", "Read Hebrews 11 with the stories it remembers: Genesis 22, Exodus 14, and Joshua 6, within two weeks.", "laurel_wreath", ["HEB.11", "GEN.22", "EXO.14", "JOS.6"], days: 14),
        journey("servant", "The Suffering Servant", "Read Isaiah 53, Psalm 22, and Matthew 27 within one week.", "lamb", ["ISA.53", "PSA.22", "MAT.27"], days: 7),
        journey("wisdom", "Month of Wisdom", "Read all 31 chapters of Proverbs within 31 days.", "golden_key", refs("PRO", 1...31), days: 31),
        journey("ascent", "Songs of Ascent", "Read Psalms 120 to 134 within 15 days.", "stone_steps", refs("PSA", 120...134), days: 15),
        journey("exile", "Exile and Return", "Read 2 Kings 25, Lamentations 1, Ezra 1, and Nehemiah 8 within two weeks.", "harp_willow", ["2KI.25", "LAM.1", "EZR.1", "NEH.8"], days: 14),
        journey("elijah", "Fire from Heaven", "Read 1 Kings 17, 18, and 19 within three days.", "altar_fire", refs("1KI", 17...19), days: 3),
        journey("breath", "Breath of Life", "Read Ezekiel 37, Joel 2, and Acts 2 within one week.", "dove", ["EZK.37", "JOL.2", "ACT.2"], days: 7),
        journey("ruth", "Kinsman Redeemer", "Read all four chapters of Ruth in one day.", "wheat_sheaf", refs("RUT", 1...4), days: 1),
        journey("walls", "Rebuild the Walls", "Read Nehemiah 1 to 6 within six days.", "trowel_wall", refs("NEH", 1...6), days: 6),
        journey("seeds", "Seeds and Soils", "Read the parable of the sower in Matthew 13, Mark 4, and Luke 8 within one week.", "seed_sower", ["MAT.13", "MRK.4", "LUK.8"], days: 7),
        journey("rainbow", "The Rainbow Promise", "Read Genesis 1 to 9 within nine days.", "rainbow", refs("GEN", 1...9), days: 9),
        journey("home", "Welcome Home", "Read Luke 15, Hosea 11, and Jeremiah 31 within one week.", "signet_ring", ["LUK.15", "HOS.11", "JER.31"], days: 7),
        journey("blessed", "Blessed", "Read Matthew 5 and Luke 6 on the same day.", "lily", ["MAT.5", "LUK.6"], days: 1),
        journey("revelation", "Things to Come", "Read all 22 chapters of Revelation within 22 days.", "trumpet_angel", refs("REV", 1...22), days: 22)
    ]

    static let holyDays: [Achievement] = [
        Achievement(id: "holy.easter", group: .holyDays, name: "He Is Risen", detail: "On Easter Sunday, read Matthew 28, Mark 16, Luke 24, or John 20.", art: "empty_tomb", goal: 1) {
            $0.readOn(["MAT.28", "MRK.16", "LUK.24", "JHN.20"], days: $0.holyDays(offset: 0)) ? 1 : 0
        },
        Achievement(id: "holy.palm", group: .holyDays, name: "Hosanna", detail: "On Palm Sunday, read Matthew 21, Mark 11, Luke 19, or John 12.", art: "palm_branch", goal: 1) {
            $0.readOn(["MAT.21", "MRK.11", "LUK.19", "JHN.12"], days: $0.holyDays(offset: -7)) ? 1 : 0
        },
        Achievement(id: "holy.friday", group: .holyDays, name: "It Is Finished", detail: "On Good Friday, read Matthew 27, Mark 15, Luke 23, or John 19.", art: "cross_radiant", goal: 1) {
            $0.readOn(["MAT.27", "MRK.15", "LUK.23", "JHN.19"], days: $0.holyDays(offset: -2)) ? 1 : 0
        },
        Achievement(id: "holy.pentecost", group: .holyDays, name: "Tongues of Fire", detail: "Read Acts 2 on Pentecost Sunday.", art: "tongues_fire", goal: 1) {
            $0.readOn(["ACT.2"], days: $0.holyDays(offset: 49)) ? 1 : 0
        },
        Achievement(id: "holy.tidings", group: .holyDays, name: "Good Tidings", detail: "Read Luke 2 during December.", art: "star_manger", goal: 1) { s in
            (s.daysByChapter["LUK.2"] ?? []).contains { $0.dropFirst(5).hasPrefix("12") } ? 1 : 0
        },
        Achievement(id: "holy.christmas", group: .holyDays, name: "Christmas Morning", detail: "Read any chapter on Christmas Day.", art: "bethlehem_star", goal: 1) {
            $0.daysMatching("-12-25").isEmpty ? 0 : 1
        },
        Achievement(id: "holy.newyear", group: .holyDays, name: "New Every Morning", detail: "Read any chapter on New Year's Day.", art: "renewal_sprout", goal: 1) {
            $0.daysMatching("-01-01").isEmpty ? 0 : 1
        },
        Achievement(id: "holy.sabbath", group: .holyDays, name: "Sabbath Keeper", detail: "Read on 10 different Sundays.", art: "sabbath_candles", goal: 10) { $0.sundays.count },
        Achievement(id: "holy.lordsday", group: .holyDays, name: "Every Lord's Day", detail: "Read on 52 different Sundays.", art: "church_bell", goal: 52) { $0.sundays.count }
    ]

    static let mastery: [Achievement] = [
        Achievement(id: "quiz.1", group: .mastery, name: "Sharp Mind", detail: "Get every question right on a quiz.", art: "star_bronze", goal: 1) { $0.perfectCount },
        Achievement(id: "quiz.10", group: .mastery, name: "Well Studied", detail: "Get a perfect quiz 10 times.", art: "star_silver", goal: 10) { $0.perfectCount },
        Achievement(id: "quiz.50", group: .mastery, name: "Scholar", detail: "Get a perfect quiz 50 times.", art: "star_gold", goal: 50) { $0.perfectCount },
        Achievement(id: "quiz.week", group: .mastery, name: "Perfect Week", detail: "Get a perfect quiz 7 days in a row.", art: "star_radiant", goal: 7) { $0.longestRun($0.perfectDays) },
        Achievement(id: "quiz.scribe", group: .mastery, name: "The Scribe", detail: "Get a perfect quiz 30 days in a row.", art: "ink_scroll", goal: 30) { $0.longestRun($0.perfectDays) },
        Achievement(id: "quiz.500", group: .mastery, name: "Always Ready", detail: "Answer 500 questions correctly.", art: "open_book_star", goal: 500) { $0.correctAnswers },
        Achievement(id: "quiz.2000", group: .mastery, name: "Sword of the Spirit", detail: "Answer 2,000 questions correctly.", art: "sword_word", goal: 2000) { $0.correctAnswers },
        Achievement(id: "quiz.comeback", group: .mastery, name: "Cast the Net Again", detail: "Miss a quiz, then pass it later the same day.", art: "fishing_net", goal: 1) { $0.comebacks }
    ]

    static let reflection: [Achievement] = [
        Achievement(id: "reflect.first", group: .reflection, name: "First Words", detail: "Save your first reflection.", art: "feather_quill", goal: 1) { $0.reflections.count },
        Achievement(id: "reflect.1000", group: .reflection, name: "Pages Filled", detail: "Write or speak 1,000 words of reflection.", art: "journal_book", goal: 1000) { $0.wordsWritten },
        Achievement(id: "reflect.10000", group: .reflection, name: "Journal Keeper", detail: "Write or speak 10,000 words of reflection.", art: "illuminated_manuscript", goal: 10000) { $0.wordsWritten },
        Achievement(id: "reflect.long", group: .reflection, name: "A Long Letter", detail: "Save one reflection over 300 words.", art: "letter_seal", goal: 1) { s in
            s.reflections.contains { TextChecks.words($0).count > 300 } ? 1 : 0
        },
        Achievement(id: "reflect.voice", group: .reflection, name: "Voice of Praise", detail: "Speak 25 reflections out loud.", art: "shofar", goal: 25) { $0.spokenReflections },
        Achievement(id: "reflect.ways", group: .reflection, name: "Many Ways to Pray", detail: "Reflect by typing, by speaking, and with prompts.", art: "praying_hands", goal: 3) { $0.reflectModes.count },
        Achievement(id: "reflect.100", group: .reflection, name: "Deep Well", detail: "Save 100 reflections.", art: "well_water", goal: 100) { $0.reflections.count }
    ]

    static let ways: [Achievement] = [
        Achievement(id: "ways.all", group: .ways, name: "Every Way", detail: "Read with a paper Bible, in Phos, out loud, and by listening.", art: "compass", goal: ReadMode.allCases.count) { $0.readModes.count },
        Achievement(id: "ways.aloud10", group: .ways, name: "Read Aloud", detail: "Read 10 chapters out loud.", art: "speaking_scroll", goal: 10) { $0.readModes[.speak] ?? 0 },
        Achievement(id: "ways.lector", group: .ways, name: "The Lector", detail: "Read 100 chapters out loud.", art: "lectern", goal: 100) { $0.readModes[.speak] ?? 0 },
        Achievement(id: "ways.listen", group: .ways, name: "Ears to Hear", detail: "Listen to 25 chapters.", art: "ear_waves", goal: 25) { $0.readModes[.listen] ?? 0 },
        Achievement(id: "ways.paper", group: .ways, name: "Paper and Ink", detail: "Read 50 chapters in a paper Bible.", art: "leather_bible", goal: 50) { $0.readModes[.paper] ?? 0 }
    ]

    static let time: [Achievement] = [
        Achievement(id: "time.unplugged", group: .time, name: "Unplugged", detail: "Spend less than 30 minutes on locked apps in a day.", art: "broken_chain", goal: 1) { $0.daysUnder(30).count },
        Achievement(id: "time.still", group: .time, name: "Be Still", detail: "Spend less than 15 minutes on locked apps in a day.", art: "still_waters", goal: 1) { $0.daysUnder(15).count },
        Achievement(id: "time.hour7", group: .time, name: "Guarded Hours", detail: "Have 7 days under an hour on locked apps.", art: "hourglass_bronze", goal: 7) { $0.daysUnder(60).count },
        Achievement(id: "time.hour30", group: .time, name: "Redeeming the Time", detail: "Have 30 days under an hour on locked apps.", art: "hourglass_silver", goal: 30) { $0.daysUnder(60).count },
        Achievement(id: "time.hour50", group: .time, name: "Fifty Free Days", detail: "Have 50 days under an hour on locked apps.", art: "hourglass_gold", goal: 50) { $0.daysUnder(60).count },
        Achievement(id: "time.fast", group: .time, name: "A Week Set Apart", detail: "Stay under 30 minutes on locked apps 7 days in a row.", art: "olive_branch", goal: 7) { $0.longestRun($0.daysUnder(30)) }
    ]

    static let discipline: [Achievement] = [
        Achievement(id: "habit.early", group: .discipline, name: "Early Riser", detail: "Finish a reading before 7 AM, 10 times.", art: "rooster", goal: 10) { $0.hours.filter { $0 >= 4 && $0 < 7 }.count },
        Achievement(id: "habit.firstfruits", group: .discipline, name: "First Fruits", detail: "Finish a reading before 9 AM, 30 times.", art: "grapes_basket", goal: 30) { $0.hours.filter { $0 >= 4 && $0 < 9 }.count },
        Achievement(id: "habit.night", group: .discipline, name: "Night Watch", detail: "Finish a reading after 9 PM, 10 times.", art: "moon_lantern", goal: 10) { $0.hours.filter { $0 >= 21 }.count },
        Achievement(id: "habit.held30", group: .discipline, name: "Held the Line", detail: "Go 30 days without an emergency pass.", art: "shield_gold", goal: 30) { $0.passFreeDays },
        Achievement(id: "habit.held90", group: .discipline, name: "Unshaken", detail: "Go 90 days without an emergency pass.", art: "tower", goal: 90) { $0.passFreeDays },
        Achievement(id: "habit.weekends", group: .discipline, name: "Anchored Weekends", detail: "Read on Saturday and Sunday for 4 weekends in a row.", art: "anchor", goal: 4) { $0.weekendRun }
    ]

    static let combos: [Achievement] = [
        Achievement(id: "combo.redeem", group: .combos, name: "Redeem the Time", detail: "Have 10 days with a perfect quiz and under an hour on locked apps.", art: "sun_hourglass", goal: 10) {
            $0.perfectDays.intersection($0.daysUnder(60)).count
        },
        Achievement(id: "combo.fed", group: .combos, name: "Fasted and Fed", detail: "Read 7 days in a row while staying under an hour on locked apps each day.", art: "loaves_fish", goal: 7) {
            $0.longestRun($0.dayKeys.intersection($0.daysUnder(60)))
        },
        Achievement(id: "combo.sabbath", group: .combos, name: "Sabbath Rest", detail: "On a Sunday, read and stay under 15 minutes on locked apps.", art: "tent", goal: 1) {
            $0.sundays.intersection($0.daysUnder(15)).isEmpty ? 0 : 1
        },
        Achievement(id: "combo.armor", group: .combos, name: "The Whole Armor", detail: "Reach a 30 day streak, a perfect week, and 1,000 words of reflection.", art: "armor_helmet", goal: 3) { s in
            (s.longestRun(s.dayKeys) >= 30 ? 1 : 0) + (s.longestRun(s.perfectDays) >= 7 ? 1 : 0) + (s.wordsWritten >= 1000 ? 1 : 0)
        },
        Achievement(id: "combo.light", group: .combos, name: "Light of the World", detail: "Read all four Gospels, reach a 30 day streak, and get 10 perfect quizzes.", art: "city_on_hill", goal: 3) { s in
            (s.booksDone(gospels) == 4 ? 1 : 0) + (s.longestRun(s.dayKeys) >= 30 ? 1 : 0) + (s.perfectCount >= 10 ? 1 : 0)
        }
    ]

    static let hidden: [Achievement] = [
        Achievement(id: "secret.midnight", group: .hidden, name: "Midnight Oil", detail: "Finish a reading between midnight and 4 AM.", art: "midnight_candle", goal: 1, secret: true) { $0.hours.contains { $0 < 4 } ? 1 : 0 },
        Achievement(id: "secret.wept", group: .hidden, name: "Jesus Wept", detail: "Read John 11, home of the shortest verse.", art: "tear_drop", goal: 1, secret: true) { $0.chapters.contains("JHN.11") ? 1 : 0 },
        Achievement(id: "secret.longest", group: .hidden, name: "The Longest Chapter", detail: "Read Psalm 119, all 176 verses.", art: "long_scroll", goal: 1, secret: true) { $0.chapters.contains("PSA.119") ? 1 : 0 },
        Achievement(id: "secret.seventy", group: .hidden, name: "Seventy Times Seven", detail: "Read 490 chapters.", art: "knot_rope", goal: 490, secret: true) { $0.chapters.count },
        Achievement(id: "secret.ancient", group: .hidden, name: "Ancient of Days", detail: "Read Daniel 7.", art: "throne_fire", goal: 1, secret: true) { $0.chapters.contains("DAN.7") ? 1 : 0 },
        Achievement(id: "secret.jubilee", group: .hidden, name: "Jubilee", detail: "Read on 50 different days.", art: "silver_trumpets", goal: 50, secret: true) { $0.dayKeys.count }
    ]

    /// Unfinished trophies closest to done, skipping hidden ones.
    static func almost(_ stats: AchievementStats, earned: Set<String>, limit: Int = 3) -> [Achievement] {
        all.filter { !$0.secret && !earned.contains($0.id) && !$0.done(stats) && $0.progress(stats) > 0 }
            .sorted { $0.fraction(stats) > $1.fraction(stats) }
            .prefix(limit).map { $0 }
    }
}
