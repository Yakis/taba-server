import GuideKit
import PipelineKit

/// Measurements of one finished guide, grouped by what they say about it. Plain numbers and ids, so two scores of
/// two pipeline versions can be diffed. Encoded with `GuideKit.jsonEncoder()`, so the keys are sorted.
public struct GuideScore: Codable, Sendable, Equatable {
    public let guideId: String
    public let constraints: ConstraintsScore
    public let interests: InterestsScore
    public let pace: PaceScore
    public let spend: SpendScore
    public let feasibility: FeasibilityScore
    public let content: ContentScore
    public let consistency: ConsistencyScore
}

/// Scores a guide. Deterministic: the same guide always gives the same numbers, and no model is involved.
public enum GuideScorer {
    public static func score(_ guide: Guide, walkTimes: any WalkTimes = StraightLineWalkTimes()) -> GuideScore {
        let context = GuideScoreContext(guide: guide, walkTimes: walkTimes)
        return GuideScore(
            guideId: guide.id,
            constraints: .make(context),
            interests: .make(context),
            pace: .make(context),
            spend: .make(context),
            feasibility: .make(context),
            content: .make(context),
            consistency: .make(context)
        )
    }
}
