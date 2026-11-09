/// What a plan issue is about. The raw value is the name sent to the AI.
public enum IssueKind: String, CaseIterable, Hashable, Sendable, Codable {
    /// The place is closed on that date.
    case closed
    /// The stop does not fit inside one open period of its place.
    case outsideHours
    /// The place has no known opening hours.
    case hoursUnknown
    /// A stop starts before the previous one ends.
    case overlap
    /// The gap between two stops is shorter than the walk between them.
    case tightGap
    /// The gap between two stops is short for a walk of that length.
    case shortGap
    /// A full day has no breakfast, lunch or dinner.
    case mealMissing
    /// A meal starts outside its time slot. It still counts as the meal.
    case mealOffSlot
    /// An outdoor sight ends after sunset.
    case afterSunset
    /// An outdoor sight ends less than 15 minutes before sunset.
    case nearSunset
    /// Sunset is not known for the date, so daylight is not checked.
    case noDaylightData
    /// A stop starts before the traveller can reach it after arriving.
    case beforeArrival
    /// The last stop before departure ends too late to reach the train.
    case missedDeparture
    /// The last stop before departure ends close to the leave-by time.
    case tightDeparture
    /// A logistics stop at the stay starts before check-in.
    case checkInEarly
    /// The first stop away from the stay starts after check-out.
    case checkOutLate
    /// A logistics stop at the luggage store is outside its opening hours.
    case luggageClosed
    /// The traveller has luggage to leave, the store is open, and no stop leaves bags there.
    case luggageUnused
    /// The day's walking is more than 1.2 times the pace limit.
    case walkingOverPace
    /// A transit booking does not name its station, so the walk from or to it is not checked.
    case stationUnknown
}
