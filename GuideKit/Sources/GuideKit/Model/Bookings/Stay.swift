/// Where the travellers sleep, with check-in and check-out times and an optional luggage store.
public struct Stay: Hashable, Sendable, Codable {
    public let placeId: String
    public let checkIn: LocalTime
    public let checkOut: LocalTime
    public let luggage: LuggageSlot?
    /// True when the travellers carry only hand luggage, so no bag drops or bag talk. Nil means not said.
    public let handLuggageOnly: Bool?

    public init(placeId: String, checkIn: LocalTime, checkOut: LocalTime, luggage: LuggageSlot?,
                handLuggageOnly: Bool? = nil) {
        self.placeId = placeId
        self.checkIn = checkIn
        self.checkOut = checkOut
        self.luggage = luggage
        self.handLuggageOnly = handLuggageOnly
    }
}
