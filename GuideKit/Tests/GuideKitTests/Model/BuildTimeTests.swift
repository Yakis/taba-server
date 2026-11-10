import Foundation
import GuideKit
import Testing

struct BuildTimeTests {
    @Test func aGuideWithoutABuildTimeOmitsTheField() throws {
        let guide = try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghGuideData())
        #expect(guide.buildTime == nil)
        let encoded = try String(data: GuideKit.jsonEncoder().encode(guide), encoding: .utf8) ?? ""
        #expect(!encoded.contains("buildTime"))
    }

    @Test func recordingABuildTimeKeepsTheModelAndRoundTrips() throws {
        let guide = try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghGuideData())
        let stamped = guide.recordingAIModel("claude-sonnet-5-5")
            .recordingBuildTime(BuildTime(totalSeconds: 2100, workSeconds: 540))
        #expect(stamped.aiModel == "claude-sonnet-5-5")
        #expect(stamped.buildTime == BuildTime(totalSeconds: 2100, workSeconds: 540))
        #expect(stamped.recordingAIModel("gpt-6.1-sol").buildTime == stamped.buildTime)
        let decoded = try GuideKit.jsonDecoder().decode(Guide.self, from: GuideKit.jsonEncoder().encode(stamped))
        #expect(decoded == stamped)
    }

    @Test func typedArrivalAndLeavingTimesRoundTrip() throws {
        let dates = TripDates(start: SampleGuide.date("2026-11-22"), end: SampleGuide.date("2026-11-24"),
                              arrives: SampleGuide.time("14:30"), leaves: SampleGuide.time("17:05"))
        let data = try GuideKit.jsonEncoder().encode(dates)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["arrives"] as? String == "14:30")
        #expect(object["leaves"] as? String == "17:05")
        #expect(try GuideKit.jsonDecoder().decode(TripDates.self, from: data) == dates)
    }
}
