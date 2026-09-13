import FamilyControls
import SwiftUI

// MARK: - Protected saving

/// Walks a settings change through passcode, countdown, and waiting rules.
@Observable
final class SaveFlow {
    var proposal: LockConfig?
    var passcodeOK = false
    var cooldownDone = false
    var askPasscode = false
    var askCooldown = false
    var cooldownMinutes = 0
    var messageTitle = ""
    var message: String?
    private var onSaved: (() -> Void)?

    func submit(_ config: LockConfig, model: AppModel, onSaved: (() -> Void)? = nil) {
        proposal = config
        passcodeOK = false
        cooldownDone = false
        self.onSaved = onSaved
        step(model)
    }

    func step(_ model: AppModel) {
        guard let p = proposal else { return }
        switch model.save(p, passcodeOK: passcodeOK, cooldownDone: cooldownDone) {
        case .applied:
            proposal = nil
            onSaved?()
        case .pending(let date):
            proposal = nil
            messageTitle = "Saved for later"
            message = "This makes Phos easier, so it starts \(date.formatted(date: .abbreviated, time: .shortened)). You can cancel it from Settings."
            onSaved?()
        case .blocked(let text):
            proposal = nil
            messageTitle = "Not right now"
            message = text
        case .needsPasscode:
            askPasscode = true
        case .needsCooldown(let minutes):
            cooldownMinutes = minutes
            askCooldown = true
        }
    }

    func cancel() {
        proposal = nil
        askPasscode = false
        askCooldown = false
    }
}

struct SaveFlowModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Bindable var flow: SaveFlow

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $flow.askPasscode) {
                PasscodeEntrySheet(onSuccess: {
                    flow.passcodeOK = true
                    flow.askPasscode = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { flow.step(model) }
                }, onCancel: { flow.cancel() })
                .environment(model)
            }
            .sheet(isPresented: $flow.askCooldown) {
                CooldownSheet(minutes: flow.cooldownMinutes, onDone: {
                    flow.cooldownDone = true
                    flow.askCooldown = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { flow.step(model) }
                }, onCancel: { flow.cancel() })
                .interactiveDismissDisabled()
            }
            .alert(flow.messageTitle, isPresented: Binding(get: { flow.message != nil }, set: { if !$0 { flow.message = nil } })) {
                Button("OK") { flow.message = nil }
            } message: {
                Text(flow.message ?? "")
            }
    }
}

extension View {
    func saveFlow(_ flow: SaveFlow) -> some View { modifier(SaveFlowModifier(flow: flow)) }
}

// MARK: - Settings

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var libraryShown = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                if let pending = model.settings.pendingConfig {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("An easier change starts \(pending.effectiveAt.formatted(.dateTime.weekday(.wide).hour().minute()))", systemImage: "clock")
                                .font(.headline).foregroundStyle(Theme.gold)
                            Text("Saving another change replaces it.").font(.footnote).foregroundStyle(Theme.dim)
                            Button("Cancel the waiting change") { model.cancelPending() }.font(.footnote.weight(.semibold))
                        }
                    }
                }
                if let ends = model.settings.setupWindowEnds, ends > Date() {
                    Section {
                        Label("Setup day: countdowns and waits are skipped until \(ends.formatted(.dateTime.weekday(.wide).hour().minute())).", systemImage: "sparkles")
                            .font(.footnote).foregroundStyle(Theme.ink)
                    }
                }

                Section {
                    ForEach(model.settings.lockSets) { set in
                        NavigationLink {
                            LockSetEditor(existing: set)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: set.mode.symbol).foregroundStyle(set.enabled ? Theme.gold : Theme.dim).frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(set.name).foregroundStyle(Theme.ink)
                                    Text(set.enabled ? set.summary : "Off").font(.caption).foregroundStyle(Theme.dim)
                                }
                            }
                        }
                    }
                    NavigationLink {
                        LockSetEditor(existing: nil)
                    } label: {
                        Label("Add a lock", systemImage: "plus.circle.fill").foregroundStyle(Theme.gold)
                    }
                    if !model.authorized {
                        Button("Allow Screen Time access") { Task { await model.requestAuthorization() } }
                    }
                } header: {
                    Text("Locks")
                } footer: {
                    Text("Each lock has its own apps and schedule. Phone, Messages, and Maps can never be locked.")
                }

                Section("Rules and times") {
                    NavigationLink {
                        RulesView()
                    } label: {
                        LabeledContent("Unlock rules", value: "\(model.settings.rules.questionsPerCheck) questions, \(Rules.unlockLabel(model.settings.rules.unlockMinutes))")
                    }
                    NavigationLink {
                        LockTimesView()
                    } label: {
                        LabeledContent("Morning and midday", value: model.settings.schedule.morning.label)
                    }
                }

                Section {
                    NavigationLink {
                        ProtectionView()
                    } label: {
                        LabeledContent("Protect my settings", value: protectionSummary)
                    }
                } header: {
                    Text("Protection")
                } footer: {
                    Text("Passcode, countdowns, waiting periods, and commitments keep a weak moment from undoing your plan.")
                }

                Section("Reading") {
                    Button { libraryShown = true } label: {
                        LabeledContent("Books and paths", value: model.plan.name)
                    }
                    .foregroundStyle(Theme.ink)
                    Picker("Reading style", selection: $model.settings.preferredRead) {
                        ForEach(ReadMode.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Reflection style", selection: $model.settings.preferredReflect) {
                        ForEach(ReflectMode.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section("Lock screen") {
                    Picker("Style", selection: $model.settings.shieldStyle) {
                        ForEach(ShieldStyle.allCases) { Text($0.title).tag($0) }
                    }
                    ShieldPreview(style: model.settings.shieldStyle)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Emergency") {
                    NavigationLink {
                        EmergencyPassView()
                    } label: {
                        LabeledContent("Emergency passes", value: "\(model.passesLeft) left")
                    }
                }

                Section("About") {
                    Link("Help and support", destination: URL(string: "https://phos-app-sigma.vercel.app/support")!)
                    Link("Privacy policy", destination: URL(string: "https://phos-app-sigma.vercel.app/privacy")!)
                    LabeledContent("Bible text", value: "World English Bible")
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Settings")
            .onChange(of: model.settings.shieldStyle) { _, _ in model.savePreferences() }
            .onChange(of: model.settings.preferredRead) { _, _ in model.savePreferences() }
            .onChange(of: model.settings.preferredReflect) { _, _ in model.savePreferences() }
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

    private var protectionSummary: String {
        let p = model.settings.protection
        if p.committed(at: Date()) { return "Committed" }
        var parts: [String] = []
        if p.hasPasscode { parts.append("Passcode") }
        if p.delayHours > 0 { parts.append("\(p.delayHours)h wait") }
        if p.cooldownMinutes > 0 { parts.append("Countdown") }
        return parts.isEmpty ? "Off" : parts.joined(separator: ", ")
    }
}

// MARK: - Locks

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
        .padding(.vertical, 4)
    }
}

struct LockSetEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let existing: LockSet?

    @State private var draft = LockSet()
    @State private var selection = FamilyActivitySelection()
    @State private var loaded = false
    @State private var pickerShown = false
    @State private var confirmDelete = false
    @State private var flow = SaveFlow()

    var body: some View {
        Form {
            Section("Name") {
                TextField("Social media, games, bedtime…", text: $draft.name)
            }

            Section {
                Button { pickerShown = true } label: {
                    HStack {
                        Label("Apps and categories", systemImage: "square.grid.2x2").foregroundStyle(Theme.ink)
                        Spacer()
                        Text(draft.appCount == 0 ? "Choose" : "\(draft.appCount) chosen").foregroundStyle(Theme.dim)
                    }
                }
            } footer: {
                Text("Phone, Messages, and Maps can never be locked.")
            }

            Section("How it locks") {
                ForEach(LockMode.allCases) { mode in
                    Button { draft.mode = mode } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: mode.symbol).foregroundStyle(Theme.gold).frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title).font(.headline).foregroundStyle(Theme.ink)
                                Text(mode.detail).font(.footnote).foregroundStyle(Theme.dim).wrapLines()
                            }
                            Spacer()
                            Image(systemName: draft.mode == mode ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(draft.mode == mode ? Theme.gold : Theme.line)
                        }
                    }
                }
            }

            if draft.mode == .scheduled {
                Section {
                    DatePicker("Starts", selection: time(\.start), displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: time(\.end), displayedComponents: .hourAndMinute)
                    Toggle("Reading can earn open time", isOn: $draft.allowEarning)
                } header: {
                    Text("Hours")
                } footer: {
                    Text(hoursFooter)
                }
            }

            Section {
                DayChips(days: $draft.days)
            } header: {
                Text("Days")
            } footer: {
                Text(draft.days.count == 7 ? "Every day." : "Only on the highlighted days.")
            }

            Section {
                Toggle("Lock is on", isOn: $draft.enabled)
            }

            Section {
                Button(existing == nil ? "Add lock" : "Save lock") { save() }
                    .disabled(problem != nil)
            } footer: {
                if let problem { Text(problem).foregroundStyle(Theme.red) }
            }

            if existing != nil {
                Section {
                    Button("Delete lock", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle(existing == nil ? "New lock" : "Edit lock")
        .familyActivityPicker(isPresented: $pickerShown, selection: Binding(
            get: { selection },
            set: { sel in
                selection = sel
                draft.selection = Blocker.encode(sel)
                draft.appCount = Blocker.lockedCount(sel)
            }
        ))
        .onAppear {
            guard !loaded else { return }
            draft = existing ?? LockSet()
            if existing == nil { draft.name = "" }
            selection = Blocker.selection(from: draft.selection)
            loaded = true
        }
        .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete lock", role: .destructive) {
                var c = model.settings.config
                c.lockSets.removeAll { $0.id == draft.id }
                flow.submit(c, model: model) { dismiss() }
            }
        } message: {
            Text("Deleting a lock makes Phos easier, so your protections apply.")
        }
        .saveFlow(flow)
    }

    private var hoursFooter: String {
        let length = draft.windowMinutes
        let hours = length / 60, minutes = length % 60
        let span = minutes == 0 ? "\(hours) hours" : "\(hours) hr \(minutes) min"
        return draft.allowEarning
            ? "Locked for \(span). Inside these hours reading and questions still open apps for a while."
            : "Strict for \(span). Inside these hours only an emergency pass opens these apps."
    }

    private var problem: String? {
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give this lock a name." }
        if draft.appCount == 0 { return "Choose at least one app or category." }
        if draft.days.isEmpty { return "Pick at least one day." }
        if draft.mode == .scheduled && draft.windowMinutes < 15 { return "Scheduled hours must last at least 15 minutes." }
        return nil
    }

    private func save() {
        var c = model.settings.config
        if let i = c.lockSets.firstIndex(where: { $0.id == draft.id }) {
            c.lockSets[i] = draft
        } else {
            c.lockSets.append(draft)
        }
        flow.submit(c, model: model) { dismiss() }
    }

    private func time(_ key: WritableKeyPath<LockSet, TimeOfDay>) -> Binding<Date> {
        Binding(
            get: { draft[keyPath: key].date(on: Date()) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft[keyPath: key] = TimeOfDay(hour: c.hour ?? 0, minute: c.minute ?? 0)
            }
        )
    }
}

struct LockTimesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Schedule()
    @State private var loaded = false
    @State private var flow = SaveFlow()

    var body: some View {
        Form {
            Section {
                DatePicker("Morning lock", selection: time(\.morning), displayedComponents: .hourAndMinute)
            } footer: {
                Text("Your reading day starts here. \"Until I read\" and \"All day\" locks begin at this time.")
            }
            Section {
                DatePicker("First midday question", selection: time(\.midday), displayedComponents: .hourAndMinute)
            } footer: {
                let times = draft.middayTimes(count: model.settings.rules.middayQuestions).map(\.label)
                Text(times.isEmpty ? "Midday questions are off in Unlock rules." : "Questions at \(times.joined(separator: ", ")). Each relocks apps until answered.")
            }
            Section {
                Button("Save times") {
                    var c = model.settings.config
                    c.schedule = draft
                    flow.submit(c, model: model) { dismiss() }
                }
                .disabled(draft == model.settings.schedule)
            } footer: {
                Text("A later morning lock is an easier change, so your protections apply.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Morning and midday")
        .onAppear { if !loaded { draft = model.settings.schedule; loaded = true } }
        .saveFlow(flow)
    }

    private func time(_ key: WritableKeyPath<Schedule, TimeOfDay>) -> Binding<Date> {
        Binding(
            get: { draft[keyPath: key].date(on: Date()) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft[keyPath: key] = TimeOfDay(hour: c.hour ?? 0, minute: c.minute ?? 0)
            }
        )
    }
}

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = Rules()
    @State private var loaded = false
    @State private var flow = SaveFlow()

    var body: some View {
        Form {
            ForEach(RuleField.allCases) { field in
                Section {
                    if field == .unlock {
                        Picker(field.title, selection: Binding(get: { draft.unlockMinutes }, set: { draft.unlockMinutes = $0 })) {
                            ForEach(Rules.unlockChoices, id: \.self) { Text(Rules.unlockLabel($0)).tag($0) }
                        }
                    } else {
                        Stepper(value: binding(field), in: range(field), step: field.step) {
                            LabeledContent(field.title, value: field.valueLabel(field.get(draft)))
                        }
                    }
                } footer: {
                    Text(field.detail)
                }
            }
            Section {
                Button("Save rules") {
                    var c = model.settings.config
                    c.rules = draft
                    flow.submit(c, model: model) { draft = model.settings.rules }
                }
                .disabled(draft == model.settings.rules)
            } footer: {
                Text("Stricter rules apply right away. Easier ones go through the protections you set.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Unlock rules")
        .onAppear { if !loaded { draft = model.settings.rules; loaded = true } }
        .saveFlow(flow)
    }

    private func range(_ f: RuleField) -> ClosedRange<Int> {
        f == .pass ? 1...draft.questionsPerCheck : f.range
    }

    private func binding(_ f: RuleField) -> Binding<Int> {
        Binding(
            get: { f.get(draft) },
            set: { v in
                f.set(&draft, v)
                if f == .questions { draft.correctToPass = min(draft.correctToPass, v) }
            }
        )
    }
}

// MARK: - Protection

struct ProtectionView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = Protection()
    @State private var loaded = false
    @State private var setupShown = false
    @State private var flow = SaveFlow()

    var body: some View {
        Form {
            Section {
                Text("Pick any mix. These only apply when a change makes Phos easier. Making it stricter always works right away.")
                    .font(.footnote).foregroundStyle(Theme.dim)
            }

            Section {
                if draft.hasPasscode {
                    Label("Passcode is on", systemImage: "lock.shield.fill").foregroundStyle(Theme.green)
                    Button("Change passcode") { setupShown = true }
                    Button("Remove passcode", role: .destructive) {
                        draft.passcodeHash = nil
                        draft.passcodeSalt = nil
                    }
                    if let reset = model.settings.protection.passcodeResetAt {
                        Text("Your passcode clears \(reset.formatted(.dateTime.weekday(.wide).hour().minute())).").font(.footnote).foregroundStyle(Theme.dim)
                    } else if model.settings.protection.hasPasscode {
                        Button("I forgot my passcode") { model.forgotPasscode() }.font(.footnote)
                    }
                } else {
                    Button("Set a passcode") { setupShown = true }
                }
            } header: {
                Text("Passcode")
            } footer: {
                Text("Asked before any easier change. For real accountability, have a friend type it and keep it. A forgotten passcode clears after 24 hours.")
            }

            Section {
                Picker("Wait before easier changes", selection: $draft.delayHours) {
                    Text("Right away").tag(0)
                    Text("1 hour").tag(1)
                    Text("12 hours").tag(12)
                    Text("24 hours").tag(24)
                    Text("48 hours").tag(48)
                    Text("72 hours").tag(72)
                }
            } footer: {
                Text("Easier changes are saved but only start after this wait.")
            }

            Section {
                Picker("Countdown before saving", selection: $draft.cooldownMinutes) {
                    Text("Off").tag(0)
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                }
            } footer: {
                Text("You stay on a countdown screen before an easier change saves. Leave the app and it starts over.")
            }

            Section {
                Toggle("Only after today's reading", isOn: $draft.onlyAfterReading)
            } footer: {
                Text("Settings can only get easier once you have read today.")
            }

            Section {
                Toggle("Commit until a date", isOn: Binding(
                    get: { draft.commitUntil != nil },
                    set: { draft.commitUntil = $0 ? Calendar.current.date(byAdding: .day, value: 7, to: Date()) : nil }
                ))
                if draft.commitUntil != nil {
                    DatePicker("Until", selection: Binding(
                        get: { draft.commitUntil ?? Date() },
                        set: { draft.commitUntil = $0 }
                    ), in: Date().addingTimeInterval(3600)...Date().addingTimeInterval(90 * 86_400), displayedComponents: [.date, .hourAndMinute])
                }
            } footer: {
                Text("No easier changes at all until then, not even with your passcode. Emergency passes still work.")
            }

            Section {
                Toggle("Block deleting apps while locked", isOn: $draft.preventAppRemoval)
            } footer: {
                Text("While any lock is on, iOS will not let you delete apps, including Phos.")
            }

            Section {
                Button("Save protection") {
                    var c = model.settings.config
                    var p = draft
                    p.passcodeResetAt = model.settings.protection.passcodeResetAt
                    c.protection = p
                    flow.submit(c, model: model) { draft = model.settings.protection }
                }
                .disabled(draft == model.settings.protection)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Protection")
        .onAppear { if !loaded { draft = model.settings.protection; loaded = true } }
        .sheet(isPresented: $setupShown) {
            PasscodeSetupSheet { code in
                let made = Passcode.make(code)
                draft.passcodeHash = made.hash
                draft.passcodeSalt = made.salt
            }
        }
        .saveFlow(flow)
    }
}

struct PasscodeEntrySheet: View {
    @Environment(AppModel.self) private var model
    var onSuccess: () -> Void
    var onCancel: () -> Void
    @State private var code = ""
    @State private var wrong = false
    @State private var forgotNote = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill").font(.system(size: 44)).foregroundStyle(Theme.gold).padding(.top, 30)
            Text("Enter your Phos passcode").font(Theme.serif(26)).foregroundStyle(Theme.ink)
            Text("This change makes Phos easier.").foregroundStyle(Theme.dim)
            SecureField("Passcode", text: $code)
                .keyboardType(.numberPad)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(wrong ? Theme.red : Theme.line))
                .focused($focused)
            if wrong { Text("That passcode is not right.").font(.footnote).foregroundStyle(Theme.red) }
            Button("Continue") {
                if model.checkPasscode(code) { onSuccess() } else { wrong = true; code = "" }
            }
            .buttonStyle(.phos)
            .disabled(code.count < 4)
            Button("Cancel") { onCancel() }.buttonStyle(.phosQuiet)
            if forgotNote || model.settings.protection.passcodeResetAt != nil {
                Text("Your passcode clears 24 hours after you asked. Then you can set a new one.").font(.footnote).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            } else {
                Button("I forgot my passcode") { model.forgotPasscode(); forgotNote = true }.font(.footnote).foregroundStyle(Theme.dim)
            }
            Spacer()
        }
        .padding(24)
        .background(Theme.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
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
            Image(systemName: "lock.shield").font(.system(size: 44)).foregroundStyle(Theme.gold).padding(.top, 30)
            Text(confirming ? "Type it again" : "Choose a passcode").font(Theme.serif(26)).foregroundStyle(Theme.ink)
            Text("4 to 8 digits. Pick one you will not guess in a weak moment, or let a friend choose it.")
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
        .preferredColorScheme(.light)
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
                Text("This change makes Phos easier. Stay here until the countdown ends. Leaving starts it over.")
                    .foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                RingProgress(value: 1 - left / total, lineWidth: 10) {
                    Text(countdownText(left)).font(Theme.serif(48)).monospacedDigit().foregroundStyle(Theme.ink)
                }
                .frame(width: 220, height: 220)
                Text("“Be still, and know that I am God.” Psalm 46:10").font(Theme.serif(17, .regular)).italic().foregroundStyle(Theme.dim)
                Spacer()
                Button(left > 0 ? "Waiting" : "Save the change") { onDone() }
                    .buttonStyle(.phos).disabled(left > 0)
                Button("Never mind") { onCancel() }.buttonStyle(.phosQuiet)
            }
            .padding(24)
        }
        .background(Theme.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onChange(of: phase) { _, p in if p != .active { start = Date() } }
    }
}

/// A faithful preview of the lock screen people see on a locked app.
struct ShieldPreview: View {
    @Environment(AppModel.self) private var model
    let style: ShieldStyle
    var app = "Instagram"
    var large = false

    var body: some View {
        let snap = model.store.snapshot
        VStack(spacing: large ? 22 : 14) {
            Spacer(minLength: large ? 60 : 10)
            Image("LaunchLogo").resizable().scaledToFit()
                .frame(width: large ? 110 : 64, height: large ? 110 : 64)
                .clipShape(RoundedRectangle(cornerRadius: large ? 26 : 15, style: .continuous))
            Text(title(snap)).font(.system(size: large ? 30 : 20, weight: .bold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            Text(subtitle(snap)).font(.system(size: large ? 19 : 14)).foregroundStyle(Theme.dim).multilineTextAlignment(.center).padding(.horizontal, 20)
            Spacer(minLength: large ? 80 : 10)
            VStack(spacing: 6) {
                Text(button).font(.system(size: large ? 19 : 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: large ? 58 : 46)
                    .background(Theme.gold, in: RoundedRectangle(cornerRadius: large ? 16 : 12, style: .continuous))
                Text("Close").font(.system(size: large ? 18 : 14, weight: .semibold)).foregroundStyle(Theme.gold).frame(minHeight: large ? 48 : 36)
            }
            .padding(.horizontal, large ? 24 : 16)
        }
        .padding(.vertical, large ? 30 : 16)
        .frame(maxWidth: .infinity)
        .frame(height: large ? nil : 360)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: large ? 0 : 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: large ? 0 : 24, style: .continuous).stroke(Theme.line, lineWidth: large ? 0 : 1))
    }

    private func title(_ s: SharedSnapshot) -> String {
        switch style {
        case .verse: return "\(app) is locked"
        case .streak: return s.streak > 0 ? "Day \(s.streak + 1) is waiting" : "Start your streak"
        case .quiet: return "Locked until you read"
        }
    }

    private func subtitle(_ s: SharedSnapshot) -> String {
        switch style {
        case .verse: return "“\(s.verseText)”\n\(s.verseRef)"
        case .streak: return "Read \(s.chapterTitle) to keep your \(s.streak) day streak and open \(app)."
        case .quiet: return "Phos opens your apps after today's chapter."
        }
    }

    private var button: String {
        switch style {
        case .verse: return "Unlock with today's reading"
        case .streak: return "Keep my streak"
        case .quiet: return "Open Phos"
        }
    }
}
