import Foundation
import NaturalLanguage

/// Prepares Bible text for the natural voices and checks what comes back.
/// Shared with Tools/kokoro-check, which runs the same code on a Mac before a build ships.
enum SpeechText {
    /// Scripture punctuation the voice model reads badly: dashes, curly quotes, and footnote braces.
    static func clean(_ text: String) -> String {
        var s = text
        for (from, to) in [("{", ""), ("}", ""), ("\u{2014}", ", "), ("\u{2013}", ", "), ("\u{201C}", ""), ("\u{201D}", ""),
                           ("\u{2018}", ""), ("\u{2019}", "'"), ("\"", ""), ("\u{00A0}", " "), ("-", " ")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        s = s.replacingOccurrences(of: " ,", with: ",").replacingOccurrences(of: ",,", with: ",")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Short pieces keep the model's memory low: sentences first, then clauses, then words.
    static func pieces(_ text: String, limit: Int = 120) -> [String] {
        let cleaned = clean(text)
        guard cleaned.count > limit else { return cleaned.isEmpty ? [] : [cleaned] }
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = cleaned
        tokenizer.enumerateTokens(in: cleaned.startIndex..<cleaned.endIndex) { range, _ in
            let s = cleaned[range].trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { sentences.append(s) }
            return true
        }
        if sentences.isEmpty { sentences = [cleaned] }
        var out: [String] = []
        for sentence in sentences {
            if sentence.count <= limit { out.append(sentence); continue }
            out += pack(split(sentence, at: [",", ";", ":"]), limit: limit)
        }
        return out.flatMap { $0.count <= limit ? [$0] : pack($0.split(separator: " ").map(String.init), limit: limit) }
    }

    private static func split(_ s: String, at marks: [Character]) -> [String] {
        var parts: [String] = []
        var current = ""
        for ch in s {
            current.append(ch)
            if marks.contains(ch) {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { parts.append(rest) }
        return parts
    }

    /// Joins neighbors back together while they fit, so pieces are not needlessly tiny.
    private static func pack(_ parts: [String], limit: Int) -> [String] {
        var out: [String] = []
        var current = ""
        for p in parts {
            if current.isEmpty {
                current = p
            } else if current.count + 1 + p.count <= limit {
                current += " " + p
            } else {
                out.append(current)
                current = p
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// True when samples sound like a voice: not silent, not clipped noise, not a buzz.
    static func looksLikeSpeech(_ samples: [Float]) -> Bool {
        guard samples.count > 2400 else { return false }
        var sum: Double = 0
        var peak: Float = 0
        var crossings = 0
        var previous: Float = 0
        for (i, x) in samples.enumerated() {
            guard x.isFinite else { return false }
            sum += Double(x * x)
            peak = max(peak, abs(x))
            if i > 0 && (previous < 0) != (x < 0) { crossings += 1 }
            previous = x
        }
        let rms = (sum / Double(samples.count)).squareRoot()
        let zcr = Double(crossings) / Double(samples.count)
        return rms > 0.004 && rms < 0.4 && peak <= 1.5 && zcr > 0.02 && zcr < 0.45
    }
}
