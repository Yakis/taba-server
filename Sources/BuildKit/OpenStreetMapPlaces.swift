import Foundation
import GuideKit
import SourcesKit

/// The OpenStreetMap place sources: the candidates sweep and the name lookups of suggestions. Nominatim is asked first;
/// Overpass is asked only when Nominatim gives no place at all. A live run builds the defaults on its fetcher. Tests
/// pass sources with no waits.
struct OpenStreetMapPlaces: Sendable {
    /// How many places each search keeps, in both sources.
    static let placesPerSearch = 4

    let overpass: OverpassPlacesSource
    let nominatim: NominatimPlacesSource

    init(fetcher: any HTTPFetching) {
        self.overpass = OverpassPlacesSource(fetcher: fetcher)
        self.nominatim = NominatimPlacesSource(fetcher: fetcher)
    }

    init(overpass: OverpassPlacesSource, nominatim: NominatimPlacesSource) {
        self.overpass = overpass
        self.nominatim = nominatim
    }

    /// The sweep for the search labels around `centre`. Nominatim is asked first. Overpass is asked only when the
    /// Nominatim report has no place, and then its report is the one returned.
    func sweep(
        _ labels: [String],
        centre: Coordinate,
        today: LocalDate,
        record: SourceRecord
    ) async throws -> OSMSweep.Report {
        let nominatimStarted = ContinuousClock.now
        let nominatimReport = await nominatim.sweep(searches: OSMSearches.nominatimSearches(for: labels),
                                                    around: centre, limit: Self.placesPerSearch, checkedAt: today)
        try Task.checkCancellation()
        await record.append(OSMEvidence.nominatimSweepEvent(nominatimReport,
                                                            seconds: seconds(nominatimStarted.duration(to: .now))))
        guard nominatimReport.places.isEmpty else { return nominatimReport }
        let overpassStarted = ContinuousClock.now
        let overpassReport = await overpass.sweep(searches: OSMSearches.searches(for: labels), around: centre,
                                                  limit: Self.placesPerSearch, checkedAt: today)
        try Task.checkCancellation()
        await record.append(OSMEvidence.sweepEvent(overpassReport,
                                                   seconds: seconds(overpassStarted.duration(to: .now))))
        return overpassReport
    }
}
