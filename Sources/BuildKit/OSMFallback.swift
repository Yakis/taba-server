import Foundation
import FoursquareKit
import GuideKit
import SourcesKit

/// The OpenStreetMap sources the fallbacks ask, in order: Overpass, then Nominatim. A live run builds the defaults on
/// its fetcher. Tests pass sources with no waits.
struct OpenStreetMapFallback: Sendable {
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

    /// The sweep for a Foursquare sweep that found no place. Overpass is asked first, and Nominatim only when Overpass
    /// gave no place, so each source is tried only after the one before it found nothing.
    func sweep(
        _ searches: [FoursquarePlacesSource.CategorySearch],
        centre: Coordinate,
        today: LocalDate,
        record: SourceRecord
    ) async throws -> OSMSweep.Report {
        let overpassStarted = ContinuousClock.now
        let overpassReport = await overpass.sweep(searches: OSMSearches.searches(for: searches), around: centre,
                                                  limit: 6, checkedAt: today)
        try Task.checkCancellation()
        await record.append(OSMEvidence.sweepEvent(overpassReport,
                                                   seconds: seconds(overpassStarted.duration(to: .now))))
        guard overpassReport.places.isEmpty else { return overpassReport }
        let nominatimStarted = ContinuousClock.now
        let nominatimReport = await nominatim.sweep(searches: OSMSearches.nominatimSearches(for: searches),
                                                    around: centre, limit: 6, checkedAt: today)
        try Task.checkCancellation()
        await record.append(OSMEvidence.nominatimSweepEvent(nominatimReport,
                                                            seconds: seconds(nominatimStarted.duration(to: .now))))
        return nominatimReport
    }
}
