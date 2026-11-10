extension PlanChecker {
    /// Places used by more than one stop on the trip. The first use of a place is fine. Each later use is a warning,
    /// except a stop that comes straight after another stop at the same place on the same day, such as lunch at a
    /// market followed by browsing it.
    func repeatFindings(_ context: CheckContext) -> [Finding] {
        var firstUse: [String: (date: LocalDate, start: LocalTime)] = [:]
        var findings: [Finding] = []
        for day in context.guide.days.sorted(by: { $0.date < $1.date }) {
            let stops = day.stops.sorted { $0.start < $1.start }
            for (index, stop) in stops.enumerated() {
                guard
                    let placeId = stop.placeId,
                    let place = context.place(placeId),
                    Self.countsForRepeats(stop, place, context)
                else {
                    continue
                }
                guard let first = firstUse[placeId] else {
                    firstUse[placeId] = (day.date, stop.start)
                    continue
                }
                let isBackToBack = index > 0 && stops[index - 1].placeId == placeId
                if isBackToBack {
                    continue
                }
                let message = "\(place.name) is already used on \(first.date) at \(first.start). "
                    + "Use a different place here."
                findings.append(Finding(.warning, .placeRepeated, date: day.date, stop: stop, message: message))
            }
        }
        return findings
    }

    /// Meals, drinks and sights at a place that is not the stay, the luggage store, lodging, luggage or a station.
    private static func countsForRepeats(_ stop: Stop, _ place: Place, _ context: CheckContext) -> Bool {
        guard [StopKind.meal, .drink, .sight].contains(stop.kind) else {
            return false
        }
        let stay = context.guide.stay
        if place.id == stay.placeId || place.id == stay.luggage?.placeId {
            return false
        }
        return ![PlaceKind.lodging, .luggage, .station].contains(place.kind)
    }
}
