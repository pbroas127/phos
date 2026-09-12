import DeviceActivity
import SwiftUI

extension DeviceActivityReport.Context {
    static let weekly = Self("weekly")
}

struct WeeklyUsage {
    struct Day: Identifiable {
        let date: Date
        let seconds: TimeInterval
        var id: Date { date }
    }

    struct App: Identifiable {
        let name: String
        let seconds: TimeInterval
        var id: String { name }
    }

    var thisWeek: [Day]
    var thisWeekTotal: TimeInterval
    var lastWeekTotal: TimeInterval
    var topApps: [App]

    /// Builds this week and last week totals from up to 14 days of usage.
    static func build(days: [Date: TimeInterval], apps: [String: TimeInterval], now: Date, calendar: Calendar = .current) -> WeeklyUsage {
        let today = calendar.startOfDay(for: now)
        let week = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let thisWeek = week.map { Day(date: $0, seconds: days[$0] ?? 0) }
        let lastStart = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        let lastEnd = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let lastTotal = days.filter { $0.key >= lastStart && $0.key < lastEnd }.values.reduce(0, +)
        let top = apps.sorted { $0.value > $1.value }.prefix(5).map { App(name: $0.key, seconds: $0.value) }
        return WeeklyUsage(thisWeek: thisWeek, thisWeekTotal: thisWeek.map(\.seconds).reduce(0, +), lastWeekTotal: lastTotal, topApps: Array(top))
    }

    var changeText: String {
        guard lastWeekTotal > 60 else { return "This week" }
        let change = (thisWeekTotal - lastWeekTotal) / lastWeekTotal
        let pct = Int((abs(change) * 100).rounded())
        return change <= 0 ? "Locked apps down \(pct)%" : "Locked apps up \(pct)%"
    }

    static func duration(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }
}

struct WeeklyUsageView: View {
    let usage: WeeklyUsage

    private let gold = Color(red: 0xA8 / 255, green: 0x7A / 255, blue: 0x22 / 255)
    private let ink = Color(red: 0x22 / 255, green: 0x1D / 255, blue: 0x17 / 255)
    private let dim = Color(red: 0x8A / 255, green: 0x7F / 255, blue: 0x71 / 255)
    private let line = Color(red: 0xEC / 255, green: 0xE5 / 255, blue: 0xD8 / 255)

    var body: some View {
        let maxSeconds = max(usage.thisWeek.map(\.seconds).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("THIS WEEK").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(dim)
                Text(usage.changeText).font(.system(size: 28, weight: .medium, design: .serif)).foregroundStyle(ink)
                Text("\(WeeklyUsage.duration(usage.thisWeekTotal)) in locked apps").font(.subheadline).foregroundStyle(dim)
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(usage.thisWeek) { day in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Calendar.current.isDateInToday(day.date) ? gold : gold.opacity(0.35))
                            .frame(height: max(6, 130 * day.seconds / maxSeconds))
                        Text(day.date.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(dim)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 160, alignment: .bottom)
            if !usage.topApps.isEmpty {
                VStack(spacing: 0) {
                    ForEach(usage.topApps) { app in
                        HStack {
                            Text(app.name).font(.body.weight(.medium)).foregroundStyle(ink)
                            Spacer()
                            Text(WeeklyUsage.duration(app.seconds)).foregroundStyle(dim).monospacedDigit()
                        }
                        .padding(.vertical, 12)
                        if app.id != usage.topApps.last?.id { Divider().overlay(line) }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
