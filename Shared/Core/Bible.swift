import Foundation

struct BibleChapter: Decodable {
    let title: String?
    let verses: [String]
}

struct BibleBook: Decodable {
    let id: String
    let name: String
    let chapters: [BibleChapter]
}

private struct BibleFile: Decodable {
    let translation: String
    let books: [BibleBook]
}

/// World English Bible text. Words of Jesus are wrapped in { }.
final class Bible {
    static let shared: Bible = {
        if let url = Bundle.main.url(forResource: "bible", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let bible = try? Bible(data: data) {
            return bible
        }
        return Bible(books: [])
    }()

    let translation: String
    let books: [BibleBook]
    private let byID: [String: BibleBook]

    init(data: Data) throws {
        let file = try JSONDecoder().decode(BibleFile.self, from: data)
        translation = file.translation
        books = file.books
        byID = Dictionary(uniqueKeysWithValues: file.books.map { ($0.id, $0) })
    }

    private init(books: [BibleBook]) {
        translation = "World English Bible"
        self.books = books
        byID = [:]
    }

    func book(_ id: String) -> BibleBook? { byID[id] }

    func chapter(_ ref: ChapterRef) -> BibleChapter? {
        guard let b = byID[ref.book], ref.chapter >= 1, ref.chapter <= b.chapters.count else { return nil }
        return b.chapters[ref.chapter - 1]
    }

    func title(_ ref: ChapterRef) -> String {
        BookNames.title(ref)
    }

    /// Plain verse text without red letter markers.
    func verse(_ ref: ChapterRef, _ number: Int) -> String {
        guard let ch = chapter(ref), number >= 1, number <= ch.verses.count else { return "" }
        return TextChecks.plain(ch.verses[number - 1])
    }

    func plainText(_ ref: ChapterRef) -> String {
        guard let ch = chapter(ref) else { return "" }
        return ch.verses.map(TextChecks.plain).joined(separator: " ")
    }
}

/// Names that work in the widget and shield extensions without loading the whole Bible.
enum BookNames {
    static let names: [String: String] = [
        "GEN": "Genesis", "EXO": "Exodus", "LEV": "Leviticus", "NUM": "Numbers", "DEU": "Deuteronomy",
        "JOS": "Joshua", "JDG": "Judges", "RUT": "Ruth", "1SA": "1 Samuel", "2SA": "2 Samuel",
        "1KI": "1 Kings", "2KI": "2 Kings", "1CH": "1 Chronicles", "2CH": "2 Chronicles", "EZR": "Ezra",
        "NEH": "Nehemiah", "EST": "Esther", "JOB": "Job", "PSA": "Psalms", "PRO": "Proverbs",
        "ECC": "Ecclesiastes", "SNG": "Song of Solomon", "ISA": "Isaiah", "JER": "Jeremiah", "LAM": "Lamentations",
        "EZK": "Ezekiel", "DAN": "Daniel", "HOS": "Hosea", "JOL": "Joel", "AMO": "Amos", "OBA": "Obadiah",
        "JON": "Jonah", "MIC": "Micah", "NAM": "Nahum", "HAB": "Habakkuk", "ZEP": "Zephaniah", "HAG": "Haggai",
        "ZEC": "Zechariah", "MAL": "Malachi", "MAT": "Matthew", "MRK": "Mark", "LUK": "Luke", "JHN": "John",
        "ACT": "Acts", "ROM": "Romans", "1CO": "1 Corinthians", "2CO": "2 Corinthians", "GAL": "Galatians",
        "EPH": "Ephesians", "PHP": "Philippians", "COL": "Colossians", "1TH": "1 Thessalonians",
        "2TH": "2 Thessalonians", "1TI": "1 Timothy", "2TI": "2 Timothy", "TIT": "Titus", "PHM": "Philemon",
        "HEB": "Hebrews", "JAS": "James", "1PE": "1 Peter", "2PE": "2 Peter", "1JN": "1 John", "2JN": "2 John",
        "3JN": "3 John", "JUD": "Jude", "REV": "Revelation"
    ]

    static let order: [String] = [
        "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA", "1KI", "2KI", "1CH", "2CH", "EZR",
        "NEH", "EST", "JOB", "PSA", "PRO", "ECC", "SNG", "ISA", "JER", "LAM", "EZK", "DAN", "HOS", "JOL", "AMO",
        "OBA", "JON", "MIC", "NAM", "HAB", "ZEP", "HAG", "ZEC", "MAL", "MAT", "MRK", "LUK", "JHN", "ACT", "ROM",
        "1CO", "2CO", "GAL", "EPH", "PHP", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE",
        "2PE", "1JN", "2JN", "3JN", "JUD", "REV"
    ]

    static func name(_ id: String) -> String { names[id] ?? id }

    /// Single chapter books read naturally without a number.
    static let singleChapter: Set<String> = ["OBA", "PHM", "2JN", "3JN", "JUD"]

    static func title(_ ref: ChapterRef) -> String {
        if ref.book == "PSA" { return "Psalm \(ref.chapter)" }
        if singleChapter.contains(ref.book) { return name(ref.book) }
        return "\(name(ref.book)) \(ref.chapter)"
    }

    static func verseTitle(_ ref: ChapterRef, _ verse: Int) -> String {
        if ref.book == "PSA" { return "Psalm \(ref.chapter):\(verse)" }
        return "\(name(ref.book)) \(ref.chapter):\(verse)"
    }
}

/// Short verses for the lock screen, rotated by day.
enum DailyVerses {
    static let refs: [(ChapterRef, Int)] = [
        (ChapterRef(book: "PSA", chapter: 119), 105), (ChapterRef(book: "JOS", chapter: 1), 9),
        (ChapterRef(book: "MAT", chapter: 6), 33), (ChapterRef(book: "PSA", chapter: 46), 10),
        (ChapterRef(book: "PRO", chapter: 3), 5), (ChapterRef(book: "ISA", chapter: 40), 31),
        (ChapterRef(book: "JHN", chapter: 8), 12), (ChapterRef(book: "ROM", chapter: 12), 2),
        (ChapterRef(book: "PHP", chapter: 4), 8), (ChapterRef(book: "COL", chapter: 3), 2),
        (ChapterRef(book: "PSA", chapter: 90), 12), (ChapterRef(book: "MAT", chapter: 4), 4),
        (ChapterRef(book: "EPH", chapter: 5), 16), (ChapterRef(book: "JAS", chapter: 1), 22),
        (ChapterRef(book: "PSA", chapter: 1), 2), (ChapterRef(book: "HEB", chapter: 12), 1),
        (ChapterRef(book: "LAM", chapter: 3), 23), (ChapterRef(book: "2TI", chapter: 3), 16),
        (ChapterRef(book: "PSA", chapter: 27), 1), (ChapterRef(book: "JHN", chapter: 15), 5),
        (ChapterRef(book: "1PE", chapter: 5), 7), (ChapterRef(book: "PSA", chapter: 16), 11),
        (ChapterRef(book: "PRO", chapter: 4), 23), (ChapterRef(book: "GAL", chapter: 6), 9),
        (ChapterRef(book: "MIC", chapter: 6), 8), (ChapterRef(book: "PSA", chapter: 139), 23),
        (ChapterRef(book: "ROM", chapter: 8), 28), (ChapterRef(book: "1CO", chapter: 10), 13),
        (ChapterRef(book: "PSA", chapter: 37), 4), (ChapterRef(book: "JHN", chapter: 1), 5),
        (ChapterRef(book: "2CO", chapter: 5), 17)
    ]

    static func pick(for dayKey: String) -> (ChapterRef, Int) {
        let n = dayKey.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 100_003 }
        return refs[n % refs.count]
    }
}
