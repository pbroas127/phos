import FamilyControls
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var pickerShown = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Button { pickerShown = true } label: {
                        HStack {
                            Label("Locked apps", systemImage: "lock.app.dashed").foregroundStyle(Theme.ink)
                            Spacer()
                            Text(model.lockedCount == 0 ? "None" : "\(model.lockedCount) chosen").foregroundStyle(Theme.dim)
                        }
                    }
                    if !model.authorized {
                        Button("Allow Screen Time access") { Task { await model.requestAuthorization() } }
                    }
                } footer: {
                    Text("Phone, Messages, and Maps can never be locked.")
                }

                Section("Reading") {
                    NavigationLink {
                        ScrollView { PlanList().padding(20) }
                            .background(Theme.paper)
                            .navigationTitle("Reading plan")
                            .toolbar {
                                Button("Restart plan") { model.restartPlan() }
                            }
                    } label: {
                        LabeledContent("Plan", value: model.plan.name)
                    }
                    Picker("Reading style", selection: $model.settings.preferredRead) {
                        ForEach(ReadMode.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Reflection style", selection: $model.settings.preferredReflect) {
                        ForEach(ReflectMode.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    DatePicker("Morning lock", selection: timeBinding(\.morning), displayedComponents: .hourAndMinute)
                    if model.settings.rules.middayQuestions > 0 {
                        DatePicker("First midday question", selection: timeBinding(\.midday), displayedComponents: .hourAndMinute)
                    }
                    Toggle("Evening lock", isOn: $model.settings.schedule.eveningOn)
                    if model.settings.schedule.eveningOn {
                        DatePicker("Evening lock starts", selection: timeBinding(\.evening), displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text(scheduleFooter)
                }

                Section("Rules") {
                    NavigationLink {
                        RulesView()
                    } label: {
                        LabeledContent("Unlock rules", value: "\(model.settings.rules.questionsPerCheck) questions, \(Rules.unlockLabel(model.settings.rules.unlockMinutes))")
                    }
                    if model.settings.pendingRules != nil {
                        Label("Easier rules are waiting", systemImage: "clock").foregroundStyle(Theme.gold)
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
                    Link("Help and support", destination: URL(string: "https://phos-app.vercel.app/support")!)
                    Link("Privacy policy", destination: URL(string: "https://phos-app.vercel.app/privacy")!)
                    LabeledContent("Bible text", value: "World English Bible")
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Settings")
            .onChange(of: model.settings.schedule) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.shieldStyle) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.preferredRead) { _, _ in model.saveSettings() }
            .onChange(of: model.settings.preferredReflect) { _, _ in model.saveSettings() }
            .familyActivityPicker(isPresented: $pickerShown, selection: Binding(
                get: { model.selection },
                set: { model.updateSelection($0) }
            ))
        }
    }

    private var scheduleFooter: String {
        let times = model.settings.schedule.middayTimes(count: model.settings.rules.middayQuestions).map(\.label)
        var text = "Apps lock at \(model.settings.schedule.morning.label) until you read."
        if !times.isEmpty { text += " Midday questions at \(times.joined(separator: ", "))." }
        if model.settings.schedule.eveningOn { text += " Evening lock keeps apps closed until morning, except for emergency passes." }
        return text
    }

    private func timeBinding(_ key: WritableKeyPath<Schedule, TimeOfDay>) -> Binding<Date> {
        Binding(
            get: { model.settings.schedule[keyPath: key].date(on: Date()) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.settings.schedule[keyPath: key] = TimeOfDay(hour: c.hour ?? 0, minute: c.minute ?? 0)
            }
        )
    }
}

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = Rules()
    @State private var loaded = false

    var body: some View {
        Form {
            if let pending = model.settings.pendingRules {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Easier rules start \(pending.effectiveAt.formatted(.dateTime.weekday(.wide).hour().minute()))", systemImage: "clock")
                            .font(.headline).foregroundStyle(Theme.gold)
                        Text("Stricter changes apply right away. Easier ones wait a day so a tired moment cannot undo your plan.")
                            .font(.footnote).foregroundStyle(Theme.dim)
                        Button("Cancel the waiting change") { model.cancelPendingRules(); draft = model.settings.rules }
                            .font(.footnote.weight(.semibold))
                    }
                }
            }
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
                Toggle("Wait a day before easier rules apply", isOn: $draft.delayEasierChanges)
            } footer: {
                Text("Recommended. Turning this off is also an easier change, so it waits a day too.")
            }
            Section {
                Button("Save rules") {
                    model.proposeRules(draft)
                    draft = model.settings.rules
                }
                .disabled(draft == model.settings.rules)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Unlock rules")
        .onAppear {
            if !loaded { draft = model.settings.rules; loaded = true }
        }
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
            Group {
                if style == .streak {
                    Image(systemName: "flame.fill").foregroundStyle(.white)
                } else {
                    Image(systemName: "sun.max.fill").foregroundStyle(.white)
                }
            }
            .font(.system(size: large ? 44 : 28))
            .frame(width: large ? 96 : 60, height: large ? 96 : 60)
            .background(Theme.gold, in: RoundedRectangle(cornerRadius: large ? 24 : 15, style: .continuous))
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
