import GuideKit

/// The Edinburgh mock trip, finished the way the server finishes a guide. The mock's plan and places go through
/// `GuideAssembler`, with a hero, notes, open questions and the weather added. The extras are invented for the sample
/// and name only public places.
enum FinishedGuide {
    static let id = "edinburgh-guide"

    static func make() throws -> Guide {
        let fixture = try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghMockData())
        let result = GuideAssembler(walkTimes: StraightLineWalkTimes()).assemble(
            id: id,
            facts: facts(from: fixture),
            draft: plan(from: fixture),
            copy: writing(from: fixture)
        )
        guard result.problems.isEmpty else {
            throw FinishedGuideError(problems: result.problems)
        }
        let guide = finished(result.guide)
        try guide.validateStructure()
        return guide
    }

    private static func facts(from fixture: Guide) -> TripFacts {
        TripFacts(
            trip: fixture.trip,
            bookings: fixture.bookings,
            stay: fixture.stay,
            places: fixture.places,
            practical: fixture.practical,
            sources: fixture.sources
        )
    }

    /// The mock's plan, with the open questions added.
    private static func plan(from fixture: Guide) -> PlanDraft {
        let plan = FixtureDraft.planDraft(from: fixture)
        return PlanDraft(
            days: plan.days,
            lists: plan.lists,
            skippedMeals: plan.skippedMeals,
            openQuestions: openQuestions,
            changes: plan.changes
        )
    }

    /// The mock's words, with the hero and notes added.
    private static func writing(from fixture: Guide) -> GuideCopy {
        let words = FixtureDraft.copy(from: fixture)
        return GuideCopy(
            hero: hero,
            days: words.days,
            stops: words.stops,
            places: words.places,
            lists: words.lists,
            tasting: words.tasting,
            notes: notes
        )
    }

    /// The assembled guide, marked ready, with the weather added to each day.
    private static func finished(_ assembled: Guide) -> Guide {
        let days = assembled.days.map { day in
            Day(date: day.date, copy: day.copy, stops: day.stops, weather: outlook(for: day.date))
        }
        return Guide(
            id: assembled.id,
            version: assembled.version,
            status: .ready,
            trip: assembled.trip,
            bookings: assembled.bookings,
            stay: assembled.stay,
            places: assembled.places,
            days: days,
            lists: assembled.lists,
            tasting: assembled.tasting,
            practical: assembled.practical,
            sources: assembled.sources,
            hero: assembled.hero,
            notes: assembled.notes,
            openQuestions: assembled.openQuestions
        )
    }

    private static let hero = GuideHero(
        title: "Three short days in Edinburgh",
        subtitle: "Markets, closes and a pint by the fire",
        tagline: "Dress for drizzle, plan for magic."
    )

    private static let notes = GuideNotes(
        weather: "Expect 1 to 9°C, short days and rain on at least one of them. "
            + "A waterproof and good shoes matter more than anything smart.",
        light: "The sun rises after eight and sets before four. "
            + "Blue hour is the best time for the Christmas lights.",
        backupPlan: "If it pours, swap Calton Hill for the street food hall and save the views for a dry hour.",
        rules: "Eat when you're hungry, not when the plan says. One pub an evening is plenty. "
            + "Stairs are fine; hurry is not."
    )

    private static let openQuestions = [
        "Check the luggage store's Sunday hours before you travel.",
        "Opening hours for Calton Hill are not confirmed.",
        "Decide whether to book Monday's dinner or keep it loose."
    ]

    /// The expected weather for each trip day. Every outlook is typical for late November, not a forecast.
    private static let weather: [(date: String, outlook: DayOutlook)] = [
        ("2025-11-23", typical("Cloudy with dry spells", high: 9, low: 4, rain: 30)),
        ("2025-11-24", typical("Rain likely", high: 8, low: 3, rain: 70)),
        ("2025-11-25", typical("Bright and cold", high: 7, low: 1, rain: 20))
    ]

    private static func typical(_ summary: String, high: Int, low: Int, rain: Int) -> DayOutlook {
        DayOutlook(summary: summary, highCelsius: high, lowCelsius: low, rainChance: rain, isForecast: false)
    }

    private static func outlook(for date: LocalDate) -> DayOutlook? {
        weather.first { LocalDate($0.date) == date }?.outlook
    }
}

/// The assembler reported copy that does not match the plan, so the sample would be incomplete.
struct FinishedGuideError: Error {
    let problems: [AssemblyProblem]
}
