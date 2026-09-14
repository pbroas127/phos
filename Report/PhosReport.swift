import DeviceActivity
import FamilyControls
import ManagedSettings
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
        // iOS reports the whole phone. Locked apps are found by matching the tokens chosen in Wick's locks.
        var apps = Set<ApplicationToken>(), categories = Set<ActivityCategoryToken>(), domains = Set<WebDomainToken>()
        for lock in SharedStore.shared.settings.lockSets {
            guard let data = lock.selection, let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { continue }
            apps.formUnion(sel.applicationTokens)
            categories.formUnion(sel.categoryTokens)
            domains.formUnion(sel.webDomainTokens)
        }

        var allTotals: [Date: TimeInterval] = [:]
        var lockedTotals: [Date: TimeInterval] = [:]
        var appDays: [String: [Date: TimeInterval]] = [:]
        let calendar = Calendar.current
        for await item in data {
            for await segment in item.activitySegments {
                let day = calendar.startOfDay(for: segment.dateInterval.start)
                allTotals[day, default: 0] += segment.totalActivityDuration
                for await category in segment.categories {
                    let wholeCategory = category.category.token.map { categories.contains($0) } ?? false
                    for await app in category.applications {
                        guard wholeCategory || (app.application.token.map { apps.contains($0) } ?? false) else { continue }
                        lockedTotals[day, default: 0] += app.totalActivityDuration
                        let name = app.application.localizedDisplayName ?? "Other"
                        appDays[name, default: [:]][day, default: 0] += app.totalActivityDuration
                    }
                    for await site in category.webDomains {
                        guard wholeCategory || (site.webDomain.token.map { domains.contains($0) } ?? false) else { continue }
                        lockedTotals[day, default: 0] += site.totalActivityDuration
                        let name = site.webDomain.domain ?? "Website"
                        appDays[name, default: [:]][day, default: 0] += site.totalActivityDuration
                    }
                }
            }
        }
        return WeeklyUsage.build(dayTotals: lockedTotals, allDayTotals: allTotals, appDays: appDays, now: Date(), calendar: calendar)
    }
}
