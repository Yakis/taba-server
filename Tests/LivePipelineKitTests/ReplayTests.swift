import Foundation
import GuideKit
import LivePipelineKit
import PipelineKit
import ServerKit
import Testing

private actor EvidenceLog {
    var copyIssues: [CopyCheckIssue] = []
    func add(_ event: BuildEvidence) {
        if case .pipeline(.copy(let issues)) = event { copyIssues = issues }
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TABA_REPLAY_TEST_DIRECTORY"] != nil))
func replayRunsAllSevenStagesOffline() async throws {
    let directory = try #require(ProcessInfo.processInfo.environment["TABA_REPLAY_TEST_DIRECTORY"])
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("GuideKitTests/Fixtures/edinburgh-mock.json")
    let guide = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: fixture))
    let input = try TripBuildInput(destination: guide.trip.destination.name, from: guide.trip.dates.start,
                                   to: guide.trip.dates.end, facts: guide)
    let runner = try ReplayStageRunner(directory: URL(fileURLWithPath: directory))
    let id = UUID()
    let missing = BuildWork(tripID: id, input: input, stage: .candidates, checkpoints: [:])
    await #expect(throws: LiveStageError.self) {
        try await runner.run(missing, evidence: { _ in })
    }
    let different = try TripBuildInput(destination: "Somewhere Else", from: guide.trip.dates.start,
                                       to: guide.trip.dates.end)
    await #expect(throws: ReplayError.self) {
        try await runner.run(BuildWork(tripID: id, input: different, stage: .basics, checkpoints: [:]),
                             evidence: { _ in })
    }
    var checkpoints: [BuildStage: Data] = [:]
    let log = EvidenceLog()
    for stage in BuildStage.allCases {
        let output = try await runner.run(BuildWork(tripID: id, input: input, stage: stage, checkpoints: checkpoints),
                                          evidence: { await log.add($0) })
        checkpoints[stage] = output.checkpoint
        #expect((output.guide != nil) == (stage == .assemble))
    }
    let issues = await log.copyIssues
    #expect(issues.count == 7)
    #expect(issues.allSatisfy { if case .ungroundedNumber = $0.kind { true } else { false } })
}
