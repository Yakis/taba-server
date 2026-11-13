extension Guide {
    /// Every place in the guide's prose that contradicts its facts. Empty for a guide whose words agree with what
    /// the traveller arranged. Checked on the finished guide, so it catches what the writer and the planner said,
    /// whatever the prompts asked for.
    ///
    /// - With no stay the traveller named, no prose talks about somewhere to sleep, or checking in or out.
    /// - With a named stay but no night in the trip, no prose talks about checking in or out.
    /// - No logistics or rest stop is at a hotel or other lodging that is not the traveller's stay.
    ///
    /// Practical facts and place facts are left out: they are sourced text, not the guide's own words.
    public var contradictions: [GuideContradiction] {
        let arrangement = stayArrangement
        let names = places.values.map(\.name)
        var found: [GuideContradiction] = []
        for (path, text) in proseFields where !text.isEmpty {
            if arrangement != .booked, let words = StayTalk.accommodation(in: text, ignoring: names) {
                found.append(GuideContradiction(path: path, words: words, text: text,
                                                reason: Self.noStayReason(arrangement)))
            } else if arrangement != .booked || isOneDay,
                      let words = StayTalk.checkInOrOut(in: text, ignoring: names) {
                let reason = arrangement == .booked
                    ? "The trip has no night, so there is no check-in or check-out."
                    : Self.noStayReason(arrangement)
                found.append(GuideContradiction(path: path, words: words, text: text, reason: reason))
            }
        }
        for day in days {
            for stop in day.stops where [StopKind.logistics, .rest].contains(stop.kind) {
                guard let id = stop.placeId, let place = places[id], place.kind == .lodging,
                      !isStayPlace(id) else { continue }
                found.append(GuideContradiction(
                    path: "stops[\(stop.id)].placeId", words: place.name, text: stop.copy.title,
                    reason: "\(place.name) is not where the traveller stays, "
                        + "so the plan cannot rest or leave bags there."))
            }
        }
        return found
    }

    private static func noStayReason(_ arrangement: StayArrangement) -> String {
        arrangement == .notNeeded
            ? "The trip has no night and no stay, so there is nowhere to sleep, check in or check out."
            : "The traveller did not say where they sleep, so the guide says nothing about it."
    }

    /// Every piece of prose the guide shows, with a path that says where it is.
    var proseFields: [(path: String, text: String)] {
        var fields: [(path: String, text: String)] = []
        if let hero {
            fields += [("hero.title", hero.title), ("hero.subtitle", hero.subtitle), ("hero.tagline", hero.tagline)]
        }
        for day in days {
            fields += [("days[\(day.date)].title", day.copy.title), ("days[\(day.date)].summary", day.copy.summary)]
            for stop in day.stops {
                fields += [("stops[\(stop.id)].title", stop.copy.title), ("stops[\(stop.id)].body", stop.copy.body)]
                if let label = stop.copy.actionLabel { fields.append(("stops[\(stop.id)].actionLabel", label)) }
            }
        }
        for (id, place) in places.sorted(by: { $0.key < $1.key }) {
            guard let copy = place.copy else { continue }
            fields += [("places[\(id)].tag", copy.tag), ("places[\(id)].blurb", copy.blurb)]
        }
        for (index, list) in lists.enumerated() {
            fields += [("lists[\(index)].title", list.title), ("lists[\(index)].caption", list.caption)]
        }
        for (index, item) in tasting.enumerated() {
            fields += [("tasting[\(index)].name", item.name), ("tasting[\(index)].note", item.note)]
        }
        if let notes {
            fields += [("notes.weather", notes.weather), ("notes.light", notes.light),
                       ("notes.backupPlan", notes.backupPlan), ("notes.rules", notes.rules)]
        }
        for (index, question) in (openQuestions ?? []).enumerated() {
            fields.append(("openQuestions[\(index)]", question))
        }
        return fields
    }
}
