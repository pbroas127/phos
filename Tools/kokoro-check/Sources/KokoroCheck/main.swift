import AVFoundation
import Foundation
import KokoroSwift
import MLX
import MLXUtilsLibrary

// Usage: KokoroCheck <model.safetensors> <voices.npz> <outDir> <cpu|gpu>
let args = CommandLine.arguments
let modelURL = URL(fileURLWithPath: args[1])
let voicesURL = URL(fileURLWithPath: args[2])
let out = URL(fileURLWithPath: args[3], isDirectory: true)
let useCPU = args.count > 4 && args[4] == "cpu"
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

Memory.cacheLimit = 32 * 1024 * 1024
if useCPU { Device.setDefault(device: .cpu) }
print("device", useCPU ? "cpu" : "gpu")

func stats(_ s: [Float]) -> String {
    let finite = s.filter { $0.isFinite }
    let nan = s.count - finite.count
    let rms = sqrt(finite.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, finite.count)))
    let peak = finite.map { abs($0) }.max() ?? 0
    var crossings = 0
    if finite.count > 1 {
        for i in 1..<finite.count where (finite[i - 1] < 0) != (finite[i] < 0) { crossings += 1 }
    }
    return String(format: "samples %d seconds %.2f rms %.4f peak %.4f nan %d zcr %.3f", s.count, Double(s.count) / 24000, rms, peak, nan,
                  Double(crossings) / Double(max(1, finite.count)))
}

func writeWAV(_ samples: [Float], rate: Double, to url: URL) {
    guard !samples.isEmpty, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
    buffer.frameLength = buffer.frameCapacity
    samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                                   AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
    do {
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    } catch {
        print("write failed", error)
    }
}

/// Plays the samples through the node chain the app uses, rendered offline, to hear what the speaker hears.
func render(_ samples: [Float], timePitch: Bool) -> [Float] {
    let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let pitch = AVAudioUnitTimePitch()
    engine.attach(player)
    engine.attach(pitch)
    if timePitch {
        engine.connect(player, to: pitch, format: format)
        engine.connect(pitch, to: engine.mainMixerNode, format: format)
    } else {
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }
    let outFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    do {
        try engine.enableManualRenderingMode(.offline, format: outFormat, maximumFrameCount: 4096)
        try engine.start()
    } catch {
        print("render setup failed", error)
        return []
    }
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = buffer.frameCapacity
    samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
    player.scheduleBuffer(buffer)
    player.play()
    var result: [Float] = []
    let chunk = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: 4096)!
    let total = samples.count * 2
    while result.count < total {
        guard let status = try? engine.renderOffline(4096, to: chunk), status == .success else { break }
        result += Array(UnsafeBufferPointer(start: chunk.floatChannelData![0], count: Int(chunk.frameLength)))
    }
    engine.stop()
    return result
}

let start = Date()
let tts = KokoroTTS(modelPath: modelURL)
let styles = NpyzReader.read(fileFromPath: voicesURL) ?? [:]
print(String(format: "loaded in %.1fs, %d voices, active %d MB", Date().timeIntervalSince(start), styles.count, Memory.activeMemory / 1_048_576))

let texts = [
    "In the beginning was the Word, and the Word was with God, and the Word was God.",
    "Now faith is assurance of things hoped for, proof of things not seen.",
]
for voice in ["af_heart", "am_michael", "bf_emma"] {
    guard let style = styles[voice + ".npy"] else { print("missing", voice); continue }
    for (i, text) in texts.enumerated() {
        let t = Date()
        do {
            let audio = try tts.generateAudio(voice: style, language: voice.hasPrefix("b") ? .enGB : .enUS, text: text).0
            let secs = Date().timeIntervalSince(t)
            print(voice, i, String(format: "gen %.2fs", secs), stats(audio), "peak mem MB", Memory.peakMemory / 1_048_576)
            writeWAV(audio, rate: 24000, to: out.appendingPathComponent("\(voice)_\(i)_raw.wav"))
            if i == 0 {
                writeWAV(render(audio, timePitch: true), rate: 48000, to: out.appendingPathComponent("\(voice)_\(i)_timepitch.wav"))
                writeWAV(render(audio, timePitch: false), rate: 48000, to: out.appendingPathComponent("\(voice)_\(i)_direct.wav"))
            }
        } catch {
            print(voice, i, "error", error)
        }
        Memory.clearCache()
    }
}
print("done, peak memory MB", Memory.peakMemory / 1_048_576)
