import SwiftUI

/// Result screen after a reading or another way of earning time: which locks opened and for how long.
struct UnlockSummary: View {
    @Environment(AppModel.self) private var model
    let title: String
    var after: PathLogic.After? = nil
    var onDone: () -> Void
    @State private var saved = false

    /// Open the apps now, or keep them locked and come back later without reading again.
    private var choice: some View {
        let asksQuestion = model.readyToUnlock.contains { $0.policy == .questionEach || ($0.policy == .limited && $0.limitNeedsQuestion) }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Open your apps now?").font(.headline).foregroundStyle(Theme.ink)
            Text(model.readyToUnlock.map(\.name).joined(separator: ", ")).font(.subheadline).foregroundStyle(Theme.dim)
            Button("Unlock now") { withAnimation { model.unlockReady() } }.buttonStyle(.phos)
            Button("Save for later") {
                withAnimation {
                    model.readyToUnlock = []
                    saved = true
                }
            }
            .buttonStyle(.phosSecondary)
            Text(asksQuestion
                 ? "Saving keeps them locked. Your reading still counts today, and locks that ask a question each time will ask one when you open them."
                 : "Saving keeps them locked. Your reading still counts today, so you can open them later without reading again.")
                .font(.caption).foregroundStyle(Theme.dim)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
    }

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
                    if !model.readyToUnlock.isEmpty {
                        choice
                    } else if saved {
                        Text("Saved for later. Today's reading counts for all your locks, so open them any time from the lock screen or the Unlock screen.")
                            .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    } else if model.lastUnlocked.isEmpty {
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
            Button("Done") {
                // Leaving without choosing keeps the apps locked, same as saving for later.
                model.readyToUnlock = []
                onDone()
            }
            .buttonStyle(PrimaryButtonStyle(kind: model.readyToUnlock.isEmpty ? .primary : .quiet))
            .padding(.horizontal, 20).padding(.bottom, 12)
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
                if lock.policy == .limited && state != .inactive {
                    UnlockDots(left: max(0, lock.limit - day.count), total: lock.limit)
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

/// Unlocks left today for a limited lock: filled dots are left, empty dots are used.
struct UnlockDots: View {
    let left: Int
    let total: Int

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<min(total, 10), id: \.self) { i in
                    Circle()
                        .fill(i < left ? Theme.gold : Color.clear)
                        .overlay(Circle().stroke(i < left ? Theme.gold : Theme.line, lineWidth: 1.5))
                        .frame(width: 11, height: 11)
                }
            }
            Text(ShieldArt.unlocksLabel(left)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(left) of \(total) unlocks left today")
    }
}

