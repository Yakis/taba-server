import Foundation
import GuideKit

/// The report both OpenStreetMap sweeps give: Overpass (one query for every search) and Nominatim (one name search per
/// phrase). Each search keeps its best places, ranked the same way, and a place is listed once however many searches
/// keep it.
public enum OSMSweep {
    /// What one search did. `returned` is the number of OpenStreetMap objects the search matched, before the sweep
    /// skipped any of them and before it ranked them.
    public struct Outcome: Sendable, Equatable {
        public let label: String
        public let returned: Int
        /// The ids of the places this search kept, which may include places another search also kept.
        public let placeIds: [String]
    }

    public struct Report: Sendable, Equatable {
        public let places: [Place]
        /// The OpenStreetMap pages of the places whose hours are known or that have a fact.
        public let sources: [Source]
        public let sweeps: [Outcome]
        /// The first error when the sweep could not get every answer, or nil when it did.
        public let error: SourcesError?
    }

    /// A mapped place that one search matched, with what ranks it.
    struct Candidate {
        let place: Place
        /// Wikidata and Wikipedia tags, a website and opening hours (see `score`).
        let score: Int
        /// Nominatim's importance from 0 to 1. Overpass gives none, so its candidates have 0.
        let importance: Double
        /// Metres from the centre of the sweep.
        let distance: Double
    }

    /// One search's matches: how many objects it matched, and the candidates among them that mapped to a place.
    struct SearchResult {
        let label: String
        let returned: Int
        let candidates: [Candidate]
    }

    /// The report for a sweep that found nothing, with one outcome per search and the error when there was one.
    static func emptyReport(labels: [String], error: SourcesError?) -> Report {
        Report(
            places: [],
            sources: [],
            sweeps: labels.map { Outcome(label: $0, returned: 0, placeIds: []) },
            error: error
        )
    }

    /// Each search keeps its best `limit` candidates: by score, then importance, then distance. A place is listed once
    /// in `places`, though several searches may keep it.
    static func report(_ results: [SearchResult], limit: Int, checkedAt: LocalDate, error: SourcesError?) -> Report {
        var places: [Place] = []
        var sources: [Source] = []
        var seenIds = Set<String>()
        var sweeps: [Outcome] = []
        for result in results {
            let ranked = result.candidates.sorted(by: precedes)
            let kept = Array(ranked.prefix(max(limit, 0))).map(\.place)
            for place in kept where seenIds.insert(place.id).inserted {
                places.append(place)
                if place.hours.hoursKnown || !place.facts.isEmpty,
                   let source = OverpassPlacesSource.source(forPlaceId: place.id, checkedAt: checkedAt) {
                    sources.append(source)
                }
            }
            sweeps.append(Outcome(label: result.label, returned: result.returned, placeIds: kept.map(\.id)))
        }
        return Report(places: places, sources: sources, sweeps: sweeps, error: error)
    }

    static func precedes(_ first: Candidate, _ second: Candidate) -> Bool {
        if first.score != second.score {
            return first.score > second.score
        }
        if first.importance != second.importance {
            return first.importance > second.importance
        }
        return first.distance < second.distance
    }

    /// Wikidata and Wikipedia tags are worth most, then a website, then opening hours.
    static func score(_ tags: [String: String]) -> Int {
        var score = 0
        if OSMPlaceMapper.value("wikidata", in: tags) != nil || OSMPlaceMapper.value("wikipedia", in: tags) != nil {
            score += 4
        }
        if OSMPlaceMapper.website(in: tags) != nil {
            score += 1
        }
        if OSMPlaceMapper.value("opening_hours", in: tags) != nil {
            score += 1
        }
        return score
    }

    /// True when the tags match one of the filters, each an Overpass-style selector such as `["amenity"="cafe"]`.
    static func selects(_ filters: [String], _ tags: [String: String]) -> Bool {
        filters.contains { filter in
            TagSelector(filter)?.matches(tags) ?? false
        }
    }
}
