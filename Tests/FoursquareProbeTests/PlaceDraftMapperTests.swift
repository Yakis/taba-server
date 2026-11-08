import FoursquareKit
import GuideKit
import Testing

struct PlaceDraftMapperTests {
    @Test func buildsAFixturePlaceDraft() throws {
        let place = try Samples.decodePlace(Samples.detailsJSON)
        let draft = try #require(PlaceDraftMapper.draft(from: place))
        #expect(draft.id == "fsq:4b5f2d1e0000000000000001")
        #expect(draft.name == "The Abbotsford")
        #expect(draft.kind == .pub)
        #expect(draft.indoor)
        #expect(draft.location.coordinate.latitude == 55.9532705)
        #expect(draft.location.address == "3-5 Rose Street, Edinburgh EH2 2PR")
        #expect(draft.hours.hoursKnown)
        #expect(draft.priceLevel == nil)
        #expect(draft.images.isEmpty)
    }

    @Test func outdoorKindsAreNotIndoor() throws {
        let json = """
        {"fsq_place_id":"s","name":"Calton Hill","latitude":55.9552,"longitude":-3.1827,
         "categories":[{"fsq_category_id":"c","name":"Scenic Lookouts"}]}
        """
        let draft = try #require(PlaceDraftMapper.draft(from: Samples.decodePlace(json)))
        #expect(draft.kind == .viewpoint)
        #expect(!draft.indoor)
        #expect(!draft.hours.hoursKnown)
    }

    @Test func placeWithoutCoordinatesGivesNoDraft() throws {
        let json = "{\"fsq_place_id\":\"n\",\"name\":\"No Position\",\"categories\":[]}"
        #expect(PlaceDraftMapper.draft(from: try Samples.decodePlace(json)) == nil)
    }
}
