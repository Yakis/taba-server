/// One stop in a plan draft. Has no id, legs or checks: those are added when the guide is assembled.
public struct PlanDraftStop: Hashable, Sendable, Codable {
    public let placeId: String?
    public let kind: StopKind
    public let mealSlot: MealSlot?
    public let start: LocalTime
    public let minutes: Int
    public let flexible: Bool
    public let alternative: StopAlternative?
    public let copy: StopCopy

    public init(
        placeId: String?,
        kind: StopKind,
        mealSlot: MealSlot?,
        start: LocalTime,
        minutes: Int,
        flexible: Bool,
        alternative: StopAlternative?,
        copy: StopCopy
    ) {
        self.placeId = placeId
        self.kind = kind
        self.mealSlot = mealSlot
        self.start = start
        self.minutes = minutes
        self.flexible = flexible
        self.alternative = alternative
        self.copy = copy
    }
}
