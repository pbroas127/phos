import Foundation

/// Follows someone reading a passage out loud. Speech recognition is messy, so matching is forgiving:
/// it looks a few words ahead, accepts close spellings and sound alikes, skips words it never hears,
/// and jumps ahead when the reader clearly moved on.
struct ReadAlong {
    struct Word: Hashable {
        let text: String
        let key: String
        let verse: Int
    }

    let words: [Word]
    private(set) var cursor = 0
    private(set) var heard: Set<Int> = []
    /// Where the current recognition segment started. Partial results get revised, so each update re-aligns from here.
    private var segmentStart = 0
    private var segmentHeard: Set<Int> = []

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
    /// Every word heard so far, including the segment still being recognized.
    var heardAll: Set<Int> { heard.union(segmentHeard) }
    var coverage: Double { words.isEmpty ? 1 : Double(heardAll.count) / Double(words.count) }
    var firstMissed: Int? {
        let all = heardAll
        return (0..<min(cursor, words.count)).first { !all.contains($0) }
    }
    var currentVerse: Int { words.isEmpty ? 1 : words[min(cursor, words.count - 1)].verse }

    /// Call when a new recognition segment begins (a restart or a final result).
    mutating func beginSegment() {
        heard.formUnion(segmentHeard)
        segmentHeard = []
        segmentStart = cursor
    }

    /// Moves the reader to a word, like tapping a verse to start there.
    mutating func jump(to index: Int) {
        heard.formUnion(segmentHeard)
        segmentHeard = []
        cursor = min(max(0, index), words.count)
        segmentStart = cursor
    }

    /// Re-aligns the whole transcript of the current segment.
    mutating func update(transcript: String) {
        let spoken = transcript.split(whereSeparator: { $0.isWhitespace }).map { Self.key(String($0)) }.filter { !$0.isEmpty }
        var pos = segmentStart
        var matched: Set<Int> = []
        var misses = 0
        var i = 0
        while i < spoken.count && pos < words.count {
            let h = spoken[i]
            let joined = i + 1 < spoken.count ? h + spoken[i + 1] : nil
            if let j = find(h, joined: joined, from: pos, within: 6) {
                matched.insert(j.index)
                pos = j.index + 1
                i += j.used
                misses = 0
                continue
            }
            misses += 1
            // Several unmatched words in a row usually means the reader skipped ahead or went back to a spot we lost.
            if misses >= 3, i + 1 < spoken.count, let jump = anchor(spoken[i], spoken[i + 1], from: pos, within: 60) {
                matched.insert(jump)
                matched.insert(jump + 1)
                pos = jump + 2
                i += 2
                misses = 0
                continue
            }
            i += 1
        }
        segmentHeard = matched
        cursor = pos
    }

    private func find(_ h: String, joined: String?, from pos: Int, within window: Int) -> (index: Int, used: Int)? {
        let end = min(words.count, pos + window)
        guard pos < end else { return nil }
        // Exact matches win anywhere in the window, so a common word does not match early by accident.
        for j in pos..<end where words[j].key == h { return (j, 1) }
        if let joined {
            for j in pos..<end where words[j].key == joined { return (j, 2) }
        }
        for j in pos..<min(end, pos + 3) where Self.close(h, words[j].key) { return (j, 1) }
        return nil
    }

    private func anchor(_ a: String, _ b: String, from pos: Int, within window: Int) -> Int? {
        let lower = max(0, pos - 20)
        let upper = min(words.count - 1, pos + window)
        guard lower < upper else { return nil }
        for j in lower..<upper where words[j].key == a && Self.close(b, words[j + 1].key) && a.count + b.count >= 6 {
            return j
        }
        return nil
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
