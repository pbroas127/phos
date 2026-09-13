import AVFoundation
import SwiftUI

/// Read, reflect, answer, unlock.
struct ReadingFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let ref: ChapterRef

    enum Step: Equatable { case mode, read, reflect, quiz, result }

    @State private var step: Step
    @State private var readMode: ReadMode = .paper
    @State private var reflectMode: ReflectMode = .typed
    @State private var reflection = ""
    @State private var items: [QuizItem] = []
    @State private var score = 0
    @State private var missed: [Question] = []
    @State private var confirmLeave = false

    init(ref: ChapterRef, startStep: Step = .mode) {
        self.ref = ref
        _step = State(initialValue: startStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            FlowHeader(title: BookNames.title(ref), subtitle: stepLabel) {
                if step == .quiz { confirmLeave = true } else { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Group {
                switch step {
                case .mode:
                    ModeChoice(selected: $readMode) { go(.read) }
                case .read:
                    ReadStep(ref: ref, mode: readMode) { go(.reflect) }
                case .reflect:
                    ReflectStep(ref: ref, mode: $reflectMode, text: $reflection) { startQuiz() }
                case .quiz:
                    QuizRunner(items: items) { correct, missedQuestions in
                        score = correct
                        missed = missedQuestions
                        finishQuiz()
                    }
                    .id(items.map(\.id).joined())
                case .result:
                    if score >= min(model.readingCheck.pass, max(items.count, 1)) || items.isEmpty {
                        UnlockSummary(title: "\(score) of \(items.count) correct", after: model.lastAfter) {
                            dismiss()
                        }
                    } else {
                        MissedView(ref: ref, score: score, total: items.count, missed: missed,
                                   onRetry: { startQuiz() }, onReread: { go(.read) })
                    }
                }
            }
            .transition(.opacity)
        }
        .background(Theme.paper.ignoresSafeArea())
        .onAppear {
            readMode = model.settings.preferredRead
            reflectMode = model.settings.preferredReflect
            if reflection.isEmpty, let record = model.record(for: ref) { reflection = record.reflection }
            model.lastAfter = nil
            model.beginReading(ref)
            if step == .quiz && items.isEmpty { startQuiz() }
        }
        .confirmationDialog("Leave the questions?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave and count it as a miss", role: .destructive) {
                model.registerMiss()
                dismiss()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Leaving now counts as a missed check, so questions cannot be previewed.")
        }
    }

    private var stepLabel: String {
        switch step {
        case .mode: return "Today's reading"
        case .read: return readMode.title
        case .reflect: return "Reflection"
        case .quiz: return "Questions"
        case .result: return "Result"
        }
    }

    private func go(_ s: Step) {
        withAnimation(.easeInOut(duration: 0.25)) { step = s }
    }

    private func startQuiz() {
        let bank = QuestionBank.shared.questions(for: ref)?.questions ?? []
        items = QuizEngine.pick(from: bank, count: model.readingCheck.questions, avoiding: Set(model.today.askedQuestionIDs))
        model.markAsked(items)
        if items.isEmpty {
            score = model.readingCheck.pass
            finishQuiz()
        } else {
            go(.quiz)
        }
    }

    private func finishQuiz() {
        let needed = min(model.readingCheck.pass, max(items.count, 1))
        if score >= needed || items.isEmpty {
            model.completeReading(ref: ref, readMode: readMode, reflectMode: reflectMode, reflection: reflection,
                                  score: score, total: items.count)
        } else {
            model.registerMiss()
        }
        go(.result)
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

struct ReadStep: View {
    @Environment(AppModel.self) private var model
    let ref: ChapterRef
    let mode: ReadMode
    var onDone: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let minimum = TimeInterval(model.readingCheck.minutes * 60)
            let started = model.today.readingStartedAt ?? context.date
            let elapsed = context.date.timeIntervalSince(started)
            let remaining = model.demo ? 0 : max(0, minimum - elapsed)
            switch mode {
            case .paper: PaperRead(ref: ref, remaining: remaining, minimum: minimum, onDone: onDone)
            case .inApp: InAppRead(ref: ref, remaining: remaining, onDone: onDone)
            case .listen: ListenRead(ref: ref, remaining: remaining, onDone: onDone)
            }
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
