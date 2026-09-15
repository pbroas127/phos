import AVFoundation
import Foundation
import NaturalLanguage
#if !targetEnvironment(simulator)
import KokoroSwift
import MLX
import MLXUtilsLibrary
#endif

struct VoiceChoice: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
}

/// Every voice Phos can read with: natural Kokoro voices (one download) and the voices already on the iPhone.
enum VoiceCatalog {
    static let natural: [VoiceChoice] = [
        ("af_heart", "Heart", "American, warm"), ("af_bella", "Bella", "American, bright"),
        ("af_nicole", "Nicole", "American, soft"), ("af_sarah", "Sarah", "American, clear"),
        ("af_aoede", "Aoede", "American, gentle"), ("af_kore", "Kore", "American, calm"),
        ("am_michael", "Michael", "American, steady"), ("am_fenrir", "Fenrir", "American, deep"),
        ("am_puck", "Puck", "American, lively"), ("bf_emma", "Emma", "British, warm"),
        ("bf_isabella", "Isabella", "British, clear"), ("bm_george", "George", "British, rich"),
        ("bm_fable", "Fable", "British, storyteller")
    ].map { VoiceChoice(id: "kokoro:\($0.0)", name: $0.1, detail: $0.2) }

    static var naturalSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    /// Listing the iPhone's voices can take seconds the first time, so it happens once, off the main thread.
    private static var systemCache: [VoiceChoice]?
    private static var bestCache: AVSpeechSynthesisVoice?
    private static let lock = NSLock()

    static var isWarm: Bool {
        lock.lock()
        defer { lock.unlock() }
        return systemCache != nil && bestCache != nil
    }

    /// Loads the voice list in the background, then calls back on the main thread.
    static func warm(_ done: @escaping () -> Void = {}) {
        if isWarm { done(); return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = system()
            _ = bestSystemVoice()
            DispatchQueue.main.async(execute: done)
        }
    }

    static func system() -> [VoiceChoice] {
        lock.lock()
        defer { lock.unlock() }
        if let systemCache { return systemCache }
        let list = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { $0.quality.rawValue != $1.quality.rawValue ? $0.quality.rawValue > $1.quality.rawValue : $0.name < $1.name }
            .map { VoiceChoice(id: "system:\($0.identifier)", name: $0.name, detail: "\(accent($0.language)), \(quality($0.quality))") }
        systemCache = list
        return list
    }

    private static func bestSystemVoice() -> AVSpeechSynthesisVoice {
        lock.lock()
        defer { lock.unlock() }
        if let bestCache { return bestCache }
        let best = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "en-US" && !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .max { $0.quality.rawValue < $1.quality.rawValue }
        let voice = best ?? AVSpeechSynthesisVoice(language: "en-US") ?? AVSpeechSynthesisVoice()
        bestCache = voice
        return voice
    }

    static func accent(_ code: String) -> String {
        let names = ["en-US": "American", "en-GB": "British", "en-AU": "Australian", "en-IE": "Irish", "en-IN": "Indian",
                     "en-ZA": "South African", "en-GB-u-sd-gbsct": "Scottish"]
        return names[code] ?? "English"
    }

    static func quality(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Standard"
        }
    }

    /// The system voice for an id, or the best American voice on the phone.
    static func systemVoice(_ id: String) -> AVSpeechSynthesisVoice {
        if id.hasPrefix("system:"), let v = AVSpeechSynthesisVoice(identifier: String(id.dropFirst(7))) { return v }
        return bestSystemVoice()
    }

    static func name(_ id: String) -> String {
        if let n = natural.first(where: { $0.id == id }) { return n.name }
        if id.hasPrefix("system:"), let n = system().first(where: { $0.id == id })?.name { return n }
        guard isWarm else { return "iPhone voice" }
        return systemVoice(id).name
    }

    static func kokoroName(_ id: String) -> String? {
        id.hasPrefix("kokoro:") ? String(id.dropFirst(7)) : nil
    }
}

/// Downloads the Kokoro model once. The voices themselves ship inside the app.
final class KokoroModel: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = KokoroModel()
    static let expectedBytes: Int64 = 327_115_152
    static let megabytes = 312
    private static let source = URL(string: "https://huggingface.co/prince-canuma/Kokoro-82M/resolve/main/kokoro-v1_0.safetensors")!

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kokoro", isDirectory: true)
        return dir.appendingPathComponent("kokoro-v1_0.safetensors")
    }

    @Published private(set) var ready: Bool
    @Published private(set) var progress: Double?
    @Published private(set) var problem: String?

    private var task: URLSessionDownloadTask?
    /// A background session, so the download keeps going with the phone locked or Wick closed.
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "wick.kokoro")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    /// Handed over by the app delegate when iOS relaunches Wick for a finished background download.
    static var backgroundCompletion: (() -> Void)?

    override init() {
        let size = (try? FileManager.default.attributesOfItem(atPath: Self.fileURL.path)[.size] as? Int64) ?? nil
        ready = size == Self.expectedBytes
        super.init()
        reattach()
    }

    /// Picks up a download that was still running the last time Wick closed.
    private func reattach() {
        guard !ready else { return }
        session.getTasksWithCompletionHandler { [weak self] _, _, downloads in
            guard let self, let running = downloads.first(where: { $0.state == .running || $0.state == .suspended }) else { return }
            DispatchQueue.main.async {
                self.task = running
                let expected = running.countOfBytesExpectedToReceive
                self.progress = expected > 0 ? Double(running.countOfBytesReceived) / Double(expected) : 0
            }
        }
    }

    func download() {
        guard !ready, task == nil else { return }
        problem = nil
        progress = 0
        task = session.downloadTask(with: Self.source)
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        progress = nil
    }

    func remove() {
        KokoroEngine.shared.unload()
        try? FileManager.default.removeItem(at: Self.fileURL)
        ready = false
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Self.expectedBytes
        let value = Double(totalBytesWritten) / Double(total)
        DispatchQueue.main.async { self.progress = value }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file disappears when this returns, so move it now.
        let fm = FileManager.default
        var dest = Self.fileURL
        let size = (try? fm.attributesOfItem(atPath: location.path)[.size] as? Int64) ?? nil
        guard size == Self.expectedBytes else {
            DispatchQueue.main.async { self.problem = "The download was incomplete. Try again on WiFi." }
            return
        }
        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: location, to: dest)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dest.setResourceValues(values)
            DispatchQueue.main.async { self.ready = true }
        } catch {
            DispatchQueue.main.async { self.problem = "Wick could not save the voices. Check that your iPhone has free space." }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            Self.backgroundCompletion?()
            Self.backgroundCompletion = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            self.task = nil
            self.progress = nil
            if let error = error as? URLError, error.code != .cancelled {
                self.problem = "The download stopped. Check your connection and try again."
            }
        }
    }
}

/// Turns verses into audio with Kokoro on a background queue. Keeps the next verse ready so playback has no gaps.
final class KokoroEngine: @unchecked Sendable {
    static let shared = KokoroEngine()
    static let sampleRate = 24_000.0
    private let queue = DispatchQueue(label: "phos.kokoro", qos: .userInitiated)
    private var cache: [String: AVAudioPCMBuffer] = [:]
    /// The voice playback wants right now. Queued work for any other voice is skipped, so switching voices never waits behind it.
    private var wanted = ""
    #if !targetEnvironment(simulator)
    private var tts: KokoroTTS?
    private var styles: [String: MLXArray] = [:]
    #endif

    func buffer(_ text: String, voice: String, done: @escaping (AVAudioPCMBuffer?) -> Void) {
        wanted = voice
        queue.async {
            let b = self.make(text, voice)
            DispatchQueue.main.async { done(b) }
        }
    }

    func prefetch(_ text: String, voice: String) {
        queue.async {
            guard self.wanted == voice else { return }
            _ = self.make(text, voice)
        }
    }

    /// Loads the model and voices the given text ahead of time, so the first play with a new voice starts at once.
    func warm(_ text: String, voice: String) {
        wanted = voice
        queue.async {
            guard self.wanted == voice else { return }
            _ = self.make(text, voice)
        }
    }

    func unload() {
        queue.async {
            self.cache.removeAll()
            #if !targetEnvironment(simulator)
            self.tts = nil
            self.styles = [:]
            #endif
        }
    }

    private func make(_ text: String, _ voice: String) -> AVAudioPCMBuffer? {
        let key = voice + "|" + text
        if let hit = cache[key] { return hit }
        #if targetEnvironment(simulator)
        return nil
        #else
        guard KokoroModel.shared.ready else { return nil }
        if tts == nil {
            tts = KokoroTTS(modelPath: KokoroModel.fileURL)
            if let url = Bundle.main.url(forResource: "kokoro-voices", withExtension: "npz") {
                styles = NpyzReader.read(fileFromPath: url) ?? [:]
            }
        }
        guard let tts, let style = styles[voice + ".npy"] else { return nil }
        let language: Language = voice.hasPrefix("b") ? .enGB : .enUS
        var samples: [Float] = []
        for part in Self.chunks(text) {
            if let audio = try? tts.generateAudio(voice: style, language: language, text: part).0 {
                samples += audio
            }
        }
        guard !samples.isEmpty else { return nil }
        samples += [Float](repeating: 0, count: Int(Self.sampleRate * 0.3)) // a short breath between verses
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        if cache.count >= 6 { cache.removeAll() } // ponytail: tiny cache, only the verses around playback matter
        cache[key] = buffer
        return buffer
        #endif
    }

    /// Kokoro handles about 500 phonemes at once, so long verses go in sentence sized pieces.
    static func chunks(_ text: String) -> [String] {
        guard text.count > 220 else { return [text] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var parts: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = text[range].trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { parts.append(s) }
            return true
        }
        return parts.isEmpty ? [text] : parts
    }
}

/// Reads a quiz question and its choices out loud with the iPhone voice, for people who listen rather than read.
final class QuestionSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = QuestionSpeaker()
    @Published private(set) var speaking = false
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String, voiceID: String, rate: Double) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(rate)))
        u.voice = VoiceCatalog.systemVoice(voiceID)
        speaking = true
        synth.speak(u)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        speaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.speaking = false }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.speaking = false }
    }
}
