import AVFoundation
import Foundation
import UIKit
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
    /// Longest piece of text voiced at once. Short pieces keep the model's memory well under what iOS allows.
    /// Measured on a Mac with Tools/kokoro-check: 80 characters peaks near 680 MB, a whole long verse passed 2 GB.
    static let pieceLimit = 80
    /// Below this much free memory the natural voice steps aside for the iPhone voice instead of risking a crash.
    static let minimumFreeMemory = 900 * 1024 * 1024

    private let queue = DispatchQueue(label: "phos.kokoro", qos: .userInitiated)
    private let lock = NSLock()
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var cacheOrder: [String] = []
    private var _wanted = ""
    private var _active = true
    private var failuresInARow = 0
    #if !targetEnvironment(simulator)
    private var tts: KokoroTTS?
    private var styles: [String: MLXArray] = [:]
    #endif

    /// Set when the natural voice could not play, shown in Listen and Settings.
    static let problemChanged = Notification.Name("wick.kokoro.problem")
    private(set) var problem: String? {
        didSet { DispatchQueue.main.async { NotificationCenter.default.post(name: Self.problemChanged, object: nil) } }
    }

    private var wanted: String {
        get { lock.lock(); defer { lock.unlock() }; return _wanted }
        set { lock.lock(); _wanted = newValue; lock.unlock() }
    }

    /// iOS does not let apps use the GPU in the background, so voicing only happens while Wick is on screen.
    /// Verses made ahead of time still play with the phone locked; anything else uses the iPhone voice.
    private var active: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _active }
        set { lock.lock(); _active = newValue; lock.unlock() }
    }

    init() {
        #if canImport(UIKit)
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in self?.active = false }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in self?.active = false }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in self?.active = true }
        #endif
    }

    static func key(_ text: String, _ voice: String, _ speed: Double) -> String { "\(voice)|\(speed)|\(text)" }

    /// A verse already voiced and waiting, if there is one.
    func cached(_ text: String, voice: String, speed: Double) -> AVAudioPCMBuffer? {
        lock.lock(); defer { lock.unlock() }
        return cache[Self.key(text, voice, speed)]
    }

    func buffer(_ text: String, voice: String, speed: Double, done: @escaping (AVAudioPCMBuffer?) -> Void) {
        wanted = voice
        if let hit = cached(text, voice: voice, speed: speed) { done(hit); return }
        queue.async {
            let b = self.make(text, voice, speed)
            DispatchQueue.main.async { done(b) }
        }
    }

    /// Voices the next few verses while Wick is open, so playback continues smoothly and keeps going if the phone locks.
    func prefetch(_ texts: [String], voice: String, speed: Double) {
        queue.async {
            for text in texts {
                guard self.wanted == voice, self.active else { return }
                _ = self.make(text, voice, speed)
            }
        }
    }

    /// Loads the model and voices the given text ahead of time, so the first play with a new voice starts quickly.
    func warm(_ text: String, voice: String, speed: Double) {
        wanted = voice
        prefetch([text], voice: voice, speed: speed)
    }

    func unload() {
        queue.async {
            self.lock.lock()
            self.cache.removeAll()
            self.cacheOrder.removeAll()
            self.lock.unlock()
            #if !targetEnvironment(simulator)
            self.tts = nil
            self.styles = [:]
            Memory.clearCache()
            #endif
        }
    }

    func clearProblem() {
        failuresInARow = 0
        problem = nil
    }

    private func store(_ buffer: AVAudioPCMBuffer, key: String) {
        lock.lock(); defer { lock.unlock() }
        cache[key] = buffer
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        // ponytail: about 12 verses of audio is a few MB, plenty for the verses around playback.
        while cacheOrder.count > 12 { cache[cacheOrder.removeFirst()] = nil }
    }

    private func make(_ text: String, _ voice: String, _ speed: Double) -> AVAudioPCMBuffer? {
        let key = Self.key(text, voice, speed)
        if let hit = cached(text, voice: voice, speed: speed) { return hit }
        #if targetEnvironment(simulator)
        return nil
        #else
        guard KokoroModel.shared.ready, active else { return nil }
        guard os_proc_available_memory() > Self.minimumFreeMemory || tts != nil && os_proc_available_memory() > Self.minimumFreeMemory / 2 else {
            problem = "Your iPhone is low on memory, so the iPhone voice is reading for now."
            return nil
        }
        if tts == nil {
            Memory.cacheLimit = 16 * 1024 * 1024
            Memory.memoryLimit = 900 * 1024 * 1024
            tts = KokoroTTS(modelPath: KokoroModel.fileURL)
            if let url = Bundle.main.url(forResource: "kokoro-voices", withExtension: "npz") {
                styles = NpyzReader.read(fileFromPath: url) ?? [:]
            }
        }
        guard let tts, let style = styles[voice + ".npy"] else {
            problem = "The natural voices could not load. Try removing and downloading them again in Settings."
            return nil
        }
        let language: Language = voice.hasPrefix("b") ? .enGB : .enUS
        var samples: [Float] = []
        for piece in SpeechText.pieces(text, limit: Self.pieceLimit) {
            guard active, wanted == voice else { Memory.clearCache(); return nil }
            do {
                let audio = try tts.generateAudio(voice: style, language: language, text: piece, speed: Float(speed)).0
                Memory.clearCache()
                guard SpeechText.looksLikeSpeech(audio) else { return failed("A verse did not sound right, so the iPhone voice read it.") }
                samples += audio
                samples += [Float](repeating: 0, count: Int(Self.sampleRate * 0.12))
            } catch {
                Memory.clearCache()
                return failed("A verse could not be voiced, so the iPhone voice read it.")
            }
        }
        guard !samples.isEmpty else { return nil }
        samples += [Float](repeating: 0, count: Int(Self.sampleRate * 0.2)) // a short breath between verses
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        store(buffer, key: key)
        if failuresInARow > 0 || problem != nil {
            failuresInARow = 0
            problem = nil
        }
        return buffer
        #endif
    }

    private func failed(_ message: String) -> AVAudioPCMBuffer? {
        failuresInARow += 1
        problem = failuresInARow >= 3 ? "Natural voices are not working on this iPhone right now, so the iPhone voice is reading." : message
        return nil
    }

    /// Natural voices step aside after several failures in a row, until the reader tries again.
    var gaveUp: Bool { failuresInARow >= 3 }
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
