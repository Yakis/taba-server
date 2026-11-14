/// Checks that the plan follows the traveller's preferences: the ranked interests, the pace of each day, drink stops
/// and the daily spend. These mirror plan.md rules 10, 16 and 17.
///
/// The interest checks read the places' recorded interests (`Place.interests`). A guide with none recorded gets no
/// interest findings, rather than a guess from the kinds of places.
extension Stop {
    /// Sights and drinks: the stops a day's pace counts. Meals, rests, travel and logistics do not count.
    public var isMainStop: Bool {
        kind == .sight || kind == .drink
    }
}

/// A main stop with the trip interests its place serves.
private struct ServedMainStop {
    let stop: Stop
    let interests: Set<String>
}

extension PlanChecker {
    /// Every finding about the traveller's preferences.
    func preferenceFindings(_ context: CheckContext) -> [Finding] {
        interestFindings(context)
            + context.guide.days.flatMap { dayFindings($0, context) }
            + spendFindings(context)
    }

    // MARK: Interests

    private func interestFindings(_ context: CheckContext) -> [Finding] {
        guard context.guide.places.values.contains(where: { $0.interests != nil }) else { return [] }
        let mains = servedMainStops(context)
        return topInterestFindings(context, mains) + dominanceFindings(context, mains)
    }

    private func servedMainStops(_ context: CheckContext) -> [ServedMainStop] {
        context.guide.days.flatMap(\.stops).filter(\.isMainStop).map { stop in
            ServedMainStop(stop: stop, interests: Set(context.place(stop.placeId)?.interests ?? []))
        }
    }

    /// The main-stop minutes that serve an interest. A stop counts for every interest its place serves.
    private func minutes(for interest: String, _ mains: [ServedMainStop]) -> Int {
        mains.filter { $0.interests.contains(interest) }.reduce(0) { $0 + $1.stop.minutes }
    }

    /// The top-ranked interest, once served by a main stop, should get more main-stop minutes than any other.
    private func topInterestFindings(_ context: CheckContext, _ mains: [ServedMainStop]) -> [Finding] {
        let interests = context.guide.trip.interests
        guard interests.count >= 2, let top = interests.first,
              mains.contains(where: { $0.interests.contains(top) }) else { return [] }
        let topMinutes = minutes(for: top, mains)
        let lower = interests.dropFirst().map { (name: $0, minutes: minutes(for: $0, mains)) }
        guard let rival = lower.max(by: { $0.minutes < $1.minutes }), rival.minutes > topMinutes else { return [] }
        let message = "\"\(top)\" is the top interest, but \"\(rival.name)\" gets \(rival.minutes) minutes at main "
            + "stops and \"\(top)\" gets \(topMinutes). The top-ranked interest should get the most time and the best "
            + "slots, without dropping the others."
        return [Finding(.warning, .topInterestOutweighed, date: context.guide.trip.dates.start, message: message)]
    }

    /// With three or more interests and four or more main stops, no one interest may take over half the main-stop time.
    private func dominanceFindings(_ context: CheckContext, _ mains: [ServedMainStop]) -> [Finding] {
        let interests = context.guide.trip.interests
        let total = mains.reduce(0) { $0 + $1.stop.minutes }
        guard interests.count >= 3, mains.count >= 4, total > 0 else { return [] }
        let leader = interests.map { (name: $0, minutes: minutes(for: $0, mains)) }
            .max(by: { $0.minutes < $1.minutes })
        guard let leader, leader.minutes * 2 > total else { return [] }
        let percent = leader.minutes * 100 / total
        let message = "\"\(leader.name)\" takes \(percent)% of the main-stop time (\(leader.minutes) of \(total) "
            + "minutes). Give more of the time to the other interests and to the city's best sights."
        return [Finding(.warning, .interestDominates, date: context.guide.trip.dates.start, message: message)]
    }

    // MARK: Days

    /// A full day is neither the arrival day nor the departure day, and a one-day trip has none.
    private func isFullDay(_ day: Day, _ context: CheckContext) -> Bool {
        guard !context.guide.isOneDay else { return false }
        return context.arrival?.time.date != day.date && context.departure?.time.date != day.date
    }

    private func dayFindings(_ day: Day, _ context: CheckContext) -> [Finding] {
        var findings = drinkFindings(day) + mainStopCountFindings(day, context)
        if isFullDay(day, context) {
            findings += startFindings(day, context) + restFindings(day, context)
        }
        return findings
    }

    /// More than two drink stops in a day is too many, whatever the pace.
    private func drinkFindings(_ day: Day) -> [Finding] {
        let drinks = day.stops.filter { $0.kind == .drink }.count
        guard drinks > 2 else { return [] }
        let message = "There are \(drinks) drink stops on \(day.date), more than 2 in a day."
        return [Finding(.warning, .drinkHeavyDay, date: day.date, message: message)]
    }

    /// Too many main stops is a warning on any day. Too few is only information, and only on a full day.
    private func mainStopCountFindings(_ day: Day, _ context: CheckContext) -> [Finding] {
        let pace = context.guide.trip.pace
        let range = pace.mainStopRange
        let count = day.stops.filter(\.isMainStop).count
        let limits = "The \(pace.rawValue) pace allows \(Self.rangeText(pace))."
        if count > range.upperBound {
            let message = "There are \(count) main stops on \(day.date). \(limits)"
            return [Finding(.warning, .mainStopsOverPace, date: day.date, message: message)]
        }
        guard count < range.lowerBound, isFullDay(day, context) else { return [] }
        let message = "There are \(count) main stops on \(day.date). \(limits)"
        return [Finding(.info, .mainStopsUnderPace, date: day.date, message: message)]
    }

    /// The first main stop of a full day starts no earlier than the pace allows.
    private func startFindings(_ day: Day, _ context: CheckContext) -> [Finding] {
        let pace = context.guide.trip.pace
        guard let notBefore = pace.firstMainStopNotBefore,
              let first = day.stops.filter(\.isMainStop).min(by: { $0.start < $1.start }),
              first.start < notBefore else { return [] }
        let message = "The first main stop on \(day.date) starts at \(first.start), before \(notBefore), "
            + "the earliest for the \(pace.rawValue) pace."
        return [Finding(.warning, .startsBeforePace, date: day.date, stop: first, message: message)]
    }

    /// A relaxed or unhurried full day has a rest stop of at least 45 minutes.
    private func restFindings(_ day: Day, _ context: CheckContext) -> [Finding] {
        let pace = context.guide.trip.pace
        guard pace != .packed else { return [] }
        let hasRest = day.stops.contains { $0.kind == .rest && $0.minutes >= Self.restMinutes }
        guard !hasRest else { return [] }
        let message = "There is no rest of \(Self.restMinutes) minutes or more on \(day.date). "
            + "Relaxed and unhurried days "
            + "need one, such as a cafe, a park or a museum bench."
        return [Finding(.warning, .restMissing, date: day.date, message: message)]
    }

    private static let restMinutes = 45

    private static func rangeText(_ pace: Pace) -> String {
        let range = pace.mainStopRange
        return range.upperBound == Int.max
            ? "\(range.lowerBound) or more main stops"
            : "\(range.lowerBound) to \(range.upperBound) main stops"
    }

    // MARK: Spend

    /// A meal or drink above the trip's price ceiling. A place with no price level never counts.
    private func spendFindings(_ context: CheckContext) -> [Finding] {
        let spend = context.guide.trip.budget.dailySpend
        guard let ceiling = spend.priceCeiling else { return [] }
        var findings: [Finding] = []
        for day in context.guide.days {
            for stop in day.stops where [.meal, .drink].contains(stop.kind) {
                guard let place = context.place(stop.placeId), let level = place.priceLevel, level > ceiling else {
                    continue
                }
                let message = "\(place.name) has price level \(level), above the ceiling of \(ceiling) "
                    + "for a \(spend.rawValue) daily spend."
                findings.append(Finding(.warning, .overSpend, date: day.date, stop: stop, message: message))
            }
        }
        return findings
    }
}
