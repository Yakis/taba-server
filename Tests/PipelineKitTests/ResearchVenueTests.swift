import GuideKit
import PipelineKit
import Testing

struct ResearchVenueTests {
    private let url = "https://example.com/christmas"

    private func finding(
        id: String = "f1",
        kind: FindingKind = .market,
        placeName: String? = "Princes Street Gardens",
        address: String? = "Princes Street, Edinburgh",
        url: String? = nil,
        onTripDates: Bool = true
    ) -> ResearchFinding {
        ResearchFinding(id: id, kind: kind, title: "Christmas Market", summary: "A seasonal market.",
                        startDate: nil, endDate: nil, times: nil, placeName: placeName, address: address,
                        url: url ?? self.url, sourceTitle: "Council page", confidence: .high, onTripDates: onTripDates)
    }

    private func suggestion(_ name: String, kind: PlaceKind = .cafe) -> SuggestedPlace {
        SuggestedPlace(name: name, area: "Centre", kind: kind, why: "Worth a visit")
    }

    @Test func aMarketOnTripDatesBecomesAMarketVenue() {
        let venues = ResearchVerification.venueSuggestions(for: [finding()], reportedURLs: [url], existing: [])
        #expect(venues == [SuggestedPlace(name: "Princes Street Gardens", area: "Princes Street, Edinburgh",
                                          kind: .market, why: "Christmas Market")])
    }

    @Test func anEventBecomesALandmarkVenue() {
        let event = finding(kind: .event, placeName: "Old Town Hall")
        let venues = ResearchVerification.venueSuggestions(for: [event], reportedURLs: [url], existing: [])
        #expect(venues.map(\.kind) == [.landmark])
        #expect(venues.map(\.name) == ["Old Town Hall"])
    }

    @Test func otherFindingKindsAddNothing() {
        let kinds: [FindingKind] = [.closure, .transport, .holiday, .other]
        let findings = kinds.enumerated().map { finding(id: "f\($0.offset)", kind: $0.element) }
        #expect(ResearchVerification.venueSuggestions(for: findings, reportedURLs: [url], existing: []).isEmpty)
    }

    @Test func findingsOffTheTripDatesAddNothing() {
        let off = finding(onTripDates: false)
        #expect(ResearchVerification.venueSuggestions(for: [off], reportedURLs: [url], existing: []).isEmpty)
    }

    @Test func aFindingWithoutAPlaceNameAddsNothing() {
        let nameless = [finding(placeName: nil), finding(id: "f2", placeName: "   ")]
        #expect(ResearchVerification.venueSuggestions(for: nameless, reportedURLs: [url], existing: []).isEmpty)
    }

    @Test func aFindingWhoseSourceWasNotReportedAddsNothing() {
        let unreported = finding(url: "https://example.com/not-searched")
        #expect(ResearchVerification.venueSuggestions(for: [unreported], reportedURLs: [url], existing: []).isEmpty)
    }

    @Test func aVenueAnExistingSuggestionNamesIsNotAddedTwice() {
        let existing = [suggestion("princes street gardens east lawn")]
        let venues = ResearchVerification.venueSuggestions(for: [finding()], reportedURLs: [url], existing: existing)
        #expect(venues.isEmpty)
    }

    @Test func nameMatchingIgnoresCaseAndEitherContainsTheOther() {
        let existing = [suggestion("CHRISTMAS VILLAGE, Princes Street Gardens")]
        let venues = ResearchVerification.venueSuggestions(for: [finding()], reportedURLs: [url], existing: existing)
        #expect(venues.isEmpty)
    }

    @Test func aVenueWithADifferentNameIsAddedBesideAnExistingSuggestion() {
        let existing = [suggestion("Waverley Market")]
        let venues = ResearchVerification.venueSuggestions(for: [finding()], reportedURLs: [url], existing: existing)
        #expect(venues.map(\.name) == ["Princes Street Gardens"])
    }

    @Test func oneVenueTwoFindingsIsAddedOnce() {
        let first = finding(id: "f1")
        let second = finding(id: "f2", kind: .event)
        let venues = ResearchVerification.venueSuggestions(for: [first, second], reportedURLs: [url], existing: [])
        #expect(venues.map(\.name) == ["Princes Street Gardens"])
    }

    @Test func missingAddressGivesAnEmptyArea() {
        let venues = ResearchVerification.venueSuggestions(
            for: [finding(address: nil)], reportedURLs: [url], existing: []
        )
        #expect(venues.map(\.area) == [""])
    }
}
