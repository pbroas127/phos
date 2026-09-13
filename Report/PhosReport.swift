import DeviceActivity
import SwiftUI

@main
struct PhosReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        WeeklyReportScene { usage in
            WeeklyUsageView(usage: usage)
        }
    }
}

struct WeeklyReportScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .weekly
    let content: (WeeklyUsage) -> WeeklyUsageView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> WeeklyUsage {
        var dayTotals: [Date: TimeInterval] = [:]
        var appDays: [String: [Date: TimeInterval]] = [:]
        let calendar = Calendar.current
        for await item in data {
            for await segment in item.activitySegments {
                let day = calendar.startOfDay(for: segment.dateInterval.start)
                dayTotals[day, default: 0] += segment.totalActivityDuration
                for await category in segment.categories {
                    for await app in category.applications {
                        let name = app.application.localizedDisplayName ?? "Other"
                        appDays[name, default: [:]][day, default: 0] += app.totalActivityDuration
                    }
                }
            }
        }
        return WeeklyUsage.build(dayTotals: dayTotals, appDays: appDays, now: Date(), calendar: calendar)
    }
}
