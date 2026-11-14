@testable import BuildKit
import Foundation
import GuideKit
import SourcesKit
import Testing

private func sourceInput(interests: [String] = []) throws -> SourceInput {
    let day = try #require(LocalDate("2026-11-14"))
    return SourceInput(destination: "Edinburgh", from: day, to: day, preferences: TripPreferences(interests: interests))
}

/// What the candidate sweep added, the labels it gave, and the evidence it wrote.
private struct CandidateRun {
    let places: [String: Place]
    let sources: [Source]
    let labels: [String: [String]]
    let log: EvidenceLog
    let lookupFailed: Bool
}

struct OpenStreetMapPlacesTests {
    /// Runs the candidate sweep, returning what it added and the evidence it wrote.
    private func collect(
        _ fetcher: ByHostFetcher,
        interests: [String] = []
    ) async throws -> CandidateRun {
        let log = EvidenceLog()
        let centre = try #require(Coordinate(latitude: 55.9500, longitude: -3.2000))
        let today = try #require(LocalDate("2026-11-14"))
        let capped = CappedFetcher(inner: fetcher, limit: 150)
        var places: [String: Place] = [:]
        var sources: [Source] = []
        let (lookup, labels) = try await SourcePreparation.collectCandidates(
            try sourceInput(interests: interests), fetcher: capped, today: today, centre: centre, seed: nil,
            places: &places, sources: &sources, record: SourceRecord { await log.add($0) },
            openStreetMap: zeroWaits(capped))
        return CandidateRun(places: places, sources: sources, labels: labels, log: log,
                            lookupFailed: lookup.error != nil)
    }

    /// An Overpass answer with six cafes, so the cafe search has to keep only its best four.
    private var sixCafes: String {
        let cafes = (1...6).map { index in
            #"{"type":"node","id":\#(100 + index),"lat":55.95\#(index),"lon":-3.2000,"#
                + #""tags":{"name":"Cafe \#(index)","amenity":"cafe"}}"#
        }
        return #"{"elements":[\#(cafes.joined(separator: ","))]}"#
    }

    // MARK: The candidate sweep

    @Test func nominatimIsAskedFirstAndItsPlacesAreTheCandidates() async throws {
        let fetcher = ByHostFetcher(answer: byHost())
        let result = try await collect(fetcher, interests: ["Music", "Parks"])
        #expect(Set(result.places.keys) == ["osm:node/7", "osm:node/8", "osm:node/9"])
        #expect(result.places["osm:node/7"]?.hours.hoursKnown == true)
        #expect(result.sources.map(\.id) == ["osm:node/7"])
        #expect(result.labels["osm:node/7"] == ["music"])
        #expect(result.labels["osm:node/8"] == ["parks"])
        #expect(result.labels["osm:node/9"] == nil)
        // One request for each distinct phrase: 11 for the base searches, plus "music venue", "park" and "garden".
        #expect(await fetcher.count(host: nominatimHost) == 14)
        // Overpass is not asked when Nominatim gives places.
        #expect(await fetcher.count(host: overpassHost) == 0)
        #expect(await fetcher.count(host: overpassBackupHost) == 0)
        #expect(!(await result.log.names).contains("osmSweep"))
        #expect(await result.log.names.contains("nominatimSweep"))
        #expect(!result.lookupFailed)
    }

    @Test func overpassIsAskedWhenNominatimGivesNoPlaces() async throws {
        let fetcher = ByHostFetcher(answer: byHost(nominatim: reply("[]")))
        let result = try await collect(fetcher, interests: ["Music", "Parks"])
        #expect(Set(result.places.keys) == ["osm:node/7", "osm:node/8", "osm:node/9"])
        #expect(result.places["osm:node/7"]?.hours.hoursKnown == true)
        #expect(result.places["osm:node/8"]?.kind == .landmark)
        #expect(result.sources.map(\.id) == ["osm:node/7"])
        #expect(result.labels["osm:node/7"] == ["music"])
        #expect(result.labels["osm:node/8"] == ["parks"])
        // One Overpass query, answered by its first server.
        #expect(await fetcher.count(host: overpassHost) == 1)
        #expect(await fetcher.count(host: overpassBackupHost) == 0)
        #expect(!result.lookupFailed)
    }

    @Test func overpassIsAskedWhenNominatimFails() async throws {
        let fetcher = ByHostFetcher(answer: byHost(nominatim: reply("", status: 503)))
        let result = try await collect(fetcher, interests: ["Music", "Parks"])
        #expect(Set(result.places.keys) == ["osm:node/7", "osm:node/8", "osm:node/9"])
        #expect(await fetcher.count(host: overpassHost) == 1)
        #expect(await result.log.names.contains("nominatimSweep"))
    }

    @Test func theSweepEvidenceIsNominatimThenOverpass() async throws {
        let fetcher = ByHostFetcher(answer: byHost(nominatim: reply("[]")))
        let result = try await collect(fetcher, interests: ["Music", "Parks"])
        let sweeps = (await result.log.names).filter { $0 == "nominatimSweep" || $0 == "osmSweep" }
        #expect(sweeps == ["nominatimSweep", "osmSweep"])
        #expect(!(await result.log.names).contains("foursquareSweep"))
    }

    @Test func aSearchKeepsFourPlaces() async throws {
        #expect(OpenStreetMapPlaces.placesPerSearch == 4)
        let fetcher = ByHostFetcher(answer: byHost(overpass: reply(sixCafes), nominatim: reply("[]")))
        let result = try await collect(fetcher)
        #expect(result.places.count == 4)
        #expect(result.labels.isEmpty)
    }

    @Test func noCandidatesIsThrownWhenBothSourcesFindNothing() async throws {
        let fetcher = ByHostFetcher(answer: byHost(overpass: reply("{}", status: 400),
                                                   nominatim: reply("[]")))
        await #expect(throws: SourcePreparationError.noCandidates) {
            _ = try await self.collect(fetcher)
        }
    }

    @Test func noRequestGoesToFoursquare() async throws {
        let fetcher = ByHostFetcher(answer: byHost(nominatim: reply("", status: 503)))
        _ = try? await collect(fetcher, interests: ["Music"])
        #expect(await fetcher.count(host: foursquareHost) == 0)
        #expect(!(await fetcher.requests).isEmpty)
    }
}
