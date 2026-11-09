import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GuideKit
import PipelineKit
import SourcesKit
import Testing

struct AreaClustererTests {
    private func candidate(_ id: String, _ latitude: Double, _ longitude: Double = 0, _ name: String? = nil)
        -> AreaCandidate {
        AreaCandidate(id: id, coordinate: Coordinate(latitude: latitude, longitude: longitude)!, areaName: name)
    }

    @Test func nearbyDistantSingleAndEmpty() throws {
        let clusterer = AreaClusterer()
        let result = try clusterer.cluster([
            candidate("b", 0.002), candidate("a", 0), candidate("c", 0.02)
        ])
        #expect(result.clusters.map(\.candidateIDs) == [["a", "b"], ["c"]])
        #expect(abs(result.clusters[0].centre.latitude - 0.001) < 0.000001)
        #expect(result.clusters[1].centre == candidate("c", 0.02).coordinate)
        #expect(try clusterer.cluster([]).clusters.isEmpty)
        #expect(try clusterer.cluster([candidate("a", 0)]).walks.isEmpty)
    }

    @Test func proximityDoesNotChainAcrossAnEntireCity() throws {
        let result = try AreaClusterer().cluster([
            candidate("a", 0), candidate("b", 0.004), candidate("c", 0.008)
        ])
        #expect(result.clusters.map(\.candidateIDs) == [["a", "b"], ["c"]])
    }

    @Test func majorityTiesAndInputOrderAreDeterministic() throws {
        let candidates = [
            candidate("a", 0, 0, "Abbeyhill"), candidate("b", 0.0001, 0, "Old Town"),
            candidate("c", 0.0002, 0, " Old Town "), candidate("d", 0.0003, 0, " ")
        ]
        let clusterer = AreaClusterer()
        let result = try clusterer.cluster(candidates)
        #expect(result.clusters[0].name == "Old Town")
        #expect(try clusterer.cluster(candidates.reversed()) == result)
        let tie = try clusterer.cluster(Array(candidates.prefix(2)))
        #expect(tie.clusters[0].name == "Abbeyhill")
        #expect(try clusterer.cluster([candidate("a", 0)]).clusters[0].name == nil)
    }

    @Test func antimeridianCentreIsNotOnTheOtherSideOfTheWorld() throws {
        let result = try AreaClusterer().cluster([candidate("a", 0, 179.999), candidate("b", 0, -179.999)])
        #expect(result.clusters.count == 1)
        #expect(abs(abs(result.clusters[0].centre.longitude) - 180) < 0.00001)
    }

    @Test func measuresBothDirectionsBetweenCentres() throws {
        struct DirectionalWalks: WalkTimes {
            func minutes(from origin: Coordinate, to destination: Coordinate) -> Int {
                origin.latitude < destination.latitude ? 7 : 11
            }
        }
        let result = try AreaClusterer(walkTimes: DirectionalWalks()).cluster([
            candidate("a", 0), candidate("b", 0.002), candidate("c", 0.02)
        ])
        #expect(result.walks.count == 2)
        #expect(result.walks[0].fromAreaID == "a")
        #expect(result.walks[0].toAreaID == "c")
        #expect(result.walks.map(\.minutes) == [7, 11])
        let real = try AreaClusterer().cluster([candidate("a", 0), candidate("b", 0.01)])
        #expect(real.walks.map(\.minutes) == [19, 19])
        // Area minutes are travel minutes: a walk up to 30 minutes, otherwise a bus or taxi ride.
        let expected = Travel.leg(
            from: result.clusters[0].centre, to: result.clusters[1].centre, walkTimes: StraightLineWalkTimes()
        ).minutes
        let measured = try AreaClusterer().cluster([
            candidate("a", 0), candidate("b", 0.002), candidate("c", 0.02)
        ])
        #expect(measured.walks[0].minutes == expected)
    }

    @Test func resolverLooksUpEachCandidateAndVotes() async throws {
        let result = try await AreaClusterer().cluster([
            candidate("c", 0.002), candidate("a", 0), candidate("b", 0.001)
        ], resolveAreaName: { point in
            point.latitude == 0 ? "Abbeyhill" : "Old Town"
        })
        #expect(result.clusters[0].name == "Old Town")
    }

    @Test func nominatimIgnoresVillageAndCityFallbacks() async throws {
        struct FakeFetcher: HTTPFetching {
            func send(_ request: URLRequest) async throws -> HTTPResponse {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
                let latitude = query?.first { $0.name == "lat" }?.value
                let address: String
                switch latitude {
                case "0.000000":
                    address = #"{"neighbourhood":"Abbeyhill","suburb":"Old Town","quarter":"Other"}"#
                case "0.001000":
                    address = #"{"neighbourhood":"Abbeyhill","quarter":"Old Town"}"#
                default:
                    address = #"{"village":"Example Village","city":"Edinburgh"}"#
                }
                return HTTPResponse(status: 200, body: Data("{\"address\":\(address)}".utf8), headers: [:])
            }
        }
        let geocoder = NominatimGeocoder(fetcher: FakeFetcher(), interval: .zero)
        let result = try await AreaClusterer().cluster([
            candidate("a", 0), candidate("b", 0.001), candidate("c", 0.002)
        ], geocoder: geocoder)
        #expect(result.clusters[0].name == "Old Town")
    }

    @Test func neighbourhoodIsFallbackAndCityAndVillageAreNotUsed() async throws {
        struct FakeFetcher: HTTPFetching {
            func send(_ request: URLRequest) async throws -> HTTPResponse {
                let latitude = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "lat" }?.value
                let address = latitude == "0.000000"
                    ? #"{"neighbourhood":"Abbeyhill","city":"Edinburgh"}"#
                    : #"{"village":"Example Village","city":"Edinburgh"}"#
                return HTTPResponse(status: 200, body: Data("{\"address\":\(address)}".utf8), headers: [:])
            }
        }
        let geocoder = NominatimGeocoder(fetcher: FakeFetcher(), interval: .zero)
        let result = try await AreaClusterer().cluster([
            candidate("a", 0), candidate("b", 0.01)
        ], geocoder: geocoder)
        #expect(result.clusters.map(\.name) == ["Abbeyhill", nil])
    }

    @Test func cancellationDuringFinalLookupIsPropagated() async {
        let task = Task {
            try await AreaClusterer().cluster([candidate("a", 0)], resolveAreaName: { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return "Old Town"
            })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func duplicateIDsAreRejectedBeforeAnyLookup() async throws {
        let candidates = [candidate("a", 0), candidate("a", 0.01)]
        #expect(throws: AreaClusteringError.duplicateCandidateID("a")) {
            try AreaClusterer().cluster(candidates)
        }
        await #expect(throws: AreaClusteringError.duplicateCandidateID("a")) {
            try await AreaClusterer().cluster(candidates, resolveAreaName: { _ in
                Issue.record("Lookup should not run for duplicate IDs")
                return nil
            })
        }
    }
}
