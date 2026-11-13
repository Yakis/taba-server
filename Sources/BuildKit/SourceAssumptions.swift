import Foundation
import GuideKit

// The practical facts the build adds on its own, and what the traveller is told about the day's start and end.
extension SourcePreparation {
    /// The practical facts the build adds on its own. Each is true and useful to the traveller: a booked stay whose
    /// check-in and check-out times are typical, where the day starts and ends when a hub was looked up or not found,
    /// and the luggage store. Nothing is said about accommodation or currency. The `taba-assumptions` source is added
    /// only when a fact uses it.
    public static func assumptions(_ options: SourceInput, seed: Guide?, today: LocalDate, facts: TripFacts,
                                   sources: inout [Source]) -> [Fact] {
        if let seed { return seed.practical }
        var texts: [String] = []
        if facts.stay.timesEstimated == true {
            texts.append("Check-in 15:00 and check-out 11:00 are typical times, not from your booking. "
                + "Check them with your stay.")
        }
        if let hub = hubFact(options, facts: facts) { texts.append(hub) }
        // Hand luggage only means there are no bags to store, so there is no luggage store to report on.
        if options.luggage != nil && !options.handLuggageOnly {
            texts.append(facts.stay.luggage != nil
                ? "Luggage store hours 08:00 to 20:00 are an assumption, not confirmed. "
                    + "Check them before relying on it."
                : "The luggage store could not be found on the map, so the plan carries the bags. "
                    + "Check where bags can be left.")
        }
        guard !texts.isEmpty else { return [] }
        let source = Source(id: "taba-assumptions", url: "https://example.com/assumptions",
                            title: "Planning assumptions", checkedAt: today)
        sources.append(source)
        return texts.map { Fact(text: $0, sourceId: source.id, checkedAt: today) }
    }

    /// What the traveller is told about where the day starts and ends. A hub found by the build is named; a typed
    /// place that is not on the map is reported. A typed place that was found says nothing more.
    private static func hubFact(_ options: SourceInput, facts: TripFacts) -> String? {
        let arrivalId = facts.trip.travel?.arrivalPlaceId
        if let typed = options.travelPlace {
            return arrivalId == nil
                ? "\(typed) could not be found on the map, so the walks to and from it are not measured."
                : nil
        }
        guard let mode = options.travelMode, let arrivalId, let place = facts.places[arrivalId] else { return nil }
        let noun: String = switch mode {
        case .train: "station"
        case .coach: "coach station"
        case .flight: "airport"
        case .car: "car park"
        }
        return "The day starts and ends at \(place.name), the main \(noun) on the map. "
            + "If you arrive somewhere else, the first and last walks will be different."
    }
}
