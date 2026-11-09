/// What the planner returns for a trip: which places, in what order, at what times. It has no prose, only a short
/// reason for each stop. The writer turns a checked plan into a `GuideCopy`.
///
/// Stops are timed by the AI, but walking times, opening hours and daylight are measured by code and checked
/// afterwards. A repair answer has the same shape and fills `changes`.
public struct PlanDraft: Hashable, Sendable, Codable {
    public let days: [PlanDraftDay]
    public let lists: [DraftList]
    public let skippedMeals: [SkippedMeal]
    public let openQuestions: [String]
    /// One plain sentence per change made by a repair. Empty on a first plan.
    public let changes: [String]

    public init(
        days: [PlanDraftDay],
        lists: [DraftList],
        skippedMeals: [SkippedMeal],
        openQuestions: [String],
        changes: [String]
    ) {
        self.days = days
        self.lists = lists
        self.skippedMeals = skippedMeals
        self.openQuestions = openQuestions
        self.changes = changes
    }
}
