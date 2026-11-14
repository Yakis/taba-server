import Foundation
import GuideKit
@testable import GuideScoreKit
import Testing

/// The committed Edinburgh benchmark guide, which lives in GuideKit's test fixtures.
struct EdinburghScoreTests {
    private func edinburgh() throws -> Guide {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = root.appending(path: "GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-guide.json")
        return try GuideKit.jsonDecoder().decode(Guide.self, from: Data(contentsOf: file))
    }

    @Test func theFixtureScoresWithoutProblems() throws {
        let guide = try edinburgh()
        let score = GuideScorer.score(guide)
        #expect(score.constraints.structureValid)
        #expect(score.pace.days.count == guide.days.count)
        #expect(score.interests.byRank.count == guide.trip.interests.count)
        // The fixture records no interests on its places, so the kind of each place decides them.
        #expect(score.interests.source == .kind)
    }

    @Test func theFixtureIsSimilarToItself() throws {
        let guide = try edinburgh()
        let comparison = GuideScorer.compare(guide, guide)
        #expect(comparison.visitedSimilarity == 1)
        #expect(comparison.stopSimilarity == 1)
    }
}
