import Foundation

struct ReadingPlan: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let chapters: [ChapterRef]
}

enum ReadingPlans {
    static let chapterCounts: [String: Int] = [
        "MAT": 28, "MRK": 16, "LUK": 24, "JHN": 21, "ACT": 28, "ROM": 16, "1CO": 16, "2CO": 13, "GAL": 6,
        "EPH": 6, "PHP": 4, "COL": 4, "1TH": 5, "2TH": 3, "1TI": 6, "2TI": 4, "TIT": 3, "PHM": 1, "HEB": 13,
        "JAS": 5, "1PE": 5, "2PE": 3, "1JN": 5, "2JN": 1, "3JN": 1, "JUD": 1, "REV": 22,
        "GEN": 50, "PSA": 150, "PRO": 31
    ]

    static func book(_ id: String) -> [ChapterRef] {
        (1...(chapterCounts[id] ?? 1)).map { ChapterRef(book: id, chapter: $0) }
    }

    static func books(_ ids: [String]) -> [ChapterRef] { ids.flatMap(book) }

    static let newTestament = ["MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL", "EPH", "PHP", "COL",
                               "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE", "2PE", "1JN", "2JN",
                               "3JN", "JUD", "REV"]

    static let all: [ReadingPlan] = [
        ReadingPlan(id: "john", name: "Gospel of John", detail: "21 days. A great place to start.", chapters: book("JHN")),
        ReadingPlan(id: "mark", name: "Gospel of Mark", detail: "16 days. The shortest Gospel.", chapters: book("MRK")),
        ReadingPlan(id: "matthew", name: "Gospel of Matthew", detail: "28 days.", chapters: book("MAT")),
        ReadingPlan(id: "luke", name: "Gospel of Luke", detail: "24 days.", chapters: book("LUK")),
        ReadingPlan(id: "acts", name: "Acts", detail: "28 days. The early church.", chapters: book("ACT")),
        ReadingPlan(id: "letters", name: "Letters of Paul", detail: "87 days. Romans through Philemon.",
                    chapters: books(["ROM", "1CO", "2CO", "GAL", "EPH", "PHP", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM"])),
        ReadingPlan(id: "nt", name: "New Testament", detail: "260 days. Matthew through Revelation.", chapters: books(newTestament)),
        ReadingPlan(id: "genesis", name: "Genesis", detail: "50 days. Where it all begins.", chapters: book("GEN")),
        ReadingPlan(id: "psalms", name: "Psalms", detail: "150 days. Prayers and songs.", chapters: book("PSA")),
        ReadingPlan(id: "proverbs", name: "Proverbs", detail: "31 days. Wisdom for every day.", chapters: book("PRO"))
    ]

    static func plan(_ id: String) -> ReadingPlan { all.first { $0.id == id } ?? all[0] }
}

enum Streaks {
    /// Days in a row with a plan reading, counting today if done, otherwise ending yesterday.
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
