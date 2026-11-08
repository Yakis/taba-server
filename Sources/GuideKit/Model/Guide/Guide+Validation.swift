extension Guide {
    /// Every structural problem in this guide, in a stable order. Empty when the guide is structurally valid.
    public var structureProblems: [StructureProblem] {
        var problems: [StructureProblem] = []
        if trip.dates.end < trip.dates.start {
            problems.append(.tripEndsBeforeStart)
        }
        for (key, place) in places.sorted(by: { $0.key < $1.key }) {
            if key != place.id {
                problems.append(.placeKeyMismatch(key: key, placeId: place.id))
            }
            if let level = place.priceLevel, !(1...4).contains(level) {
                problems.append(.priceLevelOutOfRange(placeId: place.id, level: level))
            }
        }
        for booking in bookings where booking.arrives < booking.departs {
            problems.append(.bookingArrivesBeforeDeparts(bookingId: booking.id))
        }
        for day in days {
            for stop in day.stops where stop.minutes <= 0 {
                problems.append(.stopMinutesNotPositive(stopId: stop.id))
            }
        }
        return problems + referenceProblems
    }

    /// Throws `GuideStructureError` listing every problem, if there are any.
    public func validateStructure() throws(GuideStructureError) {
        let problems = structureProblems
        if !problems.isEmpty {
            throw GuideStructureError(problems: problems)
        }
    }
}
