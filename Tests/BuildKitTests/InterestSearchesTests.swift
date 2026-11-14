@testable import BuildKit
import Testing

struct InterestSearchesTests {
    @Test(arguments: [
        ("music", "music"), ("gigs", "music"), ("concerts", "music"),
        ("art", "galleries"), ("galleries", "galleries"),
        ("nature", "parks"), ("parks", "parks"), ("gardens", "parks"),
        ("history", "heritage"), ("architecture", "heritage"), ("heritage", "heritage"),
        ("photography", "views"), ("photos", "views"), ("Views", "views"), ("viewpoints", "views")
    ])
    func eachRowMapsItsWordsToItsLabel(interest: String, label: String) {
        #expect(InterestSearches.labels(for: [interest]) == [label])
    }

    @Test func matchingIsOnWholeWords() {
        // "art" must not match "architecture", and "music" must not match "musical" or "museums".
        #expect(InterestSearches.labels(for: ["architecture"]) == ["heritage"])
        #expect(InterestSearches.labels(for: ["art"]) == ["galleries"])
        #expect(InterestSearches.labels(for: ["musical"]).isEmpty)
        #expect(InterestSearches.labels(for: ["museums"]).isEmpty)
        #expect(InterestSearches.labels(for: ["Artisan"]).isEmpty)
    }

    @Test func anInterestWithSeveralWordsMatchesOnAnyWord() {
        #expect(InterestSearches.labels(for: ["Live music"]) == ["music"])
        #expect(InterestSearches.labels(for: ["Street art and gardens"]) == ["galleries", "parks"])
    }

    @Test func inputIsTrimmedAndCaseInsensitive() {
        #expect(InterestSearches.labels(for: ["  MUSIC  "]) == ["music"])
        #expect(InterestSearches.labels(for: ["Photography", " Markets "]) == ["views"])
    }

    @Test func otherInterestsAddNothing() {
        #expect(InterestSearches.labels(for: ["Food", "Pubs", "Coffee", "Markets"]).isEmpty)
    }

    @Test func emptyInputAddsNothing() {
        #expect(InterestSearches.labels(for: []).isEmpty)
        #expect(InterestSearches.labels(for: ["", "   "]).isEmpty)
    }

    @Test func labelsFollowTheInterestOrder() {
        #expect(InterestSearches.labels(for: ["history", "music", "art"]) == ["heritage", "music", "galleries"])
    }

    @Test func aLabelIsOnlyAddedOnce() {
        #expect(InterestSearches.labels(for: ["music", "gigs", "live music", "music"]) == ["music"])
    }

    @Test func aLabelMatchedByTwoInterestsKeepsItsFirstPosition() {
        #expect(InterestSearches.labels(for: ["parks", "art", "gardens"]) == ["parks", "galleries"])
    }

    @Test func atMostFourLabelsAreReturned() {
        let interests = ["history", "music", "art", "nature", "Food", "Pubs"]
        #expect(InterestSearches.labels(for: interests) == ["heritage", "music", "galleries", "parks"])
        #expect(InterestSearches.maximumSearches == 4)
    }

    @Test func everyLabelHasOpenStreetMapSearches() {
        let labels = InterestSearches.labels(for: ["music", "art", "nature", "history", "photography"])
        #expect(labels == ["music", "galleries", "parks", "heritage"])
        #expect(OSMSearches.searches(for: labels).map(\.label) == labels)
        #expect(OSMSearches.nominatimSearches(for: labels).map(\.label) == labels)
    }
}
