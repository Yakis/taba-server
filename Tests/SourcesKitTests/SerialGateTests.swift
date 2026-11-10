import Foundation
import SourcesKit
import Testing

private actor GateProbe {
    private var active = 0
    private(set) var maximum = 0
    private(set) var entered: [Int] = []

    func enter(_ number: Int) {
        active += 1
        maximum = max(maximum, active)
        entered.append(number)
    }

    func leave() { active -= 1 }
}

struct SerialGateTests {
    @Test func onlyOneBodyRunsAtATime() async throws {
        let gate = SerialGate()
        let probe = GateProbe()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for number in 0..<5 {
                group.addTask {
                    _ = try await gate.run {
                        await probe.enter(number)
                        try await Task.sleep(for: .milliseconds(30))
                        await probe.leave()
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(await probe.maximum == 1)
        #expect(Set(await probe.entered) == Set(0..<5))
    }

    @Test func aCancelledWaiterNeverRuns() async throws {
        let gate = SerialGate()
        let probe = GateProbe()
        let holder = Task { try await gate.run { try await Task.sleep(for: .milliseconds(300)) } }
        try await Task.sleep(for: .milliseconds(50))
        let waiter = Task { try await gate.run { await probe.enter(2) } }
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        try await holder.value
        #expect(await probe.entered.isEmpty)
        // The gate is free again for the next caller.
        #expect(try await gate.run { 3 } == 3)
    }

    @Test func aFailingBodyStillReleasesTheGate() async throws {
        let gate = SerialGate()
        await #expect(throws: CancellationError.self) {
            try await gate.run { throw CancellationError() }
        }
        #expect(try await gate.run { 4 } == 4)
    }
}
