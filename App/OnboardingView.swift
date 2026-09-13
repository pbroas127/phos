import FamilyControls
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0
    @State private var pickerShown = false
    @State private var working = false
    @State private var lock = LockSet()
    @State private var selection = FamilyActivitySelection()

    private let pages = 7

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
                    case 3: chooseApps
                    case 4: chooseMode
                    case 5: choosePlan
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
                if page > 0 {
                    Button("Back") { withAnimation { page -= 1 } }.buttonStyle(.phosQuiet)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(Theme.paper.ignoresSafeArea())
        .familyActivityPicker(isPresented: $pickerShown, selection: Binding(
            get: { selection },
            set: { sel in
                selection = sel
                lock.selection = Blocker.encode(sel)
                lock.appCount = Blocker.lockedCount(sel)
                model.setupLock(lock)
            }
        ))
        .onAppear {
            if let first = model.settings.lockSets.first {
                lock = first
                selection = Blocker.selection(from: first.selection)
            } else {
                lock.name = "Distractions"
                lock.mode = .untilRead
            }
        }
    }

    private var primaryLabel: String {
        switch page {
        case 2: return model.authorized ? "Continue" : "Allow Screen Time access"
        case 3: return lock.appCount == 0 ? "Choose apps to lock" : "Continue"
        case 6: return "Start with \(model.todaysTitle)"
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
        case 3 where lock.appCount == 0:
            pickerShown = true
        case 4:
            model.setupLock(lock)
            withAnimation { page += 1 }
        case 6:
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
            Text("Phos").font(Theme.serif(56)).foregroundStyle(Theme.ink)
            Text("Greek for light.").font(.title3).foregroundStyle(Theme.dim)
            Text("Your most distracting apps stay locked until you read a chapter of the Bible, reflect on it, and answer a few questions.")
                .font(.title3).foregroundStyle(Theme.ink).wrapLines()
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
            step("lock.fill", "Apps lock", "The apps you choose lock on the schedule you pick.")
            step("book.closed", "Read the chapter", "Use your own Bible, read it in Phos, or listen.")
            step("mic", "Reflect", "Type or say what stood out. Paste is turned off.")
            step("checkmark.circle", "Answer questions", "A few questions written for that chapter. If you read it, you will know.")
            step("sun.max", "Apps open", "For as long as you choose. Later, one quick question opens them again.")
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
            Text("Phos uses Apple's Screen Time to lock the apps you pick. Apple keeps your app list private. Phos never sees which apps you use, and nothing leaves your iPhone.")
                .font(.body).foregroundStyle(Theme.ink).wrapLines()
            if model.authorized {
                Label("Access allowed", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Theme.green)
            }
        }
    }

    private var chooseApps: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What should wait?").font(Theme.serif(36)).foregroundStyle(Theme.ink)
            Text("Pick the apps or categories that pull you in. Social media and entertainment are a good start. You can add more locks later.")
                .foregroundStyle(Theme.ink).wrapLines()
            CardBox {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lock.appCount == 0 ? "Nothing chosen yet" : "\(lock.appCount) chosen").font(.headline).foregroundStyle(Theme.ink)
                        Text("Phone, Messages, and Maps always stay open.").font(.footnote).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Button("Choose") { pickerShown = true }.font(.headline).foregroundStyle(Theme.gold)
                }
            }
        }
    }

    private var chooseMode: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How should it lock?").font(Theme.serif(36)).foregroundStyle(Theme.ink)
            ForEach(LockMode.allCases) { mode in
                Button { lock.mode = mode } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: mode.symbol).font(.title3).foregroundStyle(Theme.gold).frame(width: 40, height: 40).background(Theme.soft, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(mode.title).font(.headline).foregroundStyle(Theme.ink)
                            Text(mode.detail).font(.subheadline).foregroundStyle(Theme.dim).wrapLines()
                        }
                        Spacer()
                        Image(systemName: lock.mode == mode ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(lock.mode == mode ? Theme.gold : Theme.line)
                    }
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(lock.mode == mode ? Theme.gold : Theme.line, lineWidth: lock.mode == mode ? 1.5 : 1))
                }
                .buttonStyle(.plain)
            }
            if lock.mode == .scheduled {
                CardBox {
                    VStack(spacing: 10) {
                        DatePicker("Starts", selection: time(\.start), displayedComponents: .hourAndMinute)
                        DatePicker("Ends", selection: time(\.end), displayedComponents: .hourAndMinute)
                    }
                }
            }
            Text("You can add more locks with different apps and schedules in Settings.").font(.footnote).foregroundStyle(Theme.dim)
        }
    }

    private var choosePlan: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Where do you want to start?").font(Theme.serif(36)).foregroundStyle(Theme.ink)
            Text("Phos keeps your place in every book, so you can switch any time and pick up where you left off.")
                .foregroundStyle(Theme.ink).wrapLines()
            PlanList()
        }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("One last thing").font(Theme.serif(36)).foregroundStyle(Theme.ink)
            Text("When you open a locked app, tap the unlock button and Phos sends a notification. Tap it to jump straight to your reading. Allow notifications on the next screen so that works.")
                .foregroundStyle(Theme.ink).wrapLines()
            CardBox(fill: Theme.soft) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("\(lock.mode.title) · \(lock.appCount) chosen", systemImage: lock.mode.symbol)
                    Label("Apps open for \(Rules.unlockLabel(model.settings.rules.unlockMinutes))", systemImage: "lock.open")
                    Label("\(model.settings.rules.questionsPerCheck) questions, \(model.settings.rules.correctToPass) to pass", systemImage: "checkmark.circle")
                }
                .foregroundStyle(Theme.ink)
            }
            Text("For your first 24 hours every setting change applies right away, so you can find what fits.").font(.footnote).foregroundStyle(Theme.dim)
        }
    }

    private func time(_ key: WritableKeyPath<LockSet, TimeOfDay>) -> Binding<Date> {
        Binding(
            get: { lock[keyPath: key].date(on: Date()) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                lock[keyPath: key] = TimeOfDay(hour: c.hour ?? 0, minute: c.minute ?? 0)
            }
        )
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
