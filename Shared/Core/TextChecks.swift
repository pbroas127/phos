import Foundation

enum TextChecks {
    /// Lowercased word tokens. Apostrophes stay inside words.
    static func words(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber || ((ch == "'" || ch == "’") && !cur.isEmpty) {
                cur.append(ch == "’" ? "'" : ch)
            } else if !cur.isEmpty {
                out.append(cur); cur = ""
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out.map { $0.hasSuffix("'") ? String($0.dropLast()) : $0 }.filter { $0.contains(where: \.isLetter) }
    }

    static func wordCount(_ s: String) -> Int { words(s).count }

    static func distinctCount(_ s: String) -> Int { Set(words(s)).count }

    static func requiredDistinct(typedWords: Int) -> Int { Int((Double(typedWords) * 0.6).rounded(.up)) }

    static func requiredDistinct(spokenSeconds: Int) -> Int { max(8, Int((Double(spokenSeconds) * 0.9).rounded())) }

    static func stem(_ w: String) -> String {
        var s = w
        if s.hasSuffix("'s") { s = String(s.dropLast(2)) }
        for suffix in ["ing", "ed", "es", "s"] where s.hasSuffix(suffix) && s.count - suffix.count >= 3 {
            s = String(s.dropLast(suffix.count))
            break
        }
        if s.hasSuffix("e") && s.count > 3 { s = String(s.dropLast()) }
        return s
    }

    static let stopwords: Set<String> = Set("""
    a about above after again against all also am an and any are aren't as at be because been before being below \
    between both but by can can't cannot could couldn't did didn't do does doesn't doing don't down during each few \
    for from further had hadn't has hasn't have haven't having he he'd he'll he's her here here's hers herself him \
    himself his how how's i i'd i'll i'm i've if in into is isn't it it's its itself let's me more most mustn't my \
    myself no nor not of off on once only or other ought our ours ourselves out over own same shan't she she'd \
    she'll she's should shouldn't so some such than that that's the their theirs them themselves then there there's \
    these they they'd they'll they're they've this those through to too under until up very was wasn't we we'd \
    we'll we're we've were weren't what what's when when's where where's which while who who's whom why why's with \
    won't would wouldn't you you'd you'll you're you've your yours yourself yourselves just like really think thing \
    things something want wanted feel felt know knew make made get got go going went come came say said see saw \
    look looked good great day today time also even much many one two three first last new way lot kind still \
    thought started start check checked people person man men woman women need needs use used take took give gave \
    tell told part keep kept work right well back put find found long little big better best around every really \
    stood out chapter verse read reading reflect reflection stand stands shows show shown means mean meant way \
    lord god us him them unto shall will may might must upon yet
    """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))

    static func contentStems(_ s: String) -> Set<String> {
        Set(words(s).filter { $0.count >= 3 && !stopwords.contains($0) }.map(stem))
    }

    /// Distinct meaningful words the reflection shares with the chapter.
    static func overlap(reflection: String, chapterText: String) -> Int {
        contentStems(reflection).intersection(contentStems(chapterText)).count
    }

    static func isRelevant(reflection: String, chapterText: String) -> Bool {
        let needed = wordCount(reflection) >= 40 ? 3 : 2
        return overlap(reflection: reflection, chapterText: chapterText) >= needed
    }

    /// Splits a verse into plain and red letter runs.
    static func segments(_ verse: String) -> [(text: String, red: Bool)] {
        var out: [(String, Bool)] = []
        var cur = ""
        var red = false
        for ch in verse {
            if ch == "{" || ch == "}" {
                if !cur.isEmpty { out.append((cur, red)); cur = "" }
                red = ch == "{"
            } else {
                cur.append(ch)
            }
        }
        if !cur.isEmpty { out.append((cur, red)) }
        return out
    }

    static func plain(_ verse: String) -> String {
        verse.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
    }


    /// First sentence of a reflection, trimmed for quoting back.
    static func quote(_ reflection: String, limit: Int = 140) -> String {
        let trimmed = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        var sentence = trimmed
        if let r = trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?")) {
            sentence = String(trimmed[..<r.upperBound])
        }
        if sentence.count > limit {
            let cut = sentence.prefix(limit)
            sentence = (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
        }
        return sentence
    }
}
