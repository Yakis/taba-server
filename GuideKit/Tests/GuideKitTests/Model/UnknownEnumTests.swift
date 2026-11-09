import Foundation
import GuideKit
import Testing

struct UnknownEnumTests {
    @Test func unknownStopKindFailsToDecode() {
        #expect(throws: DecodingError.self) {
            _ = try GuideKit.jsonDecoder().decode(StopKind.self, from: Data(#""teleport""#.utf8))
        }
    }

    @Test func unknownPaceFailsToDecode() {
        #expect(throws: DecodingError.self) {
            _ = try GuideKit.jsonDecoder().decode(Pace.self, from: Data(#""frantic""#.utf8))
        }
    }

    @Test func unknownWeekdayFailsToDecode() {
        #expect(throws: DecodingError.self) {
            _ = try GuideKit.jsonDecoder().decode(Weekday.self, from: Data(#""funday""#.utf8))
        }
    }

    @Test func unknownGuideStatusFailsToDecode() {
        #expect(throws: DecodingError.self) {
            _ = try GuideKit.jsonDecoder().decode(GuideStatus.self, from: Data(#""archived""#.utf8))
        }
    }

    @Test func unknownStopKindInsideAStopFailsToDecode() {
        let text = #"{"id":"s1","kind":"teleport","start":"13:15","minutes":30,"flexible":false,"#
            + #""copy":{"title":"x","body":"y"}}"#
        let json = Data(text.utf8)
        #expect(throws: DecodingError.self) {
            _ = try GuideKit.jsonDecoder().decode(Stop.self, from: json)
        }
    }
}
