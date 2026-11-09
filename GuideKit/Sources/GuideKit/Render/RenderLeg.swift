/// The row on the timeline that says how to get from the previous stop to this one: "8 min walk",
/// "21 min walk · long walk" or "12 min by transit". Same rules as the app's `LegRow`.
enum RenderLeg {
    /// The row's text, or nil when no row is worth showing: no leg, under 60 metres, or both stops at the same place.
    /// - Parameters:
    ///   - previousPlaceId: The place of the stop before. Nil when unknown, which never hides the leg.
    ///   - placeId: The place of this stop.
    static func text(_ leg: Leg?, previousPlaceId: String?, placeId: String?) -> String? {
        guard let leg, leg.metres >= 60 else { return nil }
        if let previousPlaceId, previousPlaceId == placeId {
            return nil
        }
        guard leg.mode == .walk else {
            return "\(leg.minutes) min by transit"
        }
        return leg.minutes > 20 ? "\(leg.minutes) min walk · long walk" : "\(leg.minutes) min walk"
    }
}
