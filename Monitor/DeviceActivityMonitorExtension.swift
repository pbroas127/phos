import DeviceActivity
import Foundation

/// Runs in the background when a day starts, when lock windows open and close, when an unlock ends, and when usage passes a threshold.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        LockEngine.handleIntervalStart(activity)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        LockEngine.recordUsage(event)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        LockEngine.handleIntervalEnd(activity)
    }
}
