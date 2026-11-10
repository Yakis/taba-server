import Foundation
import PipelineKit
import ResponsesKit
import Testing

struct SearchLabelsCheckpointTests {
    private func measurements() -> PipelineInputMeasurements {
        PipelineInputMeasurements(areas: ["p": "a"], walkFromStay: ["p": 4], areaWalkMinutes: .object([:]),
                                  arrivalWalkMinutes: 1, departureWalkMinutes: 2,
                                  searchLabels: ["p": ["music", "parks"]])
    }

    /// The same JSON as a checkpoint written before `searchLabels` existed.
    private func withoutSearchLabels<T: Encodable>(_ value: T) throws -> Data {
        var object = try #require(JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)).objectValue)
        object.removeValue(forKey: "searchLabels")
        return try JSONEncoder().encode(JSONValue.object(object))
    }

    @Test func measurementsCheckpointKeepsSearchLabels() throws {
        let data = try JSONEncoder().encode(MeasurementsCheckpoint(measurements()))
        let restored = try JSONDecoder().decode(MeasurementsCheckpoint.self, from: data)
        #expect(restored.value.searchLabels == ["p": ["music", "parks"]])
        #expect(restored.value.areas == ["p": "a"])
    }

    @Test func oldMeasurementsCheckpointDecodesWithNoLabels() throws {
        let data = try withoutSearchLabels(MeasurementsCheckpoint(measurements()))
        let restored = try JSONDecoder().decode(MeasurementsCheckpoint.self, from: data)
        #expect(restored.value.searchLabels.isEmpty)
        #expect(restored.value.areas == ["p": "a"])
        #expect(restored.value.walkFromStay == ["p": 4])
    }
}
