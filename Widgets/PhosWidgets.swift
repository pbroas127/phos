import SwiftUI
import WidgetKit

struct PhosEntry: TimelineEntry {
    let date: Date
    let snap: SharedSnapshot
}

struct PhosProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhosEntry {
        var s = SharedSnapshot()
        s.chapterTitle = "John 3"
        s.streak = 11
        s.lockedCount = 4
        s.planName = "Gospel of John"
        s.planDay = 3
        s.planLength = 21
        return PhosEntry(date: Date(), snap: s)
    }

    func getSnapshot(in context: Context, completion: @escaping (PhosEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : PhosEntry(date: Date(), snap: SharedStore.shared.snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhosEntry>) -> Void) {
        let entry = PhosEntry(date: Date(), snap: SharedStore.shared.snapshot)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

private enum W {
    static let paper = Color(red: 0xFB / 255, green: 0xF9 / 255, blue: 0xF4 / 255)
    static let ink = Color(red: 0x22 / 255, green: 0x1D / 255, blue: 0x17 / 255)
    static let dim = Color(red: 0x8A / 255, green: 0x7F / 255, blue: 0x71 / 255)
    static let gold = Color(red: 0xA8 / 255, green: 0x7A / 255, blue: 0x22 / 255)
    static let line = Color(red: 0xEC / 255, green: 0xE5 / 255, blue: 0xD8 / 255)
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: PhosEntry

    var body: some View {
        let s = entry.snap
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(s.readingDone ? "READ TODAY" : "TODAY").font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(W.dim)
                Spacer()
                if s.streak > 0 {
                    Label("\(s.streak)", systemImage: "flame.fill").font(.caption.weight(.semibold)).foregroundStyle(W.gold).labelStyle(.titleAndIcon)
                }
            }
            Spacer(minLength: 0)
            Text(s.chapterTitle).font(.system(size: family == .systemSmall ? 26 : 32, weight: .medium, design: .serif)).foregroundStyle(W.ink).minimumScaleFactor(0.6).lineLimit(1)
            if family != .systemSmall, !s.planName.isEmpty {
                Text("\(s.planName) · day \(s.planDay) of \(s.planLength)").font(.caption).foregroundStyle(W.dim)
            }
            HStack(spacing: 4) {
                Image(systemName: s.readingDone ? "checkmark.circle.fill" : "lock.fill")
                Text(s.readingDone ? "Apps earned" : "\(s.lockedCount) locked")
            }
            .font(.caption).foregroundStyle(s.readingDone ? W.gold : W.dim)
            if s.planLength > 0 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(W.line)
                        Capsule().fill(W.gold).frame(width: g.size.width * CGFloat(max(0, s.planDay - (s.readingDone ? 0 : 1))) / CGFloat(max(1, s.planLength)))
                    }
                }
                .frame(height: 5)
            }
        }
        .containerBackground(W.paper, for: .widget)
        .widgetURL(URL(string: "phos://today"))
    }
}

struct LockWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: PhosEntry

    var body: some View {
        let s = entry.snap
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "flame.fill").font(.caption2)
                    Text("\(s.streak)").font(.system(size: 18, weight: .bold, design: .rounded))
                }
            }
            .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            Text(s.readingDone ? "Read \(s.chapterTitle)" : "Today: \(s.chapterTitle)")
                .containerBackground(.clear, for: .widget)
        default:
            VStack(alignment: .leading, spacing: 1) {
                Label("Phos", systemImage: "sun.max").font(.caption2)
                Text(s.chapterTitle).font(.headline)
                Text(s.readingDone ? "Read today" : "Not read yet").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.clear, for: .widget)
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PhosToday", provider: PhosProvider()) { TodayWidgetView(entry: $0) }
            .configurationDisplayName("Today's chapter")
            .description("Your chapter, streak, and locked apps.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PhosLock", provider: PhosProvider()) { LockWidgetView(entry: $0) }
            .configurationDisplayName("Phos on the Lock Screen")
            .description("See today's chapter and your streak under the clock.")
            .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct PhosWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        LockWidget()
    }
}
