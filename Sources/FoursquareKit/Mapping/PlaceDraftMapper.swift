import GuideKit

/// Turns a Foursquare place into a GuideKit `Place` draft for review.
///
/// The id is "fsq:<fsq_place_id>". Fields Foursquare does not give here are left empty: price level, booking, images,
/// facts and copy. Indoor is inferred from the kind, since Foursquare does not say.
public enum PlaceDraftMapper {
    /// Returns nil when the place has no usable coordinate.
    public static func draft(from place: FoursquarePlace) -> Place? {
        guard let latitude = place.latitude,
              let longitude = place.longitude,
              let coordinate = Coordinate(latitude: latitude, longitude: longitude)
        else {
            return nil
        }
        let kind = PlaceKindMapper.kind(for: place.categories)
        let address = place.location?.formattedAddress ?? place.location?.address
        return Place(
            id: "fsq:\(place.fsqPlaceId)",
            name: place.name,
            kind: kind,
            location: PlaceLocation(coordinate: coordinate, address: address, approximate: false),
            hours: HoursMapper.openingHours(from: place.hours).hours,
            priceLevel: nil,
            booking: PlaceBooking(needed: false, url: nil),
            indoor: isIndoor(kind),
            images: [],
            facts: [],
            copy: nil
        )
    }

    /// Streets, viewpoints, neighbourhoods and markets are taken as outdoors. Everything else as indoors.
    static func isIndoor(_ kind: PlaceKind) -> Bool {
        switch kind {
        case .street, .viewpoint, .neighbourhood, .market:
            return false
        default:
            return true
        }
    }
}
