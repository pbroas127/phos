import FamilyControls
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0
    @State private var pickerShown = false
    @State private var working = false
    @State private var notificationsAsked = false

    private let pages = 6

    var body: some View {
        @Bindable var model = model
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
                .disabled(!canContinue || working)
                if page > 0 {
                    Button("Back") { withAnimation { page -= 1 } }.buttonStyle(.phosQuiet)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(Theme.paper.ignoresSafeArea())
        .familyActivityPicker(isPresented: $pickerShown, selection: Binding(
            get: { model.selection },
            set: { model.updateSelection($0) }
        ))
    }

    private var primaryLabel: String {
        switch page {
        case 2: return model.authorized ? "Continue" : "Allow Screen Time access"
        case 3: return model.lockedCount == 0 ? "Choose apps to lock" : "Continue"
        case 5: return "Start with \(model.todaysTitle)"
        default: return "Continue"
        }
    }

    private var canContinue: Bool { true }

    private func next() {
        switch page {
        case 2 where !model.authorized:
            working = true
            Task {
                await model.requestAuthorization()
                working = false
                if model.authorized { withAnimation { page += 1 } }
            }
        case 3 where model.lockedCount == 0:
            pickerShown = true
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
            Text("Phos").font(Theme.serif(56)).foregroundStyle(Theme.ink)
            Text("Greek for light.").font(.title3).foregroundStyle(Theme.dim)
            Text("Your most distracting apps stay locked each morning until you read a chapter of the Bible, reflect on it, and answer a few questions.")
                .font(.title3).foregroundStyle(Theme.ink).fixedSize()
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
            step("lock.fill", "Apps lock each morning", "The apps you choose stay closed until today's reading is done.")
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
                Text(detail).font(.subheadline).foregroundStyle(Theme.dim).fixedSize()
            }
        }
    }

    private var screenTime: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Screen Time access").font(Theme.serif(36)).foregroundStyle(Theme.ink)
            Text("Phos uses Apple's Screen Time to lock the apps you pick. Apple keeps your app list private. Phos never sees which apps you use, and nothing leaves your iPhone.")
                .font(.body).foregroundStyle(Theme.ink).fixedSize()
            if model.authorized {
                Label("Access allowed", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Theme.green)
            }
        }
    }

    private var chooseApps: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What should wait?").font(Theme.serif(36)).foregroundStyle(Theme.ink)
            Text("Pick the apps or categories that pull you in. Social media and entertainment are a good start.")
                .foregroundStyle(Theme.ink).fixedSize()
            CardBox {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.lockedCount == 0 ? "Nothing chosen yet" : "\(model.lockedCount) chosen").font(.headline).foregroundStyle(Theme.ink)
                        Text("Phone, Messages, and Maps always stay open.").font(.footnote).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Button("Choose") { pickerShown = true }.font(.headline).foregroundStyle(Theme.gold)
                }
            }
        }
    }

    private var choosePlan: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick a reading plan").font(Theme.serif(36)).foregroundStyle(Theme.ink)
            Text("The plan chooses each day's chapter, so there is no hunting for the shortest one.")
                .foregroundStyle(Theme.ink).fixedSize()
            PlanList()
        }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("One last thing").font(Theme.serif(36)).foregroundStyle(Theme.ink)
            Text("When you open a locked app, tap the unlock button and Phos sends a notification. Tap it to jump straight to your reading. Allow notifications on the next screen so that works.")
                .foregroundStyle(Theme.ink).fixedSize()
            CardBox(fill: Theme.soft) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Locks at \(model.settings.schedule.morning.label)", systemImage: "sunrise")
                    Label("Apps open for \(Rules.unlockLabel(model.settings.rules.unlockMinutes))", systemImage: "lock.open")
                    Label("\(model.settings.rules.questionsPerCheck) questions, \(model.settings.rules.correctToPass) to pass", systemImage: "checkmark.circle")
                }
                .foregroundStyle(Theme.ink)
            }
            Text("You can change all of this in Settings.").font(.footnote).foregroundStyle(Theme.dim)
        }
    }
}

extension View {
    func fixedSize() -> some View { fixedSize(horizontal: false, vertical: true) }
}

struct PlanList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            ForEach(ReadingPlans.all) { plan in
                Button {
                    model.choosePlan(plan.id)
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
        }
    }
}
