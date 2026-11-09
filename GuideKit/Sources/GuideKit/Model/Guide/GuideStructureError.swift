/// Thrown by `Guide.validateStructure()`. Lists every problem found, not just the first.
public struct GuideStructureError: Error, Hashable, Sendable {
    public let problems: [StructureProblem]

    public init(problems: [StructureProblem]) {
        self.problems = problems
    }
}
