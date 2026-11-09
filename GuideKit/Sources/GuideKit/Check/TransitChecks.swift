extension PlanChecker {
    /// Stops that start before the traveller can arrive at them, and stops too close to the train home.
    /// A booking without a station id is reported once as info, and its journeys count as 0.
    func transitFindings(_ context: CheckContext) -> [Finding] {
        var findings: [Finding] = []
        if let arrival = context.arrival, let day = context.day(on: arrival.time.date) {
            findings += arrivalFindings(arrival, day, context)
        }
        if let departure = context.departure, let day = context.day(on: departure.time.date) {
            findings += departureFindings(departure, day, context)
        }
        if let booking = context.arrivalBooking, booking.toPlaceId == nil {
            findings.append(stationUnknown(booking, "arrival", context))
        }
        if let booking = context.departureBooking, booking.fromPlaceId == nil {
            findings.append(stationUnknown(booking, "departure", context))
        }
        return findings
    }

    private func stationUnknown(_ booking: Booking, _ direction: String, _ context: CheckContext) -> Finding {
        let date = direction == "arrival" ? booking.arrives.date : booking.departs.date
        let message = "The \(direction) station for booking \(booking.id) is not set, "
            + "so the journey from it is not checked."
        return Finding(.info, .stationUnknown, date: date, message: message)
    }

    private func arrivalFindings(_ arrival: TransitTime, _ day: Day, _ context: CheckContext) -> [Finding] {
        let arrivalMinutes = arrival.time.time.minutesSinceMidnight
        let station = context.place(arrival.stationPlaceId)
        var findings: [Finding] = []
        for stop in day.stops where stop.kind != .travel {
            let journey = journeyMinutes(station, and: stop.placeId, context)
            let start = stop.start.minutesSinceMidnight
            if start < arrivalMinutes + journey {
                let message = "\(context.label(stop)) starts at \(Clock.text(start)), "
                    + "but the train arrives at \(Clock.text(arrivalMinutes)) "
                    + "and the journey from the station takes \(journey) minutes."
                findings.append(Finding(.error, .beforeArrival, date: day.date, stop: stop, message: message))
            }
        }
        return findings
    }

    private func departureFindings(_ departure: TransitTime, _ day: Day, _ context: CheckContext) -> [Finding] {
        let departMinutes = departure.time.time.minutesSinceMidnight
        let station = context.place(departure.stationPlaceId)
        let stopsBefore = day.stops.filter {
            $0.kind != .travel && $0.start.minutesSinceMidnight < departMinutes
        }
        guard let stop = stopsBefore.max(by: { $0.start < $1.start }) else {
            return []
        }
        let end = stop.start.minutesSinceMidnight + stop.minutes
        let journey = journeyMinutes(station, and: stop.placeId, context)
        let leaveBy = departMinutes - 30 - journey
        if end > leaveBy {
            let message = "\(context.label(stop)) ends at \(Clock.text(end)), "
                + "but you need to leave by \(Clock.text(leaveBy)) for the \(Clock.text(departMinutes)) train, "
                + "with a 30-minute margin and a \(journey)-minute journey."
            return [Finding(.error, .missedDeparture, date: day.date, stop: stop, message: message)]
        }
        if leaveBy - end < 15 {
            let message = "\(context.label(stop)) ends at \(Clock.text(end)), "
                + "less than 15 minutes before the leave-by time of \(Clock.text(leaveBy))."
            return [Finding(.warning, .tightDeparture, date: day.date, stop: stop, message: message)]
        }
        return []
    }

    /// Minutes between the station and a stop's place, walk or bus or taxi. Zero when either is unknown.
    private func journeyMinutes(_ station: Place?, and placeId: String?, _ context: CheckContext) -> Int {
        guard let station, let place = context.place(placeId) else {
            return 0
        }
        return context.leg(station, place).minutes
    }
}
