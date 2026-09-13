import Foundation

struct ReadingPlan: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let chapters: [ChapterRef]
    /// Set for single book paths.
    let bookID: String?
}

struct PlanGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let plans: [ReadingPlan]
}

enum ReadingPlans {
    static let chapterCounts: [String: Int] = [
        "GEN": 50, "EXO": 40, "LEV": 27, "NUM": 36, "DEU": 34, "JOS": 24, "JDG": 21, "RUT": 4, "1SA": 31, "2SA": 24,
        "1KI": 22, "2KI": 25, "1CH": 29, "2CH": 36, "EZR": 10, "NEH": 13, "EST": 10, "JOB": 42, "PSA": 150, "PRO": 31,
        "ECC": 12, "SNG": 8, "ISA": 66, "JER": 52, "LAM": 5, "EZK": 48, "DAN": 12, "HOS": 14, "JOL": 3, "AMO": 9,
        "OBA": 1, "JON": 4, "MIC": 7, "NAM": 3, "HAB": 3, "ZEP": 3, "HAG": 2, "ZEC": 14, "MAL": 4,
        "MAT": 28, "MRK": 16, "LUK": 24, "JHN": 21, "ACT": 28, "ROM": 16, "1CO": 16, "2CO": 13, "GAL": 6,
        "EPH": 6, "PHP": 4, "COL": 4, "1TH": 5, "2TH": 3, "1TI": 6, "2TI": 4, "TIT": 3, "PHM": 1, "HEB": 13,
        "JAS": 5, "1PE": 5, "2PE": 3, "1JN": 5, "2JN": 1, "3JN": 1, "JUD": 1, "REV": 22
    ]

    static let oldTestament = ["GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA", "1KI", "2KI", "1CH",
                               "2CH", "EZR", "NEH", "EST", "JOB", "PSA", "PRO", "ECC", "SNG", "ISA", "JER", "LAM", "EZK",
                               "DAN", "HOS", "JOL", "AMO", "OBA", "JON", "MIC", "NAM", "HAB", "ZEP", "HAG", "ZEC", "MAL"]
    static let newTestament = ["MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL", "EPH", "PHP", "COL",
                               "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE", "2PE", "1JN", "2JN",
                               "3JN", "JUD", "REV"]
    static let prophets = ["ISA", "JER", "LAM", "EZK", "DAN", "HOS", "JOL", "AMO", "OBA", "JON", "MIC", "NAM", "HAB",
                           "ZEP", "HAG", "ZEC", "MAL"]

    static func book(_ id: String) -> [ChapterRef] {
        (1...(chapterCounts[id] ?? 1)).map { ChapterRef(book: id, chapter: $0) }
    }

    static func books(_ ids: [String]) -> [ChapterRef] { ids.flatMap(book) }

    static let bookPlans: [ReadingPlan] = (oldTestament + newTestament).map { id in
        let n = chapterCounts[id] ?? 1
        return ReadingPlan(id: "book.\(id)", name: BookNames.name(id), detail: n == 1 ? "1 chapter" : "\(n) chapters",
                           chapters: book(id), bookID: id)
    }

    static let curated: [ReadingPlan] = [
        ReadingPlan(id: "gospels", name: "The Gospels", detail: "89 days. Matthew, Mark, Luke, and John.",
                    chapters: books(["MAT", "MRK", "LUK", "JHN"]), bookID: nil),
        ReadingPlan(id: "letters", name: "Letters of Paul", detail: "87 days. Romans through Philemon.",
                    chapters: books(["ROM", "1CO", "2CO", "GAL", "EPH", "PHP", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM"]), bookID: nil),
        ReadingPlan(id: "nt", name: "New Testament", detail: "260 days. Matthew through Revelation.",
                    chapters: books(newTestament), bookID: nil),
        ReadingPlan(id: "wisdom", name: "Psalms and Proverbs", detail: "181 days of prayer and wisdom.",
                    chapters: books(["PSA", "PRO"]), bookID: nil),
        ReadingPlan(id: "moses", name: "Books of Moses", detail: "187 days. Genesis through Deuteronomy.",
                    chapters: books(["GEN", "EXO", "LEV", "NUM", "DEU"]), bookID: nil),
        ReadingPlan(id: "prophets", name: "The Prophets", detail: "250 days. Isaiah through Malachi.",
                    chapters: books(prophets), bookID: nil),
        ReadingPlan(id: "ot", name: "Old Testament", detail: "929 days. Genesis through Malachi.",
                    chapters: books(oldTestament), bookID: nil),
        ReadingPlan(id: "bible", name: "The Whole Bible", detail: "1,189 days. Every chapter, Genesis to Revelation.",
                    chapters: books(oldTestament + newTestament), bookID: nil)
    ]

    /// Short topical and story plans. They can jump around the Bible like a journey.
    static let topicGroups: [PlanGroup] = [
        PlanGroup(id: "seasons", title: "For hard seasons", subtitle: "Short paths for what you are walking through", plans: [
            topic("seasons.anxious", "When You Feel Anxious", "Peace for a restless mind.", "PSA.23 PSA.46 PSA.55 PSA.121 ISA.41 MAT.6 PHP.4 1PE.5"),
            topic("seasons.grief", "Grief and Loss", "Hope and comfort when someone is gone.", "PSA.34 PSA.42 PSA.88 LAM.3 JHN.11 1TH.4 2CO.1 REV.21"),
            topic("seasons.fear", "Courage in Fear", "Strength to face what scares you.", "JOS.1 1SA.17 PSA.27 PSA.91 ISA.43 DAN.3 DAN.6 MRK.4"),
            topic("seasons.temptation", "Standing Firm in Temptation", "Help to say no and walk free.", "GEN.39 MAT.4 1CO.10 ROM.6 ROM.7 GAL.5 EPH.6 JAS.1"),
            topic("seasons.anger", "Anger and Forgiveness", "Letting go of what you are holding.", "GEN.45 PRO.15 MAT.18 LUK.23 ROM.12 EPH.4 COL.3 JAS.3"),
            topic("seasons.alone", "When You Feel Alone", "God stays near when people are far.", "RUT.1 1KI.19 PSA.25 PSA.139 ISA.49 JHN.14 2TI.4 HEB.13"),
            topic("seasons.doubt", "Honest Doubt", "Bring your questions to God.", "JOB.38 PSA.73 HAB.1 HAB.3 MRK.9 JHN.20 HEB.11 JUD.1"),
            topic("seasons.shame", "Shame and Starting Over", "Mercy for the things you regret.", "GEN.3 PSA.32 PSA.51 ISA.1 LUK.15 JHN.8 JHN.21 ROM.8"),
            topic("seasons.money", "Money and Contentment", "Freedom from always wanting more.", "PRO.30 MAL.3 MAT.6 LUK.12 LUK.16 PHP.4 1TI.6 HEB.13"),
            topic("seasons.waiting", "Waiting on God", "Faith for the long in between.", "GEN.15 GEN.21 PSA.40 PSA.130 ISA.40 HAB.2 LUK.2 JAS.5"),
            topic("seasons.weary", "Weary and Worn Out", "Rest for the tired and burned out.", "1KI.19 PSA.62 PSA.127 ISA.40 MAT.11 MRK.6 2CO.4 GAL.6"),
            topic("seasons.love", "Love and Relationships", "What real love looks like.", "GEN.2 RUT.2 SNG.2 PRO.31 1CO.13 EPH.5 COL.3 1JN.4")
        ]),
        PlanGroup(id: "questions", title: "Big questions", subtitle: "Straight to what the Bible says", plans: [
            topic("questions.jesus", "Who Is Jesus?", "The one the whole Bible points to.", "ISA.53 MRK.8 JHN.1 JHN.14 PHP.2 COL.1 HEB.1 REV.1"),
            topic("questions.suffering", "Why Is There Suffering?", "Pain, evil, and a God who is still good.", "GEN.3 JOB.1 JOB.42 PSA.73 ROM.8 2CO.4 1PE.1 REV.21"),
            topic("questions.pray", "How Do I Pray?", "Learn to talk with God.", "1KI.8 PSA.5 DAN.9 MAT.6 LUK.11 LUK.18 JHN.17 JAS.5"),
            topic("questions.saved", "What Does It Mean to Be Saved?", "Grace, faith, and new life.", "JHN.3 ACT.16 ROM.3 ROM.5 ROM.10 EPH.2 TIT.3 1JN.5"),
            topic("questions.death", "What Happens When We Die?", "The hope of resurrection.", "JHN.11 JHN.14 1CO.15 2CO.5 PHP.1 1TH.4 REV.21 REV.22"),
            topic("questions.will", "What Does God Want From Me?", "Finding God's will for your life.", "PRO.3 JER.29 MIC.6 MAT.22 ROM.12 EPH.5 1TH.5 JAS.4"),
            topic("questions.spirit", "Who Is the Holy Spirit?", "The Helper Jesus promised.", "JOL.2 JHN.14 JHN.16 ACT.2 ROM.8 1CO.12 GAL.5 EPH.1"),
            topic("questions.church", "Why Does Church Matter?", "Belonging to God's family.", "MAT.16 ACT.2 ACT.4 1CO.12 EPH.4 HEB.10 1PE.2 REV.2"),
            topic("questions.word", "Can I Trust the Bible?", "Why God's word stands.", "PSA.19 PSA.119 ISA.55 LUK.1 JHN.20 2TI.3 HEB.4 2PE.1"),
            topic("questions.godlike", "What Is God Like?", "Holy, faithful, and full of love.", "EXO.34 PSA.103 PSA.145 ISA.6 ISA.40 JHN.4 1JN.4 REV.4")
        ]),
        PlanGroup(id: "stories", title: "Great stories", subtitle: "Follow one life or one story from start to finish", plans: [
            topic("stories.beginnings", "In the Beginning", "Creation, the fall, the flood, and Babel.", "GEN.1 GEN.2 GEN.3 GEN.4 GEN.6 GEN.7 GEN.8 GEN.9 GEN.11"),
            topic("stories.abraham", "Abraham's Journey of Faith", "A promise, a son, and a mountain.", "GEN.12 GEN.15 GEN.17 GEN.18 GEN.21 GEN.22"),
            topic("stories.joseph", "The Story of Joseph", "From the pit to the palace.", "GEN.37 GEN.39 GEN.40 GEN.41 GEN.42 GEN.43 GEN.44 GEN.45 GEN.46 GEN.50"),
            topic("stories.moses", "Moses and the Exodus", "Out of slavery and into freedom.", "EXO.1 EXO.2 EXO.3 EXO.4 EXO.5 EXO.7 EXO.11 EXO.12 EXO.14 EXO.16 EXO.19 EXO.20"),
            topic("stories.judges", "Heroes of the Judges", "Deborah, Gideon, and Samson.", "JDG.4 JDG.6 JDG.7 JDG.13 JDG.14 JDG.16"),
            topic("stories.ruthesther", "Ruth and Esther", "Two brave women and a faithful God.", "RUT.1 RUT.2 RUT.3 RUT.4 EST.2 EST.4 EST.5 EST.7 EST.8"),
            topic("stories.david", "The Life of David", "Shepherd, giant slayer, king, and sinner forgiven.", "1SA.16 1SA.17 1SA.18 1SA.24 2SA.5 2SA.6 2SA.7 2SA.11 2SA.12 2SA.18 PSA.51"),
            topic("stories.elijah", "Elijah and Elisha", "Fire from heaven and a chariot in the sky.", "1KI.17 1KI.18 1KI.19 1KI.21 2KI.2 2KI.4 2KI.5 2KI.6"),
            topic("stories.daniel", "Daniel in Babylon", "Faithful in a foreign land.", "DAN.1 DAN.2 DAN.3 DAN.4 DAN.5 DAN.6"),
            topic("stories.exile", "Exile and Coming Home", "Losing everything and being brought back.", "2KI.25 LAM.1 JER.29 EZK.37 EZR.1 EZR.3 NEH.2 NEH.8"),
            topic("stories.women", "Women of Faith", "Sarah, Rahab, Deborah, Hannah, Mary, and more.", "GEN.18 EXO.2 JOS.2 JDG.4 RUT.1 1SA.1 EST.4 LUK.1 LUK.10 JHN.20"),
            topic("stories.lifeofjesus", "The Life of Jesus", "From the manger to the empty tomb.", "LUK.1 LUK.2 MAT.3 MAT.4 MAT.5 JHN.2 MRK.4 JHN.6 MAT.17 JHN.11 MAT.21 JHN.13 MAT.26 JHN.19 JHN.20 ACT.1"),
            topic("stories.miracles", "Miracles of Jesus", "Water, storms, blindness, and death overturned.", "JHN.2 MRK.2 MRK.4 MRK.5 MAT.14 LUK.7 JHN.9 JHN.11"),
            topic("stories.parables", "Parables of Jesus", "The stories Jesus told.", "MAT.13 MRK.4 LUK.10 LUK.15 LUK.16 LUK.18 MAT.20 MAT.25"),
            topic("stories.peter", "Peter, the Rock", "A fisherman who fell and was restored.", "LUK.5 MAT.14 MAT.16 MRK.14 JHN.21 ACT.2 ACT.10 1PE.1"),
            topic("stories.paul", "Paul's Journeys", "From enemy of the church to apostle.", "ACT.9 ACT.13 ACT.16 ACT.17 ACT.19 ACT.20 ACT.27 ACT.28")
        ]),
        PlanGroup(id: "wisdom", title: "Wisdom for life", subtitle: "Habits, character, and seasons of the year", plans: [
            topic("wisdom.everyday", "Wisdom for Everyday Life", "Proverbs for work, words, and friends.", "PRO.1 PRO.3 PRO.4 PRO.10 PRO.16 PRO.22 PRO.27 PRO.31"),
            topic("wisdom.sermon", "The Sermon on the Mount", "Jesus on the life that truly flourishes.", "MAT.5 MAT.6 MAT.7"),
            topic("wisdom.fruit", "Fruit of the Spirit", "Love, joy, peace, and patience.", "GAL.5 JHN.15 1CO.13 ROM.5 PHP.4 COL.3 JAS.3 2PE.1"),
            topic("wisdom.identity", "Who God Says You Are", "Chosen, loved, and made new.", "PSA.139 EPH.1 EPH.2 ROM.8 2CO.5 GAL.3 COL.3 1PE.2"),
            topic("wisdom.grateful", "A Grateful Heart", "Learning to give thanks.", "PSA.100 PSA.103 PSA.107 PSA.136 PSA.150 LUK.17 PHP.4 1TH.5"),
            topic("wisdom.comfort", "Psalms for Comfort", "Twelve psalms to return to.", "PSA.4 PSA.16 PSA.23 PSA.27 PSA.34 PSA.46 PSA.62 PSA.91 PSA.103 PSA.121 PSA.139 PSA.145"),
            topic("wisdom.lead", "Leading Well", "Serving others as a leader.", "EXO.18 NEH.1 NEH.2 MRK.10 JHN.13 1TI.3 TIT.1 1PE.5"),
            topic("wisdom.work", "Faith at Work", "Doing your job for God.", "GEN.2 PRO.6 PRO.24 NEH.4 ECC.9 EPH.6 COL.3 2TH.3"),
            topic("wisdom.prophets", "Voices of the Prophets", "Ten chapters, ten prophets.", "ISA.6 JER.1 EZK.37 HOS.11 JOL.2 AMO.5 JON.3 MIC.6 HAB.3 MAL.3"),
            topic("wisdom.advent", "Advent, the Promised King", "Get ready for Christmas.", "ISA.7 ISA.9 ISA.11 MIC.5 MAT.1 LUK.1 LUK.2 JHN.1"),
            topic("wisdom.holyweek", "Holy Week", "Walk with Jesus to the cross and the empty tomb.", "MAT.21 MRK.11 MAT.24 JHN.13 MAT.26 JHN.18 JHN.19 MAT.28")
        ])
    ]

    private static func topic(_ id: String, _ name: String, _ blurb: String, _ refs: String) -> ReadingPlan {
        let chapters = refs.split(separator: " ").compactMap { piece -> ChapterRef? in
            let parts = piece.split(separator: ".")
            guard parts.count == 2, let n = Int(parts[1]) else { return nil }
            return ChapterRef(book: String(parts[0]), chapter: n)
        }
        let days = chapters.count == 1 ? "1 day" : "\(chapters.count) days"
        return ReadingPlan(id: "topic.\(id)", name: name, detail: "\(days). \(blurb)", chapters: chapters, bookID: nil)
    }

    static let all: [ReadingPlan] = curated + topicGroups.flatMap(\.plans) + bookPlans

    /// Good first paths for setup.
    static let starters: [String] = ["book.JHN", "book.MRK", "gospels", "book.PSA", "book.PRO", "book.GEN", "nt"]

    /// Older builds used short ids for single book plans.
    static func canonical(_ id: String) -> String {
        let legacy = ["john": "book.JHN", "mark": "book.MRK", "matthew": "book.MAT", "luke": "book.LUK", "acts": "book.ACT",
                      "genesis": "book.GEN", "psalms": "book.PSA", "proverbs": "book.PRO"]
        return legacy[id] ?? id
    }

    static func plan(_ id: String) -> ReadingPlan {
        let key = canonical(id)
        return all.first { $0.id == key } ?? bookPlans.first { $0.id == "book.JHN" }!
    }

    static func bookPlan(_ bookID: String) -> ReadingPlan? {
        bookPlans.first { $0.bookID == bookID }
    }
}

enum PathLogic {
    enum Kind: Equatable {
        /// Read the next chapter in the path.
        case onPath
        /// Read the last chapter of the path.
        case finished
        /// Went back to a chapter before the current place.
        case reread
        /// Jumped past the current place.
        case skippedAhead
    }

    struct After: Equatable {
        let planID: String
        let kind: Kind
        /// Where the path picks up next, applied right away.
        let position: Int
        /// The other sensible place to pick up, offered as a choice.
        let alternative: Int?
    }

    static func after(planID: String, index: Int, position: Int, count: Int) -> After {
        let next = min(index + 1, count)
        if index == position {
            return After(planID: planID, kind: next >= count ? .finished : .onPath, position: next, alternative: nil)
        }
        if index < position {
            let alt = next < count && next != position ? next : nil
            return After(planID: planID, kind: .reread, position: position, alternative: alt)
        }
        return After(planID: planID, kind: .skippedAhead, position: next, alternative: position)
    }
}

enum Streaks {
    /// Days in a row with a reading, counting today if done, otherwise ending yesterday.
    static func current(doneKeys: Set<String>, todayKey: String) -> Int {
        var key = doneKeys.contains(todayKey) ? todayKey : DayKey.adding(-1, to: todayKey)
        var count = 0
        while doneKeys.contains(key) {
            count += 1
            key = DayKey.adding(-1, to: key)
        }
        return count
    }

    static func longest(doneKeys: Set<String>) -> Int {
        var best = 0
        for key in doneKeys where !doneKeys.contains(DayKey.adding(-1, to: key)) {
            var run = 0, k = key
            while doneKeys.contains(k) { run += 1; k = DayKey.adding(1, to: k) }
            best = max(best, run)
        }
        return best
    }
}
