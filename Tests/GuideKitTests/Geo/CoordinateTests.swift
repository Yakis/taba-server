import Foundation
import GuideKit
import Testing

struct CoordinateTests {
    @Test func acceptsRangeLimits() {
        #expect(Coordinate(latitude: 55.9533, longitude: -3.1883) != nil)
        #expect(Coordinate(latitude: 90, longitude: 180) != nil)
        #expect(Coordinate(latitude: -90, longitude: -180) != nil)
    }

    @Test func rejectsOutOfRangeValues() {
        #expect(Coordinate(latitude: 90.5, longitude: 0) == nil)
        #expect(Coordinate(latitude: -90.5, longitude: 0) == nil)
        #expect(Coordinate(latitude: 0, longitude: 180.5) == nil)
        #expect(Coordinate(latitude: 0, longitude: -180.5) == nil)
        #expect(Coordinate(latitude: .nan, longitude: 0) == nil)
    }

    @Test func decodingRejectsOutOfRangeValues() {
        #expect(throws: DecodingError.self) {
            _ = try GuideKit.jsonDecoder().decode(
                Coordinate.self,
                from: Data(#"{"latitude":91,"longitude":0}"#.utf8)
            )
        }
    }

    @Test func encodesAsPlainObjectAndRoundTrips() throws {
        let coordinate = try #require(Coordinate(latitude: 55.5, longitude: -3.25))
        let json = try encodedJSON(coordinate)
        #expect(json.contains("\"latitude\""))
        #expect(json.contains("\"longitude\""))
        #expect(try roundTrip(coordinate) == coordinate)
    }
}
