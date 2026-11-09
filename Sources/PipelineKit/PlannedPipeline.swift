import GuideKit
import ResponsesKit

/// Private trip data needed to check and repair an initial plan after a job restart.
public struct PlannedPipeline: Codable, Sendable {
    public let draft: PlanDraft
    public let previousAssistant: String
    public let conversation: PipelineConversation
    public let planInput: JSONValue

}
