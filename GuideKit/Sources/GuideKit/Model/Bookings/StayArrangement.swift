/// Whether the travellers have somewhere to sleep that the guide knows about. Code decides it once, from what the
/// traveller said, and every part of the guide reads it: the plan, the checks, the copy, the map and the lists.
public enum StayArrangement: String, CaseIterable, Hashable, Sendable, Codable {
    /// The traveller named where they sleep. `Stay.placeId` is that place.
    case booked
    /// The trip has a night, but the traveller did not say where they sleep. Nothing is planned or said about it.
    case unknown
    /// The trip has no night and the traveller named no stay: there is nowhere to check in or out of.
    case notNeeded
}
