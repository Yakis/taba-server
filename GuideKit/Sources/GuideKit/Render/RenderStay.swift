/// How far a place is from the guide's stay, in the app's words: "6 min from the stay", or "9.6 km from the stay" when
/// walking would take more than 45 minutes. Straight-line estimates, the same as the app.
enum RenderStay {
    /// Walks longer than this read as a distance instead, since nobody plans a two-hour walk from a list.
    static let longestWalkMinutes = 45

    /// "6 min from the stay" for a list row, or nil for the stay itself and places it cannot measure.
    static func listText(to place: Place, guide: Guide) -> String? {
        guard let distance = distance(to: place, guide: guide) else { return nil }
        if distance.isWalk {
            return "\(RenderText.duration(minutes: distance.minutes)) from the stay"
        }
        return "\(distance.kilometreText) km from the stay"
    }

    /// "6 min walk from the stay" for a place card, or nil for the stay itself and places it cannot measure.
    static func walkText(to place: Place, guide: Guide) -> String? {
        guard let distance = distance(to: place, guide: guide) else { return nil }
        if distance.isWalk {
            return "\(RenderText.duration(minutes: distance.minutes)) walk from the stay"
        }
        return "\(distance.kilometreText) km from the stay"
    }

    private static func distance(to place: Place, guide: Guide) -> Distance? {
        guard place.id != guide.stay.placeId, let stay = guide.places[guide.stay.placeId] else {
            return nil
        }
        let from = stay.location.coordinate
        let to = place.location.coordinate
        return Distance(
            minutes: StraightLineWalkTimes().minutes(from: from, to: to),
            kilometres: StraightLineWalkTimes.haversineMetres(from, to) / 1000
        )
    }

    private struct Distance {
        let minutes: Int
        let kilometres: Double

        var isWalk: Bool {
            minutes <= RenderStay.longestWalkMinutes
        }

        /// One decimal place, written by hand so it never depends on the locale: "9.6".
        var kilometreText: String {
            let tenths = Int((kilometres * 10).rounded())
            return "\(tenths / 10).\(tenths % 10)"
        }
    }
}
