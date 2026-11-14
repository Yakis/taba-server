import FoursquareKit
import SourcesKit

/// The OpenStreetMap searches for each Foursquare search label, so the fallbacks look for the same kinds of place. The
/// labels are the base kinds and the interest labels of `InterestSearches`. Each label has the Overpass filters that
/// select its places, and the phrases Nominatim is asked for (its name search does not read tags).
enum OSMSearches {
    private struct Terms {
        let filters: [String]
        let phrases: [String]
        var nominatimOnlyFilters: [String] = []
    }

    private static let heritageValues = "castle|monument|memorial|ruins|church|cathedral|"
        + "archaeological_site|city_gate|fort|building"
    private static let heritage = #"["historic"~"^(\#(heritageValues))$"]"#

    private static let terms: [String: Terms] = [
        "cafe": Terms(filters: [#"["amenity"="cafe"]"#], phrases: ["cafe"]),
        "restaurant": Terms(filters: [#"["amenity"="restaurant"]"#], phrases: ["restaurant"]),
        "pub": Terms(filters: [#"["amenity"="pub"]"#, #"["amenity"="bar"]"#], phrases: ["pub", "bar"]),
        "viewpoint": Terms(filters: [#"["tourism"="viewpoint"]"#], phrases: ["viewpoint"]),
        "museum": Terms(filters: [#"["tourism"="museum"]"#], phrases: ["museum"]),
        "market": Terms(filters: [#"["amenity"="marketplace"]"#], phrases: ["marketplace", "market hall"]),
        "shop": Terms(filters: [#"["shop"="bakery"]"#], phrases: ["bakery"]),
        "grocery": Terms(filters: [#"["shop"~"^(supermarket|greengrocer|deli)$"]"#],
                         phrases: ["greengrocer", "deli"]),
        "music": Terms(filters: [#"["amenity"="music_venue"]"#], phrases: ["music venue"]),
        "galleries": Terms(filters: [#"["tourism"="gallery"]"#, #"["amenity"="arts_centre"]"#],
                           phrases: ["art gallery", "arts centre"]),
        "parks": Terms(filters: [#"["leisure"="park"]"#, #"["leisure"="garden"]"#], phrases: ["park", "garden"]),
        // Nominatim files most churches as places of worship, with no historic tag, so a well-known one (with a
        // Wikidata tag, ranked first) can only come through this filter. Overpass never sees it: it has no phrases.
        "heritage": Terms(filters: [heritage], phrases: ["castle", "monument", "church", "historic building"],
                          nominatimOnlyFilters: [#"["amenity"="place_of_worship"]"#]),
        "views": Terms(filters: [#"["tourism"="viewpoint"]"#, #"["place"="square"]"#,
                                 #"["man_made"="bridge"]"#, heritage],
                       phrases: ["viewpoint", "square", "bridge"])
    ]

    /// One Overpass search for each Foursquare search whose label has OSM filters, with the same label. A label with no
    /// filters is left out.
    static func searches(for searches: [FoursquarePlacesSource.CategorySearch]) -> [OverpassPlacesSource.Search] {
        searches.compactMap { search in
            guard let filters = terms[search.label]?.filters, !filters.isEmpty else { return nil }
            return OverpassPlacesSource.Search(label: search.label, filters: filters)
        }
    }

    /// One Nominatim search for each Foursquare search whose label has OSM filters and phrases, with the same label.
    static func nominatimSearches(
        for searches: [FoursquarePlacesSource.CategorySearch]
    ) -> [NominatimPlacesSource.Search] {
        searches.compactMap { search in
            guard let term = terms[search.label], !term.filters.isEmpty, !term.phrases.isEmpty else { return nil }
            return NominatimPlacesSource.Search(label: search.label, phrases: term.phrases,
                                                filters: term.filters + term.nominatimOnlyFilters)
        }
    }
}
