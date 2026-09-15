import AVFoundation
import Foundation
import KokoroSwift
import MLX
import MLXUtilsLibrary

// Usage: KokoroCheck <model.safetensors> <voices.npz> <bible.json> <outDir>
// SpeechText.swift is copied in from Shared/Core by the workflow, so this runs the exact text handling the app uses.
let args = CommandLine.arguments
let modelURL = URL(fileURLWithPath: args[1])
let voicesURL = URL(fileURLWithPath: args[2])
let bibleURL = URL(fileURLWithPath: args[3])
let out = URL(fileURLWithPath: args[4], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

Memory.cacheLimit = 16 * 1024 * 1024

struct Book: Decodable { let id: String; let chapters: [Chapter] }
struct Chapter: Decodable { let verses: [String] }
struct Bible: Decodable { let books: [Book] }
let bible = try! JSONDecoder().decode(Bible.self, from: Data(contentsOf: bibleURL))
func verse(_ book: String, _ ch: Int, _ v: Int) -> String { bible.books.first { $0.id == book }!.chapters[ch - 1].verses[v - 1] }

func writeWAV(_ samples: [Float], to url: URL) {
    guard !samples.isEmpty, let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
    buffer.frameLength = buffer.frameCapacity
    samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1,
                                   AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
    if let file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false) {
        try? file.write(from: buffer)
    }
}

let tts = KokoroTTS(modelPath: modelURL)
let styles = NpyzReader.read(fileFromPath: voicesURL) ?? [:]
let heart = styles["af_heart.npy"]!

func speak(_ text: String, limit: Int, voice: MLXArray = heart, speed: Float = 1) -> (samples: [Float], seconds: Double, peakMB: Int, pieces: Int, failures: Int) {
    Memory.peakMemory = 0
    let start = Date()
    var all: [Float] = []
    var failures = 0
    let parts = SpeechText.pieces(text, limit: limit)
    for p in parts {
        do {
            let a = try tts.generateAudio(voice: voice, language: .enUS, text: p, speed: speed).0
            if SpeechText.looksLikeSpeech(a) { all += a } else { failures += 1 }
        } catch {
            failures += 1
            print("  error on piece:", p, error)
        }
        Memory.clearCache()
    }
    return (all, Date().timeIntervalSince(start), Memory.peakMemory / 1_048_576, parts.count, failures)
}

// Warm up so timings below are steady.
_ = speak("Hello.", limit: 120)

// 1. Memory by piece size on the longest verse in the Bible.
let longest = verse("EST", 8, 9)
print("Esther 8:9 has \(longest.count) characters")
for limit in [2000, 200, 120, 80] {
    let r = speak(longest, limit: limit)
    print(String(format: "limit %4d: pieces %d, audio %.1fs, made in %.1fs, peak %d MB, failures %d", limit, r.pieces,
                 Double(r.samples.count) / 24000, r.seconds, r.peakMB, r.failures))
    if limit == 120 { writeWAV(r.samples, to: out.appendingPathComponent("esther_8_9_limit120.wav")) }
}

// 1b. The same with the memory limit the app sets.
Memory.memoryLimit = 900 * 1024 * 1024
for limit in [120, 80] {
    let r = speak(longest, limit: limit)
    print(String(format: "with 900 MB limit, limit %d: made in %.1fs, peak %d MB, failures %d", limit, r.seconds, r.peakMB, r.failures))
}

// 2. Punctuation and names that could trip the pronunciation step.
for (b, c, v) in [("JHN", 6, 58), ("JHN", 2, 20), ("GEN", 5, 3), ("PSA", 23, 1), ("JHN", 11, 35), ("REV", 22, 21), ("PSA", 119, 105)] {
    let text = verse(b, c, v)
    let r = speak(text, limit: 120)
    print("\(b) \(c):\(v) pieces \(r.pieces) failures \(r.failures) audio \(String(format: "%.1f", Double(r.samples.count) / 24000))s peak \(r.peakMB) MB :: \(SpeechText.clean(text).prefix(70))")
}

// 3. A whole chapter the way Listen plays it, to catch any verse that throws or sounds wrong.
var total: Double = 0
var audio: Double = 0
var worstPeak = 0
var bad = 0
for (i, v) in bible.books.first(where: { $0.id == "JHN" })!.chapters[0].verses.enumerated() {
    let r = speak(v, limit: 120)
    total += r.seconds
    audio += Double(r.samples.count) / 24000
    worstPeak = max(worstPeak, r.peakMB)
    if r.failures > 0 || r.samples.isEmpty { bad += 1; print("  John 1:\(i + 1) failed pieces \(r.failures)") }
    if i == 0 { writeWAV(r.samples, to: out.appendingPathComponent("john_1_1.wav")) }
}
print(String(format: "John 1: %.0fs of audio made in %.0fs (%.1fx real time), worst peak %d MB, verses with problems %d", audio, total, audio / max(total, 0.1), worstPeak, bad))

// 4. Speed and every voice.
for name in styles.keys.sorted() {
    let r = speak("Your word is a lamp to my feet, and a light for my path.", limit: 120, voice: styles[name]!, speed: 1.25)
    print("\(name) at 1.25x: audio \(String(format: "%.2f", Double(r.samples.count) / 24000))s failures \(r.failures)")
}
print("done")
