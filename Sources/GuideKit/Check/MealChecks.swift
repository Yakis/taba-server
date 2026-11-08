extension PlanChecker {
    /// Meal slots as half-open ranges of minutes: breakfast 07:30-10:30, lunch 11:30-14:30, dinner 17:30-21:00.
    static func slotRange(_ slot: MealSlot) -> (start: Int, end: Int) {
        switch slot {
        case .breakfast:
            return (450, 630)
        case .lunch:
            return (690, 870)
        case .dinner:
            return (1050, 1260)
        }
    }

    /// Missing meals on each day, and meals that start outside their slot. Arrival and departure days only
    /// need the meals that overlap the time the traveller is in the city.
    func mealFindings(_ context: CheckContext) -> [Finding] {
        var findings: [Finding] = []
        for day in context.guide.days {
            let window = cityWindow(on: day.date, context)
            for slot in MealSlot.allCases {
                let range = Self.slotRange(slot)
                let required = range.start < window.end && range.end > window.start
                let meals = day.stops.filter { $0.kind == .meal && $0.mealSlot == slot }
                if required && meals.isEmpty {
                    let message = "There is no \(slot.rawValue) on \(day.date), and the day needs one."
                    findings.append(Finding(.warning, .mealMissing, date: day.date, message: message))
                }
                for stop in meals {
                    let start = stop.start.minutesSinceMidnight
                    if start < range.start || start >= range.end {
                        let slotText = "\(Clock.text(range.start))-\(Clock.text(range.end))"
                        let message = "The \(slot.rawValue) at \(Clock.text(start)) is outside its \(slotText) slot."
                        findings.append(Finding(.info, .mealOffSlot, date: day.date, stop: stop, message: message))
                    }
                }
            }
        }
        return findings
    }

    /// The minutes of the day the traveller is in the city: from arrival (or 00:00) to departure (or 24:00).
    private func cityWindow(on date: LocalDate, _ context: CheckContext) -> (start: Int, end: Int) {
        var start = 0
        var end = 1440
        if let arrival = context.arrival, arrival.time.date == date {
            start = arrival.time.time.minutesSinceMidnight
        }
        if let departure = context.departure, departure.time.date == date {
            end = departure.time.time.minutesSinceMidnight
        }
        return (start, end)
    }
}
