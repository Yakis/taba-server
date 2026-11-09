/// The assembled guide, the copy problems found while building it, and how plan stop ids became guide stop ids.
public struct AssemblyResult: Hashable, Sendable {
    public let guide: Guide
    /// Empty when the plan and the copy match exactly.
    public let problems: [AssemblyProblem]
    /// Maps each plan stop id to the id it has in the guide (`d<day>-s<n>`, in time order).
    public let stopIds: [String: String]

    public init(guide: Guide, problems: [AssemblyProblem], stopIds: [String: String]) {
        self.guide = guide
        self.problems = problems
        self.stopIds = stopIds
    }
}
