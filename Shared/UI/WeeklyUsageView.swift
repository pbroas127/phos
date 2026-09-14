import DeviceActivity
import SwiftUI

extension DeviceActivityReport.Context {
    static let weekly = Self("weekly")
}

struct WeeklyUsage {
    struct Day: Identifiable {
        let date: Date
        let seconds: TimeInterval
        let lastWeekSeconds: TimeInterval
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
    var apps: [App]

    /// Builds this week (the last 7 days, today included) and the 7 days before it.
    static func build(dayTotals: [Date: TimeInterval], appDays: [String: [Date: TimeInterval]], now: Date, calendar: Calendar = .current) -> WeeklyUsage {
        let today = calendar.startOfDay(for: now)
        let thisStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let lastStart = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        func isThis(_ d: Date) -> Bool { d >= thisStart }
        func isLast(_ d: Date) -> Bool { d >= lastStart && d < thisStart }

        let days = (0..<7).map { offset -> Day in
            let d = calendar.date(byAdding: .day, value: offset, to: thisStart) ?? thisStart
            let prior = calendar.date(byAdding: .day, value: -7, to: d) ?? d
            return Day(date: d, seconds: dayTotals[d] ?? 0, lastWeekSeconds: dayTotals[prior] ?? 0)
        }
        let apps = appDays.map { name, byDay in
            App(name: name,
                thisWeek: byDay.filter { isThis($0.key) }.values.reduce(0, +),
                lastWeek: byDay.filter { isLast($0.key) }.values.reduce(0, +))
        }
        .filter { $0.thisWeek + $0.lastWeek >= 60 }
        .sorted { max($0.thisWeek, $0.lastWeek) > max($1.thisWeek, $1.lastWeek) }

        return WeeklyUsage(days: days,
                           thisWeekTotal: dayTotals.filter { isThis($0.key) }.values.reduce(0, +),
                           lastWeekTotal: dayTotals.filter { isLast($0.key) }.values.reduce(0, +),
                           apps: Array(apps.prefix(8)))
    }

    static func duration(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded())
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    /// Percent change from last week, or nil when there is nothing to compare.
    static func change(this: TimeInterval, last: TimeInterval) -> Int? {
        guard last >= 60 else { return nil }
        return Int(((this - last) / last * 100).rounded())
    }
}

struct WeeklyUsageView: View {
    let usage: WeeklyUsage

    private let gold = Color(red: 0xA8 / 255, green: 0x7A / 255, blue: 0x22 / 255)
    private let ghost = Color(red: 0xE4 / 255, green: 0xD6 / 255, blue: 0xBC / 255)
    private let ink = Color(red: 0x22 / 255, green: 0x1D / 255, blue: 0x17 / 255)
    private let dim = Color(red: 0x8A / 255, green: 0x7F / 255, blue: 0x71 / 255)
    private let line = Color(red: 0xEC / 255, green: 0xE5 / 255, blue: 0xD8 / 255)
    private let paper = Color.white
    private let green = Color(red: 0x2F / 255, green: 0x8A / 255, blue: 0x57 / 255)
    private let red = Color(red: 0xB2 / 255, green: 0x3A / 255, blue: 0x2B / 255)

    var body: some View {
        let maxSeconds = max(usage.days.flatMap { [$0.seconds, $0.lastWeekSeconds] }.max() ?? 1, 60)
        let change = WeeklyUsage.change(this: usage.thisWeekTotal, last: usage.lastWeekTotal)
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TIME IN YOUR LOCKED APPS").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(dim)
                Text("\(WeeklyUsage.duration(usage.thisWeekTotal)) this week").font(.system(size: 30, weight: .medium, design: .serif)).foregroundStyle(ink)
                if let change {
                    Text(change <= 0
                         ? "\(abs(change))% less than last week (\(WeeklyUsage.duration(usage.lastWeekTotal)))"
                         : "\(change)% more than last week (\(WeeklyUsage.duration(usage.lastWeekTotal)))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(change <= 0 ? green : red)
                } else {
                    Text("Last week will show here once there is a week of history.").font(.subheadline).foregroundStyle(dim)
                }
                Text("About \(WeeklyUsage.duration(usage.thisWeekTotal / 7)) a day").font(.footnote).foregroundStyle(dim)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    legend(gold, "This week")
                    legend(ghost, "Same day last week")
                }
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(usage.days) { day in
                        VStack(spacing: 6) {
                            if Calendar.current.isDateInToday(day.date) {
                                Text(WeeklyUsage.duration(day.seconds)).font(.caption2.weight(.semibold)).foregroundStyle(ink).fixedSize()
                            }
                            HStack(alignment: .bottom, spacing: 3) {
                                RoundedRectangle(cornerRadius: 3).fill(ghost)
                                    .frame(height: max(4, 120 * day.lastWeekSeconds / maxSeconds))
                                RoundedRectangle(cornerRadius: 3).fill(gold)
                                    .frame(height: max(4, 120 * day.seconds / maxSeconds))
                            }
                            .frame(height: 124, alignment: .bottom)
                            Text(day.date.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(dim)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text("Each pair of bars is one day. Shorter gold bars mean less time in the apps you lock.")
                    .font(.caption).foregroundStyle(dim)
            }

            if !usage.apps.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text("BY APP").frame(maxWidth: .infinity, alignment: .leading)
                        Text("LAST WEEK").frame(width: 72, alignment: .trailing)
                        Text("THIS WEEK").frame(width: 72, alignment: .trailing)
                        Text("").frame(width: 58)
                    }
                    .font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(dim)
                    .padding(.bottom, 8)
                    ForEach(usage.apps) { app in
                        HStack {
                            Text(app.name).font(.subheadline.weight(.medium)).foregroundStyle(ink).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(WeeklyUsage.duration(app.lastWeek)).foregroundStyle(dim).frame(width: 72, alignment: .trailing)
                            Text(WeeklyUsage.duration(app.thisWeek)).foregroundStyle(ink).frame(width: 72, alignment: .trailing)
                            pill(WeeklyUsage.change(this: app.thisWeek, last: app.lastWeek)).frame(width: 58, alignment: .trailing)
                        }
                        .font(.subheadline).monospacedDigit()
                        .padding(.vertical, 11)
                        if app.id != usage.apps.last?.id { Rectangle().fill(line).frame(height: 1) }
                    }
                }
            }

            Text("Counts only the apps you lock in Wick. Data comes from Screen Time and never leaves your iPhone.")
                .font(.caption).foregroundStyle(dim)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(paper)
        .environment(\.colorScheme, .light)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption).foregroundStyle(dim)
        }
    }

    @ViewBuilder
    private func pill(_ change: Int?) -> some View {
        if let change {
            Text(change <= 0 ? "↓\(abs(change))%" : "↑\(change)%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(change <= 0 ? green : red)
        } else {
            Text("new").font(.caption).foregroundStyle(dim)
        }
    }
}
