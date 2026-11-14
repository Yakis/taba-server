import GuideKit
@testable import GuideScoreKit
import Testing

struct GuideCompareTests {
    @Test func identicalGuidesAreFullySimilar() {
        let comparison = GuideScorer.compare(TestGuides.tour(), TestGuides.tour())
        #expect(comparison.visitedSimilarity == 1)
        #expect(comparison.stopSimilarity == 1)
        #expect(comparison.orderA == comparison.orderB)
        #expect(comparison.orderA == ["Food", "Pubs", "Art", "Music"])
        #expect(comparison.interests.allSatisfy { $0.minutesA == $0.minutesB })
    }

    @Test func guidesWithNoPlacesInCommonAreNotSimilar() {
        let comparison = GuideScorer.compare(TestGuides.tour(), TestGuides.other())
        #expect(comparison.visitedSimilarity == 0)
        #expect(comparison.stopSimilarity == 0)
    }

    @Test func interestsAreMatchedByNameWhateverTheCase() {
        let lower = TestGuides.tour(interests: ["food", "pubs"])
        let comparison = GuideScorer.compare(TestGuides.tour(interests: ["Food", "Pubs"]), lower)
        #expect(comparison.interests.map(\.name) == ["Food", "Pubs"])
        #expect(comparison.interests.map(\.minutesB) == [85, 60])
    }

    @Test func aGuideWithNoStopsIsSimilarToItself() {
        #expect(GuideScorer.jaccard([], []) == 1)
        #expect(GuideScorer.jaccard(["a", "b"], ["b", "c"]) == 0.333)
    }
}
