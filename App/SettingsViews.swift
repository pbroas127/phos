import FamilyControls
import SwiftUI

// MARK: - Settings

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var wizardShown = DemoScreen.requested == .lockEditor
    @State private var libraryShown = false

    /// The reminder time as a Date for the picker, stored as minutes after midnight.
    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: model.settings.reminderMinutes / 60, minute: model.settings.reminderMinutes % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            model.settings.reminderMinutes = (c.hour ?? 20) * 60 + (c.minute ?? 0)
        }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    ForEach(model.locks) { lock in
                        NavigationLink(value: lock.id) { LockRow(lock: lock) }
                    }
                    Button { wizardShown = true } label: {
                        Label("New lock", systemImage: "plus.circle.fill").font(.body.weight(.semibold)).foregroundStyle(Theme.gold)
                    }
                } header: {
                    Text("Locks")
                } footer: {
                    Text("Each lock has its own apps, schedule, unlocks, and protection. Phone, Messages, and Maps can never be locked.")
                }

                if !model.authorized {
                    Section {
                        Button("Allow Screen Time access") { Task { await model.requestAuthorization() } }
                    } footer: {
                        Text("Locks need Screen Time access to work.")
                    }
                }

                Section("Reading") {
                    Button { libraryShown = true } label: {
                        LabeledContent("Books and paths", value: model.plan.name)
                    }
                    .foregroundStyle(Theme.ink)
                    NavigationLink {
                        VoiceSettingsView()
                    } label: {
                        LabeledContent("Voice and speed", value: VoiceCatalog.naturalSupported || !model.settings.voiceID.isEmpty
                                       ? "\(VoiceCatalog.name(model.settings.voiceID)), \(VoiceSpeed.label(model.settings.voiceRate))" : "iPhone voice")
                    }
                    Picker("Reading style", selection: $model.settings.preferredRead) {
                        ForEach(ReadMode.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Reflection style", selection: $model.settings.preferredReflect) {
                        ForEach(ReflectMode.allCases) { Text($0.title).tag($0) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Allow “I already read it”", isOn: $model.settings.allowAlreadyRead)
                        Text(model.settings.allowAlreadyRead
                             ? "You can skip the reading step and go straight to reflecting and the questions."
                             : "Every reading uses the timer or reading along, to keep you accountable.")
                            .font(.footnote).foregroundStyle(Theme.dim)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Quiz only on any chapter", isOn: $model.settings.allowReviewUnread)
                        Text(model.settings.allowReviewUnread
                             ? "Review quizzes are offered on every chapter, read in Wick or not."
                             : "Review quizzes are offered on chapters you have read in Wick.")
                            .font(.footnote).foregroundStyle(Theme.dim)
                    }
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $model.settings.appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Lock screen") {
                    Picker("Style", selection: $model.settings.shieldStyle) {
                        ForEach(ShieldStyle.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Look", selection: $model.settings.shieldTheme) {
                        ForEach(ShieldTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ShieldPreview(style: model.settings.shieldStyle, theme: model.settings.shieldTheme)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    Toggle("Daily reminder", isOn: $model.settings.reminderOn)
                    if model.settings.reminderOn {
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                        Picker("Tone", selection: $model.settings.reminderTone) {
                            ForEach(ReminderTone.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(model.settings.reminderTone == .gentle
                             ? "Calm invitations to read, no emoji, no streak talk."
                             : "Emoji, fun, and a little streak talk.")
                            .font(.footnote).foregroundStyle(Theme.dim)
                        Button("Send a sample now") { ReminderScheduler.sendSample(model) }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("One nudge a day, only on days you have not read yet. It changes with your streak, your next chapter, and the time you pick.")
                }

                DataSection()

                Section("About") {
                    Link("Help and support", destination: URL(string: "https://phos-app-sigma.vercel.app/support")!)
                    Link("Privacy policy", destination: URL(string: "https://phos-app-sigma.vercel.app/privacy")!)
                    LabeledContent("Bible text", value: "World English Bible")
                    NavigationLink("Acknowledgments") { AcknowledgmentsView() }
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationDestination(for: String.self) { id in LockDetailView(lockID: id) }
            .onChange(of: model.settings.shieldStyle) { _, _ in model.savePreferences() }
            .onChange(of: model.settings.shieldTheme) { _, _ in model.savePreferences() }
            .onChange(of: model.settings.appearance) { _, _ in model.savePreferences() }
            .onChange(of: model.settings.preferredRead) { _, _ in model.savePreferences() }
            .onChange(of: model.settings.preferredReflect) { _, _ in model.savePreferences() }
            .onChange(of: model.settings.allowAlreadyRead) { _, _ in model.savePreferences() }
            .onChange(of: model.settings.allowReviewUnread) { _, _ in model.savePreferences() }
            .onChange(of: model.settings.reminderOn) { _, on in
                model.savePreferences()
                if on { Task { _ = await Notifier.requestPermission(); ReminderScheduler.reschedule(model) } } else { ReminderScheduler.reschedule(model) }
            }
            .onChange(of: model.settings.reminderMinutes) { _, _ in
                model.savePreferences()
                ReminderScheduler.reschedule(model)
            }
            .onChange(of: model.settings.reminderTone) { _, _ in
                model.savePreferences()
                ReminderScheduler.reschedule(model)
            }
            .sheet(isPresented: $wizardShown) {
                LockWizard { model.createLock($0) }.environment(model)
            }
            .sheet(isPresented: $libraryShown) {
                LibraryView { pick in
                    model.choose(planID: pick.planID, index: pick.index)
                    libraryShown = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { model.route = .reading }
                }
                .environment(model)
            }
        }
    }
}

struct LockRow: View {
    @Environment(AppModel.self) private var model
    let lock: LockSet

    var body: some View {
        let state = model.state(lock)
        HStack(spacing: 12) {
            Image(systemName: state.isLocked ? "lock.fill" : (lock.enabled ? "lock.open" : "moon.zzz"))
                .foregroundStyle(state.isLocked ? Theme.gold : Theme.dim)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(lock.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(lock.enabled ? lock.summary : "Turned off").font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                if let reset = lock.protection.passcodeResetAt {
                    Label("Passcode clears \(reset.formatted(date: .abbreviated, time: .shortened))", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.red).lineLimit(1)
                }
            }
            Spacer()
            if lock.protection.kind != .none {
                Image(systemName: lock.protection.kind.symbol).font(.caption).foregroundStyle(Theme.dim)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Building blocks

struct SettingsCard<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: title).padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
            if let footer {
                Text(footer).font(.caption).foregroundStyle(Theme.dim).padding(.horizontal, 4)
            }
        }
    }
}

struct ChoiceRow: View {
    let title: String
    let detail: String
    let symbol: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).foregroundStyle(Theme.gold).frame(width: 24).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(detail).font(.footnote).foregroundStyle(Theme.dim).wrapLines()
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? Theme.gold : Theme.line)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DayChips: View {
    @Binding var days: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(on ? Color.white : Theme.ink)
                        .background(on ? Theme.gold : Theme.soft, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private func timeBinding(_ lock: Binding<LockSet>, _ key: WritableKeyPath<LockSet, TimeOfDay>) -> Binding<Date> {
    Binding(
        get: { lock.wrappedValue[keyPath: key].date(on: Date()) },
        set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            lock.wrappedValue[keyPath: key] = TimeOfDay(hour: c.hour ?? 0, minute: c.minute ?? 0)
        }
    )
}

struct WhenFields: View {
    @Binding var lock: LockSet

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Active days").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            DayChips(days: $lock.days)
            Text(lock.daysLabel).font(.caption).foregroundStyle(Theme.dim)
            Divider()
            Picker("Hours", selection: $lock.allDay) {
                Text("All day").tag(true)
                Text("Set hours").tag(false)
            }
            .pickerStyle(.segmented)
            if !lock.allDay {
                Picker("Hours mean", selection: $lock.openWindow) {
                    Text("Locked these hours").tag(false)
                    Text("Open only these hours").tag(true)
                }
                .pickerStyle(.segmented)
                // Open hours are stored as the locked window around them: open 6 to 9 PM is locked 9 PM to 6 PM.
                if lock.openWindow {
                    DatePicker("Opens", selection: timeBinding($lock, \.end), displayedComponents: .hourAndMinute)
                    DatePicker("Locks again", selection: timeBinding($lock, \.start), displayedComponents: .hourAndMinute)
                    let m = 1440 - lock.windowMinutes
                    Text("Open for \(m / 60) hr\(m % 60 == 0 ? "" : " \(m % 60) min") each day, locked the rest.").font(.caption).foregroundStyle(Theme.dim)
                } else {
                    DatePicker("Starts", selection: timeBinding($lock, \.start), displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: timeBinding($lock, \.end), displayedComponents: .hourAndMinute)
                    let m = lock.windowMinutes
                    Text("Active for \(m / 60) hr\(m % 60 == 0 ? "" : " \(m % 60) min") each day.").font(.caption).foregroundStyle(Theme.dim)
                }
                if lock.start.minutesFromMidnight > lock.end.minutesFromMidnight {
                    Text("Hours that run past midnight count for the day they start.").font(.caption).foregroundStyle(Theme.dim)
                }
            } else {
                Text("Active from midnight to midnight.").font(.caption).foregroundStyle(Theme.dim)
            }
        }
    }
}

struct UnlockFields: View {
    @Binding var lock: LockSet

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(UnlockPolicy.allCases) { p in
                ChoiceRow(title: p.title, detail: p.detail, symbol: p.symbol, selected: lock.policy == p) { lock.policy = p }
            }
            if lock.policy == .limited {
                Divider()
                Stepper(value: $lock.limit, in: 1...20) {
                    Text("\(lock.limit) unlocks a day").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                }
                Toggle("Each unlock also needs a question", isOn: $lock.limitNeedsQuestion)
            }
        }
    }
}

struct RewardFields: View {
    @Binding var lock: LockSet

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(LockSet.rewardChoices, id: \.self) { s in
                Button { lock.rewardSeconds = s } label: {
                    Text(LockSet.rewardLabel(s))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .foregroundStyle(lock.rewardSeconds == s ? Color.white : Theme.ink)
                        .background(lock.rewardSeconds == s ? Theme.gold : Theme.soft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ReadingFields: View {
    @Binding var lock: LockSet

    var body: some View {
        VStack(spacing: 10) {
            stepper("Questions", "\(lock.reading.questions)", $lock.reading.questions, 1...10, 1)
            stepper("Correct to pass", "\(min(lock.reading.pass, lock.reading.questions))", $lock.reading.pass, 1...max(1, lock.reading.questions), 1)
            stepper("Words to type", "\(lock.reading.words)", $lock.reading.words, 20...300, 5)
            stepper("Seconds of talking", "\(lock.reading.seconds)", $lock.reading.seconds, 15...300, 5)
            stepper("Minimum reading time", lock.reading.minutes == 0 ? "Off" : "\(lock.reading.minutes) min", $lock.reading.minutes, 0...30, 1)
        }
        .onChange(of: lock.reading.questions) { _, q in lock.reading.pass = min(lock.reading.pass, q) }
    }

    private func stepper(_ title: String, _ value: String, _ binding: Binding<Int>, _ range: ClosedRange<Int>, _ step: Int) -> some View {
        Stepper(value: binding, in: range, step: step) {
            HStack {
                Text(title).foregroundStyle(Theme.ink)
                Spacer()
                Text(value).foregroundStyle(Theme.dim).monospacedDigit()
            }
        }
    }
}

struct ProtectionFields: View {
    @Binding var lock: LockSet
    @State private var passcodeShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(ProtectionKind.allCases) { k in
                ChoiceRow(title: k.title, detail: k.detail, symbol: k.symbol, selected: lock.protection.kind == k) {
                    lock.protection.kind = k
                    if k == .passcode && !lock.protection.hasPasscode { passcodeShown = true }
                    if k == .commitment && lock.protection.commitUntil == nil {
                        lock.protection.commitUntil = Calendar.current.date(byAdding: .day, value: 7, to: Date())
                    }
                }
            }
            switch lock.protection.kind {
            case .passcode:
                Divider()
                HStack {
                    Label(lock.protection.hasPasscode ? "Passcode is set" : "No passcode yet", systemImage: "key.fill")
                        .foregroundStyle(lock.protection.hasPasscode ? Theme.green : Theme.red)
                    Spacer()
                    Button(lock.protection.hasPasscode ? "Change" : "Set passcode") { passcodeShown = true }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.gold)
                }
            case .countdown:
                Divider()
                Picker("Wait", selection: $lock.protection.countdownMinutes) {
                    ForEach([1, 5, 15, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                }
            case .delay:
                Divider()
                Picker("Changes start after", selection: $lock.protection.delayHours) {
                    ForEach([1, 12, 24, 48, 72], id: \.self) { Text($0 == 1 ? "1 hour" : "\($0) hours").tag($0) }
                }
            case .commitment:
                Divider()
                DatePicker("Committed until", selection: Binding(
                    get: { lock.protection.commitUntil ?? Date().addingTimeInterval(7 * 86_400) },
                    set: { lock.protection.commitUntil = $0 }
                ), in: Date().addingTimeInterval(3600)...Date().addingTimeInterval(90 * 86_400), displayedComponents: [.date, .hourAndMinute])
            case .none, .afterReading:
                EmptyView()
            }
            Divider()
            Toggle("Block deleting apps while locked", isOn: $lock.protection.blockDeletion)
            Text("While this lock is on, iOS will not let you delete any app, including Wick.").font(.caption).foregroundStyle(Theme.dim)
        }
        .sheet(isPresented: $passcodeShown) {
            PasscodeSetupSheet { code in
                let made = Passcode.make(code)
                lock.protection.passcodeHash = made.hash
                lock.protection.passcodeSalt = made.salt
                lock.protection.passcodeResetAt = nil
            }
        }
    }
}

// MARK: - New lock

struct LockWizard: View {
    @Environment(\.dismiss) private var dismiss
    var onCreate: (LockSet) -> Void

    @State private var draft: LockSet = {
        var l = LockSet()
        l.name = ""
        return l
    }()
    @State private var page = 0
    @State private var selection = FamilyActivitySelection()
    @State private var pickerShown = false

    private var pages: [Int] {
        draft.policy == .strict ? [0, 1, 2, 5, 6] : [0, 1, 2, 3, 4, 5, 6]
    }

    var body: some View {
        let order = pages
        let current = order[min(page, order.count - 1)]
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    ForEach(0..<order.count, id: \.self) { i in
                        Capsule().fill(i <= page ? Theme.gold : Theme.line).frame(height: 4)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(title(current)).font(Theme.serif(30)).foregroundStyle(Theme.ink)
                        Text(subtitle(current)).foregroundStyle(Theme.dim).wrapLines()
                        pageContent(current)
                    }
                    .padding(20)
                }

                VStack(spacing: 8) {
                    if let problem = problem(current) {
                        Text(problem).font(.footnote).foregroundStyle(Theme.dim)
                    }
                    Button(current == 6 ? "Create lock" : "Next") {
                        if current == 6 {
                            onCreate(draft)
                            dismiss()
                        } else {
                            withAnimation { page += 1 }
                        }
                    }
                    .buttonStyle(.phos)
                    .disabled(problem(current) != nil)
                    if page > 0 {
                        Button("Back") { withAnimation { page -= 1 } }.buttonStyle(.phosQuiet)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 12)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("New lock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .familyActivityPicker(isPresented: $pickerShown, selection: Binding(
                get: { selection },
                set: { sel in
                    selection = sel
                    Blocker.set(sel, on: &draft)
                }
            ))
        }
    }

    private func title(_ p: Int) -> String {
        ["Name and apps", "When it locks", "How it unlocks", "Unlock time", "Reading check", "Protect this lock", "Review"][p]
    }

    private func subtitle(_ p: Int) -> String {
        [
            "Group apps that pull you in the same way, like social media or games.",
            "Pick the days and hours this lock is active.",
            "What it takes to open these apps while the lock is active.",
            "How long each unlock opens the apps before they lock again.",
            "What today's reading must include to unlock. The recommended settings work well for most people.",
            "Once you create this lock, changing it goes through this protection. Adding apps always works.",
            "Check everything before you create it."
        ][p]
    }

    @ViewBuilder
    private func pageContent(_ p: Int) -> some View {
        switch p {
        case 0:
            SettingsCard(title: "Name") {
                TextField("Social media, games, bedtime…", text: $draft.name).font(.title3)
            }
            SettingsCard(title: "Apps", footer: "Phone, Messages, and Maps can never be locked.") {
                HStack {
                    Text(draft.appCount == 0 ? "Nothing chosen yet" : draft.appsLabel).foregroundStyle(Theme.ink)
                    Spacer()
                    Button("Choose") { pickerShown = true }.font(.body.weight(.semibold)).foregroundStyle(Theme.gold)
                }
            }
        case 1:
            SettingsCard(title: "Schedule") { WhenFields(lock: $draft) }
        case 2:
            SettingsCard(title: "Unlocks") { UnlockFields(lock: $draft) }
        case 3:
            SettingsCard(title: "Each unlock gives") { RewardFields(lock: $draft) }
        case 4:
            SettingsCard(title: "Reading check") { ReadingFields(lock: $draft) }
            Button("Use recommended") { draft.reading = ReadingCheck() }.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.gold)
        case 5:
            SettingsCard(title: "Protection") { ProtectionFields(lock: $draft) }
            SettingsCard(title: "Emergency passes", footer: "A pass opens this lock for 15 minutes after a 60 second wait.") {
                Stepper(value: $draft.emergencyPasses, in: 0...10) {
                    Text("\(draft.emergencyPasses) a month").foregroundStyle(Theme.ink)
                }
            }
        default:
            SettingsCard(title: draft.name.isEmpty ? "Lock" : draft.name) {
                review("Apps", draft.appsLabel)
                review("Days", draft.daysLabel)
                review("Hours", draft.hoursLabel)
                review("Unlocks", draft.policyLabel)
                if draft.policy != .strict {
                    review("Each unlock", LockSet.rewardLabel(draft.rewardSeconds))
                    review("Reading", "\(draft.reading.questions) questions, \(draft.reading.pass) to pass")
                }
                review("Protection", draft.protection.summary)
                review("Emergency passes", "\(draft.emergencyPasses) a month")
            }
        }
    }

    private func review(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(Theme.dim)
            Spacer()
            Text(value).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func problem(_ p: Int) -> String? {
        switch p {
        case 0:
            if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give this lock a name." }
            if draft.appCount == 0 { return "Choose at least one app or category." }
        case 1:
            if draft.days.isEmpty { return "Pick at least one day." }
            if draft.windowMinutes < 15 { return "Hours must last at least 15 minutes." }
            if draft.openWindow && !draft.allDay && 1440 - draft.windowMinutes < 15 { return "Open hours must last at least 15 minutes." }
        case 5:
            if draft.protection.kind == .passcode && !draft.protection.hasPasscode { return "Set a passcode first." }
        default:
            break
        }
        return nil
    }
}

// MARK: - Lock detail

struct LockDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let lockID: String

    @State private var draft = LockSet()
    @State private var loaded = false
    @State private var editing = false
    @State private var delayedHours: Int?
    @State private var passcodeShown = false
    @State private var countdownMinutes: Int?
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var addPickerShown = false
    @State private var addSelection = FamilyActivitySelection()
    @State private var replacePickerShown = false
    @State private var replaceSelection = FamilyActivitySelection()

    var body: some View {
        Group {
            if let lock = model.lock(lockID) {
                content(lock)
            } else {
                Text("This lock was deleted.").foregroundStyle(Theme.dim)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ lock: LockSet) -> some View {
        let unchanged = draft == lock
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lock.name).font(Theme.serif(34)).foregroundStyle(Theme.ink)
                    Label(statusText(lock), systemImage: model.state(lock).isLocked ? "lock.fill" : "lock.open")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(model.state(lock).isLocked ? Theme.gold : Theme.green)
                    Text(lock.summary).font(.caption).foregroundStyle(Theme.dim)
                }

                if let reset = lock.protection.passcodeResetAt {
                    CardBox(padding: 14, fill: Theme.soft) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("The passcode clears \(reset.formatted(date: .abbreviated, time: .shortened))", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text("Someone tapped \"I forgot the passcode\". After that time anyone can change this lock.")
                                .font(.footnote).foregroundStyle(Theme.dim).wrapLines()
                            Button("Cancel reset") { model.cancelPasscodeReset(lock.id) }
                                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.gold)
                        }
                    }
                }

                if let pending = model.pendingByLock[lock.id] {
                    CardBox(padding: 14, fill: Theme.soft) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(pending.deleted ? "This lock will be deleted \(pending.effectiveAt.formatted(date: .abbreviated, time: .shortened))" : "Your changes start \(pending.effectiveAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Button("Keep the current settings") { model.cancelPending(lock.id) }
                                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.gold)
                        }
                    }
                }

                SettingsCard(title: "Apps", footer: editing ? "You can remove apps while settings are open." : "Adding apps always works. Removing them needs Change settings.") {
                    HStack {
                        Text(lock.appsLabel).foregroundStyle(Theme.ink)
                        Spacer()
                        Button("Add apps") { addSelection = Blocker.selection(from: lock.selection); addPickerShown = true }
                            .font(.body.weight(.semibold)).foregroundStyle(Theme.gold)
                    }
                    if editing {
                        Button("Choose apps, including removing") { replaceSelection = Blocker.selection(from: draft.selection); replacePickerShown = true }
                            .font(.subheadline).foregroundStyle(Theme.ink)
                        if draft.appCount != lock.appCount {
                            Text("\(draft.appCount) after saving").font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                }

                if !editing {
                    VStack(spacing: 8) {
                        Button { requestEdit(lock) } label: {
                            Label("Change settings", systemImage: lock.protection.kind.symbol)
                                .font(.headline)
                                .padding(.horizontal, 22).padding(.vertical, 14)
                                .background(Theme.gold, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        if lock.protection.kind != .none {
                            Text("Protected by \(lock.protection.protectedBy)")
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        SettingsCard(title: "Name") { TextField("Name", text: $draft.name) }
                        SettingsCard(title: "Schedule") { WhenFields(lock: $draft) }
                        SettingsCard(title: "Unlocks") { UnlockFields(lock: $draft) }
                        if draft.policy != .strict {
                            SettingsCard(title: "Each unlock gives") { RewardFields(lock: $draft) }
                            SettingsCard(title: "Reading check") { ReadingFields(lock: $draft) }
                        }
                        SettingsCard(title: "Emergency passes") {
                            Stepper(value: $draft.emergencyPasses, in: 0...10) {
                                Text("\(draft.emergencyPasses) a month · \(model.passesLeft(lock)) left").foregroundStyle(Theme.ink)
                            }
                        }
                        SettingsCard(title: "Protection") { ProtectionFields(lock: $draft) }
                        SettingsCard(title: "Status") {
                            Toggle("Lock is on", isOn: $draft.enabled)
                            Button("Delete this lock", role: .destructive) { confirmDelete = true }
                        }
                    }
                    .disabled(!editing)
                    .opacity(editing ? 1 : 0.4)
                    .accessibilityHint(editing ? "" : "Tap Change settings first")
                }
            }
            .padding(20)
            .padding(.bottom, 90)
        }
        .safeAreaInset(edge: .bottom) {
            if editing && !unchanged {
                VStack(spacing: 6) {
                    if let problem = problem {
                        Text(problem).font(.footnote).foregroundStyle(Theme.red)
                    }
                    Button(delayedHours.map { "Save, starts in \($0) hours" } ?? "Save changes") { save(lock) }
                        .buttonStyle(.phos)
                        .disabled(problem != nil)
                    Button("Discard") { draft = lock }.buttonStyle(.phosQuiet)
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Theme.paper.shadow(.drop(color: Theme.ink.opacity(0.08), radius: 8, y: -2)))
            }
        }
        .onAppear {
            guard !loaded else { return }
            draft = lock
            editing = lock.protection.kind == .none
            loaded = true
        }
        .familyActivityPicker(isPresented: $addPickerShown, selection: Binding(
            get: { addSelection },
            set: { sel in
                addSelection = sel
                model.addApps(to: lock.id, picked: sel)
                if let updated = model.lock(lock.id) {
                    draft.selection = updated.selection
                    draft.appCount = updated.appCount
                    draft.categoryCount = updated.categoryCount
                }
            }
        ))
        .familyActivityPicker(isPresented: $replacePickerShown, selection: Binding(
            get: { replaceSelection },
            set: { sel in
                replaceSelection = sel
                Blocker.set(sel, on: &draft)
            }
        ))
        .sheet(isPresented: $passcodeShown) {
            PasscodeEntrySheet(lock: lock, onSuccess: {
                passcodeShown = false
                // The right passcode clears tries and any reset, so start editing from the saved lock.
                if let saved = model.lock(lock.id) { draft = saved }
                editing = true
            }, onCancel: { passcodeShown = false })
                .environment(model)
        }
        .sheet(isPresented: Binding(get: { countdownMinutes != nil }, set: { if !$0 { countdownMinutes = nil } })) {
            CooldownSheet(minutes: countdownMinutes ?? 5, onDone: { countdownMinutes = nil; editing = true }, onCancel: { countdownMinutes = nil })
                .interactiveDismissDisabled()
        }
        .alert("Settings", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog("Delete \(lock.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete lock", role: .destructive) {
                if let h = delayedHours {
                    let when = model.scheduleChange(lock, deleted: true, hours: h)
                    message = "This lock will be deleted \(when.formatted(date: .abbreviated, time: .shortened))."
                    editing = false
                } else {
                    model.deleteLock(lock.id)
                    dismiss()
                }
            }
        }
    }

    private var problem: String? {
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give this lock a name." }
        if draft.appCount == 0 { return "Keep at least one app, or delete the lock." }
        if draft.days.isEmpty { return "Pick at least one day." }
        if draft.windowMinutes < 15 { return "Hours must last at least 15 minutes." }
        if draft.openWindow && !draft.allDay && 1440 - draft.windowMinutes < 15 { return "Open hours must last at least 15 minutes." }
        if draft.protection.kind == .passcode && !draft.protection.hasPasscode { return "Set a passcode." }
        return nil
    }

    private func statusText(_ lock: LockSet) -> String {
        switch model.state(lock) {
        case .inactive: return lock.enabled ? "Not active right now" : "Turned off"
        case .open: return "Open right now"
        case .needsReading: return "Locked until today's reading"
        case .needsQuestion: return "Locked, one question opens it"
        case .needsTap: return "Locked, tap to unlock in Wick"
        case .usedUp: return "No unlocks left today"
        case .strict: return "Strict, passes only"
        }
    }

    private func requestEdit(_ lock: LockSet) {
        switch ProtectionLogic.access(lock, readingDone: model.today.readingDone, now: Date()) {
        case .open:
            editing = true
        case .needsPasscode:
            passcodeShown = true
        case .needsCountdown(let m):
            countdownMinutes = m
        case .delayed(let h):
            delayedHours = h
            editing = true
        case .blocked(let text):
            message = text
        }
    }

    private func save(_ lock: LockSet) {
        var updated = draft
        updated.reading = updated.reading.normalized()
        if let h = delayedHours {
            let when = model.scheduleChange(updated, deleted: false, hours: h)
            message = "Saved. These changes start \(when.formatted(date: .abbreviated, time: .shortened))."
            draft = lock
            editing = false
            delayedHours = nil
        } else {
            model.saveLock(updated)
            editing = updated.protection.kind == .none
        }
    }
}

// MARK: - Protection sheets

struct PasscodeEntrySheet: View {
    @Environment(AppModel.self) private var model
    let lock: LockSet
    var onSuccess: () -> Void
    var onCancel: () -> Void
    @State private var code = ""
    @State private var wrong = false
    @State private var confirmReset = false
    @FocusState private var focused: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            entry(lockedFor: max(0, (model.lock(lock.id)?.protection.lockedOutUntil ?? context.date).timeIntervalSince(context.date)))
        }
        .confirmationDialog("Remove the passcode in 24 hours?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Remove it in 24 hours", role: .destructive) { model.forgotPasscode(lock.id) }
            Button("Keep the passcode", role: .cancel) {}
        } message: {
            Text("Anyone with this phone can do this, so the person who keeps your code will not be asked. You can cancel it from the lock until then.")
        }
    }

    private func entry(lockedFor wait: TimeInterval) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill").font(.system(size: 40)).foregroundStyle(Theme.gold).padding(.top, 30)
            Text("Enter the passcode").font(Theme.serif(28)).foregroundStyle(Theme.ink)
            Text("To change \(lock.name).").foregroundStyle(Theme.dim)
            SecureField("Passcode", text: $code)
                .keyboardType(.numberPad)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(wrong ? Theme.red : Theme.line))
                .focused($focused)
            if wait > 0 {
                Text("Too many wrong tries. Try again in \(countdownText(wait)).").font(.footnote).foregroundStyle(Theme.red)
            } else if wrong {
                Text("That passcode is not right.").font(.footnote).foregroundStyle(Theme.red)
            }
            Button("Continue") {
                if model.checkPasscode(code, for: lock) { onSuccess() } else { wrong = true; code = "" }
            }
            .buttonStyle(.phos)
            .disabled(code.count < 4 || wait > 0)
            Button("Cancel") { onCancel() }.buttonStyle(.phosQuiet)
            if let reset = model.lock(lock.id)?.protection.passcodeResetAt {
                Text("The passcode clears \(reset.formatted(date: .abbreviated, time: .shortened)).").font(.footnote).foregroundStyle(Theme.dim)
            } else {
                Button("I forgot the passcode") { confirmReset = true }.font(.footnote).foregroundStyle(Theme.dim)
            }
            Spacer()
        }
        .padding(24)
        .background(Theme.paper.ignoresSafeArea())
        .onAppear { focused = true }
    }
}

struct PasscodeSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSet: (String) -> Void
    @State private var first = ""
    @State private var second = ""
    @State private var confirming = false
    @State private var mismatch = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "key").font(.system(size: 40)).foregroundStyle(Theme.gold).padding(.top, 30)
            Text(confirming ? "Type it again" : "Choose a passcode").font(Theme.serif(28)).foregroundStyle(Theme.ink)
            Text("4 to 8 digits. For real accountability, let a friend type it and keep it. A forgotten passcode clears after 24 hours.")
                .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            SecureField("Passcode", text: confirming ? $second : $first)
                .keyboardType(.numberPad)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(mismatch ? Theme.red : Theme.line))
                .focused($focused)
            if mismatch { Text("Those did not match. Try again.").font(.footnote).foregroundStyle(Theme.red) }
            Button(confirming ? "Set passcode" : "Next") {
                if !confirming {
                    confirming = true
                    mismatch = false
                } else if first == second {
                    onSet(first)
                    dismiss()
                } else {
                    mismatch = true
                    confirming = false
                    first = ""
                    second = ""
                }
            }
            .buttonStyle(.phos)
            .disabled(!Passcode.isValid(confirming ? second : first))
            Button("Cancel") { dismiss() }.buttonStyle(.phosQuiet)
            Spacer()
        }
        .padding(24)
        .background(Theme.paper.ignoresSafeArea())
        .onAppear { focused = true }
    }
}

struct CooldownSheet: View {
    let minutes: Int
    var onDone: () -> Void
    var onCancel: () -> Void
    @Environment(\.scenePhase) private var phase
    @State private var start = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = TimeInterval(minutes * 60)
            let left = max(0, total - context.date.timeIntervalSince(start))
            VStack(spacing: 22) {
                Spacer()
                Text("Take a breath").font(Theme.serif(32)).foregroundStyle(Theme.ink)
                Text("Settings open when the countdown ends. Leaving the app starts it over.")
                    .foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                RingProgress(value: 1 - left / total, lineWidth: 10) {
                    Text(countdownText(left)).font(Theme.serif(48)).monospacedDigit().foregroundStyle(Theme.ink)
                }
                .frame(width: 220, height: 220)
                Text("“Be still, and know that I am God.” Psalm 46:10").font(Theme.serif(17, .regular)).italic().foregroundStyle(Theme.dim)
                Spacer()
                Button(left > 0 ? "Waiting" : "Open settings") { onDone() }
                    .buttonStyle(.phos).disabled(left > 0)
                Button("Never mind") { onCancel() }.buttonStyle(.phosQuiet)
            }
            .padding(24)
        }
        .background(Theme.paper.ignoresSafeArea())
        .onChange(of: phase) { _, p in if p == .background { start = Date() } }
    }
}

/// A preview of the screen people see on a locked app.
struct ShieldPreview: View {
    @Environment(AppModel.self) private var model
    let style: ShieldStyle
    var theme: ShieldTheme = .dark
    var app = "Instagram"
    var large = false

    var body: some View {
        var snap = model.store.snapshot
        snap.style = style
        let copy = ShieldArt.copy(state: .needsReading, lock: nil, app: app, snap: snap)
        let p = ShieldArt.palette(theme)
        // Mirrors the system shield layout: emblem, title, and subtitle centered, the button at the bottom.
        return VStack(spacing: 0) {
            Spacer(minLength: large ? 120 : 24)
            VStack(spacing: large ? 14 : 10) {
                if let emblem = ShieldArt.emblem(theme) {
                    Image(uiImage: emblem).resizable().scaledToFit().frame(height: large ? 80 : 56)
                }
                Text(copy.title).font(.system(size: large ? 30 : 22, weight: .bold))
                    .foregroundStyle(Color(p.title)).multilineTextAlignment(.center)
                Text(ShieldArt.subtitle(copy)).font(.system(size: large ? 20 : 15))
                    .foregroundStyle(Color(p.body)).multilineTextAlignment(.center)
            }
            .padding(.horizontal, large ? 28 : 20)
            Spacer(minLength: large ? 120 : 24)
            Text(copy.button).font(.system(size: large ? 19 : 16, weight: .semibold)).foregroundStyle(Color(p.buttonLabel))
                .frame(maxWidth: .infinity, minHeight: large ? 56 : 48)
                .background(Color(p.buttonFill), in: Capsule())
                .padding(.horizontal, large ? 24 : 16)
                .padding(.bottom, large ? 40 : 18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: large ? nil : 420)
        .background(Color(p.background), in: RoundedRectangle(cornerRadius: large ? 0 : 28, style: .continuous))
    }
}

/// Credits and licenses for the open source pieces inside Wick.
struct AcknowledgmentsView: View {
    private let items: [(String, String, String)] = [
        ("World English Bible", "Public domain", "The Bible text used for reading, questions, and verses."),
        ("Kokoro 82M voice model", "Apache License 2.0", "Natural voices by hexgrad, downloaded only when you choose a natural voice."),
        ("KokoroSwift", "MIT License", "Swift port of Kokoro by mlalma. Copyright (c) the KokoroSwift authors."),
        ("MisakiSwift", "Apache License 2.0", "Pronunciation engine by mlalma, based on Misaki by hexgrad."),
        ("MLX Swift", "MIT License", "Machine learning framework by Apple, used to run the natural voices on device."),
        ("MLXUtilsLibrary", "MIT License", "Helpers for loading voice files, by mlalma."),
        ("ZIPFoundation", "MIT License", "Reads the bundled voice archive. Copyright (c) Thomas Zoechling."),
        ("Swift Numerics", "Apache License 2.0", "Math support used by MLX Swift. Copyright (c) Apple Inc.")
    ]

    var body: some View {
        List {
            Section {
                ForEach(items, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.0).font(.headline).foregroundStyle(Theme.ink)
                        Text(item.1).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.gold)
                        Text(item.2).font(.footnote).foregroundStyle(Theme.dim)
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("MIT License: Permission is hereby granted, free of charge, to any person obtaining a copy of this software, to deal in the software without restriction, subject to including the copyright notice and this permission notice in all copies. The software is provided as is, without warranty of any kind.\n\nApache License 2.0: Licensed under the Apache License, Version 2.0. You may obtain a copy at apache.org/licenses. Distributed on an as is basis, without warranties or conditions of any kind.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Acknowledgments")
    }
}

