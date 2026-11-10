import Foundation
import GuideKit

/// How long a build took, worked out from the trip's progress rows. Pure, so the arithmetic is tested without a
/// database.
public enum BuildTiming {
    /// One progress row: the trip entered `state` at `at`.
    public struct Event: Sendable, Equatable {
        public let state: TripState
        public let enteredAt: Date

        public init(state: TripState, enteredAt: Date) {
            self.state = state
            self.enteredAt = enteredAt
        }
    }

    /// The build time for a trip created at `created`, given its progress rows in order, with `now` as the end.
    /// Work time is the sum of the spans that begin at a running row and end at the next row, or at `now` for the
    /// last one. Work never exceeds the total, and both are whole seconds.
    public static func buildTime(created: Date, events: [Event], now: Date) -> BuildTime {
        let total = seconds(from: created, to: now)
        var work: TimeInterval = 0
        for (index, event) in events.enumerated() where event.state == .running {
            let end = index + 1 < events.count ? events[index + 1].enteredAt : now
            work += max(0, end.timeIntervalSince(event.enteredAt))
        }
        return BuildTime(totalSeconds: total, workSeconds: min(Int(work.rounded()), total))
    }

    private static func seconds(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start).rounded()))
    }
}
