extension PlanChecker {
    /// Check-in and check-out, and the luggage store's hours and use.
    func stayFindings(_ context: CheckContext) -> [Finding] {
        let stay = context.guide.stay
        let days = context.guide.days.sorted { $0.date < $1.date }
        var findings: [Finding] = []
        // A one-day trip has no night, so there is no check-in or check-out to check.
        let hasNight = !context.guide.isOneDay
        if hasNight, let first = days.first, let checkIn = stay.checkIn {
            for stop in first.stops where stop.kind == .logistics && stay.holds(stop.placeId) {
                if stop.start < checkIn {
                    let message = "\(context.label(stop)) starts at \(stop.start), before check-in at \(checkIn)."
                    findings.append(Finding(.error, .checkInEarly, date: first.date, stop: stop, message: message))
                }
            }
        }
        if hasNight, let last = days.last {
            findings += checkOutFindings(last, context)
        }
        findings += luggageFindings(days, context)
        return findings
    }

    private func checkOutFindings(_ day: Day, _ context: CheckContext) -> [Finding] {
        let stay = context.guide.stay
        guard let checkOut = stay.checkOut, stay.placeId != nil else { return [] }
        var stayLogisticsSeen = false
        for stop in day.stops.sorted(by: { $0.start < $1.start }) {
            if stay.holds(stop.placeId) {
                if stop.kind == .logistics {
                    stayLogisticsSeen = true
                }
                continue
            }
            // This is the first stop away from the stay.
            if !stayLogisticsSeen && stop.start > checkOut {
                let message = "\(context.label(stop)) starts at \(stop.start), after check-out at \(checkOut), "
                    + "and nothing at the stay comes before it."
                return [Finding(.error, .checkOutLate, date: day.date, stop: stop, message: message)]
            }
            return []
        }
        return []
    }

    private func luggageFindings(_ days: [Day], _ context: CheckContext) -> [Finding] {
        let stay = context.guide.stay
        guard let luggage = stay.luggage, let store = context.place(luggage.placeId) else {
            return []
        }
        var findings: [Finding] = []
        for day in days {
            for stop in day.stops where stop.kind == .logistics && stop.placeId == store.id {
                let start = stop.start.minutesSinceMidnight
                let end = start + stop.minutes
                guard store.hours.hoursKnown, !store.hours.covers(start, end, on: day.date) else {
                    continue
                }
                let message = "\(store.name) is not open from \(Clock.text(start)) "
                    + "to \(Clock.text(end)) on \(day.date)."
                findings.append(Finding(.error, .luggageClosed, date: day.date, stop: stop, message: message))
            }
        }
        findings += unusedLuggageFindings(store, days, context)
        return findings
    }

    /// Bags that could be dropped but are not. The traveller is away from the stay without bags:
    /// on arrival, from arrival until check-in or the first stop at the stay, whichever is earlier;
    /// on departure, from check-out or the end of the last stop at the stay, whichever is earlier, until leaving.
    private func unusedLuggageFindings(_ store: Place, _ days: [Day], _ context: CheckContext) -> [Finding] {
        let stay = context.guide.stay
        guard store.hours.hoursKnown else {
            return []
        }
        var findings: [Finding] = []
        // Without a check-in, bags are carried from arrival until a stop leaves them.
        let checkIn = stay.checkIn?.minutesSinceMidnight ?? Int.max
        if let arrival = context.arrival, arrival.time.time.minutesSinceMidnight < checkIn,
           let day = context.day(on: arrival.time.date) {
            let from = arrival.time.time.minutesSinceMidnight
            let firstStayStart = stayStops(day, context).map { $0.start.minutesSinceMidnight }.min()
            let to = min(checkIn, firstStayStart ?? Int.max, 1439)
            if to > from && isUnused(store, day, from: from, to: to) {
                let message = "You arrive at \(Clock.text(from)), and \(store.name) is open, "
                    + (to == 1439 ? "but no stop leaves bags there."
                        : "but no stop leaves bags there before \(Clock.text(to)).")
                findings.append(Finding(.warning, .luggageUnused, date: day.date, message: message))
            }
        }
        if let departure = context.departure, let checkOut = stay.checkOut, checkOut < departure.time.time,
           let day = context.day(on: departure.time.date) {
            let to = departure.time.time.minutesSinceMidnight
            let lastStayEnd = stayStops(day, context).map { $0.start.minutesSinceMidnight + $0.minutes }.max()
            let from = min(checkOut.minutesSinceMidnight, lastStayEnd ?? Int.max)
            if to > from && isUnused(store, day, from: from, to: to) {
                let message = "You are away from the stay from \(Clock.text(from)) and leave at \(Clock.text(to)), "
                    + "and \(store.name) is open, but no stop leaves bags there."
                findings.append(Finding(.warning, .luggageUnused, date: day.date, message: message))
            }
        }
        return findings
    }

    private func stayStops(_ day: Day, _ context: CheckContext) -> [Stop] {
        day.stops.filter { context.guide.stay.holds($0.placeId) }
    }

    private func isUnused(_ store: Place, _ day: Day, from: Int, to: Int) -> Bool {
        let openDuringGap = store.hours.openWindows(on: day.date).contains { $0.start < to && $0.end > from }
        let usedDuringGap = day.stops.contains {
            $0.placeId == store.id && $0.start.minutesSinceMidnight >= from && $0.start.minutesSinceMidnight < to
        }
        return openDuringGap && !usedDuringGap
    }
}
