import GuideKit
@testable import PipelineKit
import Testing

struct ServedInterestsTests {
    private func place(_ id: String, _ kind: PlaceKind, indoor: Bool = true) -> Place {
        Place(id: id, name: id, kind: kind,
              location: PlaceLocation(coordinate: Coordinate(latitude: 55.95, longitude: -3.19)!, address: nil,
                                      approximate: false),
              hours: OpeningHours(hoursKnown: false, weekly: [], exceptions: []), priceLevel: nil,
              booking: PlaceBooking(needed: false, url: nil), indoor: indoor, images: [], facts: [], copy: nil)
    }

    @Test func recordsTheInterestsEachPlaceServesInTripOrder() {
        let places = ["market": place("market", .market), "cafe": place("cafe", .cafe),
                      "museum": place("museum", .museum)]
        let served = ServedInterests.byPlace(places, interests: ["Markets", "Food", "Music"], searchLabels: [:])
        #expect(served == ["market": ["Markets", "Food"], "cafe": ["Food"]])
    }

    @Test func researchedLabelsServeTheirInterest() {
        let places = ["stall": place("stall", .other)]
        let label = InterestMatch.interestLabel(for: "Photography")
        let served = ServedInterests.byPlace(places, interests: ["Photography"],
                                             searchLabels: ["stall": [label]])
        #expect(served == ["stall": ["Photography"]])
    }
}
