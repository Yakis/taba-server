@testable import BuildKit
import Foundation
import PipelineKit
import ResponsesKit
@testable import SourcesKit
import Testing

struct SearchLabelsTests {
    @Test func labelsComeOnlyFromTheInterestSearches() {
        let sweeps: [(label: String, placeIds: [String])] = [
            ("cafe", ["a", "b"]), ("music", ["b", "c"]), ("parks", []), ("heritage", ["c"])
        ]
        let interests = [FoursquarePlacesSource.CategorySearch(label: "music", categoryIds: []),
                         FoursquarePlacesSource.CategorySearch(label: "heritage", categoryIds: [])]
        #expect(SourcePreparation.searchLabels(sweeps, interestSearches: interests)
            == ["b": ["music"], "c": ["heritage", "music"]])
        #expect(SourcePreparation.searchLabels(sweeps, interestSearches: []).isEmpty)
    }

    @Test func measurementsSnapshotKeepsLabelsAndReadsOldCheckpoints() throws {
        let measurements = PipelineInputMeasurements(areas: ["p": "a"], walkFromBase: ["p": 4],
            areaWalkMinutes: .object([:]), arrivalWalkMinutes: 1, departureWalkMinutes: 2,
            searchLabels: ["p": ["music"]])
        let encoded = try JSONEncoder().encode(MeasurementsSnapshot(measurements))
        let restored = try JSONDecoder().decode(MeasurementsSnapshot.self, from: encoded)
        #expect(restored.value.searchLabels == ["p": ["music"]])

        var object = try #require(JSONDecoder().decode(JSONValue.self, from: encoded).objectValue)
        object.removeValue(forKey: "searchLabels")
        let oldData = try JSONEncoder().encode(JSONValue.object(object))
        let old = try JSONDecoder().decode(MeasurementsSnapshot.self, from: oldData)
        #expect(old.value.searchLabels.isEmpty)
        #expect(old.value.areas == ["p": "a"])
        #expect(old.value.walkFromBase == ["p": 4])
    }
}
