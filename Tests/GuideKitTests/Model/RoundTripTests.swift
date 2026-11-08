import Foundation
import GuideKit
import Testing

struct RoundTripTests {
    @Test func guideRoundTrips() throws {
        let guide = SampleGuide.make()
        let decoded = try roundTrip(guide)
        #expect(decoded == guide)
    }

    @Test(arguments: SampleGuide.placeIds)
    func placeRoundTrips(placeId: String) throws {
        let place = try #require(SampleGuide.samplePlaces()[placeId])
        let decoded = try roundTrip(place)
        #expect(decoded == place)
    }

    @Test(arguments: 0..<3)
    func stopRoundTrips(index: Int) throws {
        let stop = SampleGuide.stops()[index]
        let decoded = try roundTrip(stop)
        #expect(decoded == stop)
    }

    @Test func bookingRoundTrips() throws {
        let booking = SampleGuide.trainBooking()
        let decoded = try roundTrip(booking)
        #expect(decoded == booking)
    }

    @Test func planDraftRoundTrips() throws {
        let draft = SampleGuide.planDraft()
        let decoded = try roundTrip(draft)
        #expect(decoded == draft)
    }

    @Test func missingOptionalsAreOmittedFromJSON() throws {
        let stop = try #require(SampleGuide.stops().last)
        let json = try encodedJSON(stop)
        #expect(!json.contains("\"placeId\""))
        #expect(!json.contains("\"mealSlot\""))
        #expect(!json.contains("\"alternative\""))
        #expect(!json.contains("\"legFromPrevious\""))
    }

    @Test func encodingIsStable() throws {
        let guide = SampleGuide.make()
        let first = try encodedJSON(guide)
        let decoded = try roundTrip(guide)
        let second = try encodedJSON(decoded)
        #expect(first == second)
    }
}
