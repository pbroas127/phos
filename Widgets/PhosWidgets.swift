import AppIntents
import SwiftUI
import WidgetKit

// MARK: Data every widget reads

struct WickEntry<Config>: TimelineEntry {
    let date: Date
    let data: WidgetData
    let config: Config
    let verseOffset: Int
    let trophyOffset: Int
    let revealed: Bool
}

private func loadData(preview: Bool) -> WidgetData {
    let store = SharedStore.shared
    return preview && !store.hasWidgetData ? .placeholder : store.widgetData
}

private func makeEntry<C>(_ config: C, preview: Bool) -> WickEntry<C> {
    WickEntry(date: Date(), data: loadData(preview: preview), config: config,
              verseOffset: WidgetData.verseOffset, trophyOffset: WidgetData.trophyOffset, revealed: WidgetData.memoryRevealed)
}

/// Widgets redraw when the app writes new data. This only keeps the day and hour labels honest in between.
private func nextRefresh(after date: Date) -> Date {
    let cal = Calendar.current
    let hour = cal.nextDate(after: date, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? date.addingTimeInterval(3600)
    return min(hour, date.addingTimeInterval(3600))
}

struct WickProvider<Config: WidgetConfigurationIntent>: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WickEntry<Config> { makeEntry(Config(), preview: true) }
    func snapshot(for configuration: Config, in context: Context) async -> WickEntry<Config> { makeEntry(configuration, preview: context.isPreview) }
    func timeline(for configuration: Config, in context: Context) async -> Timeline<WickEntry<Config>> {
        let e = makeEntry(configuration, preview: false)
        return Timeline(entries: [e], policy: .after(nextRefresh(after: e.date)))
    }
}

struct GlanceProvider: TimelineProvider {
    let info: GlanceInfo
    func placeholder(in context: Context) -> WickEntry<GlanceInfo> { makeEntry(info, preview: true) }
    func getSnapshot(in context: Context, completion: @escaping (WickEntry<GlanceInfo>) -> Void) { completion(makeEntry(info, preview: context.isPreview)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WickEntry<GlanceInfo>>) -> Void) {
        let e = makeEntry(info, preview: false)
        completion(Timeline(entries: [e], policy: .after(nextRefresh(after: e.date))))
    }
}

// MARK: Colors

struct W {
    let paper: Color, ink: Color, dim: Color, gold: Color, line: Color, soft: Color

    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static let paperLook = W(paper: hex(0xFBF9F4), ink: hex(0x221D17), dim: hex(0x8A7F71), gold: hex(0xA87A22), line: hex(0xECE5D8), soft: hex(0xF1EDE4))
    static let inkLook = W(paper: hex(0x17140F), ink: hex(0xF3EDE2), dim: hex(0xA89C8B), gold: hex(0xE0AE4B), line: hex(0x3A3229), soft: hex(0x241F18))
    static let goldLook = W(paper: hex(0x1B160F), ink: hex(0xF3DFA6), dim: hex(0xB99A55), gold: hex(0xF5C862), line: hex(0x433520), soft: hex(0x2A2214))

    static func palette(_ look: WidgetLook, _ scheme: ColorScheme) -> W {
        switch look {
        case .paper: return paperLook
        case .ink: return inkLook
        case .gold: return goldLook
        case .system: return scheme == .dark ? inkLook : paperLook
        }
    }
}

private extension WidgetData {
    /// The verse a widget shows, after any shuffles.
    func verse(_ source: VerseSource, offset: Int) -> Verse {
        if source == .chapter && offset == 0 { return keyVerse }
        guard !verses.isEmpty else { return keyVerse }
        let i = source == .chapter ? offset - 1 : offset
        return verses[((i % verses.count) + verses.count) % verses.count]
    }

    var streakLine: String {
        if readToday { return streak == 1 ? "Day 1. Read today." : "\(streak) days. Read today." }
        let evening = Calendar.current.component(.hour, from: Date()) >= 18
        if streak > 0 { return evening ? "Read tonight to keep \(streak) days" : "Read today to keep \(streak) days" }
        return "Start your streak today"
    }

    var lockLine: String {
        if lockedApps == 0 { return "No apps locked" }
        if readToday { return "Apps earned for today" }
        return lockedApps == 1 ? "1 app locked until you read" : "\(lockedApps) apps locked until you read"
    }
}

private func weekLetters(ending date: Date) -> [String] {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US")
    return (0..<7).map { i in
        let d = Calendar.current.date(byAdding: .day, value: i - 6, to: date) ?? date
        return String(f.veryShortWeekdaySymbols[Calendar.current.component(.weekday, from: d) - 1])
    }
}

// MARK: Shared pieces

private struct Eyebrow: View {
    let text: String
    let c: W
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).tracking(0.9).foregroundStyle(c.dim).lineLimit(1)
    }
}

private struct Bar: View {
    let value: Double
    let c: W
    var height: CGFloat = 5
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(c.line)
                Capsule().fill(c.gold).frame(width: g.size.width * CGFloat(min(1, max(0, value))))
            }
        }
        .frame(height: height)
    }
}

private struct WeekDots: View {
    let week: [Bool]
    let date: Date
    let c: W
    var size: CGFloat = 12
    var labels = true
    var body: some View {
        let letters = weekLetters(ending: date)
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 3) {
                    Circle()
                        .fill(week[i] ? c.gold : c.line)
                        .overlay(Circle().strokeBorder(i == 6 ? c.ink.opacity(0.35) : .clear, lineWidth: 1))
                        .frame(width: size, height: size)
                    if labels { Text(letters[i]).font(.system(size: 9, weight: .medium)).foregroundStyle(c.dim) }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct WeekRing: View {
    let week: [Bool]
    let c: W
    var body: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                Circle()
                    .trim(from: CGFloat(i) / 7 + 0.012, to: CGFloat(i + 1) / 7 - 0.012)
                    .stroke(week[i] ? c.gold : c.line, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

private struct UnlockDots: View {
    let left: Int
    let total: Int
    let c: W
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<min(total, 10), id: \.self) { i in
                Circle().fill(i < left ? c.gold : .clear).overlay(Circle().strokeBorder(c.gold.opacity(0.6), lineWidth: 1)).frame(width: 7, height: 7)
            }
        }
    }
}

private struct TrophyPicture: View {
    let art: String
    let c: W
    var size: CGFloat = 56
    var body: some View {
        if let url = WidgetData.imageURL(art), let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: "trophy.fill").font(.system(size: size * 0.5)).foregroundStyle(c.gold).frame(width: size, height: size)
                .background(c.soft, in: Circle())
        }
    }
}

private struct IntentButton<I: AppIntent, Label: View>: View {
    let intent: I
    let c: W
    let label: Label

    init(intent: I, c: W, @ViewBuilder label: () -> Label) {
        self.intent = intent
        self.c = c
        self.label = label()
    }

    var body: some View {
        Button(intent: intent) { label.foregroundStyle(c.ink).frame(width: 30, height: 30).background(c.soft, in: Circle()) }
            .buttonStyle(.plain)
    }
}

private extension View {
    func widgetCard(_ c: W, url: String) -> some View {
        containerBackground(c.paper, for: .widget).widgetURL(URL(string: "phos://\(url)"))
    }
}

// MARK: Today

struct TodayView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var scheme
    let entry: WickEntry<TodayConfig>

    var body: some View {
        let d = entry.data, o = entry.config, c = W.palette(o.look, scheme)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: d.readToday ? "Read today" : "Today", c: c)
                Spacer()
                if o.showStreak && d.streak > 0 {
                    Label("\(d.streak)", systemImage: "flame.fill").font(.caption.weight(.semibold)).foregroundStyle(c.gold)
                }
            }
            Spacer(minLength: 0)
            Text(d.chapter).font(.system(size: family == .systemSmall ? 26 : 30, weight: .medium, design: .serif))
                .foregroundStyle(c.ink).minimumScaleFactor(0.6).lineLimit(1)
            if o.showTitle && !d.chapterTitle.isEmpty {
                Text(d.chapterTitle).font(family == .systemSmall ? .caption : .subheadline).foregroundStyle(c.dim).lineLimit(family == .systemSmall ? 1 : 2)
            }
            if family == .systemLarge {
                Spacer(minLength: 6)
                WeekDots(week: d.week, date: entry.date, c: c)
                Spacer(minLength: 6)
                if !d.locks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(d.locks.prefix(3), id: \.name) { lock in
                            HStack {
                                Image(systemName: lock.locked ? "lock.fill" : "lock.open").font(.caption2).foregroundStyle(lock.locked ? c.dim : c.gold)
                                Text(lock.name).font(.footnote.weight(.medium)).foregroundStyle(c.ink)
                                Spacer()
                                Text(lock.status).font(.caption2).foregroundStyle(c.dim).lineLimit(1)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if o.showLocks {
                HStack(spacing: 4) {
                    Image(systemName: d.readToday ? "checkmark.circle.fill" : "lock.fill")
                    Text(d.readToday ? "Apps earned" : (d.lockedApps == 0 ? "Nothing locked" : "\(d.lockedApps) locked"))
                }
                .font(.caption).foregroundStyle(d.readToday ? c.gold : c.dim)
            }
            if o.showPlan && d.planTotal > 0 {
                if family != .systemSmall {
                    Text("\(d.planName) · \(d.planRead) of \(d.planTotal)").font(.caption2).foregroundStyle(c.dim).lineLimit(1)
                }
                Bar(value: Double(d.planRead) / Double(d.planTotal), c: c)
            }
        }
        .widgetCard(c, url: d.readToday ? "today" : "read")
    }
}

// MARK: Verse

struct VerseView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var scheme
    let entry: WickEntry<VerseConfig>

    var body: some View {
        let d = entry.data, o = entry.config, c = W.palette(o.look, scheme)
        let v = d.verse(o.source, offset: entry.verseOffset)
        let design: Font.Design = o.type == .serif ? .serif : o.type == .rounded ? .rounded : .monospaced
        let size: CGFloat = family == .systemSmall ? 14 : family == .systemMedium ? 17 : 21
        VStack(alignment: .leading, spacing: 6) {
            Text(v.text).font(.system(size: size, weight: .regular, design: design)).foregroundStyle(c.ink)
                .minimumScaleFactor(0.7).lineSpacing(family == .systemSmall ? 1 : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                Text(v.ref).font(.caption.weight(.semibold)).foregroundStyle(c.gold)
                Spacer()
                if o.shuffle {
                    IntentButton(intent: ShuffleVerseIntent(), c: c) { Image(systemName: "arrow.2.squarepath").font(.caption.weight(.semibold)) }
                }
            }
        }
        .widgetCard(c, url: "today")
    }
}

// MARK: Memory verse

struct MemoryView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var scheme
    let entry: WickEntry<MemoryConfig>

    var body: some View {
        let d = entry.data, o = entry.config, c = W.palette(o.look, scheme)
        let v = d.verse(o.source, offset: 0)
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Memory verse", c: c)
            Spacer(minLength: 0)
            if entry.revealed {
                Text(v.text).font(.system(size: family == .systemSmall ? 13 : 16, design: .serif)).foregroundStyle(c.ink).minimumScaleFactor(0.7)
            } else {
                Text(v.ref).font(.system(size: family == .systemSmall ? 22 : 28, weight: .medium, design: .serif)).foregroundStyle(c.ink).minimumScaleFactor(0.6)
                Text("Say it from memory, then check.").font(.caption).foregroundStyle(c.dim)
            }
            Spacer(minLength: 0)
            HStack {
                if entry.revealed { Text(v.ref).font(.caption.weight(.semibold)).foregroundStyle(c.gold) }
                Spacer()
                Button(intent: ToggleMemoryIntent()) {
                    Text(entry.revealed ? "Hide" : "Reveal").font(.caption.weight(.semibold)).foregroundStyle(c.paper)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(c.ink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .widgetCard(c, url: "today")
    }
}

// MARK: Streak

struct StreakView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var scheme
    let entry: WickEntry<StreakConfig>

    var body: some View {
        let d = entry.data, o = entry.config, c = W.palette(o.look, scheme)
        Group {
            switch o.style {
            case .ring:
                HStack(spacing: 14) {
                    ZStack {
                        WeekRing(week: d.week, c: c)
                        VStack(spacing: 0) {
                            Text("\(d.streak)").font(.system(size: family == .systemSmall ? 28 : 34, weight: .bold, design: .rounded)).foregroundStyle(c.ink)
                            Text(d.streak == 1 ? "day" : "days").font(.caption2).foregroundStyle(c.dim)
                        }
                    }
                    .frame(maxWidth: family == .systemSmall ? .infinity : 110)
                    if family != .systemSmall { details(d, o, c) }
                }
            case .dots:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Eyebrow(text: "This week", c: c)
                        Spacer()
                        Label("\(d.streak)", systemImage: "flame.fill").font(.caption.weight(.semibold)).foregroundStyle(c.gold)
                    }
                    Spacer(minLength: 0)
                    WeekDots(week: d.week, date: entry.date, c: c, size: family == .systemSmall ? 14 : 18)
                    Spacer(minLength: 0)
                    Text(d.streakLine).font(.caption).foregroundStyle(c.dim).lineLimit(2)
                    if family != .systemSmall { extras(d, o, c) }
                }
            case .number:
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "flame.fill").foregroundStyle(c.gold)
                        Eyebrow(text: "Streak", c: c)
                    }
                    Spacer(minLength: 0)
                    Text("\(d.streak)").font(.system(size: family == .systemSmall ? 44 : 52, weight: .bold, design: .rounded)).foregroundStyle(c.ink)
                    Text(d.streakLine).font(.caption).foregroundStyle(c.dim).lineLimit(2)
                    if family != .systemSmall {
                        Spacer(minLength: 4)
                        WeekDots(week: d.week, date: entry.date, c: c, size: 10, labels: false)
                        extras(d, o, c)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetCard(c, url: "progress")
    }

    private func details(_ d: WidgetData, _ o: StreakConfig, _ c: W) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Streak", c: c)
            Text(d.streakLine).font(.subheadline).foregroundStyle(c.ink).lineLimit(2)
            extras(d, o, c)
            Spacer(minLength: 0)
            WeekDots(week: d.week, date: entry.date, c: c, size: 10)
        }
    }

    @ViewBuilder
    private func extras(_ d: WidgetData, _ o: StreakConfig, _ c: W) -> some View {
        if o.showLongest || o.showTotal {
            HStack(spacing: 12) {
                if o.showLongest { Text("Longest \(d.longestStreak)") }
                if o.showTotal { Text("\(d.totalChapters) chapters") }
            }
            .font(.caption2).foregroundStyle(c.dim)
        }
    }
}

// MARK: Plan

struct PlanView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var scheme
    let entry: WickEntry<PlanConfig>

    var body: some View {
        let d = entry.data, o = entry.config, c = W.palette(o.look, scheme)
        let left = max(0, d.planTotal - d.planRead)
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Plan", c: c)
            Text(d.planName).font(.system(size: family == .systemSmall ? 20 : 24, weight: .medium, design: .serif)).foregroundStyle(c.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(left == 0 ? "Finished. Pick a new plan." : "\(d.planRead) of \(d.planTotal) read · \(left) to go").font(.caption).foregroundStyle(c.dim)
            Bar(value: d.planTotal == 0 ? 0 : Double(d.planRead) / Double(d.planTotal), c: c, height: 7)
            if o.showUpcoming && family != .systemSmall && !d.upcoming.isEmpty {
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: family == .systemLarge ? 7 : 3) {
                    ForEach(Array(d.upcoming.prefix(family == .systemLarge ? 5 : 2).enumerated()), id: \.offset) { i, ch in
                        HStack(spacing: 8) {
                            Text(i == 0 ? "Next" : "Then").font(.caption2.weight(.semibold)).foregroundStyle(i == 0 ? c.gold : c.dim).frame(width: 30, alignment: .leading)
                            Text(ch.ref).font(.footnote.weight(.medium)).foregroundStyle(c.ink)
                            if o.showTitles && !ch.text.isEmpty {
                                Text(ch.text).font(.caption).foregroundStyle(c.dim).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .widgetCard(c, url: "plan")
    }
}

// MARK: Locks

struct LocksView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var scheme
    let entry: WickEntry<LocksConfig>

    var body: some View {
        let d = entry.data, o = entry.config, c = W.palette(o.look, scheme)
        let chosen = o.lock.flatMap { pick in d.locks.first { $0.name == pick.name } }
        VStack(alignment: .leading, spacing: 6) {
            if let lock = chosen {
                HStack {
                    Image(systemName: lock.locked ? "lock.fill" : "lock.open.fill").foregroundStyle(lock.locked ? c.dim : c.gold)
                    Eyebrow(text: lock.name, c: c)
                }
                Spacer(minLength: 0)
                Text(lock.locked ? "Locked" : "Open").font(.system(size: family == .systemSmall ? 26 : 30, weight: .medium, design: .serif)).foregroundStyle(c.ink)
                Text(lock.status).font(.caption).foregroundStyle(c.dim).lineLimit(2)
                if o.showDots, let left = lock.left, let limit = lock.limit {
                    Spacer(minLength: 2)
                    UnlockDots(left: left, total: limit, c: c)
                    Text(left == 0 ? "No unlocks left today" : left == 1 ? "1 unlock left" : "\(left) unlocks left").font(.caption2).foregroundStyle(c.dim)
                }
            } else {
                HStack {
                    Image(systemName: d.readToday ? "lock.open.fill" : "lock.fill").foregroundStyle(d.readToday ? c.gold : c.dim)
                    Eyebrow(text: "Locks", c: c)
                    Spacer()
                }
                if d.locks.isEmpty {
                    Spacer(minLength: 0)
                    Text("No locks yet").font(.system(size: 20, weight: .medium, design: .serif)).foregroundStyle(c.ink)
                    Text("Add one in Wick to guard your apps.").font(.caption).foregroundStyle(c.dim)
                } else if family == .systemSmall {
                    Spacer(minLength: 0)
                    Text("\(d.lockedApps)").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(c.ink)
                    Text(d.lockLine).font(.caption).foregroundStyle(c.dim).lineLimit(2)
                } else {
                    Text(d.lockLine).font(.caption).foregroundStyle(c.dim)
                    Spacer(minLength: 2)
                    ForEach(d.locks.prefix(family == .systemLarge ? 6 : 3), id: \.name) { lock in
                        HStack(spacing: 8) {
                            Circle().fill(lock.locked ? c.dim : c.gold).frame(width: 7, height: 7)
                            Text(lock.name).font(.footnote.weight(.medium)).foregroundStyle(c.ink).lineLimit(1)
                            Spacer()
                            if o.showDots, let left = lock.left, let limit = lock.limit {
                                UnlockDots(left: left, total: limit, c: c)
                            } else {
                                Text(lock.status).font(.caption2).foregroundStyle(c.dim).lineLimit(1)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetCard(c, url: d.readToday ? "locks" : "read")
    }
}

// MARK: Trophies

struct TrophyView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var scheme
    let entry: WickEntry<TrophyConfig>

    var body: some View {
        let d = entry.data, o = entry.config, c = W.palette(o.look, scheme)
        let list: [WidgetData.Trophy] = o.pick == .latest ? [d.lastEarned].compactMap { $0 } : d.trophies
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Eyebrow(text: o.pick == .latest ? "Last earned" : "Almost there", c: c)
                Spacer()
                Text("\(d.earnedCount) of \(d.trophyTotal)").font(.caption2).foregroundStyle(c.dim)
            }
            if list.isEmpty {
                Spacer(minLength: 0)
                Text(o.pick == .latest ? "No trophies yet" : "All caught up").font(.system(size: 20, weight: .medium, design: .serif)).foregroundStyle(c.ink)
                Text("Read today to start earning.").font(.caption).foregroundStyle(c.dim)
                Spacer(minLength: 0)
            } else if family == .systemLarge {
                ForEach(list.prefix(4), id: \.name) { t in row(t, c, o, big: true) }
                Spacer(minLength: 0)
            } else {
                let t = list[((entry.trophyOffset % list.count) + list.count) % list.count]
                Spacer(minLength: 0)
                if family == .systemSmall {
                    HStack(alignment: .top, spacing: 8) {
                        TrophyPicture(art: t.art, c: c, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name).font(.footnote.weight(.semibold)).foregroundStyle(c.ink).lineLimit(2)
                            Text(t.earned ? "Earned" : "\(t.progress) of \(t.goal)").font(.caption2).foregroundStyle(c.dim)
                        }
                    }
                    if o.showProgress && !t.earned { Bar(value: Double(t.progress) / Double(max(1, t.goal)), c: c) }
                } else {
                    row(t, c, o, big: false)
                }
                Spacer(minLength: 0)
                if list.count > 1 {
                    HStack {
                        IntentButton(intent: NextTrophyIntent(step: -1), c: c) { Image(systemName: "chevron.left").font(.caption.weight(.semibold)) }
                        Spacer()
                        Text("\(((entry.trophyOffset % list.count) + list.count) % list.count + 1) of \(list.count)").font(.caption2).foregroundStyle(c.dim)
                        Spacer()
                        IntentButton(intent: NextTrophyIntent(step: 1), c: c) { Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetCard(c, url: "trophies")
    }

    private func row(_ t: WidgetData.Trophy, _ c: W, _ o: TrophyConfig, big: Bool) -> some View {
        HStack(spacing: 10) {
            TrophyPicture(art: t.art, c: c, size: big ? 44 : 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(t.name).font(.subheadline.weight(.semibold)).foregroundStyle(c.ink).lineLimit(1)
                Text(t.detail).font(.caption).foregroundStyle(c.dim).lineLimit(big ? 1 : 2)
                if o.showProgress && !t.earned {
                    HStack(spacing: 6) {
                        Bar(value: Double(t.progress) / Double(max(1, t.goal)), c: c, height: 4)
                        Text("\(t.progress)/\(t.goal)").font(.caption2.monospacedDigit()).foregroundStyle(c.dim)
                    }
                } else if t.earned {
                    Text("Earned").font(.caption2.weight(.semibold)).foregroundStyle(c.gold)
                }
            }
        }
    }
}

// MARK: Lock Screen

struct GlanceView: View {
    @Environment(\.widgetFamily) var family
    let data: WidgetData
    let info: GlanceInfo
    let date: Date

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: rectangular
            }
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(URL(string: "phos://\(link)"))
    }

    private var link: String {
        switch info {
        case .chapter, .verse: return data.readToday ? "today" : "read"
        case .streak, .plan: return "progress"
        case .locks: return "locks"
        case .trophy: return "trophies"
        }
    }

    private var planValue: Double { data.planTotal == 0 ? 0 : Double(data.planRead) / Double(data.planTotal) }
    private var trophy: WidgetData.Trophy? { data.trophies.first }

    @ViewBuilder private var circular: some View {
        let d = data
        ZStack {
            AccessoryWidgetBackground()
            switch info {
            case .chapter:
                VStack(spacing: 0) {
                    Image(systemName: d.readToday ? "checkmark" : "book.closed.fill").font(.caption2)
                    Text(d.chapter.split(separator: " ").last.map(String.init) ?? "").font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(d.chapter.split(separator: " ").dropLast().joined(separator: " ")).font(.system(size: 8, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .padding(4)
            case .streak:
                Gauge(value: Double(d.week.filter { $0 }.count), in: 0...7) {
                    Image(systemName: "flame.fill")
                } currentValueLabel: {
                    Text("\(d.streak)").font(.system(size: 18, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .verse:
                VStack(spacing: 1) {
                    Image(systemName: "quote.opening").font(.caption2)
                    Text(d.verse(.daily, offset: 0).ref).font(.system(size: 10, weight: .semibold)).multilineTextAlignment(.center).minimumScaleFactor(0.6)
                }
                .padding(5)
            case .locks:
                VStack(spacing: 0) {
                    Image(systemName: d.readToday ? "lock.open.fill" : "lock.fill").font(.caption2)
                    Text("\(d.lockedApps)").font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("apps").font(.system(size: 8, weight: .semibold))
                }
            case .plan:
                Gauge(value: planValue) {
                    Image(systemName: "map")
                } currentValueLabel: {
                    Text("\(Int((planValue * 100).rounded()))%").font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircular)
            case .trophy:
                Gauge(value: Double(trophy?.progress ?? 0), in: 0...Double(max(1, trophy?.goal ?? 1))) {
                    Image(systemName: "trophy.fill")
                } currentValueLabel: {
                    Image(systemName: "trophy.fill").font(.body)
                }
                .gaugeStyle(.accessoryCircular)
            }
        }
        .widgetAccentable()
    }

    @ViewBuilder private var inline: some View {
        let d = data
        switch info {
        case .chapter: Label(d.readToday ? "Read \(d.chapter)" : "Today: \(d.chapter)", systemImage: d.readToday ? "checkmark.circle" : "book.closed")
        case .streak: Label(d.streak == 1 ? "1 day streak" : "\(d.streak) day streak", systemImage: "flame.fill")
        case .verse: Text("\(d.verse(.daily, offset: 0).ref) · \(d.verse(.daily, offset: 0).text)")
        case .locks: Label(d.lockLine, systemImage: d.readToday ? "lock.open" : "lock")
        case .plan: Label("\(d.planName) \(d.planRead) of \(d.planTotal)", systemImage: "map")
        case .trophy: Label(trophy.map { "\($0.name) \($0.progress) of \($0.goal)" } ?? "\(d.earnedCount) trophies", systemImage: "trophy")
        }
    }

    @ViewBuilder private var rectangular: some View {
        let d = data
        VStack(alignment: .leading, spacing: 1) {
            switch info {
            case .chapter:
                Label("Wick", systemImage: "sun.max").font(.caption2).widgetAccentable()
                Text(d.chapter).font(.headline)
                Text(d.readToday ? "Read today" : (d.chapterTitle.isEmpty ? "Not read yet" : d.chapterTitle)).font(.caption).lineLimit(1)
            case .streak:
                Label(d.streak == 1 ? "1 day streak" : "\(d.streak) day streak", systemImage: "flame.fill").font(.headline).widgetAccentable()
                Text(d.streakLine).font(.caption).lineLimit(1)
                HStack(spacing: 5) {
                    ForEach(0..<7, id: \.self) { i in
                        Circle().fill(d.week[i] ? .primary : .primary.opacity(0.25)).frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 2)
            case .verse:
                let v = d.verse(.daily, offset: 0)
                Text(v.text).font(.system(size: 12, design: .serif)).lineLimit(3).minimumScaleFactor(0.8)
                Text(v.ref).font(.caption2.weight(.semibold)).widgetAccentable()
            case .locks:
                Label(d.lockLine, systemImage: d.readToday ? "lock.open.fill" : "lock.fill").font(.caption.weight(.semibold)).lineLimit(1).widgetAccentable()
                ForEach(d.locks.prefix(2), id: \.name) { lock in
                    HStack(spacing: 4) {
                        Text(lock.name).font(.caption).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(lock.left.map { "\($0) left" } ?? (lock.locked ? "Locked" : "Open")).font(.caption2).lineLimit(1)
                    }
                }
            case .plan:
                Label(d.planName, systemImage: "map").font(.caption.weight(.semibold)).lineLimit(1).widgetAccentable()
                Gauge(value: planValue) { EmptyView() }.gaugeStyle(.accessoryLinear)
                Text("\(d.planRead) of \(d.planTotal) · next \(d.upcoming.first?.ref ?? d.chapter)").font(.caption2).lineLimit(1)
            case .trophy:
                if let t = trophy {
                    Label(t.name, systemImage: "trophy.fill").font(.caption.weight(.semibold)).lineLimit(1).widgetAccentable()
                    Gauge(value: Double(t.progress), in: 0...Double(max(1, t.goal))) { EmptyView() }.gaugeStyle(.accessoryLinear)
                    Text("\(t.progress) of \(t.goal) · \(t.detail)").font(.caption2).lineLimit(1)
                } else {
                    Label("Trophies", systemImage: "trophy.fill").font(.caption.weight(.semibold)).widgetAccentable()
                    Text("\(d.earnedCount) of \(d.trophyTotal) earned").font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Widgets

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PhosToday", intent: TodayConfig.self, provider: WickProvider<TodayConfig>()) { TodayView(entry: $0) }
            .configurationDisplayName("Today")
            .description("Today's chapter, your streak, and what is locked.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct VerseWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WickVerse", intent: VerseConfig.self, provider: WickProvider<VerseConfig>()) { VerseView(entry: $0) }
            .configurationDisplayName("Verse")
            .description("A verse for the day, with a button for another.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MemoryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WickMemory", intent: MemoryConfig.self, provider: WickProvider<MemoryConfig>()) { MemoryView(entry: $0) }
            .configurationDisplayName("Memory verse")
            .description("Hides the words. Say it, then tap to check.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WickStreak", intent: StreakConfig.self, provider: WickProvider<StreakConfig>()) { StreakView(entry: $0) }
            .configurationDisplayName("Streak")
            .description("Your streak as a number, week dots, or a ring.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PlanWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WickPlan", intent: PlanConfig.self, provider: WickProvider<PlanConfig>()) { PlanView(entry: $0) }
            .configurationDisplayName("Plan")
            .description("Progress through your plan and the chapters coming up.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct LocksWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WickLocks", intent: LocksConfig.self, provider: WickProvider<LocksConfig>()) { LocksView(entry: $0) }
            .configurationDisplayName("Locks")
            .description("Every lock, or just one, with unlocks left.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TrophiesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WickTrophies", intent: TrophyConfig.self, provider: WickProvider<TrophyConfig>()) { TrophyView(entry: $0) }
            .configurationDisplayName("Trophies")
            .description("The trophies you are closest to, or the last one earned.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct GlanceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PhosLock", intent: GlanceConfig.self, provider: WickProvider<GlanceConfig>()) { e in
            GlanceView(data: e.data, info: e.config.info, date: e.date)
        }
        .configurationDisplayName("Wick glance")
        .description("Pick one thing to show: chapter, streak, verse, locks, plan, or next trophy.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// Ready made Lock Screen widgets, so the common ones need no setup. Widget needs an empty init, so each is its own type.
private func lockScreen(_ info: GlanceInfo, name: String, detail: String) -> some WidgetConfiguration {
    StaticConfiguration(kind: "WickLock_\(info.rawValue)", provider: GlanceProvider(info: info)) { e in
        GlanceView(data: e.data, info: e.config, date: e.date)
    }
    .configurationDisplayName(name)
    .description(detail)
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
}

struct LockStreakWidget: Widget {
    var body: some WidgetConfiguration { lockScreen(.streak, name: "Streak", detail: "Your streak under the clock.") }
}

struct LockChapterWidget: Widget {
    var body: some WidgetConfiguration { lockScreen(.chapter, name: "Today's chapter", detail: "What to read today.") }
}

struct LockVerseWidget: Widget {
    var body: some WidgetConfiguration { lockScreen(.verse, name: "Verse", detail: "Today's verse on the Lock Screen.") }
}

struct LockLocksWidget: Widget {
    var body: some WidgetConfiguration { lockScreen(.locks, name: "Locks", detail: "How many apps are waiting on your reading.") }
}

struct LockPlanWidget: Widget {
    var body: some WidgetConfiguration { lockScreen(.plan, name: "Plan", detail: "How far you are through your plan.") }
}

@main
struct PhosWidgetBundle: WidgetBundle {
    var body: some Widget {
        HomeWidgets().body
        LockWidgets().body
    }
}

struct HomeWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        VerseWidget()
        MemoryWidget()
        StreakWidget()
        PlanWidget()
        LocksWidget()
        TrophiesWidget()
    }
}

struct LockWidgets: WidgetBundle {
    var body: some Widget {
        GlanceWidget()
        LockStreakWidget()
        LockChapterWidget()
        LockVerseWidget()
        LockLocksWidget()
        LockPlanWidget()
    }
}
