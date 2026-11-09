import Foundation
import GuideKit
import PipelineKit
import Testing

struct Step4SafetyTests {
    enum LookupError: Error { case unavailable }

    @Test func areaLookupFailureUsesDestinationWithoutHidingOtherNames() async throws {
        let first = Coordinate(latitude: 0, longitude: 0)!
        let second = Coordinate(latitude: 0.02, longitude: 0)!
        let areas = try await AreaNameFallback.cluster(
            [AreaCandidate(id: "a", coordinate: first), AreaCandidate(id: "b", coordinate: second)],
            destination: "Example City", resolve: { coordinate in
                if coordinate == first { throw LookupError.unavailable }
                return "Old Town"
            }
        )
        #expect(areas.clusters.map(\.name) == ["Example City", "Old Town"])
    }

    @Test func areaLookupCancellationIsNotConvertedToFallback() async {
        await #expect(throws: CancellationError.self) {
            try await AreaNameFallback.cluster(
                [AreaCandidate(id: "a", coordinate: Coordinate(latitude: 0, longitude: 0)!)],
                destination: "Example", resolve: { _ in throw CancellationError() }
            )
        }
    }

    @Test func onlyReportedWebURLsAreAccepted() async throws {
        func finding(_ id: String, _ url: String) -> ResearchFinding {
            ResearchFinding(id: id, kind: .event, title: "Event", summary: "Details", startDate: nil,
                            endDate: nil, times: nil, placeName: nil, address: nil, url: url,
                            sourceTitle: "Source", confidence: .high, onTripDates: true)
        }
        let research = ResearchResult(findings: [finding("ok", "https://example.com/event"),
                                                  finding("missing", "https://example.com/other"),
                                                  finding("bad", "file:///private")],
                                      suggestedPlaces: [], searchNotes: "Unconfirmed")
        let verified = try await ResearchVerification.verify(
            research, sourceURLs: ["https://example.com/event", "file:///private"], resolve: { _ in nil }
        )
        #expect(verified.result.findings.map(\.id) == ["ok"])
        #expect(verified.result.searchNotes == "Unconfirmed")
    }
}
