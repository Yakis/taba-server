/// A structural inconsistency that decoding accepts but `Guide.validateStructure()` reports.
public enum StructureProblem: Hashable, Sendable {
    /// The dictionary key for a place does not equal that place's `id`.
    case placeKeyMismatch(key: String, placeId: String)
    /// A place's price level is outside 1...4.
    case priceLevelOutOfRange(placeId: String, level: Int)
    /// The trip's end date is before its start date.
    case tripEndsBeforeStart
    /// A booking's `arrives` is before its `departs`.
    case bookingArrivesBeforeDeparts(bookingId: String)
    /// A stop's `minutes` is zero or negative.
    case stopMinutesNotPositive(stopId: String)
    /// A place id used by the stay, a list, or a stop (or its alternative) is not in `places`.
    /// `from` says where the reference is, for example "stop d1-lunch" or "list Eat".
    case unknownPlaceReference(placeId: String, from: String)
    /// A fact cites a source id that is not in `sources`. `from` says where the fact is.
    case unknownSourceReference(sourceId: String, from: String)
    /// A day's date falls outside the trip's start and end dates.
    case dayOutsideTripDates(date: LocalDate)
    /// Two or more stops share the same id.
    case duplicateStopId(stopId: String)
}
