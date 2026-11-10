import Foundation
import GuideKit
import ServerKit
import Testing

struct BuildTimingTests {
    private let created = Date(timeIntervalSince1970: 1_000)

    /// The moment `seconds` after the trip was created.
    private func at(_ seconds: Double) -> Date {
        created.addingTimeInterval(seconds)
    }

    @Test func workIsOnlyTheRunningSpans() {
        let events: [BuildTiming.Event] = [
            .init(state: .queued, enteredAt: at(0)),
            .init(state: .running, enteredAt: at(10)),
            .init(state: .queued, enteredAt: at(40)),
            .init(state: .running, enteredAt: at(100)),
            .init(state: .completed, enteredAt: at(130))
        ]
        let time = BuildTiming.buildTime(created: created, events: events, now: at(200))
        #expect(time == BuildTime(totalSeconds: 200, workSeconds: 60))
    }

    @Test func aRunningStageStillInProgressCountsUpToNow() {
        let events: [BuildTiming.Event] = [
            .init(state: .queued, enteredAt: at(0)),
            .init(state: .running, enteredAt: at(10))
        ]
        #expect(BuildTiming.buildTime(created: created, events: events, now: at(25))
            == BuildTime(totalSeconds: 25, workSeconds: 15))
    }

    @Test func aTripThatNeverRanHasNoWork() {
        let events: [BuildTiming.Event] = [
            .init(state: .queued, enteredAt: at(0)),
            .init(state: .failed, enteredAt: at(5))
        ]
        #expect(BuildTiming.buildTime(created: created, events: events, now: at(50))
            == BuildTime(totalSeconds: 50, workSeconds: 0))
    }

    @Test func workNeverExceedsTheTotal() {
        // Overlapping or out-of-range rows must not make the work longer than the whole build.
        let events: [BuildTiming.Event] = [
            .init(state: .running, enteredAt: at(0)),
            .init(state: .completed, enteredAt: at(500))
        ]
        let time = BuildTiming.buildTime(created: created, events: events, now: at(100))
        #expect(time == BuildTime(totalSeconds: 100, workSeconds: 100))
    }

    @Test func secondsAreRoundedToWholeSeconds() {
        let events: [BuildTiming.Event] = [.init(state: .running, enteredAt: at(0.4))]
        #expect(BuildTiming.buildTime(created: created, events: events, now: at(2.6))
            == BuildTime(totalSeconds: 3, workSeconds: 2))
    }

    @Test func workerCountReadsTheEnvironmentWithADefault() {
        #expect(BuildWorkers.count(from: nil) == 3)
        #expect(BuildWorkers.count(from: "1") == 1)
        #expect(BuildWorkers.count(from: " 4 ") == 4)
        for invalid in ["0", "5", "-1", "many", "", "2.5"] {
            #expect(BuildWorkers.count(from: invalid) == BuildWorkers.defaultCount)
        }
    }
}
