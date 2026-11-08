/// One day of a plan: a working theme and its stops in the planner's order.
public struct PlanDraftDay: Hashable, Sendable, Codable {
    public let date: LocalDate
    /// A working theme of at most eight words. The writer turns it into the day's title.
    public let theme: String
    public let stops: [PlanDraftStop]

    public init(date: LocalDate, theme: String, stops: [PlanDraftStop]) {
        self.date = date
        self.theme = theme
        self.stops = stops
    }
}
