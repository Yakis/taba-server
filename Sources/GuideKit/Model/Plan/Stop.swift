/// One item in a day: a sight, meal, drink, rest, journey or logistics task.
public struct Stop: Hashable, Sendable, Codable {
    public let id: String
    public let kind: StopKind
    /// Only set for meal stops.
    public let mealSlot: MealSlot?
    /// Travel stops between stations may have no place.
    public let placeId: String?
    public let start: LocalTime
    public let minutes: Int
    public let flexible: Bool
    public let alternative: StopAlternative?
    public let copy: StopCopy
    /// Computed after planning, never written by the AI.
    public let legFromPrevious: Leg?

    public init(
        id: String,
        kind: StopKind,
        mealSlot: MealSlot?,
        placeId: String?,
        start: LocalTime,
        minutes: Int,
        flexible: Bool,
        alternative: StopAlternative?,
        copy: StopCopy,
        legFromPrevious: Leg?
    ) {
        self.id = id
        self.kind = kind
        self.mealSlot = mealSlot
        self.placeId = placeId
        self.start = start
        self.minutes = minutes
        self.flexible = flexible
        self.alternative = alternative
        self.copy = copy
        self.legFromPrevious = legFromPrevious
    }
}
