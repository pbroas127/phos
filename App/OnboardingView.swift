import FamilyControls
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0
    @State private var working = false
    @State private var wizardShown = false
    /// When the setup preview of the shield ends.
    @State private var previewEnds: Date?
    @Environment(\.scenePhase) private var phase

    private let pages = 6

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<pages, id: \.self) { i in
                    Capsule().fill(i <= page ? Theme.gold : Theme.line).frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch page {
                    case 0: welcome
                    case 1: howItWorks
                    case 2: screenTime
                    case 3: firstLock
                    case 4: choosePlan
                    default: finish
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 10) {
                Button(action: next) {
                    if working { ProgressView().tint(.white) } else { Text(primaryLabel) }
                }
                .buttonStyle(.phos)
                .disabled(working)
                if page == 2 && !model.authorized {
                    // Locks wait for access. Today shows a banner to turn it on later.
                    Button("Not now") { withAnimation { page += 1 } }.buttonStyle(.phosQuiet).disabled(working)
                } else if page == 3 && model.locks.isEmpty {
                    Button("Skip for now") { withAnimation { page += 1 } }.buttonStyle(.phosQuiet)
                }
                if page > 0 {
                    Button("Back") { withAnimation { page -= 1 } }.buttonStyle(.phosQuiet)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(Theme.paper.ignoresSafeArea())
        .sheet(isPresented: $wizardShown) {
            LockWizard { model.createLock($0) }.environment(model)
        }
        .onChange(of: phase) { _, p in if p == .active { endPreviewIfDue() } }
    }

    private func startPreview(_ lock: LockSet) {
        Blocker.preview(lock, minutes: 2)
        previewEnds = Date().addingTimeInterval(120)
        DispatchQueue.main.asyncAfter(deadline: .now() + 121) { endPreviewIfDue() }
    }

    /// Screen Time ends the preview on its own. This covers the app being open when it does, or iOS running late.
    private func endPreviewIfDue() {
        guard let ends = previewEnds, Date() >= ends else { return }
        previewEnds = nil
        guard !model.settings.onboarded else { return }
        for lock in model.locks { Blocker.apply(lock, shield: false) }
    }

    private var primaryLabel: String {
        switch page {
        case 2: return model.authorized ? "Continue" : "Allow Screen Time access"
        case 3: return model.locks.isEmpty ? "Create my first lock" : "Continue"
        case 5: return "Start with \(model.todaysTitle)"
        default: return "Continue"
        }
    }

    private func next() {
        switch page {
        case 2 where !model.authorized:
            working = true
            Task {
                await model.requestAuthorization()
                working = false
                if model.authorized { withAnimation { page += 1 } }
            }
        case 3 where model.locks.isEmpty:
            wizardShown = true
        case 5:
            working = true
            Task {
                _ = await Notifier.requestPermission()
                working = false
                model.finishOnboarding()
            }
        default:
            withAnimation { page += 1 }
        }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image("LaunchLogo").resizable().scaledToFit().frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.top, 30)
            Text("Wick").font(Theme.serif(56)).foregroundStyle(Theme.ink)
            Text("Keep your light burning.").font(.title3).foregroundStyle(Theme.dim)
            Text("Your most distracting apps stay locked until you read a chapter of the Bible, reflect on it, and answer a few questions.")
                .font(.title3).foregroundStyle(Theme.ink).wrapLines()
            RestoreOffer()
            CardBox(fill: Theme.soft) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("“Your word is a lamp to my feet, and a light for my path.”").font(Theme.serif(19, .regular)).foregroundStyle(Theme.ink)
                    Text("Psalm 119:105").font(.footnote).foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("How it works").font(Theme.serif(36)).foregroundStyle(Theme.ink)
            step("lock.fill", "Make locks", "Each lock has its own apps, days, hours, and rules.")
            step("book.closed", "Read the chapter", "Use your own Bible, read it in Wick, or listen.")
            step("mic", "Reflect", "Type or say what stood out. Paste is turned off.")
            step("checkmark.circle", "Answer questions", "A few questions written for that chapter. If you read it, you will know.")
            step("sun.max", "Apps open", "For the time each lock gives. Later unlocks follow that lock's rules.")
        }
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.gold).frame(width: 44, height: 44).background(Theme.soft, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(Theme.ink)
                Text(detail).font(.subheadline).foregroundStyle(Theme.dim).wrapLines()
            }
        }
    }

    private var screenTime: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Screen Time access").font(Theme.serif(36)).foregroundStyle(Theme.ink)
            Text("Wick uses Apple's Screen Time to lock the apps you pick. Apple keeps your app list private, so Wick never sees which apps you use. Your journal backs up to your own iCloud, and you can turn that off in Settings.")
                .font(.body).foregroundStyle(Theme.ink).wrapLines()
            if model.authorized {
                Label("Access allowed", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Theme.green)
            }
        }
    }

    private var firstLock: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your first lock").font(Theme.serif(36)).foregroundStyle(Theme.ink)
            Text("Pick the apps that pull you in, when they lock, how they unlock, and how your settings are protected. You can add more locks later.")
                .foregroundStyle(Theme.ink).wrapLines()
            ForEach(model.locks) { lock in
                CardBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(lock.name, systemImage: "lock.fill").font(.headline).foregroundStyle(Theme.ink)
                        Text(lock.summary).font(.subheadline).foregroundStyle(Theme.dim)
                        Text(lock.protection.summary).font(.caption).foregroundStyle(Theme.dim)
                    }
                }
            }
            if !model.locks.isEmpty {
                Button("Add another lock") { wizardShown = true }.buttonStyle(.phosSecondary)
            }
            if let first = model.locks.first, model.authorized, !model.demo {
                Button(previewEnds == nil ? "See it work" : "Showing the shield now") { startPreview(first) }
                    .buttonStyle(.phosSecondary)
                    .disabled(previewEnds != nil)
                Text(previewEnds == nil
                     ? "Try the lock for 2 minutes before you finish setup."
                     : "Open one of your locked apps to see the shield. It unlocks by itself in 2 minutes.")
                    .font(.footnote).foregroundStyle(Theme.dim).wrapLines()
            }
        }
    }

    private var choosePlan: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Where do you want to start?").font(Theme.serif(36)).foregroundStyle(Theme.ink)
            Text("Wick keeps your place in every book, so you can switch any time and pick up where you left off.")
                .foregroundStyle(Theme.ink).wrapLines()
            PlanList()
        }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("One last thing").font(Theme.serif(36)).foregroundStyle(Theme.ink)
            Text("When you open a locked app, tap the button and Wick sends a notification. Tap it to jump straight to your reading. Allow notifications on the next screen so that works.")
                .foregroundStyle(Theme.ink).wrapLines()
        }
    }
}

extension View {
    func wrapLines() -> some View { fixedSize(horizontal: false, vertical: true) }
}

struct PlanList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            ForEach(ReadingPlans.starters.map(ReadingPlans.plan)) { plan in
                Button {
                    model.makeActive(plan.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.name).font(.headline).foregroundStyle(Theme.ink)
                            Text(plan.detail).font(.subheadline).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Image(systemName: model.settings.planID == plan.id ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(model.settings.planID == plan.id ? Theme.gold : Theme.line)
                    }
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(model.settings.planID == plan.id ? Theme.gold : Theme.line, lineWidth: model.settings.planID == plan.id ? 1.5 : 1))
                }
                .buttonStyle(.plain)
            }
            Text("Every other book is in the Books screen.").font(.footnote).foregroundStyle(Theme.dim)
        }
    }
}
