extension Guide {
    /// Problems where one part of the guide points at another: place ids, source ids, day dates and stop ids.
    var referenceProblems: [StructureProblem] {
        var problems: [StructureProblem] = []

        var placeReferences: [(placeId: String, from: String)] = stay.placeId.map { [($0, "stay")] } ?? []
        if let travel = trip.travel {
            placeReferences += [travel.arrivalPlaceId.map { ($0, "travel arrival") },
                                travel.departurePlaceId.map { ($0, "travel departure") }].compactMap { $0 }
        }
        if let luggage = stay.luggage {
            placeReferences.append((luggage.placeId, "stay luggage"))
        }
        for booking in bookings {
            if let placeId = booking.fromPlaceId {
                placeReferences.append((placeId, "booking \(booking.id) from"))
            }
            if let placeId = booking.toPlaceId {
                placeReferences.append((placeId, "booking \(booking.id) to"))
            }
        }
        for list in lists {
            placeReferences += list.placeIds.map { (placeId: $0, from: "list \(list.title)") }
        }
        for day in days {
            for stop in day.stops {
                if let placeId = stop.placeId {
                    placeReferences.append((placeId, "stop \(stop.id)"))
                }
                if let alternative = stop.alternative {
                    placeReferences.append((alternative.placeId, "stop \(stop.id) alternative"))
                }
            }
        }
        for reference in placeReferences where places[reference.placeId] == nil {
            problems.append(.unknownPlaceReference(placeId: reference.placeId, from: reference.from))
        }

        let sourceIds = Set(sources.map(\.id))
        var sourceReferences: [(sourceId: String, from: String)] = practical.map {
            (sourceId: $0.sourceId, from: "practical")
        }
        for (key, place) in places.sorted(by: { $0.key < $1.key }) {
            sourceReferences += place.facts.map { (sourceId: $0.sourceId, from: "place \(key)") }
        }
        for reference in sourceReferences where !sourceIds.contains(reference.sourceId) {
            problems.append(.unknownSourceReference(sourceId: reference.sourceId, from: reference.from))
        }

        for day in days where day.date < trip.dates.start || trip.dates.end < day.date {
            problems.append(.dayOutsideTripDates(date: day.date))
        }

        var seenStopIds = Set<String>()
        for stopId in days.flatMap({ $0.stops.map(\.id) }) where !seenStopIds.insert(stopId).inserted {
            problems.append(.duplicateStopId(stopId: stopId))
        }
        return problems
    }
}
