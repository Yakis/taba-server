import GuideKit

/// Marks the places that a market or an event on the trip dates makes worth visiting after dark, so the plan check
/// does not call an evening stop there "after sunset". A seasonal market in a public garden is the typical case: the
/// garden is an outdoor landmark, but the market is lit up in the evening.
enum AfterDarkPlaces {
    /// `places` with `afterDark` set on each place that a finding of kind `market` or `event` names, when that finding
    /// is on the trip dates. A finding names a place by `placeName`, or by its title when it has none. The names are
    /// compared as `ResearchFactFilter` compares them, with the city's own words left out.
    static func marked(_ places: [String: Place], findings: [ResearchFinding], cityName: String?) -> [String: Place] {
        let names: [String] = findings.compactMap { finding in
            guard finding.onTripDates, finding.kind == .market || finding.kind == .event else { return nil }
            let placeName = (finding.placeName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return placeName.isEmpty ? finding.title : placeName
        }
        guard !names.isEmpty else { return places }
        return places.mapValues { place in
            guard place.afterDark != true, names.contains(where: {
                ResearchFactFilter.namesPlace($0, placeName: place.name, cityName: cityName)
            }) else { return place }
            return place.withAfterDark()
        }
    }
}

private extension Place {
    func withAfterDark() -> Place {
        Place(id: id, name: name, kind: kind, location: location, hours: hours, priceLevel: priceLevel,
              booking: booking, indoor: indoor, images: images, facts: facts, copy: copy, website: website,
              phone: phone, interests: interests, afterDark: true)
    }
}
