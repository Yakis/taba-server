@testable import BuildKit
import Foundation
import PipelineKit
import ResponsesKit
@testable import SourcesKit
import Testing

struct SearchLabelsTests {
    private func outcome(_ label: String, _ ids: [String],
                         failure: String? = nil) -> FoursquarePlacesSource.SweepOutcome {
        FoursquarePlacesSource.SweepOutcome(label: label, returned: ids.count, failure: failure, placeIds: ids)
    }

    @Test func labelsComeOnlyFromTheInterestSearches() {
        let report = FoursquarePlacesSource.SweepReport(places: [], sweeps: [
            outcome("cafe", ["a", "b"]), outcome("music", ["b", "c"]), outcome("parks", [], failure: "boom"),
            outcome("heritage", ["c"])
        ])
        let interests = [FoursquarePlacesSource.CategorySearch(label: "music", categoryIds: []),
                         FoursquarePlacesSource.CategorySearch(label: "heritage", categoryIds: [])]
        #expect(SourcePreparation.searchLabels(report, interestSearches: interests)
            == ["b": ["music"], "c": ["heritage", "music"]])
        #expect(SourcePreparation.searchLabels(report, interestSearches: []).isEmpty)
    }

    @Test func measurementsSnapshotKeepsLabelsAndReadsOldCheckpoints() throws {
        let measurements = PipelineInputMeasurements(areas: ["p": "a"], walkFromStay: ["p": 4],
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
        #expect(old.value.walkFromStay == ["p": 4])
    }
}
