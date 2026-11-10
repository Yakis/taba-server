import Foundation
import GuideKit
import SourcesKit

extension SourcePreparation {
    /// The luggage store the traveller named, placed on the map with its assumed hours. Nil when no name was given,
    /// or when the name is not found: the build goes on without a store and the plan carries the bags.
    static func luggageStore(_ options: SourceInput, geocoder: NominatimGeocoder) async throws
        -> (place: Place, slot: LuggageSlot)? {
        guard let name = options.luggage,
              let found = try await geocoder.geocode(name + ", " + options.destination) else { return nil }
        guard let opens = LocalTime("08:00"), let closes = LocalTime("20:00") else {
            throw SourcePreparationError.service
        }
        let place = Place(id: "manual:luggage", name: name, kind: .luggage,
                          location: PlaceLocation(coordinate: found.coordinate, address: found.displayName,
                                                  approximate: false),
                          hours: OpeningHours(hoursKnown: false, weekly: [], exceptions: []), priceLevel: nil,
                          booking: PlaceBooking(needed: false, url: nil), indoor: true,
                          images: [], facts: [], copy: nil)
        return (place, LuggageSlot(placeId: place.id, opens: opens, closes: closes))
    }
}
