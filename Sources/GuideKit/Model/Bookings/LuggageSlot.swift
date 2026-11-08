/// When a luggage store is open for the travellers' bags.
public struct LuggageSlot: Hashable, Sendable, Codable {
    public let placeId: String
    public let opens: LocalTime
    public let closes: LocalTime

    public init(placeId: String, opens: LocalTime, closes: LocalTime) {
        self.placeId = placeId
        self.opens = opens
        self.closes = closes
    }
}
