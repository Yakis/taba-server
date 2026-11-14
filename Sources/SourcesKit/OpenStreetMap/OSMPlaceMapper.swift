import Foundation
import GuideKit

/// Turns the tags of an OpenStreetMap object into a GuideKit place: its kind, indoor flag, hours, address and website.
enum OSMPlaceMapper {
    /// One kind rule: the tag `key` has one of `values`, or any value when `values` is nil.
    struct KindRule: Sendable {
        let key: String
        let values: [String]?
        let kind: PlaceKind

        func matches(_ tags: [String: String]) -> Bool {
            guard let tagValue = tags[key] else { return false }
            return values?.contains(tagValue) ?? true
        }
    }

    /// The rules in the order they are tried. The first rule that matches gives the kind.
    static let kindRules: [KindRule] = [
        KindRule(key: "amenity", values: ["cafe"], kind: .cafe),
        KindRule(key: "amenity", values: ["restaurant"], kind: .restaurant),
        KindRule(key: "amenity", values: ["pub"], kind: .pub),
        KindRule(key: "amenity", values: ["bar"], kind: .bar),
        KindRule(key: "amenity", values: ["music_venue"], kind: .venue),
        KindRule(key: "amenity", values: ["marketplace"], kind: .market),
        KindRule(key: "amenity", values: ["arts_centre"], kind: .museum),
        KindRule(key: "tourism", values: ["museum", "gallery"], kind: .museum),
        KindRule(key: "tourism", values: ["viewpoint"], kind: .viewpoint),
        KindRule(key: "shop", values: ["bakery"], kind: .shop),
        KindRule(key: "shop", values: ["supermarket", "greengrocer", "deli"], kind: .grocery),
        KindRule(key: "leisure", values: ["park", "garden"], kind: .landmark),
        KindRule(key: "historic", values: nil, kind: .landmark),
        KindRule(key: "amenity", values: ["place_of_worship"], kind: .landmark),
        KindRule(key: "man_made", values: ["bridge"], kind: .landmark),
        KindRule(key: "place", values: ["square"], kind: .landmark)
    ]

    /// The place for one element, or nil when it is unnamed, has no coordinate, or is marked closed or off.
    static func makePlace(from element: OverpassElement, checkedAt: LocalDate) -> Place? {
        guard let tags = element.tags, let coordinate = element.coordinate else { return nil }
        return makePlace(osmType: element.type, osmId: element.id, tags: tags, coordinate: coordinate,
                         checkedAt: checkedAt)
    }

    /// The place for one OpenStreetMap object, given by its type ("node", "way" or "relation"), its id, its tags and
    /// its point. Nil when it is unnamed, or marked closed or off.
    static func makePlace(osmType: String, osmId: Int64, tags: [String: String], coordinate: Coordinate,
                          checkedAt: LocalDate) -> Place? {
        guard let name = value("name", in: tags) else { return nil }
        let raw = value("opening_hours", in: tags)
        if let raw, ["closed", "off"].contains(raw.lowercased()) {
            return nil
        }
        let id = "\(OverpassPlacesSource.idPrefix)\(osmType)/\(osmId)"
        let hours = raw.map { OpeningHoursParser.parse($0).hours }
            ?? OpeningHours(hoursKnown: false, weekly: [], exceptions: [])
        var facts: [Fact] = []
        if let site = website(in: tags) {
            facts.append(Fact(text: "Website: \(site)", sourceId: id, checkedAt: checkedAt))
        }
        return Place(
            id: id,
            name: name,
            kind: kind(for: tags),
            location: PlaceLocation(coordinate: coordinate, address: address(in: tags), approximate: false),
            hours: hours,
            priceLevel: nil,
            booking: PlaceBooking(needed: false, url: nil),
            indoor: isIndoor(tags),
            images: [],
            facts: facts,
            copy: nil
        )
    }

    /// The kind of the first rule that matches. Anything else is `other`.
    static func kind(for tags: [String: String]) -> PlaceKind {
        kindRules.first { $0.matches(tags) }?.kind ?? .other
    }

    /// Parks, gardens, squares, bridges, viewpoints, markets and the outdoor historic sites are outdoors. Everything
    /// else is indoors.
    static func isIndoor(_ tags: [String: String]) -> Bool {
        if tags["leisure"] == "park" || tags["leisure"] == "garden" { return false }
        if tags["place"] == "square" || tags["man_made"] == "bridge" { return false }
        if tags["tourism"] == "viewpoint" || tags["amenity"] == "marketplace" { return false }
        let outdoorHistoric = ["monument", "memorial", "ruins", "archaeological_site", "city_gate"]
        if let historic = value("historic", in: tags), outdoorHistoric.contains(historic) { return false }
        return true
    }

    /// "<number> <street>, <city or postcode>", with the missing parts left out. Nil without a street.
    static func address(in tags: [String: String]) -> String? {
        guard let street = value("addr:street", in: tags) else { return nil }
        let line = value("addr:housenumber", in: tags).map { "\($0) \(street)" } ?? street
        guard let town = value("addr:city", in: tags) ?? value("addr:postcode", in: tags) else { return line }
        return "\(line), \(town)"
    }

    /// The website from `website`, or else `contact:website`.
    static func website(in tags: [String: String]) -> String? {
        value("website", in: tags) ?? value("contact:website", in: tags)
    }

    /// The tag's value with the surrounding spaces removed, or nil when it is missing or empty.
    static func value(_ key: String, in tags: [String: String]) -> String? {
        let trimmed = tags[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
