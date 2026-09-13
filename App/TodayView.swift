import SwiftUI

struct TodayScreen: View {
    @Environment(AppModel.self) private var model
    @State private var view = DemoScreen.todayView
    @State private var libraryShown = DemoScreen.requested == .library
    @State private var picked: ChapterPick?

    enum Mode: String, CaseIterable, Identifiable {
        case plan = "Plan", path = "Path", calendar = "Calendar"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Eyebrow(text: model.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            Text(model.greeting).font(Theme.serif(34)).foregroundStyle(Theme.ink)
                        }
                        Spacer()
                        Button { libraryShown = true } label: {
                            Label("Books", systemImage: "books.vertical")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Theme.soft, in: Capsule())
                                .foregroundStyle(Theme.ink)
                        }
                        .padding(.top, 6)
                    }
                    Picker("View", selection: $view) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    LockBanner()

                    switch view {
                    case .plan:
                        PlanCard(libraryShown: $libraryShown)
                        TodayTrophies().padding(.top, 8)
                    case .path: PathView(picked: $picked, libraryShown: $libraryShown)
                    case .calendar: CalendarView(picked: $picked)
                    }

                }
                .padding(20)
            }
            .background(Theme.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $libraryShown) {
                LibraryView { pick in startReading(pick, closing: { libraryShown = false }) }
                    .environment(model)
            }
            .sheet(item: $picked) { pick in
                ChapterActionSheet(pick: pick) { p in startReading(p, closing: { picked = nil }) }
                    .environment(model)
                    .presentationDetents([.medium])
            }
        }
    }

    /// Chooses the chapter, closes whatever sheet is open, then opens the reading.
    private func startReading(_ pick: ChapterPick, closing: () -> Void) {
        model.choose(planID: pick.planID, index: pick.index)
        closing()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { model.route = .reading }
    }
}

/// Status of the locks with the one action that matters right now.
struct LockBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let locked = model.lockedLocks
        let open = model.locks.filter { model.state($0) == .open }
        if model.today.readingDone && (!locked.isEmpty || !open.isEmpty) {
            Button { model.route = .unlock } label: {
                CardBox(padding: 16, fill: Theme.soft) {
                    HStack(spacing: 14) {
                        Image(systemName: locked.isEmpty ? "lock.open.fill" : "lock.fill")
                            .font(.title3).foregroundStyle(Theme.gold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(locked.isEmpty ? "Apps are open" : "\(locked.map(\.name).joined(separator: ", ")) locked")
                                .font(.headline).foregroundStyle(Theme.ink).lineLimit(1)
                            Text(detail(locked: locked, open: open)).font(.subheadline).foregroundStyle(Theme.dim).lineLimit(1)
                        }
                        Spacer()
                        Text(locked.isEmpty ? "Details" : "Unlock")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Theme.gold, in: Capsule()).foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func detail(locked: [LockSet], open: [LockSet]) -> String {
        if let first = locked.first {
            switch model.state(first) {
            case .needsQuestion: return "One question opens it"
            case .needsTap: return "Tap to unlock"
            case .usedUp: return "No unlocks left today"
            case .strict: return "Strict until \(LockLogic.activeEnd(first, now: Date()).shortTime)"
            default: return "Tap to see how to unlock"
            }
        }
        let until = open.compactMap { model.today.day($0.id).until ?? model.today.day($0.id).passUntil }.min()
        return until.map { "Next lock at \($0.shortTime)" } ?? "Open"
    }
}

struct PlanCard: View {
    @Environment(AppModel.self) private var model
    @Binding var libraryShown: Bool

    var body: some View {
        let ref = model.todaysChapter
        let chapter = Bible.shared.chapter(ref)
        let doneNow = model.currentChapterDoneToday
        let inPath = model.plan.chapters.contains(ref)
        VStack(alignment: .leading, spacing: 16) {
            CardBox(padding: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: eyebrow(inPath: inPath))
                    Text(model.todaysTitle).font(Theme.serif(52)).foregroundStyle(Theme.ink).minimumScaleFactor(0.6).lineLimit(1)
                    if let title = ChapterTitles.title(ref) {
                        Text(title).font(Theme.serif(21, .regular)).foregroundStyle(Theme.ink).lineLimit(2)
                    }
                    Text(subtitle(chapter)).font(.subheadline).foregroundStyle(Theme.dim).lineLimit(1)
                    ProgressBar(value: Double(model.readCount(model.plan)) / Double(max(1, model.plan.chapters.count)))
                        .padding(.top, 6)
                    HStack {
                        Text("\(model.readCount(model.plan)) of \(model.plan.chapters.count) chapters read in \(model.plan.name)")
                            .font(.caption).foregroundStyle(Theme.dim)
                        Spacer()
                    }
                    if doneNow, let record = model.record(for: ref) {
                        Label("Read today · \(record.score) of \(record.total) correct", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.green).padding(.top, 4)
                    }
                }
            }

            if model.planFinished && !doneNow && inPath {
                CardBox(fill: Theme.soft) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("You finished \(model.plan.name)", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Theme.ink)
                        HStack(spacing: 10) {
                            Button("Pick next book") { libraryShown = true }.buttonStyle(.phos)
                            Button("Restart") { model.restart(model.plan.id) }.buttonStyle(.phosSecondary)
                        }
                    }
                }
            } else if !doneNow {
                Button(model.draft(for: ref) == nil ? "Start reading" : "Continue where you left off") { model.route = .reading }.buttonStyle(.phos)
                Button("Choose a different chapter") { libraryShown = true }.buttonStyle(.phosSecondary)
                if !model.today.readingDone {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                        Text(model.lockedCount == 0 ? "Add a lock in Settings" : "\(model.lockedCount) locked until you finish")
                    }
                    .font(.footnote).foregroundStyle(Theme.dim).frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 10) {
                    if !model.planFinished {
                        Button("Read \(BookNames.title(model.plan.chapters[model.planPosition])) next") {
                            model.choose(planID: model.plan.id, index: model.planPosition)
                            model.route = .reading
                        }
                        .buttonStyle(.phosSecondary)
                    }
                    Button("Choose another chapter") { libraryShown = true }.buttonStyle(.phosQuiet)
                }
            }
        }
    }

    private func eyebrow(inPath: Bool) -> String {
        guard inPath else { return "Chosen chapter" }
        if model.planFinished && !model.currentChapterDoneToday { return "\(model.plan.name) · finished" }
        return "\(model.plan.name) · chapter \(model.planDay) of \(model.plan.chapters.count)"
    }

    private func subtitle(_ chapter: BibleChapter?) -> String {
        guard let chapter else { return "" }
        return chapter.verses.count == 1 ? "1 verse" : "\(chapter.verses.count) verses"
    }
}

/// The active path as a trail. Tap any chapter to read it, reread it, or make it the next one.
struct PathView: View {
    @Environment(AppModel.self) private var model
    @Binding var picked: ChapterPick?
    @Binding var libraryShown: Bool
    @State private var showAll = false
    @State private var confirmRestart = false

    var body: some View {
        let plan = model.plan
        let chapters = plan.chapters
        let pos = model.planPosition
        let read = model.readIDs
        let start = showAll ? 0 : max(0, min(pos, chapters.count - 1) - 3)
        let end = showAll ? chapters.count : min(chapters.count, start + 9)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name).font(Theme.serif(26)).foregroundStyle(Theme.ink)
                    Text("\(model.readCount(plan)) of \(chapters.count) read").font(.subheadline).foregroundStyle(Theme.dim)
                }
                Spacer()
                Menu {
                    Button("Change book or plan", systemImage: "books.vertical") { libraryShown = true }
                    Button("Restart \(plan.name)", systemImage: "arrow.counterclockwise") { confirmRestart = true }
                    Button(showAll ? "Show fewer chapters" : "Show every chapter", systemImage: "list.bullet") { showAll.toggle() }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title2).foregroundStyle(Theme.gold)
                }
            }
            .padding(.bottom, 12)
            ForEach(start..<end, id: \.self) { i in
                let ref = chapters[i]
                let isRead = read.contains(ref.id)
                let state: NodeState = i == pos ? .now : (isRead ? .done : .next)
                Button { picked = ChapterPick(planID: plan.id, index: i) } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            if i < end - 1 {
                                Rectangle().fill(Theme.line).frame(width: 3).offset(y: 30)
                            }
                            node(state)
                        }
                        .frame(width: 52, height: state == .now ? 64 : 48)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(BookNames.title(ref))
                                .font(state == .now ? Theme.serif(24) : .body)
                                .foregroundStyle(state == .next ? Theme.dim : Theme.ink)
                            if state == .now {
                                Text("Next up").font(.caption.weight(.semibold)).foregroundStyle(Theme.gold)
                            } else if let d = model.lastRead(ref) {
                                Text("Read \(d.formatted(.dateTime.month(.abbreviated).day()))").font(.caption).foregroundStyle(Theme.dim)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.line)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if pos >= chapters.count {
                CardBox(fill: Theme.soft) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("You finished \(plan.name)", systemImage: "checkmark.seal.fill").font(.headline)
                        HStack {
                            Button("Pick next book") { libraryShown = true }.buttonStyle(.phos)
                            Button("Restart") { confirmRestart = true }.buttonStyle(.phosSecondary)
                        }
                    }
                }
                .padding(.top, 12)
            } else if !model.currentChapterDoneToday || model.todaysChapter != chapters[pos] {
                Button("Read \(BookNames.title(chapters[pos]))") {
                    model.choose(planID: plan.id, index: pos)
                    model.route = .reading
                }
                .buttonStyle(.phos).padding(.top, 16)
            }
        }
        .confirmationDialog("Restart \(plan.name)?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Restart from the beginning") { model.restart(plan.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your place goes back to the first chapter. What you already read stays in your journal.")
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
    @Binding var picked: ChapterPick?
    @State private var monthOffset = 0
    @State private var selectedKey: String?

    var body: some View {
        let cal = Calendar.current
        let month = cal.date(byAdding: .month, value: monthOffset, to: cal.date(from: cal.dateComponents([.year, .month], from: model.now))!)!
        let days = cal.range(of: .day, in: .month, for: month)!.count
        let lead = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        let done = model.doneKeys
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
                    Button { selectedKey = done.contains(key) ? key : nil } label: {
                        Text("\(day)")
                            .font(.subheadline.weight(done.contains(key) || isToday ? .semibold : .regular))
                            .frame(width: 38, height: 38)
                            .foregroundStyle(done.contains(key) ? Color.white : (isToday ? Theme.ink : Theme.dim))
                            .background(done.contains(key) ? Theme.gold : Color.clear, in: Circle())
                            .overlay(Circle().stroke(selectedKey == key ? Theme.ink : (isToday && !done.contains(key) ? Theme.gold : .clear), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            if let key = selectedKey {
                let dayRecords = model.records.filter { $0.dayKey == key }.sorted { $0.completedAt < $1.completedAt }
                CardBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: DayKey.localDate(from: key)?.formatted(.dateTime.weekday(.wide).month(.wide).day()) ?? key)
                        ForEach(dayRecords) { r in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title).font(Theme.serif(20)).foregroundStyle(Theme.ink)
                                    Text("\(r.score) of \(r.total) correct").font(.caption).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                Button("Read again") {
                                    if let bp = ReadingPlans.bookPlan(r.ref.book), let i = bp.chapters.firstIndex(of: r.ref) {
                                        picked = ChapterPick(planID: bp.id, index: i)
                                    }
                                }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.gold)
                            }
                        }
                    }
                }
            } else {
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
                Text("Tap a gold day to see what you read.").font(.caption).foregroundStyle(Theme.dim)
            }
            if !model.currentChapterDoneToday {
                Button("Start reading") { model.route = .reading }.buttonStyle(.phos)
            }
        }
    }
}
