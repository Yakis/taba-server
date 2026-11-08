/// One day in a plan draft.
public struct PlanDraftDay: Hashable, Sendable, Codable {
    public let date: LocalDate
    public let copy: DayCopy
    public let stops: [PlanDraftStop]

    public init(date: LocalDate, copy: DayCopy, stops: [PlanDraftStop]) {
        self.date = date
        self.copy = copy
        self.stops = stops
    }
}
