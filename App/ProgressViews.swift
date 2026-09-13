import DeviceActivity
import FamilyControls
import SwiftUI

struct ProgressScreen: View {
    @Environment(AppModel.self) private var model
    @State private var tab = DemoScreen.progressTab

    enum Tab: String, CaseIterable, Identifiable {
        case streak = "Streak", time = "Time won back", journal = "Journal"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Progress").font(Theme.serif(34)).foregroundStyle(Theme.ink)
                    Picker("Progress", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch tab {
                    case .streak: StreakView()
                    case .time: TimeWonBackView()
                    case .journal: JournalView()
                    }
                }
                .padding(20)
            }
            .background(Theme.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct StreakView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let keys = model.doneKeys
        let week = (0..<7).reversed().map { DayKey.adding(-$0, to: model.today.dayKey) }
        VStack(spacing: 14) {
            CardBox(padding: 26) {
                VStack(spacing: 8) {
                    Image(systemName: "flame.fill").font(.system(size: 46)).foregroundStyle(Theme.gold)
                    Text("\(model.streak)").font(Theme.serif(76)).foregroundStyle(Theme.ink)
                    Text(model.streak == 1 ? "day in a row" : "days in a row").foregroundStyle(Theme.dim)
                    HStack(spacing: 10) {
                        ForEach(week, id: \.self) { key in
                            let done = keys.contains(key)
                            VStack(spacing: 5) {
                                ZStack {
                                    Circle().fill(done ? Theme.gold : Color.clear)
                                    Circle().strokeBorder(done ? Color.clear : Theme.gold.opacity(key == model.today.dayKey ? 1 : 0.3), style: StrokeStyle(lineWidth: 2, dash: key == model.today.dayKey ? [4, 3] : []))
                                    if done { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) }
                                }
                                .frame(width: 34, height: 34)
                                Text(DayKey.localDate(from: key)?.formatted(.dateTime.weekday(.narrow)) ?? "").font(.caption2).foregroundStyle(Theme.dim)
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 12) {
                stat("\(model.records.count)", "chapters read")
                stat("\(model.records.map(\.readingSeconds).reduce(0, +) / 60)", "minutes in the Word")
            }
            HStack(spacing: 12) {
                stat("\(Streaks.longest(doneKeys: keys))", "longest streak")
                stat("\(model.readCount(model.plan)) of \(model.plan.chapters.count)", model.plan.name)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        CardBox(padding: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(Theme.serif(28)).foregroundStyle(Theme.ink).minimumScaleFactor(0.6).lineLimit(1)
                Text(label).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
            }
        }
    }
}

struct TimeWonBackView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardBox(padding: 0) {
                if model.demo {
                    WeeklyUsageView(usage: DemoData.usage)
                } else {
                    DeviceActivityReport(.weekly, filter: filter)
                        .frame(minHeight: 640)
                }
            }
            let readingMinutes = model.records.filter { record in
                guard let d = DayKey.date(from: record.dayKey), let today = DayKey.date(from: model.today.dayKey) else { return false }
                return today.timeIntervalSince(d) < 7 * 86_400
            }.map(\.readingSeconds).reduce(0, +) / 60
            CardBox {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: "In the Word this week")
                        Text("\(readingMinutes) minutes").font(Theme.serif(28)).foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Image(systemName: "book.fill").font(.title).foregroundStyle(Theme.gold)
                }
            }
            Text("Usage comes from Apple's Screen Time and stays on your iPhone.").font(.caption).foregroundStyle(Theme.dim)
        }
    }

    private var filter: DeviceActivityFilter {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -13, to: cal.startOfDay(for: Date())) ?? Date()
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: Date())),
            users: .all,
            devices: .init([.iPhone]),
            applications: model.reportSelection.applicationTokens,
            categories: model.reportSelection.categoryTokens,
            webDomains: model.reportSelection.webDomainTokens
        )
    }
}

struct JournalView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let entries = model.records.sorted { $0.completedAt > $1.completedAt }
        VStack(alignment: .leading, spacing: 12) {
            if entries.isEmpty {
                CardBox {
                    Text("Your reflections will collect here, one for every chapter you read.").foregroundStyle(Theme.dim)
                }
            }
            ForEach(entries) { entry in
                CardBox(padding: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Eyebrow(text: "\(entry.completedAt.formatted(.dateTime.month(.abbreviated).day())) · \(entry.title)")
                            Spacer()
                            Image(systemName: entry.reflectMode.symbol).font(.caption).foregroundStyle(Theme.dim)
                        }
                        Text(entry.reflection.isEmpty ? "No reflection saved." : entry.reflection)
                            .font(Theme.serif(17, .regular)).foregroundStyle(Theme.ink).lineSpacing(3)
                        HStack {
                            Text("\(entry.score) of \(entry.total) correct").font(.caption).foregroundStyle(Theme.dim)
                            Spacer()
                            if let bp = ReadingPlans.bookPlan(entry.ref.book), let i = bp.chapters.firstIndex(of: entry.ref) {
                                Button("Read again") {
                                    model.choose(planID: bp.id, index: i)
                                    model.route = .reading
                                }
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.gold)
                            }
                        }
                    }
                }
            }
        }
    }
}
