import Foundation
import FoursquareKit
import Testing

struct WireTests {
    @Test func decodesASearchResultWithItsCoreFields() throws {
        let places = try Samples.decodePlaces("{\"results\":[\(Samples.abbotsfordJSON)]}")
        let place = try #require(places.first)
        #expect(place.fsqPlaceId == "4b5f2d1e0000000000000001")
        #expect(place.name == "The Abbotsford")
        #expect(place.latitude == 55.9532705)
        #expect(place.longitude == -3.1946516)
        #expect(place.location?.formattedAddress == "3-5 Rose Street, Edinburgh EH2 2PR")
        #expect(place.location?.postcode == "EH2 2PR")
        #expect(place.categories.map(\.name) == ["Pubs"])
        #expect(place.categories.first?.id == "4bf58dd8d48988d11b941735")
        #expect(place.dateClosed == "")
        #expect(place.hours == nil)
    }

    @Test func decodesDetailsWithHoursAndRating() throws {
        let place = try Samples.decodePlace(Samples.detailsJSON)
        #expect(place.rating == 8.1)
        #expect(place.hours?.display == "Open until 1:00 AM")
        #expect(place.hours?.openNow == true)
        #expect(place.hours?.regular.count == 4)
        #expect(place.hours?.regular.first?.day == 1)
        #expect(place.hours?.regular.first?.open == "1100")
    }

    @Test func aMalformedSectionIsDroppedNotFatal() throws {
        // "hours" is a string here, not an object. The place must still decode, with hours missing.
        let json = """
        {"fsq_place_id":"abc","name":"Test Place","latitude":55.95,"longitude":-3.19,
         "categories":[],"hours":"unexpected text"}
        """
        let place = try Samples.decodePlace(json)
        #expect(place.name == "Test Place")
        #expect(place.hours == nil)
    }

    @Test func aMissingNameIsAnError() {
        #expect(throws: (any Error).self) {
            _ = try Samples.decodePlace("{\"fsq_place_id\":\"abc\"}")
        }
    }

    @Test func errorBodyCarriesTheMessage() throws {
        let body = try JSONDecoder().decode(FoursquareErrorBody.self, from: Data("{\"message\":\"Invalid key\"}".utf8))
        #expect(body.message == "Invalid key")
    }
}
