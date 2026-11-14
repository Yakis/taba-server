import FoursquareKit
import SourcesKit

/// The OpenStreetMap filters for each Foursquare search label, so the Overpass fallback looks for the same kinds of
/// place. The labels are the base kinds and the interest labels of `InterestSearches`.
enum OSMSearches {
    private static let heritageValues = "castle|monument|memorial|ruins|church|cathedral|"
        + "archaeological_site|city_gate|fort|building"
    private static let heritage = #"["historic"~"^(\#(heritageValues))$"]"#

    private static let filters: [String: [String]] = [
        "cafe": [#"["amenity"="cafe"]"#],
        "restaurant": [#"["amenity"="restaurant"]"#],
        "pub": [#"["amenity"="pub"]"#, #"["amenity"="bar"]"#],
        "viewpoint": [#"["tourism"="viewpoint"]"#],
        "museum": [#"["tourism"="museum"]"#],
        "market": [#"["amenity"="marketplace"]"#],
        "shop": [#"["shop"="bakery"]"#],
        "grocery": [#"["shop"~"^(supermarket|greengrocer|deli)$"]"#],
        "music": [#"["amenity"="music_venue"]"#],
        "galleries": [#"["tourism"="gallery"]"#, #"["amenity"="arts_centre"]"#],
        "parks": [#"["leisure"="park"]"#, #"["leisure"="garden"]"#],
        "heritage": [heritage],
        "views": [#"["tourism"="viewpoint"]"#, #"["place"="square"]"#, #"["man_made"="bridge"]"#, heritage]
    ]

    /// One OSM search for each Foursquare search whose label has OSM filters, with the same label. A label with no
    /// filters is left out.
    static func searches(for searches: [FoursquarePlacesSource.CategorySearch]) -> [OverpassPlacesSource.Search] {
        searches.compactMap { search in
            guard let filters = filters[search.label], !filters.isEmpty else { return nil }
            return OverpassPlacesSource.Search(label: search.label, filters: filters)
        }
    }
}
