import Foundation
import GuideKit
@testable import GuideScoreKit
import Testing

struct ScoreFolderTests {
    private static let edinburgh = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-guide.json")

    @Test func aFolderIsScoredIntoScoresJsonAndItsOwnFileIsNeverReadBack() throws {
        let folder = try makeFolder()
        try FileManager.default.copyItem(at: Self.edinburgh, to: folder.appending(path: "edinburgh.json"))
        try Data(#"{"name": "not a guide"}"#.utf8).write(to: folder.appending(path: "notes.json"))

        let first = try ScoreFolder.summarize(folder)
        #expect(Array(first.scores.keys) == ["edinburgh.json"])
        #expect(first.skipped == ["notes.json"])

        try ScoreFolder.write(first.scores, to: folder)
        let second = try ScoreFolder.summarize(folder)
        #expect(Array(second.scores.keys) == ["edinburgh.json"])
        #expect(second.skipped == ["notes.json"])
        let written = try GuideKit.jsonDecoder().decode(
            [String: GuideScore].self, from: Data(contentsOf: folder.appending(path: "scores.json"))
        )
        #expect(written == first.scores)
    }

    @Test func theReportNamesWhatNeedsALook() {
        let score = GuideScorer.score(TestGuides.tour())
        let flags = ScoreReport.attention(score)
        #expect(flags.contains("No stop serves: Music."))
        #expect(flags.contains("Generic tasting names: Bread."))
        #expect(flags.contains("1 stop(s) have an unusual length."))
        #expect(!flags.contains { $0.hasPrefix("Rank agreement") })
        let text = ScoreReport.text(score)
        #expect(text.contains("Interests (kind)"))
        #expect(text.contains("  - \(flags.last ?? "")"))
    }

    @Test func aCleanGuideHasNothingAttention() {
        let guide = TestGuides.guide(
            places: [TestGuides.place("p-cafe", .cafe, level: 1)],
            days: [TestGuides.day(TestGuides.arrival, [
                TestGuides.stop("d1-s1", .meal, "p-cafe", "12:00", 60, meal: .lunch)
            ])],
            interests: ["Food"],
            lists: [],
            tasting: [],
            practical: [],
            sources: [],
            notes: GuideNotes(weather: "a", light: "b", backupPlan: "c", rules: "d")
        )
        let text = ScoreReport.text(GuideScorer.score(guide))
        #expect(text.hasSuffix("Attention\n  none\n"))
    }
}
