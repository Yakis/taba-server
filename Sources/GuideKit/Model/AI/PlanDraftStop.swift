/// One timed stop in a plan. The `id` is the planner's (`d<day>-s<n>`); assembly renumbers stops in time order.
public struct PlanDraftStop: Hashable, Sendable, Codable {
    public let id: String
    /// A candidate place id, or nil for a stop with no place (a station transfer, or a meal "somewhere near").
    public let placeId: String?
    public let kind: StopKind
    /// Only set for meal stops.
    public let mealSlot: MealSlot?
    public let start: LocalTime
    public let minutes: Int
    public let flexible: Bool
    public let alternative: StopAlternative?
    /// At most 20 words on why the stop is here at this time. Read by the writer and the developer, not the traveller.
    public let reason: String
    /// The findings this stop relies on, or an empty list.
    public let findingIds: [String]

    public init(
        id: String,
        placeId: String?,
        kind: StopKind,
        mealSlot: MealSlot?,
        start: LocalTime,
        minutes: Int,
        flexible: Bool,
        alternative: StopAlternative?,
        reason: String,
        findingIds: [String]
    ) {
        self.id = id
        self.placeId = placeId
        self.kind = kind
        self.mealSlot = mealSlot
        self.start = start
        self.minutes = minutes
        self.flexible = flexible
        self.alternative = alternative
        self.reason = reason
        self.findingIds = findingIds
    }
}
