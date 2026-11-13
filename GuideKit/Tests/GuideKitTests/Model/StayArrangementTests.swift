import GuideKit
import Testing

/// The four trips the traveller can make, and what the guide says about where they sleep. The arrangement decides the
/// base, the stay and the prose: nothing is invented.
struct StayArrangementScenarioTests {
    @Test func dayTripByTrainHasNoStayAndUsesTheStationAsBase() {
        let guide = StayScenarios.dayTripByTrain()
        #expect(guide.stayArrangement == .notNeeded)
        #expect(guide.stayPlace == nil)
        #expect(guide.base?.kind == .arrival(.train))
        #expect(guide.base?.phrase == "the station")
        #expect(guide.base?.place.id == StayScenarios.stationId)
        #expect(guide.structureProblems.isEmpty)
    }

    @Test func dayTripByTrainSaysNothingAboutSleeping() {
        #expect(StayScenarios.dayTripByTrain().contradictions.isEmpty)
    }

    @Test func overnightTripWithBookedStayUsesTheStay() {
        let guide = StayScenarios.overnightWithStay()
        #expect(guide.stayArrangement == .booked)
        #expect(guide.stayPlace?.id == StayScenarios.hotelId)
        #expect(guide.base?.kind == .stay)
        #expect(guide.base?.phrase == "the stay")
        #expect(guide.structureProblems.isEmpty)
    }

    @Test func checkInAndCheckOutWordsAreFineOnAnOvernightBookedStay() {
        #expect(StayScenarios.overnightWithStay().contradictions.isEmpty)
    }

    @Test func multiDayTripWithoutStayHasNoBase() {
        let guide = StayScenarios.multiDayWithoutStay()
        #expect(guide.stayArrangement == .unknown)
        #expect(guide.base == nil)
        #expect(guide.stayPlace == nil)
        #expect(guide.contradictions.isEmpty)
    }

    @Test func accommodationInAStopBodyIsAContradictionWithoutAStay() throws {
        let guide = StayScenarios.multiDayWithoutStay(body: "Check in at your hotel before dinner.")
        let found = try #require(guide.contradictions.first { $0.path == "stops[coffee].body" })
        #expect(found.words.lowercased() == "hotel")
        #expect(found.reason.contains("did not say where they sleep"))
    }

    @Test func accommodationInOpenQuestionsIsAContradictionWithoutAStay() throws {
        let guide = StayScenarios.multiDayWithoutStay(openQuestions: ["Do you need accommodation?"])
        let found = try #require(guide.contradictions.first)
        #expect(found.path == "openQuestions[0]")
        #expect(found.words.lowercased() == "accommodation")
    }

    @Test func checkInWordsAreAContradictionWithoutAStay() throws {
        let guide = StayScenarios.multiDayWithoutStay(body: "Check in on arrival.")
        let found = try #require(guide.contradictions.first { $0.path == "stops[coffee].body" })
        #expect(found.words == "Check in")
    }

    @Test func sameDayStayWithoutTimesUsesTheStayAsBase() {
        let guide = StayScenarios.sameDayWithStay(body: "Drop your bags at the hotel first.")
        #expect(guide.stayArrangement == .booked)
        #expect(guide.base?.kind == .stay)
        #expect(guide.base?.place.id == StayScenarios.hotelId)
    }

    @Test func mentioningTheStayIsFineOnADayTripWithAStay() {
        #expect(StayScenarios.sameDayWithStay(body: "Drop your bags at the hotel first.").contradictions.isEmpty)
    }

    @Test func checkInWordsAreAContradictionOnADayTripWithAStayAndSayNoNight() throws {
        let guide = StayScenarios.sameDayWithStay(body: "Check in at the hotel first.")
        let found = try #require(guide.contradictions.first { $0.path == "stops[rest].body" })
        #expect(found.reason.contains("no night"))
    }
}

/// Guides made before `arrangement` was recorded are read through their place (see `GuideBase.arrangement`).
struct StayLegacyArrangementTests {
    @Test func oneDayPlaceholderStayReadsAsNotNeeded() {
        let guide = StayScenarios.legacyGuide(oneDay: true, approximate: true)
        #expect(guide.stay.arrangement == nil)
        #expect(guide.stayArrangement == .notNeeded)
        #expect(guide.stayPlace == nil)
        #expect(guide.base == nil)
    }

    @Test func multiDayPlaceholderStayReadsAsUnknown() {
        let guide = StayScenarios.legacyGuide(oneDay: false, approximate: true)
        #expect(guide.stayArrangement == .unknown)
        #expect(guide.stayPlace == nil)
        #expect(guide.base == nil)
    }

    @Test func multiDayStayAtARealPlaceReadsAsBooked() {
        let guide = StayScenarios.legacyGuide(oneDay: false, approximate: false)
        #expect(guide.stayArrangement == .booked)
        #expect(guide.stayPlace?.id == "manual:stay")
        #expect(guide.base?.kind == .stay)
    }

    @Test func oneDayStayAtARealPlaceReadsAsBooked() {
        let guide = StayScenarios.legacyGuide(oneDay: true, approximate: false)
        #expect(guide.stayArrangement == .booked)
        #expect(guide.base?.kind == .stay)
    }
}

/// `Stay.holds` and `Guide.isStayPlace` must never match a missing place with a missing stay.
struct StayHoldsTests {
    private let hotel = StayScenarios.hotelId

    @Test func aStayWithNoPlaceHoldsNothing() {
        let stay = Stay(placeId: nil, checkIn: nil, checkOut: nil, luggage: nil, arrangement: .notNeeded)
        #expect(!stay.holds(nil))
        #expect(!stay.holds(hotel))
    }

    @Test func aStayHoldsItsOwnPlaceOnly() {
        let stay = Stay(placeId: hotel, checkIn: nil, checkOut: nil, luggage: nil, arrangement: .booked)
        #expect(stay.holds(hotel))
        #expect(!stay.holds(StayScenarios.cafeId))
        #expect(!stay.holds(nil))
    }

    @Test func noPlaceIsNeverTheStayPlaceOfAGuideWithoutOne() {
        let guide = StayScenarios.dayTripByTrain()
        #expect(guide.stayPlace == nil)
        #expect(!guide.isStayPlace(nil))
    }

    @Test func noPlaceIsNeverTheStayPlaceOfABookedGuide() {
        #expect(!StayScenarios.overnightWithStay().isStayPlace(nil))
        #expect(StayScenarios.overnightWithStay().isStayPlace(hotel))
    }

    @Test func aStopWithNoPlaceIsNotCheckedAgainstAStayWithNoPlace() {
        // Regression: a stop with no place must not count as "at the stay" just because the stay has no place.
        // The stay here has check-in and check-out times but no place, so the checker must not match them up.
        let stay = Stay(placeId: nil, checkIn: SampleGuide.time("15:00"), checkOut: SampleGuide.time("11:00"),
                        luggage: nil, arrangement: .unknown)
        let first = StayScenarios.day("2026-11-22", stops: [
            StayScenarios.stop("early", at: "14:00", minutes: 20, place: nil, kind: .logistics)
        ])
        let last = StayScenarios.day("2026-11-24", stops: [
            StayScenarios.stop("away", at: "12:00", minutes: 60, place: nil)
        ])
        let guide = StayScenarios.guide(
            trip: StayScenarios.trip(start: "2026-11-22", end: "2026-11-24"),
            stay: stay,
            places: [StayScenarios.cafe()],
            days: [first, StayScenarios.day("2026-11-23"), last]
        )
        let issues = Plan.issues(guide)
        #expect(!Plan.has(issues, .checkInEarly))
        #expect(!Plan.has(issues, .checkOutLate))
    }
}

/// The stay's place and the travel places must exist in `places`.
struct StayReferenceTests {
    @Test func aTravelArrivalPlaceMustBeAKnownPlace() {
        let travel = TripTravel(mode: .train, arrivalPlaceId: "manual:nowhere", departurePlaceId: nil)
        let guide = StayScenarios.guide(
            trip: StayScenarios.trip(start: "2026-11-22", end: "2026-11-22", travel: travel),
            stay: StayScenarios.noStay,
            places: [StayScenarios.cafe()]
        )
        #expect(guide.structureProblems == [.unknownPlaceReference(placeId: "manual:nowhere", from: "travel arrival")])
    }

    @Test func aTravelDeparturePlaceMustBeAKnownPlace() {
        let travel = TripTravel(mode: .coach, arrivalPlaceId: nil, departurePlaceId: "manual:nowhere")
        let guide = StayScenarios.guide(
            trip: StayScenarios.trip(start: "2026-11-22", end: "2026-11-22", travel: travel),
            stay: StayScenarios.noStay,
            places: [StayScenarios.cafe()]
        )
        #expect(guide.structureProblems == [
            .unknownPlaceReference(placeId: "manual:nowhere", from: "travel departure")
        ])
    }

    @Test func knownTravelPlacesAreFine() {
        let travel = TripTravel(mode: .train, arrivalPlaceId: StayScenarios.stationId,
                                departurePlaceId: StayScenarios.stationId)
        let guide = StayScenarios.guide(
            trip: StayScenarios.trip(start: "2026-11-22", end: "2026-11-22", travel: travel),
            stay: StayScenarios.noStay,
            places: [StayScenarios.station(), StayScenarios.cafe()]
        )
        #expect(guide.structureProblems.isEmpty)
    }
}

/// "from the station" and "from the stay" in the rendered page, following the guide's base.
struct StayRenderTests {
    @Test func dayTripByTrainMeasuresFromTheStation() {
        let html = GuideHTMLRenderer().render(StayScenarios.dayTripByTrain())
        #expect(html.contains("from the station"))
        #expect(!html.contains("from the stay"))
    }

    @Test func multiDayTripWithoutStayMeasuresFromNothing() {
        let html = GuideHTMLRenderer().render(StayScenarios.multiDayWithoutStay())
        #expect(!html.contains("from the station"))
        #expect(!html.contains("from the stay"))
        #expect(!html.contains("walk from"))
    }
}

/// The arrangement, times and travel survive encoding. Fields that are not set are not written.
struct StayRoundTripTests {
    @Test func dayTripWithTravelRoundTrips() throws {
        let guide = StayScenarios.dayTripByTrain()
        #expect(try roundTrip(guide) == guide)
        let json = try encodedJSON(guide)
        #expect(json.contains("\"arrangement\" : \"notNeeded\""))
        #expect(json.contains("\"arrivalPlaceId\" : \"\(StayScenarios.stationId)\""))
    }

    @Test func overnightBookedStayWithEstimatedTimesRoundTrips() throws {
        let guide = StayScenarios.overnightWithStay()
        #expect(try roundTrip(guide) == guide)
        let json = try encodedJSON(guide)
        #expect(json.contains("\"arrangement\" : \"booked\""))
        #expect(json.contains("\"timesEstimated\" : true"))
    }

    @Test func legacyGuideRoundTripsWithoutNewKeys() throws {
        let guide = StayScenarios.legacyGuide(oneDay: false, approximate: true)
        #expect(try roundTrip(guide) == guide)
        let json = try encodedJSON(guide)
        #expect(!json.contains("\"arrangement\""))
        #expect(!json.contains("\"timesEstimated\""))
        #expect(!json.contains("\"travel\""))
    }
}
