import AVFoundation
import Speech
import SwiftUI

/// Listens while someone reads the chapter aloud and moves a highlight through the words.
final class PassageListener: ObservableObject {
    @Published private(set) var along: ReadAlong
    @Published var listening = false
    @Published var level: Double = 0
    @Published var problem: String?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartTimer: Timer?
    private var generation = 0
    private let names: [String]

    init(verses: [String]) {
        along = ReadAlong(verses: verses)
        // Capitalized words that are not sentence starts are mostly names. Hinting them helps recognition a lot.
        var seen = Set<String>()
        var found: [String] = []
        for verse in verses {
            for piece in verse.split(separator: " ").dropFirst() {
                let word = String(piece).trimmingCharacters(in: .punctuationCharacters)
                guard word.count > 3, word.first?.isUppercase == true, !seen.contains(word) else { continue }
                seen.insert(word)
                found.append(word)
            }
        }
        names = Array(found.prefix(100))
    }

    func start() {
        guard !listening else { return }
        problem = nil
        guard recognizer?.isAvailable == true else {
            problem = "Speech recognition is not available right now. Try again in a moment."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            begin()
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
                self?.request?.append(buffer)
                self?.measure(buffer)
            }
            engine.prepare()
            try engine.start()
            listening = true
            // Recognition is most reliable in short stretches, so start a fresh one every 45 seconds.
            restartTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in self?.begin() }
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
        request = nil
        task = nil
        listening = false
        level = 0
        along.beginSegment()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func restore(heard: [Int], cursor: Int) {
        along.restore(heard: heard, cursor: cursor)
    }

    func jump(to index: Int) {
        along.jump(to: index)
        if listening { begin() }
    }

    private func begin() {
        generation += 1
        let gen = generation
        request?.endAudio()
        task?.cancel()
        along.beginSegment()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        req.contextualStrings = names
        if recognizer?.supportsOnDeviceRecognition == true { req.requiresOnDeviceRecognition = true }
        request = req
        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                if let result {
                    self.along.update(transcript: result.bestTranscription.formattedString)
                    if self.along.finished { self.stop(); return }
                    if result.isFinal && self.listening { self.begin() }
                } else if error != nil && self.listening {
                    // A pause or a hiccup ends the task. Keep listening from the same spot after a short beat.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        if gen == self.generation && self.listening { self.begin() }
                    }
                }
            }
        }
    }

    private func measure(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        DispatchQueue.main.async { self.level = Double(min(1, rms * 12)) }
    }
}

struct SpeakRead: View {
    let ref: ChapterRef
    @Binding var savedHeard: [Int]
    @Binding var savedCursor: Int
    var onDone: () -> Void
    @StateObject private var listener: PassageListener
    @State private var permitted: Bool?
    @Environment(\.scenePhase) private var phase

    /// Share of words that must be heard before the reading counts.
    static let needed = 0.8

    init(ref: ChapterRef, heard: Binding<[Int]> = .constant([]), cursor: Binding<Int> = .constant(0), onDone: @escaping () -> Void) {
        self.ref = ref
        self.onDone = onDone
        _savedHeard = heard
        _savedCursor = cursor
        let saved = (heard.wrappedValue, cursor.wrappedValue)
        _listener = StateObject(wrappedValue: {
            let verses = (Bible.shared.chapter(ref)?.verses ?? []).map(TextChecks.plain)
            let l = PassageListener(verses: verses)
            l.restore(heard: saved.0, cursor: saved.1)
            return l
        }())
    }

    var body: some View {
        let along = listener.along
        VStack(spacing: 0) {
            header(along)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(verseRanges(along), id: \.verse) { item in
                            verseText(item, along: along)
                                .id(item.verse)
                                .onTapGesture { listener.jump(to: item.range.lowerBound) }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                }
                .onChange(of: along.currentVerse) { _, v in
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(v, anchor: UnitPoint(x: 0.5, y: 0.3)) }
                }
            }
            footer(along)
        }
        .task {
            let ok = await SpeechRecorder.requestPermissions()
            permitted = ok
            if ok { listener.start() }
        }
        .onChange(of: phase) { _, p in if p != .active { listener.stop() } }
        // Autosave as words are heard, so leaving and coming back keeps everything read so far.
        .onChange(of: along.heardAll.count) { _, _ in savedHeard = Array(listener.along.heardAll).sorted() }
        .onChange(of: along.cursor) { _, c in savedCursor = c }
        .onChange(of: along.finished) { _, done in
            if done { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
        .onDisappear { listener.stop() }
    }

    private func header(_ along: ReadAlong) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Circle().fill(listener.listening ? Theme.green : Theme.line).frame(width: 9, height: 9)
                Text(listener.listening ? "Listening" : "Paused").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                LevelBars(level: listener.level, active: listener.listening)
                Spacer()
                Text("\(along.heardAll.count) of \(along.words.count) words").font(.caption.monospacedDigit()).foregroundStyle(Theme.dim)
            }
            ProgressBar(value: along.words.isEmpty ? 0 : Double(min(along.cursor, along.words.count)) / Double(along.words.count))
            if let problem = listener.problem {
                Text(problem).font(.footnote).foregroundStyle(Theme.red).frame(maxWidth: .infinity, alignment: .leading)
            } else if permitted == false {
                Text("Wick needs the microphone and speech recognition to follow along. Turn them on in Settings.")
                    .font(.footnote).foregroundStyle(Theme.red).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Read at your own pace. Tap any verse to start from there.")
                    .font(.footnote).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func footer(_ along: ReadAlong) -> some View {
        VStack(spacing: 10) {
            if along.finished && along.coverage >= Self.needed {
                Button("Finished reading", action: onDone).buttonStyle(.phos)
            } else if along.finished {
                Text("Some words were missed. Read the faded parts again to finish.")
                    .font(.footnote).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                Button("Go to the first missed word") {
                    if let first = along.firstMissed { listener.jump(to: first) }
                    listener.start()
                }
                .buttonStyle(.phos)
            } else {
                Button(listener.listening ? "Pause" : "Keep reading") {
                    listener.listening ? listener.stop() : listener.start()
                }
                .buttonStyle(.phos)
                .disabled(permitted == false)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Theme.paper)
    }

    private struct VerseRange { let verse: Int; let range: Range<Int> }

    private func verseRanges(_ along: ReadAlong) -> [VerseRange] {
        var out: [VerseRange] = []
        var start = 0
        for i in along.words.indices where i == along.words.count - 1 || along.words[i + 1].verse != along.words[i].verse {
            out.append(VerseRange(verse: along.words[i].verse, range: start..<(i + 1)))
            start = i + 1
        }
        return out
    }

    private func verseText(_ item: VerseRange, along: ReadAlong) -> some View {
        let heard = along.heardAll
        var text = Text("\(item.verse) ").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.dim).baselineOffset(7)
        for i in item.range {
            let word = Text(along.words[i].text + " ")
            let styled: Text
            if i == along.cursor {
                styled = word.foregroundColor(Theme.gold).bold().underline(true, color: Theme.gold)
            } else if heard.contains(i) {
                styled = word.foregroundColor(Theme.ink)
            } else if i < along.cursor {
                styled = word.foregroundColor(Theme.dim.opacity(0.55))
            } else {
                styled = word.foregroundColor(Theme.dim.opacity(0.75))
            }
            text = text + styled
        }
        return text.font(Theme.serif(21, .regular)).lineSpacing(7)
    }
}

private struct LevelBars: View {
    let level: Double
    let active: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(active && level > Double(i) * 0.18 ? Theme.gold : Theme.line)
                    .frame(width: 3, height: CGFloat(6 + i * 3))
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }
}
