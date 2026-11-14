import GuideKit
@testable import GuideScoreKit
import Testing

/// Numbers worked out by hand for `TestGuides.tour()`. Main stops are sights and drinks: 30 + 60 + 45 + 60 + 10 = 205
/// minutes. Food: 30 + 45 + 10 = 85 (share 0.415). Pubs and Art: 60 each (0.293). Music: nothing.
struct GuideScorerTests {
    private let score = GuideScorer.score(TestGuides.tour())

    @Test func interestsGetTheirMinutesAndSharesInRankOrder() {
        let rows = score.interests.byRank
        #expect(rows.map(\.name) == ["Food", "Pubs", "Art", "Music"])
        #expect(rows.map(\.rank) == [1, 2, 3, 4])
        #expect(rows.map(\.minutes) == [85, 60, 60, 0])
        #expect(rows.map(\.mainStops) == [3, 1, 1, 0])
        #expect(rows.first?.mealStops == 1)
        #expect(rows.first?.share == 0.415)
        #expect(rows[1].share == 0.293)
    }

    @Test func earliestStartIsTheEarliestServingStop() {
        #expect(score.interests.byRank.map(\.earliestStart) == ["10:00", "18:00", "09:30", nil])
    }

    @Test func rankAgreementAndTopShare() {
        #expect(score.interests.rankAgreement == 1)
        #expect(score.interests.topShare == 0.415)
        #expect(score.interests.missed == ["Music"])
        #expect(score.interests.source == .kind)
    }

    @Test func aHigherRankedInterestWithFewerMinutesLowersAgreement() {
        let swapped = GuideScorer.score(TestGuides.tour(interests: ["Pubs", "Food"]))
        #expect(swapped.interests.byRank.map(\.minutes) == [60, 85])
        #expect(swapped.interests.rankAgreement == 0)
        #expect(swapped.interests.missed.isEmpty)
    }

    @Test func recordedInterestsReplaceTheKindMatch() {
        let recorded = GuideScorer.score(TestGuides.tour(recorded: true))
        #expect(recorded.interests.source == .recorded)
        let food = recorded.interests.byRank[0]
        #expect(food.mainStops == 0)
        #expect(food.mealStops == 1)
        #expect(recorded.interests.missed == ["Music"])
    }

    @Test func paceCountsMainStopsWalkingAndUnplannedTime() {
        let days = score.pace.days
        #expect(days.map(\.fullDay) == [false, true, false])
        #expect(days.map(\.mainStops) == [1, 3, 1])
        #expect(days.map(\.firstMainStart) == ["14:00", "09:30", "10:00"])
        #expect(days.map(\.walkingMinutes) == [0, 3, 0])
        #expect(days[1].restStops == 0)
        // Gaps of 29, 14 and 299 minutes after the walks between the stops.
        #expect(days[1].unplannedMinutes == 342)
        #expect(days[1].withinTarget == TargetCheck(mainStops: false, walking: true))
    }

    @Test func paceTargetsComeFromThePlanningRules() {
        #expect(PaceTarget.of(.relaxed) == PaceTarget(mainStopsMin: 3, mainStopsMax: 4, firstStartNotBefore: "09:30",
                                                      walkingMinutes: 100))
        #expect(PaceTarget.of(.unhurried).mainStopsMin == 4)
        #expect(PaceTarget.of(.unhurried).walkingMinutes == 130)
        #expect(PaceTarget.of(.packed).mainStopsMax == nil)
        #expect(PaceTarget.of(.packed).walkingMinutes == 180)
    }

    @Test func spendCountsPriceLevelsAndStopsAboveTheCeiling() {
        #expect(score.spend.ceiling == 3)
        #expect(score.spend.mealAndDrink.byLevel["1"] == 1)
        #expect(score.spend.mealAndDrink.byLevel["4"] == 1)
        #expect(score.spend.mealAndDrink.aboveCeiling == ["d2-s4"])
        #expect(score.spend.sights.byLevel["1"] == 3)
        #expect(score.spend.sights.byLevel["unknown"] == 1)
        #expect(score.spend.sights.aboveCeiling.isEmpty)
    }

    @Test func aHighBudgetHasNoCeiling() {
        #expect(DailySpend.low.priceCeiling == 2)
        #expect(DailySpend.moderate.priceCeiling == 3)
        #expect(DailySpend.high.priceCeiling == nil)
    }

    @Test func feasibilityFindsUnknownHoursAndUnusualLengths() {
        #expect(score.feasibility.hoursUnknownStops == ["d2-s1"])
        #expect(score.feasibility.hoursUnknownFindings == 1)
        #expect(score.feasibility.durationsOutOfRange == [DurationIssue(stopId: "d3-s1", kind: "sight", minutes: 10)])
        #expect(score.feasibility.longLegs.isEmpty)
        #expect(score.feasibility.days.map(\.firstStart) == ["14:00", "09:30", "10:00"])
        #expect(score.feasibility.days.map(\.lastEnd) == ["14:30", "19:00", "10:10"])
    }

    @Test func contentFindsGenericTastingRepeatedPhrasesAndLongBodies() {
        #expect(score.content.tasting == 2)
        #expect(score.content.genericTasting == ["Bread"])
        #expect(score.content.practicalFacts == 2)
        #expect(score.content.openQuestions == 1)
        #expect(score.content.repeatedPhrases == [
            RepeatedPhrase(phrase: "famous old stone", stops: 3),
            RepeatedPhrase(phrase: "the famous old", stops: 3)
        ])
        #expect(score.content.longBodyStops == ["d2-s1"])
        #expect(score.content.emptyNotes == ["light", "rules"])
    }

    @Test func consistencyFindsTheBrokenReferences() {
        #expect(score.consistency.listPlaceIdsMissing == ["p-missing"])
        #expect(score.consistency.stopPlaceIdsMissing.isEmpty)
        #expect(score.consistency.listKindMismatches == ["p-market"])
        #expect(score.consistency.unusedPlaceIds == ["p-unused"])
        #expect(score.consistency.practicalSourcesMissing == ["src-missing"])
        #expect(score.consistency.problemCount == 3)
    }

    @Test func constraintsReadTheStructureAndTheStay() {
        // The list and the practical fact cite ids the guide does not hold, so the structure check fails and says so.
        #expect(!score.constraints.structureValid)
        #expect(score.constraints.structureError?.contains("p-missing") == true)
        #expect(score.constraints.contradictions == 0)
        #expect(score.constraints.stayArrangement == "unknown")
        #expect(score.constraints.base == nil)
        #expect(score.constraints.findingsBySeverity.keys.sorted() == ["error", "info", "warning"])
    }

    @Test func aHotelOnATripWithNoStayIsAContradiction() {
        let guide = TestGuides.guide(
            places: [TestGuides.place("p-cafe", .cafe, level: 1)],
            days: [TestGuides.day(TestGuides.arrival, [
                TestGuides.stop("d1-s1", .meal, "p-cafe", "12:00", 60, meal: .lunch,
                                body: "Check in at the hotel first.")
            ])],
            interests: ["Food"]
        )
        #expect(GuideScorer.score(guide).constraints.contradictions == 1)
    }

    @Test func aStructuralProblemIsReportedWithItsText() {
        let guide = TestGuides.guide(
            places: [TestGuides.place("p-cafe", .cafe, level: 9)],
            days: [TestGuides.day(TestGuides.arrival, [])],
            interests: ["Food"]
        )
        let result = GuideScorer.score(guide).constraints
        #expect(!result.structureValid)
        #expect(result.structureError?.isEmpty == false)
    }

    @Test func aScoreRoundTripsThroughJSON() throws {
        let data = try GuideKit.jsonEncoder().encode(score)
        let decoded = try GuideKit.jsonDecoder().decode(GuideScore.self, from: data)
        #expect(decoded == score)
    }

    @Test func repeatedPhrasesNeedThreeStops() {
        let bodies = ["a b c d", "a b c e", "a b c f", "x y z", "x y z", "p q r"]
        #expect(ContentScore.repeatedPhrases(bodies) == [RepeatedPhrase(phrase: "a b c", stops: 3)])
    }
}
