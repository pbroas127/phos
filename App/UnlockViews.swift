import SwiftUI

/// Result screen after a reading or another way of earning time: which locks opened and for how long.
struct UnlockSummary: View {
    @Environment(AppModel.self) private var model
    let title: String
    var ref: ChapterRef? = nil
    var after: PathLogic.After? = nil
    var onDone: () -> Void
    @State private var saved = false

    /// The chapter's key verse and a line to carry, so finishing feels like more than a score.
    @ViewBuilder
    private var carry: some View {
        if let ref, let key = QuestionBank.shared.questions(for: ref)?.keyVerse,
           let chapter = Bible.shared.chapter(ref), key >= 1, key <= chapter.verses.count {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Carry this with you today")
                RedLetterText(verse: chapter.verses[key - 1], number: key, size: 19)
                Text(BookNames.verseTitle(ref, key)).font(.caption.weight(.semibold)).foregroundStyle(Theme.gold)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.soft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    /// Open the apps now, or keep them locked and come back later without reading again.
    private var choice: some View {
        let asksQuestion = model.readyToUnlock.contains { $0.policy == .questionEach || ($0.policy == .limited && $0.limitNeedsQuestion) }
        let hasLimited = model.readyToUnlock.contains { $0.policy == .limited }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Open your apps now?").font(.headline).foregroundStyle(Theme.ink)
            Text(model.readyToUnlock.map(\.name).joined(separator: ", ")).font(.subheadline).foregroundStyle(Theme.dim)
            Button("Unlock now") { withAnimation { model.unlockReady() } }.buttonStyle(.phos)
            if hasLimited {
                Text("Opening now does not use one of today's limited unlocks.").font(.caption).foregroundStyle(Theme.dim)
            }
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
                    if ref != nil && model.streak > 0 {
                        Label(model.streak == 1 ? "Day 1 of your streak" : "\(model.streak) days in a row", systemImage: "flame.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.gold)
                    }
                    carry
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
        guard let until = model.lockDay(lock).until else { return "Open" }
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
            let wait = max(0, (model.today.nextAttemptAt ?? context.date).timeIntervalSince(TrustedClock.now()))
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
                                    Text(q.q ?? "Put these in order")
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                                        Text(q.correctText).font(.subheadline).foregroundStyle(Theme.ink)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Divider().padding(.vertical, 2)
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
                QuestionUnlockView(lock: lock,
                                   onRead: { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { model.route = .reading } },
                                   onPass: { passLock = lock })
            }
            .sheet(item: $passLock) { lock in
                EmergencyPassSheet(lock: lock).environment(model).presentationDetents([.medium])
            }
        }
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
        let day = model.lockDay(lock)
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
                    EmptyView()
                case .open:
                    Button("Lock now") { model.lockNow(lock) }.buttonStyle(.phosSecondary)
                case .inactive:
                    EmptyView()
                }
                if state.isLocked && lock.emergencyPasses > 0 {
                    Button("Use an emergency pass (\(model.passesLeft(lock)) left)", action: onPass)
                        .buttonStyle(PrimaryButtonStyle(kind: state == .usedUp || state == .strict ? .secondary : .quiet))
                        .disabled(model.passesLeft(lock) == 0)
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
        case .strict: return LockLogic.reopenPhrase(lock, now: Date()).map { "Strict, opens again \($0)" } ?? "Strict all day, every day"
        }
    }
}

/// One question about today's reading that unlocks one lock.
struct QuestionUnlockView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    let lock: LockSet
    var onRead: () -> Void = {}
    var onPass: () -> Void = {}
    @State private var item: QuizItem?
    @State private var answered: Bool?
    @State private var loaded = false

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
                let chapters = model.questionChapters(for: lock)
                if !chapters.isEmpty {
                    Text(chapters.count == 1 ? "One question about \(BookNames.title(chapters[0]))." : "One question about what you read today.")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                }
                if let item {
                    QuestionView(item: item, locked: answered != nil) { right in
                        answered = right
                        model.answerUnlockQuestion(for: lock, right: right)
                    }
                    .id(item.id)
                    if answered == nil {
                        Text("Leaving before you answer counts as a miss.").font(.caption).foregroundStyle(Theme.dim)
                    }
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
                } else if loaded, model.nextAttemptAt != nil {
                    // A miss is waiting out its timer. Reopening this screen does not skip it.
                    Text("You missed the last question.").font(.headline).foregroundStyle(Theme.ink)
                    RetryButton { newQuestion() }
                } else {
                    Text("No questions are available for what you read today.").foregroundStyle(Theme.dim)
                    Button("Read today's chapter", action: onRead).buttonStyle(.phos)
                    if lock.emergencyPasses > 0 {
                        Button("Use an emergency pass (\(model.passesLeft(lock)) left)") { dismiss(); onPass() }
                            .buttonStyle(.phosSecondary)
                            .disabled(model.passesLeft(lock) == 0)
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("One question")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if item == nil { newQuestion() }
            loaded = true
        }
        // Leaving with a question on screen counts as a miss, so it cannot be looked up or traded for another.
        .onDisappear { leftUnanswered() }
        .onChange(of: phase) { _, p in if p == .background { leftUnanswered() } }
    }

    private func newQuestion() {
        answered = nil
        item = model.unlockQuestion(for: lock)
    }

    private func leftUnanswered() {
        guard item != nil, answered == nil else { return }
        answered = false
        model.answerUnlockQuestion(for: lock, right: false)
    }
}

struct RetryButton: View {
    @Environment(AppModel.self) private var model
    var action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wait = max(0, (model.today.nextAttemptAt ?? context.date).timeIntervalSince(TrustedClock.now()))
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
                    let left = end.timeIntervalSince(TrustedClock.now())
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
                Button("Use a pass") { end = TrustedClock.now().addingTimeInterval(model.demo ? 3 : 60) }
                    .buttonStyle(.phos)
                    .disabled(model.passesLeft(lock) == 0)
            }
            Button("Never mind") { dismiss() }.buttonStyle(.phosQuiet)
        }
        .padding(24)
        .background(Theme.paper.ignoresSafeArea())
    }
}

/// Unlocks left today for a limited lock: filled dots are left, empty dots are used.
struct UnlockDots: View {
    let left: Int
    let total: Int

    var body: some View {
        let shown = min(total, 20)
        let size: CGFloat = shown > 10 ? 9 : 11
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(stride(from: 0, to: shown, by: 10)), id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(row..<min(row + 10, shown), id: \.self) { i in
                            Circle()
                                .fill(i < left ? Theme.gold : Color.clear)
                                .overlay(Circle().stroke(i < left ? Theme.gold : Theme.line, lineWidth: 1.5))
                                .frame(width: size, height: size)
                        }
                    }
                }
            }
            Text(ShieldArt.unlocksLabel(left)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(left) of \(total) unlocks left today")
    }
}

/// Shown on Today when Screen Time access is off, since no lock can work without it.
struct ScreenTimeOffBanner: View {
    @Environment(AppModel.self) private var model
    @State private var working = false

    var body: some View {
        CardBox(padding: 16, fill: Theme.soft) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Screen Time access is off, so your locks are not working.", systemImage: "exclamationmark.lock.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    working = true
                    Task {
                        await model.requestAuthorization()
                        working = false
                    }
                } label: {
                    if working { ProgressView().tint(.white) } else { Text("Turn it back on") }
                }
                .buttonStyle(.phos)
                .disabled(working)
            }
        }
    }
}

/// Shown on Today when notifications are off. The lock screen button works by sending a notification, so without them it cannot open Wick.
struct NotificationsOffBanner: View {
    var body: some View {
        CardBox(padding: 16, fill: Theme.soft) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Notifications are off, so the button on a locked app cannot open Wick.", systemImage: "bell.slash.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Turn on notifications for Wick, or open Wick from your Home Screen when an app is locked.")
                    .font(.footnote).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.phosSecondary)
            }
        }
    }
}
