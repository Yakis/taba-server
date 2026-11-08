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
}
