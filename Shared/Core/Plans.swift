import Foundation

struct ReadingPlan: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let chapters: [ChapterRef]
    /// Set for single book paths.
    let bookID: String?
}

enum ReadingPlans {
    static let chapterCounts: [String: Int] = [
        "MAT": 28, "MRK": 16, "LUK": 24, "JHN": 21, "ACT": 28, "ROM": 16, "1CO": 16, "2CO": 13, "GAL": 6,
        "EPH": 6, "PHP": 4, "COL": 4, "1TH": 5, "2TH": 3, "1TI": 6, "2TI": 4, "TIT": 3, "PHM": 1, "HEB": 13,
        "JAS": 5, "1PE": 5, "2PE": 3, "1JN": 5, "2JN": 1, "3JN": 1, "JUD": 1, "REV": 22,
        "GEN": 50, "PSA": 150, "PRO": 31
    ]

    static let oldTestament = ["GEN", "PSA", "PRO"]
    static let newTestament = ["MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL", "EPH", "PHP", "COL",
                               "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE", "2PE", "1JN", "2JN",
                               "3JN", "JUD", "REV"]

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
                    chapters: books(["PSA", "PRO"]), bookID: nil)
    ]

    static let all: [ReadingPlan] = curated + bookPlans

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
