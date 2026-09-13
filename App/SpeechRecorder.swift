import AVFoundation
import Foundation
import Speech

/// Records speech, transcribes it on device when possible, and counts only the seconds someone is talking.
final class SpeechRecorder: ObservableObject {
    @Published var transcript = ""
    @Published var speechSeconds: Double = 0
    @Published var isRecording = false
    @Published var level: Double = 0
    @Published var problem: String?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var committed = ""
    private var generation = 0
    private var restartTimer: Timer?
    private var noiseFloor: Float = 0.004
    private var hangover: Double = 0

    static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }

    func start() {
        guard !isRecording else { return }
        problem = nil
        guard recognizer?.isAvailable == true else {
            problem = "Speech recognition is not available right now. You can type instead."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            startRecognition()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
                self?.measure(buffer)
            }
            engine.prepare()
            try engine.start()
            isRecording = true
            restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: true) { [weak self] _ in
                self?.restartRecognition()
            }
        } catch {
            problem = "The microphone could not start. Check microphone access in Settings."
            stop()
        }
    }

    func stop() {
        restartTimer?.invalidate()
        restartTimer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Picks up a saved reflection so more talking adds to it.
    func seed(transcript: String, seconds: Double) {
        self.transcript = transcript
        committed = transcript
        speechSeconds = seconds
    }

    func reset() {
        stop()
        transcript = ""
        committed = ""
        speechSeconds = 0
    }

    private func startRecognition() {
        generation += 1
        let gen = generation
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if recognizer?.supportsOnDeviceRecognition == true { req.requiresOnDeviceRecognition = true }
        request = req
        let base = committed
        task = recognizer?.recognitionTask(with: req) { [weak self] result, _ in
            guard let self, let result else { return }
            let text = result.bestTranscription.formattedString
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                self.transcript = base.isEmpty ? text : base + " " + text
            }
        }
    }

    /// On device recognition works best in chunks, so start a fresh request about once a minute.
    private func restartRecognition() {
        guard isRecording else { return }
        committed = transcript
        request?.endAudio()
        task?.finish()
        startRecognition()
    }

    private func measure(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = (sum / Float(n)).squareRoot()
        let duration = Double(n) / buffer.format.sampleRate
        // Track the room's quiet level slowly so steady noise does not count as talking.
        if rms < noiseFloor * 1.5 { noiseFloor = noiseFloor * 0.97 + rms * 0.03 }
        let talking = rms > max(noiseFloor * 3.2, 0.012)
        if talking { hangover = 0.3 } else { hangover = max(0, hangover - duration) }
        let counts = talking || hangover > 0
        DispatchQueue.main.async {
            self.level = Double(min(1, rms * 12))
            if counts { self.speechSeconds += duration }
        }
    }
}
