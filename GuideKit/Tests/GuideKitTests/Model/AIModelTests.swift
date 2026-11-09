import Foundation
import GuideKit
import Testing

struct AIModelTests {
    @Test func aGuideWithoutAModelOmitsTheField() throws {
        let guide = try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghGuideData())
        #expect(guide.aiModel == nil)
        let encoded = try String(data: GuideKit.jsonEncoder().encode(guide), encoding: .utf8) ?? ""
        #expect(!encoded.contains("aiModel"))
    }

    @Test func recordingAModelRoundTrips() throws {
        let guide = try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghGuideData())
        let stamped = guide.recordingAIModel("gpt-6.1-terra")
        #expect(stamped.aiModel == "gpt-6.1-terra")
        #expect(stamped.openQuestions == guide.openQuestions)
        let decoded = try GuideKit.jsonDecoder().decode(Guide.self, from: GuideKit.jsonEncoder().encode(stamped))
        #expect(decoded == stamped)
        #expect(decoded.aiModel == "gpt-6.1-terra")
    }
}
