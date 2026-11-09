import BuildKit
import SourcesKit
import Testing

struct InterestSearchesTests {
    private let music = FoursquarePlacesSource.CategorySearch(label: "music", categoryIds: ["4bf58dd8d48988d1e5931735"])
    private let galleries = FoursquarePlacesSource.CategorySearch(
        label: "galleries", categoryIds: ["4bf58dd8d48988d1e2931735"]
    )
    private let parks = FoursquarePlacesSource.CategorySearch(
        label: "parks", categoryIds: ["4bf58dd8d48988d163941735", "4bf58dd8d48988d15a941735"]
    )
    private let heritage = FoursquarePlacesSource.CategorySearch(
        label: "heritage", categoryIds: ["4deefb944765f83613cdba6e", "4bf58dd8d48988d12d941735"]
    )

    @Test(arguments: [
        ("music", "music"), ("gigs", "music"), ("concerts", "music"),
        ("art", "galleries"), ("galleries", "galleries"),
        ("nature", "parks"), ("parks", "parks"), ("gardens", "parks"),
        ("history", "heritage"), ("architecture", "heritage"), ("heritage", "heritage")
    ])
    func eachRowMapsItsWordsToItsSearch(interest: String, label: String) {
        let searches = InterestSearches.searches(for: [interest])
        #expect(searches.map(\.label) == [label])
    }

    @Test func theRowsCarryTheirCategoryIds() {
        #expect(InterestSearches.searches(for: ["music"]) == [music])
        #expect(InterestSearches.searches(for: ["art"]) == [galleries])
        #expect(InterestSearches.searches(for: ["parks"]) == [parks])
        #expect(InterestSearches.searches(for: ["history"]) == [heritage])
    }

    @Test func matchingIsOnWholeWords() {
        // "art" must not match "architecture", and "music" must not match "musical" or "museums".
        #expect(InterestSearches.searches(for: ["architecture"]) == [heritage])
        #expect(InterestSearches.searches(for: ["art"]).map(\.label) == ["galleries"])
        #expect(InterestSearches.searches(for: ["musical"]).isEmpty)
        #expect(InterestSearches.searches(for: ["museums"]).isEmpty)
        #expect(InterestSearches.searches(for: ["Artisan"]).isEmpty)
    }

    @Test func anInterestWithSeveralWordsMatchesOnAnyWord() {
        #expect(InterestSearches.searches(for: ["Live music"]) == [music])
        #expect(InterestSearches.searches(for: ["Street art and gardens"]) == [galleries, parks])
    }

    @Test func inputIsTrimmedAndCaseInsensitive() {
        #expect(InterestSearches.searches(for: ["  MUSIC  "]) == [music])
        #expect(InterestSearches.searches(for: ["Photography", " Markets "]).isEmpty)
    }

    @Test func otherInterestsAddNothing() {
        #expect(InterestSearches.searches(for: ["Food", "Pubs", "Photography", "Markets"]).isEmpty)
    }

    @Test func emptyInputAddsNothing() {
        #expect(InterestSearches.searches(for: []).isEmpty)
        #expect(InterestSearches.searches(for: ["", "   "]).isEmpty)
    }

    @Test func searchesFollowTheInterestOrder() {
        #expect(InterestSearches.searches(for: ["history", "music", "art"]) == [heritage, music, galleries])
    }

    @Test func aLabelIsOnlyAddedOnce() {
        let searches = InterestSearches.searches(for: ["music", "gigs", "live music", "music"])
        #expect(searches == [music])
    }

    @Test func aLabelMatchedByTwoInterestsKeepsItsFirstPosition() {
        let searches = InterestSearches.searches(for: ["parks", "art", "gardens"])
        #expect(searches == [parks, galleries])
    }

    @Test func atMostFourSearchesAreReturned() {
        let interests = ["history", "music", "art", "nature", "Food", "Pubs"]
        let searches = InterestSearches.searches(for: interests)
        #expect(searches.count == 4)
        #expect(searches == [heritage, music, galleries, parks])
        #expect(InterestSearches.maximumSearches == 4)
    }
}
