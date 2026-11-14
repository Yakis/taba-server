import GuideKit

/// Which of the trip's interests each place serves, recorded on the finished guide as `Place.interests`. It uses the
/// same `InterestMatch` rule as the plan's candidates, so the guide records what the planner was shown.
enum ServedInterests {
    /// Place id to the interests it serves, in trip order. Places that serve none have no entry.
    static func byPlace(_ places: [String: Place], interests: [String],
                        searchLabels: [String: [String]]) -> [String: [String]] {
        var served: [String: [String]] = [:]
        for (id, place) in places {
            let names = InterestMatch.interests(for: interests, kind: place.kind, indoor: place.indoor,
                                                searchLabels: searchLabels[id] ?? [])
            if !names.isEmpty {
                served[id] = names
            }
        }
        return served
    }
}
