import Foundation

struct Question: Decodable, Hashable, Identifiable {
    enum Kind: String, Decodable {
        case choice, blank, order, tf
    }

    var t: Kind
    var d: Int
    var v: Int
    var q: String?
    var options: [String]?
    var answerText: String?
    var answerBool: Bool?
    var wrong: [String]?
    var items: [String]?
    var id: String = ""

    enum CodingKeys: String, CodingKey {
        case t, d, v, q, options, answer, wrong, items
    }

    init(t: Kind, d: Int, v: Int, q: String? = nil, options: [String]? = nil, answerText: String? = nil,
         answerBool: Bool? = nil, wrong: [String]? = nil, items: [String]? = nil, id: String = "") {
        self.t = t; self.d = d; self.v = v; self.q = q; self.options = options
        self.answerText = answerText; self.answerBool = answerBool; self.wrong = wrong; self.items = items; self.id = id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(Kind.self, forKey: .t)
        d = (try? c.decode(Int.self, forKey: .d)) ?? 2
        v = (try? c.decode(Int.self, forKey: .v)) ?? 1
        q = try? c.decode(String.self, forKey: .q)
        options = try? c.decode([String].self, forKey: .options)
        answerBool = try? c.decode(Bool.self, forKey: .answer)
        answerText = answerBool == nil ? (try? c.decode(String.self, forKey: .answer)) : nil
        wrong = try? c.decode([String].self, forKey: .wrong)
        items = try? c.decode([String].self, forKey: .items)
    }

    /// The right answer written out, for feedback after a miss.
    var correctText: String {
        switch t {
        case .choice: return options?.first ?? ""
        case .blank: return answerText ?? ""
        case .order: return (items ?? []).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        case .tf: return (answerBool ?? false) ? "True" : "False"
        }
    }

    var isUsable: Bool {
        switch t {
        case .choice: return (options?.count ?? 0) >= 2 && q != nil
        case .blank: return answerText != nil && (wrong?.count ?? 0) >= 1 && q != nil
        case .order: return (items?.count ?? 0) >= 3
        case .tf: return answerBool != nil && q != nil
        }
    }
}

struct ChapterQuestions: Decodable {
    var keyVerse: Int
    var questions: [Question]
}

private struct QuestionFile: Decodable {
    var book: String
    var chapters: [String: ChapterQuestions]
}

final class QuestionBank {
    static let shared: QuestionBank = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let data = urls.filter { !["bible.json", "chapter_titles.json"].contains($0.lastPathComponent) }.compactMap { try? Data(contentsOf: $0) }
        return QuestionBank(files: data)
    }()

    private(set) var chapters: [String: ChapterQuestions] = [:]

    init(files: [Data]) {
        for data in files {
            guard let file = try? JSONDecoder().decode(QuestionFile.self, from: data) else { continue }
            for (number, var chapter) in file.chapters {
                guard let n = Int(number) else { continue }
                let ref = ChapterRef(book: file.book, chapter: n)
                chapter.questions = chapter.questions.enumerated().compactMap { i, q in
                    var q = q
                    q.id = "\(ref.id).\(i)"
                    return q.isUsable ? q : nil
                }
                if !chapter.questions.isEmpty { chapters[ref.id] = chapter }
            }
        }
    }

    func questions(for ref: ChapterRef) -> ChapterQuestions? { chapters[ref.id] }

    func has(_ ref: ChapterRef) -> Bool { chapters[ref.id] != nil }

    var coveredBooks: [String] {
        let books = Set(chapters.keys.compactMap { $0.split(separator: ".").first.map(String.init) })
        return BookNames.order.filter { books.contains($0) }
    }
}

/// One question ready to show, with its choices already shuffled.
struct QuizItem: Identifiable, Hashable {
    let question: Question
    let choices: [String]

    var id: String { question.id }

    func isCorrect(choice: String) -> Bool {
        switch question.t {
        case .choice: return choice == question.options?.first
        case .blank: return choice == question.answerText
        default: return false
        }
    }

    func isCorrect(order: [String]) -> Bool { order == (question.items ?? []) }

    func isCorrect(bool: Bool) -> Bool { bool == question.answerBool }
}

enum QuizEngine {
    /// Picks questions easy to hard, covering every difficulty and mixing types, avoiding ones already asked today.
    static func pick<R: RandomNumberGenerator>(from bank: [Question], count: Int, avoiding: Set<String>, using rng: inout R) -> [QuizItem] {
        let n = min(max(count, 0), bank.count)
        guard n > 0 else { return [] }
        var pool = bank.filter { !avoiding.contains($0.id) }
        if pool.count < n {
            // Recycle, keeping the unasked ones first.
            pool += bank.filter { avoiding.contains($0.id) }.shuffled(using: &rng)
        } else {
            pool.shuffle(using: &rng)
        }
        var chosen: [Question] = []
        if n >= 3 {
            for level in 1...3 {
                if let i = pool.firstIndex(where: { $0.d == level }) { chosen.append(pool.remove(at: i)) }
            }
        }
        while chosen.count < n, !pool.isEmpty {
            let used = Set(chosen.map(\.t))
            let i = pool.firstIndex(where: { !used.contains($0.t) }) ?? 0
            chosen.append(pool.remove(at: i))
        }
        return chosen.sorted { $0.d < $1.d }.map { item(for: $0, using: &rng) }
    }

    static func pick(from bank: [Question], count: Int, avoiding: Set<String>) -> [QuizItem] {
        var g = SystemRandomNumberGenerator()
        return pick(from: bank, count: count, avoiding: avoiding, using: &g)
    }

    static func item<R: RandomNumberGenerator>(for q: Question, using rng: inout R) -> QuizItem {
        switch q.t {
        case .choice:
            return QuizItem(question: q, choices: (q.options ?? []).shuffled(using: &rng))
        case .blank:
            return QuizItem(question: q, choices: ([q.answerText ?? ""] + (q.wrong ?? [])).shuffled(using: &rng))
        case .order:
            let items = q.items ?? []
            var shuffled = items
            for _ in 0..<8 where shuffled == items && items.count > 1 { shuffled.shuffle(using: &rng) }
            if shuffled == items && items.count > 1 { shuffled.swapAt(0, 1) }
            return QuizItem(question: q, choices: shuffled)
        case .tf:
            return QuizItem(question: q, choices: [])
        }
    }

    /// Wait before new questions: none after the first miss, 2 minutes after the second, 5 after that.
    static func waitAfterMiss(missCount: Int) -> TimeInterval {
        switch missCount {
        case ...1: return 0
        case 2: return 120
        default: return 300
        }
    }
}

/// Repeatable randomness for tests and screenshots.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
