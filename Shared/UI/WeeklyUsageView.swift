import DeviceActivity
import SwiftUI

extension DeviceActivityReport.Context {
    static let weekly = Self("weekly")
}

struct WeeklyUsage {
    struct Day: Identifiable {
        let date: Date
        /// Time in locked apps.
        let seconds: TimeInterval
        /// All screen time on the iPhone that day.
        let allSeconds: TimeInterval
        var id: Date { date }
    }

    struct App: Identifiable {
        let name: String
        let thisWeek: TimeInterval
        let lastWeek: TimeInterval
        var id: String { name }
    }

    var days: [Day]
    var thisWeekTotal: TimeInterval
    var lastWeekTotal: TimeInterval
    var allThisWeek: TimeInterval
    var allLastWeek: TimeInterval
    var apps: [App]

    /// This week is the last 7 days, today included. Last week is the 7 days before it.
    /// dayTotals and appDays hold locked apps only. allDayTotals holds all screen time.
    static func build(dayTotals: [Date: TimeInterval], allDayTotals: [Date: TimeInterval], appDays: [String: [Date: TimeInterval]],
                      now: Date, calendar: Calendar = .current) -> WeeklyUsage {
        let today = calendar.startOfDay(for: now)
        let thisStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let lastStart = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        func isThis(_ d: Date) -> Bool { d >= thisStart }
        func isLast(_ d: Date) -> Bool { d >= lastStart && d < thisStart }
        func sum(_ totals: [Date: TimeInterval], _ test: (Date) -> Bool) -> TimeInterval { totals.filter { test($0.key) }.values.reduce(0, +) }

        let days = (0..<7).map { offset -> Day in
            let d = calendar.date(byAdding: .day, value: offset, to: thisStart) ?? thisStart
            return Day(date: d, seconds: dayTotals[d] ?? 0, allSeconds: max(allDayTotals[d] ?? 0, dayTotals[d] ?? 0))
        }
        let apps = appDays.map { name, byDay in
            App(name: name, thisWeek: byDay.filter { isThis($0.key) }.values.reduce(0, +), lastWeek: byDay.filter { isLast($0.key) }.values.reduce(0, +))
        }
        .filter { $0.thisWeek >= 60 }
        .sorted { $0.thisWeek > $1.thisWeek }

        return WeeklyUsage(days: days, thisWeekTotal: sum(dayTotals, isThis), lastWeekTotal: sum(dayTotals, isLast),
                           allThisWeek: sum(allDayTotals, isThis), allLastWeek: sum(allDayTotals, isLast), apps: Array(apps.prefix(6)))
    }

    static func duration(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded())
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    /// Time saved or added since last week, or nil when there is nothing to compare.
    static func change(this: TimeInterval, last: TimeInterval) -> TimeInterval? {
        guard last >= 60 else { return nil }
        return this - last
    }
}

struct WeeklyUsageView: View {
    let usage: WeeklyUsage

    private let gold = Color(red: 0xA8 / 255, green: 0x7A / 255, blue: 0x22 / 255)
    private let ghost = Color(red: 0xEC / 255, green: 0xE2 / 255, blue: 0xCF / 255)
    private let ink = Color(red: 0x22 / 255, green: 0x1D / 255, blue: 0x17 / 255)
    private let dim = Color(red: 0x8A / 255, green: 0x7F / 255, blue: 0x71 / 255)
    private let line = Color(red: 0xEC / 255, green: 0xE5 / 255, blue: 0xD8 / 255)
    private let soft = Color(red: 0xF7 / 255, green: 0xF2 / 255, blue: 0xE8 / 255)
    private let green = Color(red: 0x2F / 255, green: 0x8A / 255, blue: 0x57 / 255)
    private let red = Color(red: 0xB2 / 255, green: 0x3A / 255, blue: 0x2B / 255)

    var body: some View {
        let maxSeconds = max(usage.days.map(\.allSeconds).max() ?? 1, 60)
        VStack(alignment: .leading, spacing: 20) {
            Text("THIS WEEK").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(dim)

            HStack(spacing: 12) {
                stat("All screen time", usage.allThisWeek, last: usage.allLastWeek, color: dim)
                stat("Locked apps", usage.thisWeekTotal, last: usage.thisWeekTotal == 0 ? 0 : usage.lastWeekTotal, color: gold)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(usage.days) { day in
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4).fill(ghost)
                                    .frame(height: max(4, 130 * day.allSeconds / maxSeconds))
                                RoundedRectangle(cornerRadius: 4).fill(gold)
                                    .frame(height: max(day.seconds > 0 ? 4 : 0, 130 * day.seconds / maxSeconds))
                            }
                            .frame(height: 134, alignment: .bottom)
                            Text(day.date.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(dim)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 14) {
                    legend(ghost, "All screen time")
                    legend(gold, "Locked apps")
                }
            }

            if !usage.apps.isEmpty {
                VStack(spacing: 0) {
                    Text("LOCKED APPS").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 6)
                    ForEach(usage.apps) { app in
                        HStack {
                            Text(app.name).font(.subheadline.weight(.medium)).foregroundStyle(ink).lineLimit(1)
                            Spacer()
                            Text(WeeklyUsage.duration(app.thisWeek)).font(.subheadline).monospacedDigit().foregroundStyle(ink)
                            pill(WeeklyUsage.change(this: app.thisWeek, last: app.lastWeek)).frame(width: 64, alignment: .trailing)
                        }
                        .padding(.vertical, 10)
                        if app.id != usage.apps.last?.id { Rectangle().fill(line).frame(height: 1) }
                    }
                }
            }

            Text("From Screen Time on this iPhone. It never leaves your phone.")
                .font(.caption).foregroundStyle(dim)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func stat(_ title: String, _ seconds: TimeInterval, last: TimeInterval, color: Color) -> some View {
        let change = WeeklyUsage.change(this: seconds, last: last)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(dim)
            }
            Text(WeeklyUsage.duration(seconds)).font(.system(size: 26, weight: .medium, design: .serif)).foregroundStyle(ink)
                .minimumScaleFactor(0.7).lineLimit(1)
            if let change, abs(change) >= 60 {
                Text(change < 0 ? "\(WeeklyUsage.duration(abs(change))) less than last week" : "\(WeeklyUsage.duration(change)) more than last week")
                    .font(.caption.weight(.semibold)).foregroundStyle(change < 0 ? green : red)
            } else if change != nil {
                Text("About the same as last week").font(.caption.weight(.semibold)).foregroundStyle(dim)
            } else {
                Text("About \(WeeklyUsage.duration(seconds / 7)) a day").font(.caption).foregroundStyle(dim)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption).foregroundStyle(dim)
        }
    }

    @ViewBuilder
    private func pill(_ change: TimeInterval?) -> some View {
        if let change, abs(change) >= 60 {
            Text(change < 0 ? "↓\(WeeklyUsage.duration(abs(change)))" : "↑\(WeeklyUsage.duration(change))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(change < 0 ? green : red)
        } else if change != nil {
            Text("same").font(.caption).foregroundStyle(dim)
        } else {
            Text("new").font(.caption).foregroundStyle(dim)
        }
    }
}
