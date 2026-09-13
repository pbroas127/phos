import Foundation

/// Follows someone reading a passage out loud. Speech recognition is messy, so matching is forgiving:
/// it looks a few words ahead, accepts close spellings and sound alikes, skips words it never hears,
/// and jumps ahead only when the reader clearly moved on. Progress never moves backward by itself.
struct ReadAlong {
    struct Word: Hashable {
        let text: String
        let key: String
        let verse: Int
    }

    let words: [Word]
    /// Words heard so far. Only ever grows: speech recognition revising itself never un-reads a word.
    private(set) var heard: Set<Int> = []
    /// Furthest point reached. Moves backward only when the reader taps a verse.
    private(set) var cursor = 0
    /// Where matching continues inside the current recognition segment.
    private var pos = 0
    /// Spoken words already processed in this segment, to find what is new in each partial result.
    private var segmentWords: [String] = []
    private var recentMisses: [String] = []

    /// verses: plain verse text, 1 based by position.
    init(verses: [String]) {
        var list: [Word] = []
        for (i, verse) in verses.enumerated() {
            for piece in verse.split(whereSeparator: { $0.isWhitespace }) {
                let key = Self.key(String(piece))
                if !key.isEmpty { list.append(Word(text: String(piece), key: key, verse: i + 1)) }
            }
        }
        words = list
    }

    var finished: Bool { cursor >= words.count }
    var heardAll: Set<Int> { heard }
    var coverage: Double { words.isEmpty ? 1 : Double(heard.count) / Double(words.count) }
    var firstMissed: Int? { (0..<min(cursor, words.count)).first { !heard.contains($0) } }
    var currentVerse: Int { words.isEmpty ? 1 : words[min(cursor, words.count - 1)].verse }

    /// Brings back saved progress.
    mutating func restore(heard saved: [Int], cursor savedCursor: Int) {
        heard = Set(saved.filter { $0 >= 0 && $0 < words.count })
        cursor = min(max(0, savedCursor), words.count)
        pos = cursor
        segmentWords = []
        recentMisses = []
    }

    /// Call when a new recognition segment begins (a restart or a final result).
    mutating func beginSegment() {
        segmentWords = []
        recentMisses = []
        pos = cursor
    }

    /// Moves the reader to a word, like tapping a verse to start there. The only way to go backward.
    mutating func jump(to index: Int) {
        cursor = min(max(0, index), words.count)
        beginSegment()
    }

    /// Takes the recognizer's whole transcript for this segment and handles only the words that are new.
    mutating func update(transcript: String) {
        let spoken = transcript.split(whereSeparator: { $0.isWhitespace }).map { Self.key(String($0)) }.filter { !$0.isEmpty }
        var shared = 0
        while shared < min(spoken.count, segmentWords.count) && spoken[shared] == segmentWords[shared] { shared += 1 }
        // On device recognition sometimes starts its transcript over after a pause. Treat that as a fresh segment
        // from where the reader already is, instead of matching it again from the start.
        if shared < segmentWords.count - 3 || spoken.count < segmentWords.count / 2 {
            beginSegment()
            shared = 0
        }
        var i = max(shared, min(segmentWords.count, spoken.count))
        if shared < segmentWords.count { i = shared }
        while i < spoken.count && pos < words.count {
            let next = i + 1 < spoken.count ? spoken[i + 1] : nil
            i += consume(spoken[i], next: next)
        }
        segmentWords = spoken
    }

    /// Matches one spoken word going forward. Returns how many spoken words it used.
    private mutating func consume(_ h: String, next: String?) -> Int {
        // Short common words (the, and, of) only match right where the reader is, so they cannot pull the highlight ahead.
        let reach = h.count <= 3 ? 2 : 7
        let end = min(words.count, pos + reach)
        if let j = (pos..<end).first(where: { words[$0].key == h }) {
            mark(j, through: j)
            return 1
        }
        if let next, let j = (pos..<min(words.count, pos + 3)).first(where: { words[$0].key == h + next }) {
            mark(j, through: j)
            return 2
        }
        if h.count >= 4, let j = (pos..<min(words.count, pos + 3)).first(where: { Self.close(h, words[$0].key) }) {
            mark(j, through: j)
            return 1
        }
        recentMisses.append(h)
        if recentMisses.count > 3 { recentMisses.removeFirst() }
        // Three unmatched words in a row usually means the reader skipped ahead. Only jump when those same three
        // words appear together later in the chapter.
        if recentMisses.count == 3, recentMisses.joined().count >= 9, let j = anchor(recentMisses) {
            mark(j, through: j + 2)
        }
        return 1
    }

    private func anchor(_ three: [String]) -> Int? {
        let upper = min(words.count - 3, pos + 40)
        guard pos <= upper else { return nil }
        return (pos...upper).first { j in
            (0..<3).allSatisfy { k in words[j + k].key == three[k] || (three[k].count >= 4 && Self.close(three[k], words[j + k].key)) }
        }
    }

    private mutating func mark(_ first: Int, through last: Int) {
        for j in first...last { heard.insert(j) }
        pos = last + 1
        cursor = max(cursor, pos)
        recentMisses = []
    }

    // MARK: Matching helpers

    static func key(_ s: String) -> String {
        let lowered = s.lowercased().replacingOccurrences(of: "’", with: "'")
        var out = ""
        for ch in lowered where ch.isLetter || ch.isNumber { out.append(ch) }
        if let n = Int(out), let spelled = spell(n) { return spelled }
        return out
    }

    private static func spell(_ n: Int) -> String? {
        guard n >= 0 && n < 100_000 else { return nil }
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: n)).map { key($0) }
    }

    /// Close enough for a word that was misheard or mispronounced.
    static func close(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shorter = min(a.count, b.count)
        if shorter <= 2 { return false }
        if shorter >= 4 && (a.hasPrefix(b.prefix(4)) || b.hasPrefix(a.prefix(4))) { return true }
        let limit = shorter <= 4 ? 1 : max(2, shorter / 3)
        if distance(a, b, limit: limit) <= limit { return true }
        return soundex(a) == soundex(b) && abs(a.count - b.count) <= 3
    }

    private static func distance(_ a: String, _ b: String, limit: Int) -> Int {
        let x = Array(a), y = Array(b)
        if abs(x.count - y.count) > limit { return limit + 1 }
        var prev = Array(0...y.count)
        for i in 1...max(1, x.count) where !x.isEmpty {
            var row = [i] + [Int](repeating: 0, count: y.count)
            for j in 1...max(1, y.count) where !y.isEmpty {
                row[j] = min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = row
        }
        return prev[y.count]
    }

    private static func soundex(_ s: String) -> String {
        let codes: [Character: Character] = ["b": "1", "f": "1", "p": "1", "v": "1", "c": "2", "g": "2", "j": "2", "k": "2",
                                             "q": "2", "s": "2", "x": "2", "z": "2", "d": "3", "t": "3", "l": "4", "m": "5",
                                             "n": "5", "r": "6"]
        guard let first = s.first else { return "" }
        var out = String(first)
        var last = codes[first]
        for ch in s.dropFirst() {
            let c = codes[ch]
            if let c, c != last { out.append(c) }
            if ch != "h" && ch != "w" { last = c }
            if out.count == 4 { break }
        }
        return out.padding(toLength: 4, withPad: "0", startingAt: 0)
    }
}
