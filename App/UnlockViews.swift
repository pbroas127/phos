import CoreMotion
import SwiftUI

/// Pass screen: choose how long apps stay open.
struct PickTimeView: View {
    @Environment(AppModel.self) private var model
    let title: String
    let subtitle: String
    var after: PathLogic.After? = nil
    var onUnlocked: () -> Void
    @State private var minutes: Int?

    var body: some View {
        let choices = model.unlockChoices
        let alreadyOpen = model.lockReason == .none && model.today.unlockedUntil != nil
        VStack(spacing: 22) {
            ScrollView {
            VStack(spacing: 22) {
            Image(systemName: "checkmark")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: after == nil ? 120 : 92, height: after == nil ? 120 : 92)
                .background(Theme.gold, in: Circle())
                .padding(.top, 20)
            VStack(spacing: 6) {
                Text(title).font(Theme.serif(34)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.body).foregroundStyle(Theme.dim)
            }
            FlowLayout(spacing: 10) {
                ForEach(choices, id: \.self) { m in
                    Button { minutes = m } label: {
                        Text(Rules.unlockLabel(m))
                            .font(.headline)
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .foregroundStyle((minutes ?? choices.last) == m ? Color.white : Theme.ink)
                            .background((minutes ?? choices.last) == m ? Theme.gold : Theme.card, in: Capsule())
                            .overlay(Capsule().stroke(Theme.line))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 30)
            if let after {
                NextStepCard(after: after)
            }
            }
            }
            Button(alreadyOpen ? "Add this time" : "Unlock my apps") {
                model.unlock(minutes: minutes ?? choices.last ?? 30)
                onUnlocked()
            }
            .buttonStyle(.phos)
            Button(alreadyOpen ? "Done" : "Keep them locked") { onUnlocked() }.buttonStyle(.phosQuiet)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

/// Miss screen: shows the verses behind the missed questions and when new questions are allowed.
struct MissedView: View {
    @Environment(AppModel.self) private var model
    let ref: ChapterRef
    let score: Int
    let total: Int
    let missed: [Question]
    var onRetry: () -> Void
    var onReread: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wait = max(0, (model.today.nextAttemptAt ?? context.date).timeIntervalSince(context.date))
            VStack(spacing: 16) {
                ScrollView {
                    VStack(spacing: 16) {
                        Image(systemName: "xmark")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(Theme.red)
                            .frame(width: 96, height: 96)
                            .background(Theme.soft, in: Circle())
                            .padding(.top, 20)
                        Text("\(score) of \(total) correct").font(Theme.serif(32)).foregroundStyle(Theme.ink)
                        Text("You need \(min(model.settings.rules.correctToPass, total)) to unlock").foregroundStyle(Theme.dim)
                        ForEach(missed, id: \.id) { q in
                            CardBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Eyebrow(text: "You missed this one", color: Theme.red)
                                    if let chapter = Bible.shared.chapter(ref), q.v <= chapter.verses.count {
                                        RedLetterText(verse: chapter.verses[q.v - 1], number: q.v, size: 17)
                                    }
                                    Text(BookNames.verseTitle(ref, q.v)).font(.caption).foregroundStyle(Theme.dim)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                VStack(spacing: 8) {
                    Button(wait > 0 ? "New questions in \(countdownText(wait))" : "Try new questions", action: onRetry)
                        .buttonStyle(.phos).disabled(wait > 0)
                    Button("Read the chapter again", action: onReread).buttonStyle(.phosSecondary)
                    Text("The wait grows after each miss: none, then 2 minutes, then 5.").font(.caption).foregroundStyle(Theme.dim)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
    }
}

/// One question to reopen apps after the first unlock of the day.
struct RecallFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var item: QuizItem?
    @State private var answered: Bool?
    @State private var passed = false

    var body: some View {
        VStack(spacing: 0) {
            FlowHeader(title: model.lockReason == .midday ? "Midday question" : "One question", subtitle: model.todaysRecord?.title ?? model.todaysTitle) { dismiss() }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
            if !model.today.readingDone {
                Spacer()
                Text("Read today's chapter first.").font(Theme.serif(24)).foregroundStyle(Theme.ink)
                Button("Start reading") { model.route = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { model.route = .reading } }
                    .buttonStyle(.phos).padding(20)
                Spacer()
            } else if passed {
                PickTimeView(title: "Right", subtitle: "Your apps open for") { dismiss() }
            } else if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if useYourWords, let record = model.todaysRecord, !record.reflection.isEmpty {
                            CardBox(fill: Theme.soft) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("“\(TextChecks.quote(record.reflection))”").font(Theme.serif(18, .regular)).italic().foregroundStyle(Theme.ink)
                                    Text("You, this morning at \(record.completedAt.shortTime)").font(.caption).foregroundStyle(Theme.dim)
                                }
                            }
                            Text("You wrote that about \(record.title). Now one question from it.").font(.subheadline).foregroundStyle(Theme.dim)
                        }
                        QuestionView(item: item, locked: answered != nil) { right in
                            answered = right
                            if !right { model.registerMiss() }
                        }
                        .id(item.id)
                        if let answered {
                            Feedback(item: item, right: answered)
                            if answered {
                                Button("Continue") { passed = true }.buttonStyle(.phos)
                            } else {
                                RetryButton { newQuestion() }
                            }
                        }
                        if model.lockReason != .midday {
                            OtherUnlocks()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .onAppear { if item == nil { newQuestion() } }
    }

    private var useYourWords: Bool { model.today.recallCount % 2 == 0 }

    private func newQuestion() {
        let bank = QuestionBank.shared.questions(for: model.todaysRecord?.ref ?? model.todaysChapter)?.questions ?? []
        item = QuizEngine.pick(from: bank, count: 1, avoiding: Set(model.today.askedQuestionIDs)).first
        if let item { model.markAsked([item]) }
        answered = nil
        if item == nil { passed = true }
    }
}

struct RetryButton: View {
    @Environment(AppModel.self) private var model
    var action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wait = max(0, (model.today.nextAttemptAt ?? context.date).timeIntervalSince(context.date))
            Button(wait > 0 ? "Another question in \(countdownText(wait))" : "Try another question", action: action)
                .buttonStyle(.phos).disabled(wait > 0)
        }
    }
}

/// Opens apps after the phone stays face down for a while.
final class FaceDownMonitor: ObservableObject {
    @Published var faceDown = false
    @Published var elapsed: TimeInterval = 0
    @Published var resets = 0
    private let motion = CMMotionManager()
    private var last: Date?

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 0.5
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let down = data.gravity.z > 0.75
            let now = Date()
            if down {
                if let last { self.elapsed += now.timeIntervalSince(last) }
                self.last = now
            } else {
                if self.faceDown && self.elapsed > 2 { self.resets += 1 }
                self.elapsed = 0
                self.last = nil
            }
            self.faceDown = down
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}

struct FocusSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var monitor = FaceDownMonitor()
    @State private var minutes = 30
    @State private var running = false
    @State private var done = false

    var body: some View {
        VStack(spacing: 0) {
            FlowHeader(title: "Focus session", subtitle: "Other ways to open apps") { finish() }
                .padding(.horizontal, 20).padding(.top, 12)
            if done {
                PickTimeView(title: "Focus complete", subtitle: "Your apps open for") { finish() }
            } else {
                VStack(spacing: 24) {
                    Spacer()
                    let total = Double(minutes * 60)
                    let shown = model.demo && !running ? total * 0.2 : monitor.elapsed
                    RingProgress(value: shown / total, lineWidth: 8) {
                        VStack(spacing: 4) {
                            Text(countdownText(max(0, total - shown))).font(Theme.serif(54)).monospacedDigit().foregroundStyle(Theme.ink)
                            Text("of \(minutes):00").foregroundStyle(Theme.dim)
                        }
                    }
                    .frame(width: 250, height: 250)
                    CardBox(padding: 16) {
                        Label(running ? (monitor.faceDown ? "Face down. Keep going." : "Turn your phone face down to start counting.") : "Place your phone face down. Pick it up and the timer starts over.",
                              systemImage: "iphone.gen3")
                            .foregroundStyle(Theme.ink)
                    }
                    if !running {
                        HStack(spacing: 10) {
                            ForEach([15, 30, 45, 60], id: \.self) { m in
                                Button { minutes = m } label: {
                                    Text("\(m) min").font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 14).padding(.vertical, 10)
                                        .foregroundStyle(minutes == m ? Color.white : Theme.ink)
                                        .background(minutes == m ? Theme.gold : Theme.card, in: Capsule())
                                        .overlay(Capsule().stroke(Theme.line))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Spacer()
                    Button(running ? "Stop" : "Start focus session") {
                        if running { monitor.stop(); running = false } else { start() }
                    }
                    .buttonStyle(PrimaryButtonStyle(kind: running ? .secondary : .primary))
                }
                .padding(.horizontal, 20).padding(.bottom, 12)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .onChange(of: monitor.elapsed) { _, e in
            if running && e >= Double(minutes * 60) { monitor.stop(); running = false; done = true }
        }
        .onChange(of: phase) { _, p in
            if p != .active && running { monitor.elapsed = 0 }
        }
        .onDisappear {
            monitor.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func start() {
        running = true
        UIApplication.shared.isIdleTimerDisabled = true
        monitor.start()
    }

    private func finish() {
        monitor.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        dismiss()
    }
}

struct ReciteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = SpeechRecorder()
    @State private var showVerse = true
    @State private var passed = false
    @State private var notice: String?

    var body: some View {
        let ref = model.todaysRecord?.ref ?? model.todaysChapter
        let key = QuestionBank.shared.questions(for: ref)?.keyVerse ?? 1
        let target = Bible.shared.verse(ref, key)
        let spoken = model.demo && recorder.transcript.isEmpty ? String(target.split(separator: " ").prefix(9).joined(separator: " ")) : recorder.transcript
        let match = TextChecks.reciteMatch(spoken: spoken, target: target)
        let ratio = Double(match.matched) / Double(max(1, match.total))
        VStack(spacing: 0) {
            FlowHeader(title: BookNames.verseTitle(ref, key), subtitle: "Recite from memory") { recorder.stop(); dismiss() }
                .padding(.horizontal, 20).padding(.top, 12)
            if passed {
                PickTimeView(title: "Well said", subtitle: "Your apps open for") { dismiss() }
            } else {
                VStack(spacing: 18) {
                    CardBox(padding: 22) {
                        Text(showVerse ? target : maskedVerse(target, spoken: spoken))
                            .font(Theme.serif(22, .regular)).lineSpacing(6).foregroundStyle(Theme.ink)
                    }
                    Toggle("Show the verse while I study", isOn: $showVerse)
                        .disabled(recorder.isRecording)
                    Spacer()
                    Text("\(match.matched) of \(match.total) words").font(Theme.serif(26)).monospacedDigit().foregroundStyle(Theme.ink)
                    ProgressBar(value: ratio)
                    if let notice { Text(notice).font(.footnote).foregroundStyle(Theme.red) }
                    Button {
                        if recorder.isRecording { recorder.stop() } else { record() }
                    } label: {
                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill").font(.system(size: 36))
                            .frame(width: 96, height: 96)
                            .background(recorder.isRecording ? Theme.gold : Theme.soft, in: Circle())
                            .foregroundStyle(recorder.isRecording ? Color.white : Theme.gold)
                    }
                    .accessibilityLabel(recorder.isRecording ? "Stop" : "Start reciting")
                    Text("Hide the verse, then say it out loud. 85% of the words in order opens your apps.")
                        .font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                }
                .padding(20)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .onChange(of: recorder.transcript) { _, _ in
            if !showVerse && ratio >= 0.85 {
                recorder.stop()
                passed = true
            }
        }
        .onDisappear { recorder.stop() }
    }

    private func record() {
        if showVerse {
            notice = "Hide the verse first."
            return
        }
        notice = nil
        recorder.reset()
        Task {
            let ok = await SpeechRecorder.requestPermissions()
            await MainActor.run { if ok { recorder.start() } else { notice = "Allow the microphone and speech recognition in Settings." } }
        }
    }

    private func maskedVerse(_ target: String, spoken: String) -> String {
        let said = Set(TextChecks.words(spoken))
        return target.split(separator: " ").map { word in
            let w = TextChecks.words(String(word)).first ?? ""
            return said.contains(w) ? String(word) : String(repeating: "•", count: max(2, min(8, word.count)))
        }.joined(separator: " ")
    }
}

struct EmergencyPassView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var asSheet = false
    @State private var countdownEnd: Date?

    var body: some View {
        VStack(spacing: 0) {
            if asSheet {
                FlowHeader(title: "Emergency passes", subtitle: model.lockReason == .evening ? "Evening lock is on" : nil) { dismiss() }
                    .padding(.horizontal, 20).padding(.top, 12)
            }
            ScrollView {
                VStack(spacing: 20) {
                    let total = model.settings.rules.emergencyPasses
                    RingProgress(value: total == 0 ? 0 : Double(model.passesLeft) / Double(total), lineWidth: 12) {
                        VStack(spacing: 2) {
                            Text("\(model.passesLeft)").font(Theme.serif(60)).foregroundStyle(Theme.ink)
                            Text("of \(total) left").foregroundStyle(Theme.dim)
                        }
                    }
                    .frame(width: 210, height: 210)
                    .padding(.top, 20)
                    Text("Resets \(nextMonth.formatted(.dateTime.month(.wide).day()))").font(.subheadline).foregroundStyle(Theme.dim)

                    if let end = countdownEnd {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let left = end.timeIntervalSince(context.date)
                            VStack(spacing: 12) {
                                Text(left > 0 ? "Opening in \(countdownText(left))" : "Ready").font(Theme.serif(28)).foregroundStyle(Theme.ink)
                                Text("Take a breath. Is this worth it?").foregroundStyle(Theme.dim)
                                Button(left > 0 ? "Waiting" : "Open apps for \(Rules.unlockLabel(min(model.settings.rules.unlockMinutes, 30)))") {
                                    model.useEmergencyPass()
                                    countdownEnd = nil
                                    if asSheet { dismiss() }
                                }
                                .buttonStyle(.phos).disabled(left > 0)
                                Button("Never mind") { countdownEnd = nil }.buttonStyle(.phosQuiet)
                            }
                        }
                    } else {
                        Button("Use a pass") { countdownEnd = Date().addingTimeInterval(model.demo ? 3 : 60) }
                            .buttonStyle(.phosSecondary)
                            .disabled(model.passesLeft == 0)
                        Text("A pass waits 60 seconds, then opens your apps for up to 30 minutes.").font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    }

                    let uses = model.settings.passUses.sorted { $0.date > $1.date }.prefix(10)
                    if !uses.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Eyebrow(text: "Recent passes").padding(.bottom, 8)
                            ForEach(Array(uses)) { use in
                                HStack {
                                    Text(use.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                    Spacer()
                                    Text(Rules.unlockLabel(use.minutes)).foregroundStyle(Theme.dim)
                                }
                                .padding(.vertical, 10)
                                Divider()
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle(asSheet ? "" : "Emergency passes")
    }

    private var nextMonth: Date {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return cal.date(byAdding: .month, value: 1, to: start) ?? Date()
    }
}
