extension PlanChecker {
    /// Closed days, stops outside opening hours, and places whose hours are unknown.
    func hoursFindings(_ context: CheckContext) -> [Finding] {
        var findings: [Finding] = []
        for day in context.guide.days {
            for stop in day.stops {
                guard let place = context.place(stop.placeId), !skipsHours(stop, at: place, context) else {
                    continue
                }
                if place.hours.hoursKnown {
                    findings += knownHoursFindings(stop, place, on: day.date)
                } else {
                    findings += unknownHoursFindings(stop, place, on: day.date)
                }
            }
        }
        return findings
    }

    /// Travel and logistics at the stay or a station have no opening hours to check. Logistics at the luggage
    /// store are checked by the luggage rules instead.
    private func skipsHours(_ stop: Stop, at place: Place, _ context: CheckContext) -> Bool {
        if stop.kind == .logistics && place.id == context.guide.stay.luggage?.placeId {
            return true
        }
        guard stop.kind == .travel || stop.kind == .logistics else {
            return false
        }
        return place.kind == .station || context.guide.stay.holds(place.id) || context.isTravelPlace(place.id)
    }

    private func knownHoursFindings(_ stop: Stop, _ place: Place, on date: LocalDate) -> [Finding] {
        let windows = place.hours.openWindows(on: date)
        let start = stop.start.minutesSinceMidnight
        let end = start + stop.minutes
        if windows.isEmpty {
            return [
                Finding(.error, .closed, date: date, stop: stop, message: "\(place.name) is closed on \(date).")
            ]
        }
        if place.hours.covers(start, end, on: date) {
            return []
        }
        let openText = windows
            .map { "\(Clock.text($0.start))-\(Clock.text($0.end))" }
            .joined(separator: ", ")
        let message = "\(place.name) is open \(openText) on \(date), "
            + "but the stop runs \(Clock.text(start))-\(Clock.text(end))."
        return [Finding(.error, .outsideHours, date: date, stop: stop, message: message)]
    }

    private func unknownHoursFindings(_ stop: Stop, _ place: Place, on date: LocalDate) -> [Finding] {
        // A stay, a station and a luggage store are not checked for hours that are unknown.
        if [PlaceKind.lodging, .station, .luggage].contains(place.kind) {
            return []
        }
        if place.isOutdoorPublicSpace {
            return []
        }
        if !stop.flexible {
            let message = "\(place.name) has no known opening hours, and this stop is fixed in time."
            return [Finding(.warning, .hoursUnknown, date: date, stop: stop, message: message)]
        }
        let message = "\(place.name) has no known opening hours, so check them before going."
        return [Finding(.info, .hoursUnknown, date: date, stop: stop, message: message)]
    }
}
