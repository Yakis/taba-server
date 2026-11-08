/// Where the travellers sleep, with check-in and check-out times and an optional luggage store.
public struct Stay: Hashable, Sendable, Codable {
    public let placeId: String
    public let checkIn: LocalTime
    public let checkOut: LocalTime
    public let luggage: LuggageSlot?

    public init(placeId: String, checkIn: LocalTime, checkOut: LocalTime, luggage: LuggageSlot?) {
        self.placeId = placeId
        self.checkIn = checkIn
        self.checkOut = checkOut
        self.luggage = luggage
    }
}
