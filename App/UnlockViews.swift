import CoreMotion
import SwiftUI

/// Result screen after a reading or another way of earning time: which locks opened and for how long.
struct UnlockSummary: View {
    @Environment(AppModel.self) private var model
    let title: String
    var after: PathLogic.After? = nil
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 96)
                        .background(Theme.gold, in: Circle())
                        .padding(.top, 20)
                    Text(title).font(Theme.serif(32)).foregroundStyle(Theme.ink)
                    if model.lastUnlocked.isEmpty {
                        Text("Nothing was waiting to unlock.").foregroundStyle(Theme.dim)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(model.lastUnlocked) { lock in
                                HStack {
                                    Image(systemName: "lock.open.fill").foregroundStyle(Theme.gold)
                                    Text(lock.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                                    Spacer()
                                    Text(openText(lock)).font(.subheadline).foregroundStyle(Theme.dim)
                                }
                                .padding(.vertical, 12)
                                if lock.id != model.lastUnlocked.last?.id { Divider() }
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
                    }
                    if let after { NextStepCard(after: after) }
                }
                .padding(.horizontal, 20)
            }
            Button("Done", action: onDone).buttonStyle(.phos).padding(.horizontal, 20).padding(.bottom, 12)
        }
    }

    private func openText(_ lock: LockSet) -> String {
        guard let until = model.today.day(lock.id).until else { return "Open" }
        return lock.rewardSeconds == LockSet.untilEnd ? "Open until \(until.shortTime)" : "Open \(LockSet.rewardLabel(lock.rewardSeconds)), until \(until.shortTime)"
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
                        Text("You need \(min(model.readingCheck.pass, total)) to unlock").foregroundStyle(Theme.dim)
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

/// Every lock with what it takes to open it right now.
struct UnlockCenter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var questionLock: LockSet?
    @State private var passLock: LockSet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.locks.isEmpty {
                        CardBox { Text("You have no locks yet. Add one in Settings.").foregroundStyle(Theme.dim) }
                    }
                    ForEach(model.locks) { lock in
                        LockStatusCard(lock: lock,
                                       onRead: { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { model.route = .reading } },
                                       onQuestion: { questionLock = lock },
                                       onPass: { passLock = lock })
                    }
                    if model.locks.contains(where: { $0.otherWays && [.needsQuestion, .needsTap].contains(model.state($0)) }) {
                        OtherUnlocks().padding(.top, 8)
                    }
                }
                .padding(20)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Unlock")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(item: $questionLock) { lock in
                QuestionUnlockView(lock: lock)
            }
            .sheet(item: $passLock) { lock in
                EmergencyPassSheet(lock: lock).environment(model).presentationDetents([.medium])
            }
        }
        .preferredColorScheme(.light)
    }
}

struct LockStatusCard: View {
    @Environment(AppModel.self) private var model
    let lock: LockSet
    var onRead: () -> Void
    var onQuestion: () -> Void
    var onPass: () -> Void

    var body: some View {
        let state = model.state(lock)
        let day = model.today.day(lock.id)
        CardBox(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: state.isLocked ? "lock.fill" : "lock.open.fill")
                        .foregroundStyle(state.isLocked ? Theme.gold : Theme.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lock.name).font(.headline).foregroundStyle(Theme.ink)
                        Text(status(state, day)).font(.subheadline).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                }
                switch state {
                case .needsReading:
                    Button("Read today's chapter", action: onRead).buttonStyle(.phos)
                case .needsQuestion:
                    Button("Answer a question for \(LockSet.rewardLabel(lock.rewardSeconds).lowercased())", action: onQuestion).buttonStyle(.phos)
                case .needsTap:
                    Button("Unlock for \(LockSet.rewardLabel(lock.rewardSeconds).lowercased())") {
                        model.unlock(lock, method: .tap)
                    }
                    .buttonStyle(.phos)
                case .usedUp, .strict:
                    Button("Use an emergency pass (\(model.passesLeft(lock)) left)", action: onPass)
                        .buttonStyle(.phosSecondary)
                        .disabled(model.passesLeft(lock) == 0)
                case .open:
                    Button("Lock now") { model.lockNow(lock) }.buttonStyle(.phosSecondary)
                case .inactive:
                    EmptyView()
                }
            }
        }
    }

    private func status(_ state: LockLogic.State, _ day: LockDay) -> String {
        switch state {
        case .inactive: return lock.enabled ? "Not active right now · \(lock.hoursLabel)" : "Turned off"
        case .open:
            let until = [day.until, day.passUntil].compactMap { $0 }.max()
            return until.map { "Open until \($0.shortTime)" } ?? "Open"
        case .needsReading: return "Locked until today's reading"
        case .needsQuestion: return "One question opens it"
        case .needsTap:
            if lock.policy == .limited { return "\(max(0, lock.limit - day.count)) of \(lock.limit) unlocks left today" }
            return "You read today. Unlock any time."
        case .usedUp: return "No unlocks left today"
        case .strict: return "Strict until \(LockLogic.activeEnd(lock, now: Date()).shortTime)"
        }
    }
}

/// One question about today's reading that unlocks one lock.
struct QuestionUnlockView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let lock: LockSet
    @State private var item: QuizItem?
    @State private var answered: Bool?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.today.recallCount % 2 == 0, let record = model.todaysRecord, !record.reflection.isEmpty {
                    CardBox(fill: Theme.soft) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("“\(TextChecks.quote(record.reflection))”").font(Theme.serif(18, .regular)).italic().foregroundStyle(Theme.ink)
                            Text("You, earlier today at \(record.completedAt.shortTime)").font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                    Text("You wrote that about \(record.title). Now one question from it.").font(.subheadline).foregroundStyle(Theme.dim)
                }
                if let item {
                    QuestionView(item: item, locked: answered != nil) { right in
                        answered = right
                        if right { model.unlock(lock, method: .question) } else { model.registerMiss() }
                    }
                    .id(item.id)
                    if let answered {
                        Feedback(item: item, right: answered)
                        if answered {
                            Label("\(lock.name) is open for \(LockSet.rewardLabel(lock.rewardSeconds).lowercased())", systemImage: "lock.open.fill")
                                .font(.headline).foregroundStyle(Theme.green)
                            Button("Done") { dismiss() }.buttonStyle(.phos)
                        } else {
                            RetryButton { newQuestion() }
                        }
                    }
                } else {
                    Text("No questions are available for today's chapter.").foregroundStyle(Theme.dim)
                }
            }
            .padding(20)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("One question")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if item == nil { newQuestion() } }
    }

    private func newQuestion() {
        let ref = model.todaysRecord?.ref ?? model.todaysChapter
        let bank = QuestionBank.shared.questions(for: ref)?.questions ?? []
        item = QuizEngine.pick(from: bank, count: 1, avoiding: Set(model.today.askedQuestionIDs)).first
        if let item { model.markAsked([item]) }
        answered = nil
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

struct EmergencyPassSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let lock: LockSet
    @State private var end: Date?

    var body: some View {
        VStack(spacing: 18) {
            Eyebrow(text: lock.name)
            Text("\(model.passesLeft(lock)) of \(lock.emergencyPasses) passes left").font(Theme.serif(28)).foregroundStyle(Theme.ink)
            Text("A pass waits 60 seconds, then opens this lock for 15 minutes. Passes reset each month.")
                .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            if let end {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = end.timeIntervalSince(context.date)
                    VStack(spacing: 12) {
                        Text(left > 0 ? countdownText(left) : "Ready").font(Theme.serif(44)).monospacedDigit().foregroundStyle(Theme.ink)
                        Text("Take a breath. Is this worth it?").foregroundStyle(Theme.dim)
                        Button("Open \(lock.name)") {
                            model.useEmergencyPass(lock)
                            dismiss()
                        }
                        .buttonStyle(.phos).disabled(left > 0)
                    }
                }
            } else {
                Button("Use a pass") { end = Date().addingTimeInterval(model.demo ? 3 : 60) }
                    .buttonStyle(.phos)
                    .disabled(model.passesLeft(lock) == 0)
            }
            Button("Never mind") { dismiss() }.buttonStyle(.phosQuiet)
        }
        .padding(24)
        .background(Theme.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}

/// Opens apps after the phone stays face down for a while.
final class FaceDownMonitor: ObservableObject {
    @Published var faceDown = false
    @Published var elapsed: TimeInterval = 0
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

/// Unlocks every lock that allows other ways and is waiting on a question or a tap.
private func unlockOtherWays(_ model: AppModel) {
    let targets = model.locks.filter { $0.otherWays && [.needsQuestion, .needsTap].contains(model.state($0)) }
    for lock in targets { model.unlock(lock, method: .otherWay) }
    model.lastUnlocked = targets
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
                UnlockSummary(title: "Focus complete") { finish() }
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
            if running && e >= Double(minutes * 60) {
                monitor.stop()
                running = false
                unlockOtherWays(model)
                done = true
            }
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
                UnlockSummary(title: "Well said") { dismiss() }
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
                    Text("Hide the verse, then say it out loud. 85% of the words in order opens locks that allow other ways.")
                        .font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                }
                .padding(20)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .onChange(of: recorder.transcript) { _, _ in
            if !showVerse && ratio >= 0.85 {
                recorder.stop()
                unlockOtherWays(model)
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
