import Foundation

/// The current time, protected against someone changing the iPhone's clock to skip a lock or a wait.
/// A monotonic clock that keeps counting while the phone sleeps is anchored to the wall clock once per boot.
/// If the wall clock later disagrees with it by more than two minutes, the monotonic estimate wins.
/// ponytail: a clock changed before a reboot is not caught, and a changed clock is accepted after a day. Upgrade path is network time.
enum TrustedClock {
    private static let wallKey = "clock.anchorWall"
    private static let monoKey = "clock.anchorMono"
    private static let tolerance: TimeInterval = 120
    private static let reanchorAfter: TimeInterval = 86_400

    static func monotonic() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }

    static func now(defaults: UserDefaults? = UserDefaults(suiteName: AppGroup.id)) -> Date {
        let wall = Date()
        let mono = monotonic()
        guard let d = defaults else { return wall }
        let anchorWall = d.double(forKey: wallKey)
        let anchorMono = d.double(forKey: monoKey)
        // No anchor yet, or the phone restarted (the monotonic clock starts over), or a day has passed: trust the wall clock again.
        if anchorWall == 0 || mono < anchorMono || mono - anchorMono > reanchorAfter {
            d.set(wall.timeIntervalSince1970, forKey: wallKey)
            d.set(mono, forKey: monoKey)
            return wall
        }
        let estimate = Date(timeIntervalSince1970: anchorWall + (mono - anchorMono))
        return abs(wall.timeIntervalSince(estimate)) > tolerance ? estimate : wall
    }

    /// Pure check used by tests: the time to use given a wall clock reading, a monotonic reading, and the anchor.
    static func resolve(wall: Date, mono: TimeInterval, anchorWall: TimeInterval, anchorMono: TimeInterval) -> Date {
        guard anchorWall != 0, mono >= anchorMono, mono - anchorMono <= reanchorAfter else { return wall }
        let estimate = Date(timeIntervalSince1970: anchorWall + (mono - anchorMono))
        return abs(wall.timeIntervalSince(estimate)) > tolerance ? estimate : wall
    }
}
