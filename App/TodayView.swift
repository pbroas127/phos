import SwiftUI

struct TodayScreen: View {
    @Environment(AppModel.self) private var model
    @State private var view = DemoScreen.todayView
    @State private var chapterPicker = false

    enum Mode: String, CaseIterable, Identifiable {
        case plan = "Plan", path = "Path", calendar = "Calendar"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: model.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        Text(model.greeting).font(Theme.serif(34)).foregroundStyle(Theme.ink)
                    }
                    Picker("View", selection: $view) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    LockBanner()

                    switch view {
                    case .plan: PlanCard(chapterPicker: $chapterPicker)
                    case .path: PathView()
                    case .calendar: CalendarView()
                    }
                }
                .padding(20)
            }
            .background(Theme.paper.ignoresSafeArea())
            .sheet(isPresented: $chapterPicker) { ChapterPicker().environment(model) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// Status of the lock with the one action that matters right now.
struct LockBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let reason = model.lockReason
        if model.today.readingDone || reason == .evening {
            CardBox(padding: 16, fill: Theme.soft) {
                HStack(spacing: 14) {
                    Image(systemName: reason == .none ? "lock.open.fill" : "lock.fill")
                        .font(.title3).foregroundStyle(Theme.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(reason)).font(.headline).foregroundStyle(Theme.ink)
                        Text(detail(reason)).font(.subheadline).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    if let action = action(reason) {
                        Button(action.0) { action.1() }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Theme.gold, in: Capsule()).foregroundStyle(.white)
                    }
                }
            }
        }
    }

    private func title(_ r: LockReason) -> String {
        switch r {
        case .none: return "Apps are open"
        case .midday: return "Midday question"
        case .evening: return "Evening lock"
        default: return "Apps are resting"
        }
    }

    private func detail(_ r: LockReason) -> String {
        switch r {
        case .none: return model.today.unlockedUntil.map { "Until \($0.shortTime)" } ?? ""
        case .midday: return "One question opens them"
        case .evening: return "Open again in the morning"
        default: return "One question opens them"
        }
    }

    private func action(_ r: LockReason) -> (String, () -> Void)? {
        switch r {
        case .none: return ("Lock now", { model.lockNow() })
        case .recall, .midday: return ("Answer", { model.route = .recall })
        case .evening: return ("Passes", { model.route = .emergency })
        case .reading: return nil
        }
    }
}

struct PlanCard: View {
    @Environment(AppModel.self) private var model
    @Binding var chapterPicker: Bool

    var body: some View {
        let ref = model.todaysChapter
        let chapter = Bible.shared.chapter(ref)
        VStack(alignment: .leading, spacing: 16) {
            CardBox(padding: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: model.planFinished && !model.today.readingDone ? "Plan complete" : "\(model.plan.name) · day \(model.planDay) of \(model.plan.chapters.count)")
                    Text(model.todaysTitle).font(Theme.serif(52)).foregroundStyle(Theme.ink).minimumScaleFactor(0.6).lineLimit(1)
                    Text(subtitle(chapter)).font(.subheadline).foregroundStyle(Theme.dim).lineLimit(2)
                    ProgressBar(value: Double(model.planPosition) / Double(max(1, model.plan.chapters.count)))
                        .padding(.top, 6)
                    if let record = model.todaysRecord {
                        Label("Read today · \(record.score) of \(record.total) correct", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.green).padding(.top, 4)
                    }
                }
            }

            if !model.today.readingDone {
                if model.planFinished {
                    Text("You finished \(model.plan.name). Pick a new plan in Settings, or read any chapter.")
                        .font(.subheadline).foregroundStyle(Theme.dim)
                }
                Button("Start reading") { model.route = .reading }.buttonStyle(.phos)
                Button("Read a different chapter") { chapterPicker = true }.buttonStyle(.phosSecondary)
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                    Text(model.lockedCount == 0 ? "Choose apps to lock in Settings" : "\(model.lockedCount) locked until you finish")
                }
                .font(.footnote).foregroundStyle(Theme.dim).frame(maxWidth: .infinity)
            } else {
                OtherUnlocks()
            }
        }
    }

    private func subtitle(_ chapter: BibleChapter?) -> String {
        guard let chapter else { return "" }
        if let t = chapter.title { return t }
        let first = TextChecks.plain(chapter.verses.first ?? "")
        let short = first.count > 70 ? String(first.prefix(70)).trimmingCharacters(in: .whitespaces) + "…" : first
        return "\(chapter.verses.count) verses · \(short)"
    }
}

struct OtherUnlocks: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Other ways to open apps")
            HStack(spacing: 10) {
                tile("Focus session", "iphone.gen3", .focus)
                tile("Recite a verse", "text.quote", .recite)
            }
        }
        .padding(.top, 6)
    }

    private func tile(_ title: String, _ symbol: String, _ route: Route) -> some View {
        Button { model.route = route } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Theme.gold)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
        }
        .buttonStyle(.plain)
    }
}

struct PathView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let chapters = model.plan.chapters
        let pos = model.planPosition
        let current = model.today.readingDone ? pos - 1 : pos
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.plan.name).font(Theme.serif(26)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(min(pos, chapters.count)) of \(chapters.count)").font(.subheadline).foregroundStyle(Theme.dim)
            }
            .padding(.bottom, 12)
            let start = max(0, current - 3)
            let end = min(chapters.count, start + 9)
            ForEach(start..<end, id: \.self) { i in
                let state: NodeState = i == current ? .now : (i < pos ? .done : .next)
                HStack(spacing: 16) {
                    ZStack {
                        if i < end - 1 {
                            Rectangle().fill(Theme.line).frame(width: 3).offset(y: 30)
                        }
                        node(state)
                    }
                    .frame(width: 52, height: state == .now ? 64 : 48)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(BookNames.title(chapters[i]))
                            .font(state == .now ? Theme.serif(24) : .body)
                            .foregroundStyle(state == .next ? Theme.dim : Theme.ink)
                        if state == .now {
                            Text(model.today.readingDone ? "Read today" : "Today").font(.caption.weight(.semibold)).foregroundStyle(Theme.gold)
                        }
                    }
                    Spacer()
                }
            }
            if !model.today.readingDone {
                Button("Start \(model.todaysTitle)") { model.route = .reading }.buttonStyle(.phos).padding(.top, 16)
            }
        }
    }

    enum NodeState { case done, now, next }

    @ViewBuilder
    private func node(_ s: NodeState) -> some View {
        switch s {
        case .done:
            Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Theme.gold, in: Circle())
        case .now:
            Image(systemName: "book.fill").foregroundStyle(Theme.gold)
                .frame(width: 46, height: 46).background(Theme.card, in: Circle())
                .overlay(Circle().stroke(Theme.gold, lineWidth: 3))
        case .next:
            Circle().fill(Theme.card).frame(width: 30, height: 30).overlay(Circle().stroke(Theme.line, lineWidth: 2))
        }
    }
}

struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @State private var monthOffset = 0

    var body: some View {
        let cal = Calendar.current
        let month = cal.date(byAdding: .month, value: monthOffset, to: cal.date(from: cal.dateComponents([.year, .month], from: model.now))!)!
        let days = cal.range(of: .day, in: .month, for: month)!.count
        let lead = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        let done = Set(model.records.map(\.dayKey))
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(Theme.serif(26)).foregroundStyle(Theme.ink)
                Spacer()
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }.disabled(monthOffset >= 0)
            }
            .foregroundStyle(Theme.gold)
            let symbols = cal.veryShortWeekdaySymbols
            let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(0..<7, id: \.self) { Text(ordered[$0]).font(.caption.weight(.semibold)).foregroundStyle(Theme.dim) }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 38) }
                ForEach(1...days, id: \.self) { day in
                    let date = cal.date(byAdding: .day, value: day - 1, to: month)!
                    let key = String(format: "%04d-%02d-%02d", cal.component(.year, from: date), cal.component(.month, from: date), day)
                    let isToday = key == model.today.dayKey
                    Text("\(day)")
                        .font(.subheadline.weight(done.contains(key) || isToday ? .semibold : .regular))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(done.contains(key) ? Color.white : (isToday ? Theme.ink : Theme.dim))
                        .background(done.contains(key) ? Theme.gold : Color.clear, in: Circle())
                        .overlay(Circle().stroke(isToday && !done.contains(key) ? Theme.gold : .clear, lineWidth: 2))
                }
            }
            CardBox {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: "Today")
                        Text(model.todaysTitle).font(Theme.serif(24)).foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Label("\(model.streak)", systemImage: "flame.fill").font(.headline).foregroundStyle(Theme.gold)
                }
            }
            if !model.today.readingDone {
                Button("Start reading") { model.route = .reading }.buttonStyle(.phos)
            }
        }
    }
}

struct ChapterPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Any chapter unlocks your apps. Only chapters from your plan count toward your streak.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                }
                ForEach(QuestionBank.shared.coveredBooks, id: \.self) { book in
                    NavigationLink(BookNames.name(book)) {
                        List {
                            ForEach(ReadingPlans.book(book).filter(QuestionBank.shared.has)) { ref in
                                Button(BookNames.title(ref)) {
                                    model.beginReading(ref)
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.route = .reading }
                                }
                                .foregroundStyle(Theme.ink)
                            }
                        }
                        .navigationTitle(BookNames.name(book))
                    }
                }
            }
            .navigationTitle("Choose a chapter")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
