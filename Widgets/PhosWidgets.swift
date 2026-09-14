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

/// Widget colors for the light and dark Home Screen.
private struct W {
    let paper: Color, ink: Color, dim: Color, gold: Color, line: Color

    static func palette(_ scheme: ColorScheme) -> W {
        scheme == .dark
            ? W(paper: Color(red: 0x17 / 255, green: 0x14 / 255, blue: 0x10 / 255),
                ink: Color(red: 0xF3 / 255, green: 0xED / 255, blue: 0xE2 / 255),
                dim: Color(red: 0xA8 / 255, green: 0x9C / 255, blue: 0x8B / 255),
                gold: Color(red: 0xE0 / 255, green: 0xAE / 255, blue: 0x4B / 255),
                line: Color(red: 0x3A / 255, green: 0x32 / 255, blue: 0x29 / 255))
            : W(paper: Color(red: 0xFB / 255, green: 0xF9 / 255, blue: 0xF4 / 255),
                ink: Color(red: 0x22 / 255, green: 0x1D / 255, blue: 0x17 / 255),
                dim: Color(red: 0x8A / 255, green: 0x7F / 255, blue: 0x71 / 255),
                gold: Color(red: 0xA8 / 255, green: 0x7A / 255, blue: 0x22 / 255),
                line: Color(red: 0xEC / 255, green: 0xE5 / 255, blue: 0xD8 / 255))
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var scheme
    let entry: PhosEntry

    var body: some View {
        let s = entry.snap
        let c = W.palette(scheme)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(s.readingDone ? "READ TODAY" : "TODAY").font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(c.dim)
                Spacer()
                if s.streak > 0 {
                    Label("\(s.streak)", systemImage: "flame.fill").font(.caption.weight(.semibold)).foregroundStyle(c.gold).labelStyle(.titleAndIcon)
                }
            }
            Spacer(minLength: 0)
            Text(s.chapterTitle).font(.system(size: family == .systemSmall ? 26 : 32, weight: .medium, design: .serif)).foregroundStyle(c.ink).minimumScaleFactor(0.6).lineLimit(1)
            if family != .systemSmall, !s.planName.isEmpty {
                Text("\(s.planName) · day \(s.planDay) of \(s.planLength)").font(.caption).foregroundStyle(c.dim)
            }
            HStack(spacing: 4) {
                Image(systemName: s.readingDone ? "checkmark.circle.fill" : "lock.fill")
                Text(s.readingDone ? "Apps earned" : "\(s.lockedCount) locked")
            }
            .font(.caption).foregroundStyle(s.readingDone ? c.gold : c.dim)
            if s.planLength > 0 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(c.line)
                        Capsule().fill(c.gold).frame(width: g.size.width * CGFloat(max(0, s.planDay - (s.readingDone ? 0 : 1))) / CGFloat(max(1, s.planLength)))
                    }
                }
                .frame(height: 5)
            }
        }
        .containerBackground(c.paper, for: .widget)
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
                Label("Wick", systemImage: "sun.max").font(.caption2)
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
            .configurationDisplayName("Wick on the Lock Screen")
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
