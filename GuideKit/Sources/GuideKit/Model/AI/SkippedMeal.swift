/// A meal the planner left out on purpose, such as after a late, large lunch.
public struct SkippedMeal: Hashable, Sendable, Codable {
    public let date: LocalDate
    public let slot: MealSlot
    public let reason: String

    public init(date: LocalDate, slot: MealSlot, reason: String) {
        self.date = date
        self.slot = slot
        self.reason = reason
    }
}
