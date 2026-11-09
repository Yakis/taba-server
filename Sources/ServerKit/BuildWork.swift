import Foundation
import GuideKit
import PipelineKit
import ResponsesKit

/// Each stage is a separate durable job and checkpoint.
public enum BuildStage: String, Codable, Sendable, CaseIterable {
    case basics, candidates, research, plan, check, write, assemble

    public var next: BuildStage? {
        let stages = Self.allCases
        guard let index = stages.firstIndex(of: self), index + 1 < stages.count else { return nil }
        return stages[index + 1]
    }
}

public struct BuildWork: Sendable {
    public let tripID: UUID
    public let input: TripBuildInput
    public let stage: BuildStage
    public let checkpoints: [BuildStage: Data]

    public init(tripID: UUID, input: TripBuildInput, stage: BuildStage, checkpoints: [BuildStage: Data]) {
        self.tripID = tripID
        self.input = input
        self.stage = stage
        self.checkpoints = checkpoints
    }
}

public struct StageResult: Sendable {
    public let checkpoint: Data
    public let guide: Guide?

    public init(checkpoint: Data, guide: Guide? = nil) {
        self.checkpoint = checkpoint
        self.guide = guide
    }
}

public enum BuildEvidence: Sendable {
    case pipeline(PipelineEvidence)
    case source([String: JSONValue])
}

public typealias BuildEvidenceSink = @Sendable (BuildEvidence) async -> Void
public typealias StageRunner = @Sendable (BuildWork, @escaping BuildEvidenceSink) async throws -> StageResult
