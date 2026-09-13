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
                        .frame(height: 700)
                        // The report is drawn by another process and swallows swipes. A clear layer on top lets the page scroll.
                        .overlay(Color.white.opacity(0.001))
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
    @State private var mode: Mode = .recent
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var month = Calendar.current.startOfDay(for: Date())
    @State private var openBook: String?

    enum Mode: String, CaseIterable, Identifiable {
        case recent = "Recent", date = "By date", book = "By book"
        var id: String { rawValue }
    }

    var body: some View {
        let entries = model.records.sorted { $0.completedAt > $1.completedAt }
        VStack(alignment: .leading, spacing: 14) {
            Picker("Journal view", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if entries.isEmpty {
                CardBox {
                    Text("Your reflections will collect here, one for every chapter you read.").foregroundStyle(Theme.dim)
                }
            } else {
                switch mode {
                case .recent:
                    ForEach(entries) { JournalEntryRow(entry: $0) }
                case .date:
                    byDate(entries)
                case .book:
                    byBook(entries)
                }
            }
        }
    }

    @ViewBuilder
    private func byDate(_ entries: [DayRecord]) -> some View {
        let cal = Calendar.current
        let days = Set(entries.map { cal.startOfDay(for: $0.completedAt) })
        JournalCalendar(month: $month, selected: $day, marked: days)
        let onDay = entries.filter { cal.isDate($0.completedAt, inSameDayAs: day) }.sorted { $0.completedAt < $1.completedAt }
        Eyebrow(text: day.formatted(.dateTime.weekday(.wide).month(.wide).day())).padding(.top, 4)
        if onDay.isEmpty {
            Text("No readings on this day.").font(.subheadline).foregroundStyle(Theme.dim)
        }
        ForEach(onDay) { JournalEntryRow(entry: $0) }
    }

    @ViewBuilder
    private func byBook(_ entries: [DayRecord]) -> some View {
        // Only books with at least one finished chapter, in Bible order.
        let books = BookNames.order.filter { id in entries.contains { $0.ref.book == id } }
        ForEach(books, id: \.self) { book in
            let chapters = latestPerChapter(entries.filter { $0.ref.book == book })
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { openBook = openBook == book ? nil : book }
                } label: {
                    HStack {
                        Text(BookNames.name(book)).font(Theme.serif(22)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(chapters.count == 1 ? "1 chapter" : "\(chapters.count) chapters").font(.subheadline).foregroundStyle(Theme.dim)
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                            .rotationEffect(.degrees(openBook == book ? 180 : 0))
                    }
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
                }
                .buttonStyle(.plain)
                if openBook == book {
                    ForEach(chapters) { JournalEntryRow(entry: $0) }
                        .padding(.leading, 12)
                }
            }
        }
    }

    /// Each chapter once, using the latest time it was read.
    private func latestPerChapter(_ list: [DayRecord]) -> [DayRecord] {
        var best: [Int: DayRecord] = [:]
        for r in list where (best[r.ref.chapter]?.completedAt ?? .distantPast) < r.completedAt { best[r.ref.chapter] = r }
        return best.values.sorted { $0.ref.chapter < $1.ref.chapter }
    }
}

/// A journal entry that shows just the chapter and date until tapped.
struct JournalEntryRow: View {
    @Environment(AppModel.self) private var model
    let entry: DayRecord
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.headline).foregroundStyle(Theme.ink)
                        Text(entry.completedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                            .font(.caption).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Hides the entry" : "Shows the whole entry")

            if open {
                Text(entry.reflection.isEmpty ? "No reflection saved." : entry.reflection)
                    .font(Theme.serif(17, .regular)).foregroundStyle(Theme.ink).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Label(entry.reflectMode.title, systemImage: entry.reflectMode.symbol).font(.caption).foregroundStyle(Theme.dim)
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
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
    }
}

/// Month grid for the journal. Days with a reading get a gold dot.
struct JournalCalendar: View {
    @Binding var month: Date
    @Binding var selected: Date
    let marked: Set<Date>

    var body: some View {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
        let count = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        let offset = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...]) + Array(symbols[..<(cal.firstWeekday - 1)])
        VStack(spacing: 10) {
            HStack {
                Button { month = cal.date(byAdding: .month, value: -1, to: start) ?? start } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(start.formatted(.dateTime.month(.wide).year())).font(.headline).foregroundStyle(Theme.ink)
                Spacer()
                Button { month = cal.date(byAdding: .month, value: 1, to: start) ?? start } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
            }
            .foregroundStyle(Theme.gold)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(Theme.dim)
                }
                ForEach(0..<(offset + count), id: \.self) { i in
                    cell(i, offset: offset, start: start, cal: cal)
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
    }

    @ViewBuilder
    private func cell(_ i: Int, offset: Int, start: Date, cal: Calendar) -> some View {
        if i < offset {
            Color.clear.frame(height: 38)
        } else {
            let date = cal.date(byAdding: .day, value: i - offset, to: start) ?? start
            let isSelected = cal.isDate(date, inSameDayAs: selected)
            let hasEntry = marked.contains(date)
            Button { selected = date } label: {
                VStack(spacing: 3) {
                    Text("\(i - offset + 1)").font(.subheadline.monospacedDigit())
                        .foregroundStyle(isSelected ? Color.white : Theme.ink)
                    Circle().fill(hasEntry ? (isSelected ? Color.white : Theme.gold) : Color.clear)
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(isSelected ? Theme.gold : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}
