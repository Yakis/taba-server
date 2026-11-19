import GuideKit
@testable import PipelineKit
import Testing

struct AfterDarkPlacesTests {
    private let places: [String: Place]

    init() throws {
        let location = PlaceLocation(coordinate: try #require(Coordinate(latitude: 51.5, longitude: -0.1)),
                                     address: nil, approximate: false)
        func place(_ id: String, _ name: String, kind: PlaceKind) -> Place {
            Place(id: id, name: name, kind: kind, location: location,
                  hours: OpeningHours(hoursKnown: false, weekly: [], exceptions: []), priceLevel: nil,
                  booking: PlaceBooking(needed: false, url: nil), indoor: false, images: [], facts: [], copy: nil)
        }
        places = ["a": place("a", "Riverside Gardens", kind: .landmark),
                  "b": place("b", "Harbour Museum", kind: .museum)]
    }

    private func finding(kind: FindingKind = .market, title: String = "Winter market", placeName: String?,
                         onTripDates: Bool = true) -> ResearchFinding {
        ResearchFinding(id: "f1", kind: kind, title: title, summary: "Stalls and lights.", startDate: nil,
                        endDate: nil, times: nil, placeName: placeName, address: nil,
                        url: "https://example.com/market", sourceTitle: "Example", confidence: .high,
                        onTripDates: onTripDates)
    }

    private func marked(_ findings: [ResearchFinding]) -> [String: Place] {
        AfterDarkPlaces.marked(places, findings: findings, cityName: "Testville")
    }

    @Test func aMarketOnTheTripDatesMarksThePlaceItNames() {
        let result = marked([finding(placeName: "Riverside Gardens")])
        #expect(result["a"]?.afterDark == true)
        #expect(result["b"]?.afterDark == nil)
    }

    @Test func anEventMarksThePlaceItsTitleNamesWhenThereIsNoPlaceName() {
        let event = finding(kind: .event, title: "Lantern evening in Riverside Gardens", placeName: nil)
        #expect(marked([event])["a"]?.afterDark == true)
    }

    @Test func aFindingOffTheTripDatesMarksNothing() {
        #expect(marked([finding(placeName: "Riverside Gardens", onTripDates: false)]) == places)
    }

    @Test func aClosureMarksNothing() {
        #expect(marked([finding(kind: .closure, placeName: "Riverside Gardens")]) == places)
    }

    @Test func aFindingNamingAnotherPlaceMarksNothing() {
        #expect(marked([finding(placeName: "Castle Square")]) == places)
    }
}
