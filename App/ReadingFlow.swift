import AVFoundation
import MediaPlayer
import SwiftUI

/// Read, reflect, answer, unlock. Progress is saved at every step, so leaving never loses work.
struct ReadingFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let ref: ChapterRef
    typealias Step = ReadingDraft.Step

    @State private var draft: ReadingDraft
    @State private var items: [QuizItem] = []
    @State private var missed: [Question] = []
    @State private var loaded = false
    private let startStep: Step?

    init(ref: ChapterRef, startStep: Step? = nil) {
        self.ref = ref
        self.startStep = startStep
        _draft = State(initialValue: ReadingDraft(dayKey: "", ref: ref))
    }

    var body: some View {
        VStack(spacing: 0) {
            FlowHeader(title: BookNames.title(ref), subtitle: stepLabel, onBack: backAction) { dismiss() }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Group {
                switch draft.step {
                case .mode:
                    ModeChoice(selected: $draft.readMode, onAlreadyRead: model.settings.allowAlreadyRead ? { draft.skippedRead = true; go(.reflect) } : nil) { draft.skippedRead = false; go(.read) }
                case .read:
                    ReadStep(ref: ref, mode: draft.readMode, aloudHeard: $draft.aloudHeard, aloudCursor: $draft.aloudCursor,
                             listenVerse: $draft.listenVerse, listenPlayed: $draft.listenPlayed) { go(.reflect) }
                case .reflect:
                    ReflectStep(ref: ref, mode: $draft.reflectMode, text: $draft.reflection,
                                prompts: $draft.prompts, speechSeconds: $draft.speechSeconds, audioFile: $draft.audioFile) { startQuiz() }
                case .quiz:
                    QuizRunner(items: items, startIndex: draft.answered, startCorrect: draft.correct, startMissed: missed,
                               onAnswer: { answered, correct, missedQuestions in
                                   draft.answered = answered
                                   draft.correct = correct
                                   draft.missedIDs = missedQuestions.map(\.id)
                                   missed = missedQuestions
                                   save()
                               },
                               onFinish: { correct, missedQuestions in
                                   draft.correct = correct
                                   missed = missedQuestions
                                   finishQuiz()
                               })
                    .id(items.map(\.id).joined())
                case .result:
                    if !draft.failed {
                        UnlockSummary(title: "\(draft.correct) of \(items.count) correct", ref: ref, after: model.lastAfter) {
                            dismiss()
                        }
                    } else {
                        MissedView(ref: ref, score: draft.correct, total: max(items.count, draft.quizIDs.count), missed: missed,
                                   onRetry: { startQuiz() }, onReread: { go(.read) })
                    }
                }
            }
            .transition(.opacity)
        }
        .background(Theme.paper.ignoresSafeArea())
        .onAppear(perform: load)
        .onChange(of: draft.reflection) { _, _ in save() }
        .onChange(of: draft.prompts) { _, _ in save() }
        .onChange(of: draft.reflectMode) { _, _ in save() }
        .onChange(of: draft.readMode) { _, _ in save() }
        .onChange(of: draft.aloudCursor) { _, _ in save() }
        .onChange(of: draft.aloudHeard.count) { _, _ in save() }
        .onChange(of: draft.listenVerse) { _, _ in save() }
        .onChange(of: draft.listenPlayed.count) { _, _ in save() }
        .onChange(of: draft.audioFile) { _, _ in save() }
    }

    /// Reading and reflecting can always step back to change how you read. Read aloud keeps its place.
    /// The questions have no back button, so the chapter stays hidden while answering.
    private var backAction: (() -> Void)? {
        switch draft.step {
        case .read: return { go(.mode) }
        case .reflect: return { go(draft.skippedRead ? .mode : .read) }
        default: return nil
        }
    }

    private var stepLabel: String {
        switch draft.step {
        case .mode: return "Today's reading"
        case .read: return draft.readMode.title
        case .reflect: return "Reflection"
        case .quiz: return "Questions"
        case .result: return draft.failed ? "Try again" : "Result"
        }
    }

    private func bank() -> [Question] {
        QuestionBank.shared.questions(for: ref)?.questions ?? []
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        model.lastAfter = nil
        model.beginReading(ref)
        if let saved = model.draft(for: ref) {
            draft = saved
            let byID = Dictionary(uniqueKeysWithValues: bank().map { ($0.id, $0) })
            missed = saved.missedIDs.compactMap { byID[$0] }
            var questions = saved.quizIDs.compactMap { byID[$0] }
            let resume = saved.resumeStep
            if resume == .quiz, saved.answered < questions.count {
                // The question showing when they left may have been seen, so swap it for a fresh one.
                let used = Set(questions.map(\.id) + model.today.askedQuestionIDs)
                if let fresh = bank().first(where: { !used.contains($0.id) }) {
                    questions[saved.answered] = fresh
                    draft.quizIDs = questions.map(\.id)
                    model.markAsked([QuizEngine.pick(from: [fresh], count: 1, avoiding: []).first].compactMap { $0 })
                }
            }
            items = questions.map { QuizEngine.pick(from: [$0], count: 1, avoiding: []).first! }
            draft.step = startStep ?? resume
            if draft.step == .quiz && items.isEmpty { draft.step = .reflect }
            // A widget's Listen button switches a reading that has not moved past reading yet.
            if let mode = model.startMode, draft.step == .mode || draft.step == .read {
                draft.readMode = mode
                draft.step = .read
            }
            model.startMode = nil
            save()
        } else {
            draft = ReadingDraft(dayKey: model.today.dayKey, ref: ref)
            draft.readMode = model.startMode ?? model.settings.preferredRead
            draft.reflectMode = model.settings.preferredReflect
            if let record = model.record(for: ref) { draft.reflection = record.reflection }
            draft.step = startStep ?? (model.startMode == nil ? .mode : .read)
            model.startMode = nil
            if draft.step == .quiz { startQuiz() }
        }
    }

    private func save() {
        guard loaded, !model.demo else { return }
        model.saveDraft(draft)
    }

    private func go(_ s: Step) {
        withAnimation(.easeInOut(duration: 0.25)) { draft.step = s }
        save()
    }

    private func startQuiz() {
        items = QuizEngine.pick(from: bank(), count: model.readingCheck.questions, avoiding: Set(model.today.askedQuestionIDs))
        model.markAsked(items)
        draft.quizIDs = items.map(\.id)
        draft.answered = 0
        draft.correct = 0
        draft.missedIDs = []
        missed = []
        if items.isEmpty {
            draft.correct = model.readingCheck.pass
            finishQuiz()
        } else {
            go(.quiz)
        }
    }

    private func finishQuiz() {
        let needed = min(model.readingCheck.pass, max(items.count, 1))
        if draft.correct >= needed || items.isEmpty {
            draft.failed = false
            model.completeReading(ref: ref, readMode: draft.readMode, reflectMode: draft.reflectMode, reflection: draft.reflection,
                                  score: draft.correct, total: items.count, audioFile: draft.reflectMode == .spoken ? draft.audioFile : nil)
            withAnimation { draft.step = .result }
        } else {
            model.registerMiss()
            draft.failed = true
            go(.result)
        }
    }
}

struct ModeChoice: View {
    @Binding var selected: ReadMode
    var onAlreadyRead: (() -> Void)? = nil
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How are you reading today?").font(Theme.serif(28)).foregroundStyle(Theme.ink).padding(.bottom, 6)
                    ForEach(ReadMode.allCases) { mode in
                        Button { selected = mode } label: {
                            HStack(spacing: 16) {
                                Image(systemName: mode.symbol).font(.title2).foregroundStyle(Theme.gold)
                                    .frame(width: 52, height: 52).background(Theme.soft, in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(mode.title).font(.headline).foregroundStyle(Theme.ink)
                                    Text(detail(mode)).font(.subheadline).foregroundStyle(Theme.dim).wrapLines()
                                }
                                Spacer()
                                Image(systemName: selected == mode ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(selected == mode ? Theme.gold : Theme.line)
                            }
                            .padding(16)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(selected == mode ? Theme.gold : Theme.line, lineWidth: selected == mode ? 1.5 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("The reading timer keeps counting if your phone locks. Switching to another app starts it over.")
                        .font(.footnote).foregroundStyle(Theme.dim).padding(.top, 4)
                }
                .padding(20)
            }
            VStack(spacing: 6) {
                Button("Continue", action: onNext).buttonStyle(.phos)
                if let onAlreadyRead {
                    Button("I already read it", action: onAlreadyRead)
                        .font(.body.weight(.semibold)).foregroundStyle(Theme.gold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
    }

    private func detail(_ m: ReadMode) -> String {
        switch m {
        case .paper: return "Put the phone down and read your own Bible."
        case .inApp: return "The full chapter, with the words of Jesus in red."
        case .speak: return "Read the chapter out loud. Words light up as you say them, with no timer."
        case .listen: return "Your iPhone reads the chapter aloud."
        }
    }
}

/// Runs the minimum reading timer. It starts over whenever the app leaves the screen.
struct ReadStep: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    let ref: ChapterRef
    let mode: ReadMode
    var aloudHeard: Binding<[Int]> = .constant([])
    var aloudCursor: Binding<Int> = .constant(0)
    var listenVerse: Binding<Int> = .constant(0)
    var listenPlayed: Binding<[Int]> = .constant([])
    var onDone: () -> Void

    @State private var start = Date()
    @State private var restarted = false
    @State private var finished = false
    /// Paper readers may let the phone lock. These tell a screen lock apart from switching to another app.
    @State private var lockedAt: Date?
    @State private var leftAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let minimum = TimeInterval(model.readingCheck.minutes * 60)
            let remaining = (model.demo || finished || mode == .speak) ? 0 : max(0, minimum - context.date.timeIntervalSince(start))
            VStack(spacing: 0) {
                if restarted && remaining > 0 {
                    Label("You left Wick, so the timer started over.", systemImage: "arrow.counterclockwise")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.red)
                        .padding(.vertical, 8)
                }
                switch mode {
                case .paper: PaperRead(ref: ref, remaining: remaining, minimum: minimum, onDone: onDone)
                case .inApp: InAppRead(ref: ref, remaining: remaining, onDone: onDone)
                case .speak: SpeakRead(ref: ref, heard: aloudHeard, cursor: aloudCursor, onDone: onDone)
                case .listen: ListenRead(ref: ref, remaining: remaining, verse: listenVerse, played: listenPlayed, onDone: onDone)
                }
            }
            .onChange(of: remaining == 0) { _, done in if done { finished = true } }
        }
        .onAppear {
            start = Date()
            // A paper reader can set the phone down and let it lock. Reading on screen keeps it awake.
            UIApplication.shared.isIdleTimerDisabled = mode != .paper
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
            lockedAt = Date()
        }
        .onChange(of: phase) { _, p in
            // Listening keeps playing with the phone locked, so leaving never restarts it.
            guard !finished, mode != .listen else { return }
            if mode == .paper {
                // iOS reports a screen lock a few seconds after it happens, so paper mode decides on return:
                // away a while and the phone never locked means another app was used.
                if p == .background {
                    leftAt = Date()
                    lockedAt = nil
                } else if p == .active, let left = leftAt {
                    leftAt = nil
                    if lockedAt == nil && Date().timeIntervalSince(left) > 15 {
                        start = Date()
                        restarted = true
                    }
                }
                return
            }
            guard p == .background else { return }
            start = Date()
            restarted = true
        }
    }
}

struct PaperRead: View {
    let ref: ChapterRef
    let remaining: TimeInterval
    let minimum: TimeInterval
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            VStack(spacing: 6) {
                Eyebrow(text: "Paper Bible")
                Text("Open to \(BookNames.title(ref))").font(Theme.serif(30)).foregroundStyle(Theme.ink)
            }
            RingProgress(value: minimum > 0 ? 1 - remaining / minimum : 1, lineWidth: 12) {
                VStack(spacing: 2) {
                    Text(countdownText(remaining)).font(Theme.serif(52)).monospacedDigit().foregroundStyle(Theme.ink)
                    Text(remaining > 0 ? "minimum left" : "take your time").font(.subheadline).foregroundStyle(Theme.dim)
                }
            }
            .frame(width: 230, height: 230)
            Text("Set the phone down and read the whole chapter. It is fine if the screen locks. Switching to another app starts the timer over.")
                .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
            Button(remaining > 0 ? "Done reading in \(countdownText(remaining))" : "Done reading", action: onDone)
                .buttonStyle(.phos).disabled(remaining > 0)
                .padding(.horizontal, 20).padding(.bottom, 12)
        }
    }
}

struct InAppRead: View {
    let ref: ChapterRef
    let remaining: TimeInterval
    var onDone: () -> Void

    var body: some View {
        let chapter = Bible.shared.chapter(ref)
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(Bible.shared.translation).font(.footnote).foregroundStyle(Theme.dim)
                    if let title = chapter?.title {
                        Text(title).font(Theme.serif(17, .regular)).italic().foregroundStyle(Theme.dim)
                    }
                    ForEach(Array((chapter?.verses ?? []).enumerated()), id: \.offset) { i, verse in
                        if !verse.isEmpty {
                            RedLetterText(verse: verse, number: i + 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
            Button(remaining > 0 ? "Keep reading · \(countdownText(remaining))" : "Finished the chapter", action: onDone)
                .buttonStyle(.phos).disabled(remaining > 0)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Theme.paper)
        }
    }
}

final class ChapterSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var verseIndex = 0
    @Published var playing = false
    @Published var finished = false
    @Published var preparing = false
    /// Verses whose audio played all the way through. Skipping ahead never counts.
    @Published var played: Set<Int> = []
    var voiceID = ""
    var title = ""
    /// Playback speed, 1 is normal. Natural voices change at once; iPhone voices restart the verse.
    var rate: Double = 1.0 {
        didSet { pitch.rate = Float(rate) }
    }

    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let pitch = AVAudioUnitTimePitch()
    private var verses: [String] = []
    private var started = false
    /// Bumped whenever playback jumps, so audio finishing from an old verse is ignored.
    private var generation = 0
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        synth.delegate = self
        engine.attach(player)
        engine.attach(pitch)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                self.pause()
            } else if let opts = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                      AVAudioSession.InterruptionOptions(rawValue: opts).contains(.shouldResume) {
                self.resume()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            self?.pause()
        })
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        commands.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in self?.skip(1); return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in self?.skip(-1); return .success }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        let commands = MPRemoteCommandCenter.shared()
        [commands.playCommand, commands.pauseCommand, commands.togglePlayPauseCommand, commands.nextTrackCommand, commands.previousTrackCommand]
            .forEach { $0.removeTarget(nil) }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func load(_ verses: [String]) {
        self.verses = verses.map(TextChecks.plain)
    }

    private var neuralVoice: String? {
        guard let name = VoiceCatalog.kokoroName(voiceID), VoiceCatalog.naturalSupported, KokoroModel.shared.ready else { return nil }
        return name
    }

    func toggle() {
        playing ? pause() : resume()
    }

    func pause() {
        guard playing else { return }
        playing = false
        synth.pauseSpeaking(at: .word)
        player.pause()
        updateNowPlaying()
    }

    func resume() {
        guard !playing else { return }
        if started {
            playing = true
            if synth.isPaused {
                synth.continueSpeaking()
            } else if engine.isRunning {
                player.play()
            } else {
                speak(from: verseIndex)
            }
            updateNowPlaying()
        } else {
            speak(from: verseIndex)
        }
    }

    /// Moves to another verse. Keeps playing if it was playing, stays paused if it was paused.
    func skip(_ delta: Int) {
        let index = min(max(0, verseIndex + delta), max(0, verses.count - 1))
        if playing {
            speak(from: index)
        } else {
            halt()
            verseIndex = index
            finished = false
            started = false
            warm()
            updateNowPlaying()
        }
    }

    /// After picking a new voice: keep the verse, and only restart it if it was playing. Paused stays paused.
    func restartVerse() {
        guard started else { warm(); return }
        if playing {
            speak(from: verseIndex)
        } else {
            halt()
            started = false
            warm()
        }
    }

    /// Speed changes apply at once to natural voices. An iPhone voice restarts the verse at the new speed.
    func setRate(_ r: Double) {
        rate = r
        if neuralVoice == nil && playing { speak(from: verseIndex) }
        updateNowPlaying()
    }

    /// Gets the current verse ready in the new voice while nothing is playing.
    private func warm() {
        guard let voice = neuralVoice, verseIndex < verses.count else { return }
        KokoroEngine.shared.warm(verses[verseIndex], voice: voice)
    }

    private func halt() {
        generation += 1
        synth.stopSpeaking(at: .immediate)
        player.stop()
        preparing = false
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }

    private func speak(from index: Int) {
        halt()
        guard index < verses.count else {
            finished = true
            playing = false
            updateNowPlaying()
            return
        }
        activateSession()
        started = true
        playing = true
        finished = false
        verseIndex = index
        updateNowPlaying()
        if let voice = neuralVoice { speakNatural(index, voice: voice) } else { speakSystem(index) }
    }

    private func speakSystem(_ index: Int) {
        let u = AVSpeechUtterance(string: verses[index])
        u.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(rate)))
        u.voice = VoiceCatalog.systemVoice(voiceID)
        u.postUtteranceDelay = 0.15
        synth.speak(u)
    }

    private func speakNatural(_ index: Int, voice: String) {
        let gen = generation
        preparing = true
        KokoroEngine.shared.buffer(verses[index], voice: voice) { [weak self] buffer in
            guard let self, gen == self.generation else { return }
            self.preparing = false
            guard let buffer else {
                // Kokoro could not voice this verse, so the iPhone voice reads it and playback carries on.
                self.speakSystem(index)
                return
            }
            if !self.engine.isRunning {
                self.engine.connect(self.player, to: self.pitch, format: buffer.format)
                self.engine.connect(self.pitch, to: self.engine.mainMixerNode, format: buffer.format)
                try? self.engine.start()
            }
            self.player.scheduleBuffer(buffer) {
                DispatchQueue.main.async {
                    guard gen == self.generation else { return }
                    self.advance(after: index)
                }
            }
            if self.playing { self.player.play() }
            if index + 1 < self.verses.count { KokoroEngine.shared.prefetch(self.verses[index + 1], voice: voice) }
        }
    }

    private func advance(after index: Int) {
        played.insert(index)
        if index + 1 < verses.count {
            if playing {
                speak(from: index + 1)
            } else {
                verseIndex = index + 1
                started = false
            }
        } else {
            finished = true
            playing = false
            started = false
            updateNowPlaying()
        }
    }

    func stop() {
        halt()
        playing = false
        started = false
        if engine.isRunning { engine.stop() }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The Lock Screen and headphone controls show the chapter, the verse, and the voice.
    private func updateNowPlaying() {
        guard started || playing else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Verse \(min(verseIndex + 1, max(verses.count, 1))) of \(verses.count) · \(VoiceCatalog.name(voiceID))",
            MPMediaItemPropertyAlbumTitle: "Wick",
            MPNowPlayingInfoPropertyPlaybackRate: playing ? rate : 0
        ]
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let gen = generation
        DispatchQueue.main.async {
            guard gen == self.generation else { return }
            self.advance(after: self.verseIndex)
        }
    }
}

/// Speeds someone can pick for listening.
enum VoiceSpeed {
    static let options: [Double] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5]

    static func label(_ r: Double) -> String {
        r == 1 ? "1x" : String(format: "%g", r) + "x"
    }
}

struct ListenRead: View {
    @Environment(AppModel.self) private var model
    let ref: ChapterRef
    let remaining: TimeInterval
    @Binding var savedVerse: Int
    @Binding var savedPlayed: [Int]
    var onDone: () -> Void
    @StateObject private var speaker = ChapterSpeaker()
    @ObservedObject private var kokoro = KokoroModel.shared
    @State private var pendingVoice: VoiceChoice?
    /// A natural voice picked before its download finished. Applied the moment the download lands.
    @State private var pendingID: String?
    @State private var voiceHelp = false
    @State private var systemVoices: [VoiceChoice] = []
    @State private var voiceName = "Voice"

    /// Share of verses that must actually play before listening counts as finished.
    static let needed = 0.8

    init(ref: ChapterRef, remaining: TimeInterval, verse: Binding<Int> = .constant(0), played: Binding<[Int]> = .constant([]), onDone: @escaping () -> Void) {
        self.ref = ref
        self.remaining = remaining
        _savedVerse = verse
        _savedPlayed = played
        self.onDone = onDone
    }

    var body: some View {
        let verses = Bible.shared.chapter(ref)?.verses ?? []
        let enoughPlayed = Double(speaker.played.count) >= Double(verses.count) * Self.needed
        VStack(spacing: 22) {
            HStack(spacing: 10) {
                Spacer()
                speedMenu
                voiceMenu
            }
            .padding(.horizontal, 20)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.soft)
                .overlay(
                    VStack(spacing: 12) {
                        Text(BookNames.title(ref)).font(Theme.serif(40)).foregroundStyle(Theme.ink)
                        if speaker.verseIndex < verses.count {
                            ScrollView {
                                RedLetterText(verse: verses[speaker.verseIndex], number: speaker.verseIndex + 1, size: 17)
                                    .multilineTextAlignment(.center).padding(.horizontal, 20)
                            }
                            .id(speaker.verseIndex)
                        }
                        if speaker.preparing {
                            ProgressView().tint(Theme.gold)
                        }
                    }
                    .padding(.vertical, 18)
                )
                .frame(maxHeight: 320)
                .padding(.horizontal, 20)
            VStack(spacing: 6) {
                ProgressBar(value: verses.isEmpty ? 0 : Double(speaker.verseIndex + (speaker.finished ? 1 : 0)) / Double(verses.count))
                HStack {
                    Text("Verse \(min(speaker.verseIndex + 1, verses.count))")
                    Spacer()
                    Text("\(speaker.played.count) of \(verses.count) verses heard")
                }
                .font(.caption).foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 24)
            HStack(spacing: 44) {
                Button { speaker.skip(-1) } label: { Image(systemName: "backward.fill").font(.title2) }
                    .accessibilityLabel("Previous verse")
                Button { speaker.toggle() } label: {
                    Image(systemName: speaker.playing ? "pause.fill" : "play.fill").font(.largeTitle)
                        .frame(width: 84, height: 84).background(Theme.gold, in: Circle()).foregroundStyle(.white)
                }
                .accessibilityLabel(speaker.playing ? "Pause" : "Play")
                Button { speaker.skip(1) } label: { Image(systemName: "forward.fill").font(.title2) }
                    .accessibilityLabel("Next verse")
            }
            .foregroundStyle(Theme.ink)
            Spacer()
            let ready = (speaker.finished && enoughPlayed) || remaining <= 0
            if speaker.finished && !enoughPlayed && remaining > 0 {
                Text("Some verses were skipped. Listen to them to finish.")
                    .font(.footnote).foregroundStyle(Theme.dim).multilineTextAlignment(.center).padding(.horizontal, 20)
                Button("Go to the first skipped verse") {
                    if let first = (0..<verses.count).first(where: { !speaker.played.contains($0) }) {
                        speaker.skip(first - speaker.verseIndex)
                        speaker.resume()
                    }
                }
                .buttonStyle(.phos)
                .padding(.horizontal, 20).padding(.bottom, 12)
            } else {
                Button(ready ? "Finished listening" : "Keep listening · \(countdownText(remaining))") {
                    speaker.stop()
                    onDone()
                }
                .buttonStyle(.phos).disabled(!ready)
                .padding(.horizontal, 20).padding(.bottom, 12)
            }
        }
        .padding(.top, 6)
        .onAppear {
            speaker.load(verses)
            speaker.title = BookNames.title(ref)
            speaker.voiceID = model.settings.voiceID
            speaker.rate = model.settings.voiceRate
            speaker.verseIndex = min(max(0, savedVerse), max(0, verses.count - 1))
            speaker.played = Set(savedPlayed.filter { $0 >= 0 && $0 < verses.count })
            voiceName = VoiceCatalog.name(model.settings.voiceID)
            VoiceCatalog.warm {
                systemVoices = VoiceCatalog.system()
                voiceName = VoiceCatalog.name(model.settings.voiceID)
            }
        }
        .onChange(of: speaker.verseIndex) { _, v in savedVerse = v }
        .onChange(of: speaker.played.count) { _, _ in savedPlayed = Array(speaker.played).sorted() }
        .onChange(of: kokoro.ready) { _, ready in
            if ready, let id = pendingID {
                pendingID = nil
                pendingVoice = nil
                choose(id)
            }
        }
        .onDisappear { speaker.stop() }
        .sheet(item: $pendingVoice) { voice in
            NaturalVoiceSheet(voiceName: voice.name) {
                pendingVoice = nil
                if pendingID != nil {
                    pendingID = nil
                    choose(voice.id)
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $voiceHelp) {
            BetterVoicesHelp().presentationDetents([.medium])
        }
    }

    private var currentVoiceID: String {
        if !model.settings.voiceID.isEmpty { return model.settings.voiceID }
        return VoiceCatalog.isWarm ? "system:\(VoiceCatalog.systemVoice("").identifier)" : ""
    }

    private var speedMenu: some View {
        Menu {
            ForEach(VoiceSpeed.options, id: \.self) { r in
                Button {
                    model.settings.voiceRate = r
                    model.savePreferences()
                    speaker.setRate(r)
                } label: {
                    if r == model.settings.voiceRate {
                        Label(VoiceSpeed.label(r), systemImage: "checkmark")
                    } else {
                        Text(VoiceSpeed.label(r))
                    }
                }
            }
        } label: {
            Text(VoiceSpeed.label(model.settings.voiceRate))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.line))
                .foregroundStyle(Theme.ink)
        }
        .accessibilityLabel("Speed")
    }

    private var voiceMenu: some View {
        let current = currentVoiceID
        return Menu {
            if VoiceCatalog.naturalSupported {
                Section("Natural voices") {
                    ForEach(VoiceCatalog.natural) { v in
                        Button { pick(v) } label: { voiceLabel(v, current: current) }
                    }
                }
            }
            Section("iPhone voices") {
                if systemVoices.isEmpty {
                    Text("Loading voices")
                }
                ForEach(systemVoices) { v in
                    Button { pick(v) } label: { voiceLabel(v, current: current) }
                }
                Button("Get more iPhone voices") { voiceHelp = true }
            }
        } label: {
            Label(voiceName, systemImage: "person.wave.2.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.line))
                .foregroundStyle(Theme.ink)
        }
        .accessibilityLabel("Voice")
    }

    @ViewBuilder
    private func voiceLabel(_ v: VoiceChoice, current: String) -> some View {
        if v.id == current {
            Label("\(v.name), \(v.detail)", systemImage: "checkmark")
        } else {
            Text("\(v.name), \(v.detail)")
        }
    }

    private func pick(_ v: VoiceChoice) {
        if VoiceCatalog.kokoroName(v.id) != nil && !kokoro.ready {
            pendingID = v.id
            pendingVoice = v
        } else {
            choose(v.id)
        }
    }

    private func choose(_ id: String) {
        model.settings.voiceID = id
        model.savePreferences()
        voiceName = VoiceCatalog.name(id)
        speaker.voiceID = id
        speaker.restartVerse()
    }
}

/// Explains and runs the one time Kokoro download.
struct NaturalVoiceSheet: View {
    let voiceName: String
    var onReady: () -> Void
    @ObservedObject private var kokoro = KokoroModel.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Natural voices").font(Theme.serif(28)).foregroundStyle(Theme.ink)
            Text("\(voiceName) and 12 more lifelike voices read to you right on your iPhone, even with no connection. They need one download of \(KokoroModel.megabytes) MB, so WiFi is best.")
                .foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            if let progress = kokoro.progress {
                ProgressBar(value: progress)
                Text("\(Int(progress * 100))% downloaded").font(.caption).foregroundStyle(Theme.dim)
            }
            if let problem = kokoro.problem {
                Text(problem).font(.footnote).foregroundStyle(Theme.red)
            }
            Spacer()
            if kokoro.progress == nil {
                Button("Download voices") { kokoro.download() }.buttonStyle(.phos)
            } else {
                Button("Cancel download") { kokoro.cancel() }.buttonStyle(.phos)
            }
            Button("Not now") { dismiss() }.frame(maxWidth: .infinity).foregroundStyle(Theme.dim)
        }
        .padding(24)
        .background(Theme.paper.ignoresSafeArea())
        .onChange(of: kokoro.ready) { _, ready in if ready { onReady() } }
    }
}

struct BetterVoicesHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("More iPhone voices").font(Theme.serif(28)).foregroundStyle(Theme.ink)
            Text("Your iPhone has free Enhanced and Premium voices that sound much more natural. Download any you like, then pick them here.")
                .foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Open the Settings app")
                Text("2. Tap Accessibility, then Read and Speak")
                Text("3. Tap Voices, then English")
                Text("4. Pick a voice and tap download")
            }
            .foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper.ignoresSafeArea())
    }
}
