import AVFoundation
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
            FlowHeader(title: BookNames.title(ref), subtitle: stepLabel) { dismiss() }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Group {
                switch draft.step {
                case .mode:
                    ModeChoice(selected: $draft.readMode) { go(.read) }
                case .read:
                    ReadStep(ref: ref, mode: draft.readMode) { go(.reflect) }
                case .reflect:
                    ReflectStep(ref: ref, mode: $draft.reflectMode, text: $draft.reflection,
                                prompts: $draft.prompts, speechSeconds: $draft.speechSeconds) { startQuiz() }
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
                        UnlockSummary(title: "\(draft.correct) of \(items.count) correct", after: model.lastAfter) {
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
            save()
        } else {
            draft = ReadingDraft(dayKey: model.today.dayKey, ref: ref)
            draft.readMode = model.settings.preferredRead
            draft.reflectMode = model.settings.preferredReflect
            if let record = model.record(for: ref) { draft.reflection = record.reflection }
            draft.step = startStep ?? .mode
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
                                  score: draft.correct, total: items.count)
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
                    Text("The reading timer only counts while Phos stays open. Leaving the app or locking your phone starts it over, so the screen stays awake while you read.")
                        .font(.footnote).foregroundStyle(Theme.dim).padding(.top, 4)
                }
                .padding(20)
            }
            Button("Continue", action: onNext).buttonStyle(.phos).padding(.horizontal, 20).padding(.bottom, 12)
        }
    }

    private func detail(_ m: ReadMode) -> String {
        switch m {
        case .paper: return "Put the phone down and read your own Bible."
        case .inApp: return "The full chapter, with the words of Jesus in red."
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
    var onDone: () -> Void

    @State private var start = Date()
    @State private var restarted = false
    @State private var finished = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let minimum = TimeInterval(model.readingCheck.minutes * 60)
            let remaining = (model.demo || finished) ? 0 : max(0, minimum - context.date.timeIntervalSince(start))
            VStack(spacing: 0) {
                if restarted && remaining > 0 {
                    Label("You left Phos, so the timer started over.", systemImage: "arrow.counterclockwise")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.red)
                        .padding(.vertical, 8)
                }
                switch mode {
                case .paper: PaperRead(ref: ref, remaining: remaining, minimum: minimum, onDone: onDone)
                case .inApp: InAppRead(ref: ref, remaining: remaining, onDone: onDone)
                case .listen: ListenRead(ref: ref, remaining: remaining, onDone: onDone)
                }
            }
            .onChange(of: remaining == 0) { _, done in if done { finished = true } }
        }
        .onAppear {
            start = Date()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: phase) { _, p in
            guard p == .background, !finished else { return }
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
            Text("Put the phone down and read the whole chapter. The button wakes up when the timer runs out.")
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
    private let synth = AVSpeechSynthesizer()
    private var verses: [String] = []
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    override init() {
        super.init()
        synth.delegate = self
    }

    func load(_ verses: [String]) {
        self.verses = verses.map(TextChecks.plain)
    }

    func toggle() {
        if synth.isSpeaking {
            if synth.isPaused { synth.continueSpeaking(); playing = true } else { synth.pauseSpeaking(at: .word); playing = false }
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            speak(from: verseIndex)
        }
    }

    func skip(_ delta: Int) {
        let next = min(max(0, verseIndex + delta), max(0, verses.count - 1))
        synth.stopSpeaking(at: .immediate)
        speak(from: next)
    }

    private func speak(from index: Int) {
        guard index < verses.count else { finished = true; playing = false; return }
        verseIndex = index
        let u = AVSpeechUtterance(string: verses[index])
        u.rate = rate
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.postUtteranceDelay = 0.15
        synth.speak(u)
        playing = true
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        playing = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            if self.verseIndex + 1 < self.verses.count && self.playing {
                self.speak(from: self.verseIndex + 1)
            } else if self.verseIndex + 1 >= self.verses.count {
                self.finished = true
                self.playing = false
            }
        }
    }
}

struct ListenRead: View {
    let ref: ChapterRef
    let remaining: TimeInterval
    var onDone: () -> Void
    @StateObject private var speaker = ChapterSpeaker()

    var body: some View {
        let verses = Bible.shared.chapter(ref)?.verses ?? []
        VStack(spacing: 22) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.soft)
                .overlay(
                    VStack(spacing: 12) {
                        Text(BookNames.title(ref)).font(Theme.serif(40)).foregroundStyle(Theme.ink)
                        if speaker.verseIndex < verses.count {
                            RedLetterText(verse: verses[speaker.verseIndex], number: speaker.verseIndex + 1, size: 17)
                                .multilineTextAlignment(.center).lineLimit(6).padding(.horizontal, 20)
                        }
                    }
                )
                .frame(maxHeight: 340)
                .padding(.horizontal, 20)
            VStack(spacing: 6) {
                ProgressBar(value: verses.isEmpty ? 0 : Double(speaker.verseIndex + (speaker.finished ? 1 : 0)) / Double(verses.count))
                HStack {
                    Text("Verse \(min(speaker.verseIndex + 1, verses.count))")
                    Spacer()
                    Text("\(verses.count) verses")
                }
                .font(.caption).foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 24)
            HStack(spacing: 44) {
                Button { speaker.skip(-1) } label: { Image(systemName: "backward.fill").font(.title2) }
                Button { speaker.toggle() } label: {
                    Image(systemName: speaker.playing ? "pause.fill" : "play.fill").font(.largeTitle)
                        .frame(width: 84, height: 84).background(Theme.gold, in: Circle()).foregroundStyle(.white)
                }
                .accessibilityLabel(speaker.playing ? "Pause" : "Play")
                Button { speaker.skip(1) } label: { Image(systemName: "forward.fill").font(.title2) }
            }
            .foregroundStyle(Theme.ink)
            Spacer()
            let ready = speaker.finished || remaining <= 0
            Button(ready ? "Finished listening" : "Keep listening · \(countdownText(remaining))") {
                speaker.stop()
                onDone()
            }
            .buttonStyle(.phos).disabled(!ready)
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
        .padding(.top, 10)
        .onAppear { speaker.load(verses) }
        .onDisappear { speaker.stop() }
    }
}
