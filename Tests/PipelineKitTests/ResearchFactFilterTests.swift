import Foundation
import GuideKit
@testable import PipelineKit
import Testing

struct ResearchFactFilterTests {
    /// A visited place from the Edinburgh fixture, a plan that visits it, and the trip's other facts.
    private struct Setting {
        let base: TripFacts
        let draft: PlanDraft
        let visitedName: String
    }

    private func setting() throws -> Setting {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")
        let guide = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: url))
        let placeId = try #require(guide.places.keys.sorted().first)
        let visitedName = try #require(guide.places[placeId]?.name)
        let day = guide.trip.dates.start
        let stop = PlanDraftStop(id: "d1-s1", placeId: placeId, kind: .sight, mealSlot: nil,
                                 start: try #require(LocalTime("10:00")), minutes: 60, flexible: false,
                                 alternative: nil, reason: "Visit", findingIds: [])
        let draft = PlanDraft(days: [PlanDraftDay(date: day, theme: "Walk", stops: [stop])], lists: [],
                              skippedMeals: [], openQuestions: [], changes: [])
        let assumptions = Source(id: "taba-assumptions", url: "https://example.com/assumptions",
                                 title: "Assumptions", checkedAt: day)
        let practical = [Fact(text: "Bring a layer.", sourceId: "taba-assumptions", checkedAt: day),
                         Fact(text: "Do not schedule the walk.", sourceId: "taba-assumptions", checkedAt: day)]
        let base = TripFacts(trip: guide.trip, bookings: [], stay: guide.stay, places: guide.places,
                             practical: practical, sources: [assumptions])
        return Setting(base: base, draft: draft, visitedName: visitedName)
    }

    private func finding(_ id: String, kind: FindingKind = .event, title: String = "Late opening",
                         summary: String = "Open late on the day.", placeName: String?,
                         onTripDates: Bool = true) -> ResearchFinding {
        ResearchFinding(id: id, kind: kind, title: title, summary: summary, startDate: nil, endDate: nil,
                        times: nil, placeName: placeName, address: nil, url: "https://example.com/\(id)",
                        sourceTitle: "Example", confidence: .high, onTripDates: onTripDates)
    }

    /// The facts as the pipeline makes them: one research fact and source for each finding, in order.
    private func withResearch(_ base: TripFacts, _ findings: [ResearchFinding]) -> TripFacts {
        var sources = base.sources
        var practical = base.practical
        let checked = base.trip.dates.start
        for (index, finding) in findings.enumerated() {
            let id = "taba-research-\(index)"
            sources.append(Source(id: id, url: finding.url, title: finding.sourceTitle, checkedAt: checked))
            practical.append(Fact(text: ResearchFactFilter.factText(for: finding), sourceId: id, checkedAt: checked))
        }
        return TripFacts(trip: base.trip, bookings: base.bookings, stay: base.stay, places: base.places,
                         practical: practical, sources: sources)
    }

    /// The made-up station where a train trip arrives.
    private static let stationName = "Riverside Station"

    /// The trip's facts with a way of travelling recorded: arriving at a made-up station. Nil leaves them as they are.
    private func travelling(_ base: TripFacts, mode: TravelMode?) throws -> TripFacts {
        guard let mode else { return base }
        let model = try #require(base.places.values.first)
        let station = Place(id: "manual:arrival", name: Self.stationName, kind: .station, location: model.location,
                            hours: model.hours, priceLevel: nil, booking: model.booking, indoor: true, images: [],
                            facts: [], copy: nil)
        let trip = Trip(destination: base.trip.destination, dates: base.trip.dates, party: base.trip.party,
                        budget: base.trip.budget, interests: base.trip.interests, pace: base.trip.pace,
                        voice: base.trip.voice,
                        travel: TripTravel(mode: mode, arrivalPlaceId: station.id, departurePlaceId: station.id))
        return TripFacts(trip: trip, bookings: base.bookings, stay: base.stay,
                         places: base.places.merging([station.id: station]) { first, _ in first },
                         practical: base.practical, sources: base.sources)
    }

    private func filtered(_ findings: [ResearchFinding], mode: TravelMode? = nil) throws -> TripFacts {
        let setting = try setting()
        let facts = try travelling(withResearch(setting.base, findings), mode: mode)
        return ResearchFactFilter.filtered(facts, findings: findings, draft: setting.draft)
    }

    private func isKept(_ finding: ResearchFinding, mode: TravelMode? = nil) throws -> Bool {
        try texts(filtered([finding], mode: mode)).contains(ResearchFactFilter.factText(for: finding))
    }

    private func texts(_ facts: TripFacts) -> [String] {
        facts.practical.map(\.text)
    }

    // Changed: this test used to keep any transport warning on the trip dates. A warning now has to name the arrival
    // place, the stay or a visited place, so this one names the arrival station.
    @Test func keepsATransportWarningThatNamesTheArrivalStation() throws {
        let warning = finding("f1", kind: .transport, title: "Engineering works",
                              summary: "Trains to \(Self.stationName) run late.", placeName: nil)
        #expect(try isKept(warning, mode: .train))
    }

    @Test func keepsATransportWarningThatNamesTheArrivalStationWithoutItsKindOfPlace() throws {
        let warning = finding("f1", kind: .transport, title: "Engineering works",
                              summary: "Trains into Riverside run late.", placeName: nil)
        #expect(try isKept(warning, mode: .train))
    }

    @Test func keepsAClosureThatNamesTheStay() throws {
        let setting = try setting()
        let stayId = try #require(setting.base.stay.placeId)
        let stayName = try #require(setting.base.places[stayId]?.name)
        let closure = finding("f1", kind: .closure, title: "Lift closed", summary: "The lift at \(stayName) is shut.",
                              placeName: nil)
        #expect(try isKept(closure))
    }

    @Test func keepsAClosureThatNamesAVisitedPlace() throws {
        let visited = try setting().visitedName
        let closure = finding("f1", kind: .closure, title: "Closed for repairs",
                              summary: "\(visited) is shut for repairs.", placeName: nil)
        #expect(try isKept(closure, mode: .train))
    }

    @Test func dropsATransportWarningThatNamesNoPlaceThatMatters() throws {
        let warning = finding("f1", kind: .transport, title: "Rail replacement buses on the Hillford route",
                              summary: "Replacement buses run between Northgate and Hillford on Sunday.",
                              placeName: nil)
        #expect(try !isKept(warning, mode: .train))
        #expect(try !isKept(warning))
    }

    @Test func keepsAHolidayWithoutAnyPlace() throws {
        let holiday = finding("f1", kind: .holiday, title: "Bank holiday", summary: "Shops keep shorter hours.",
                              placeName: nil)
        #expect(try isKept(holiday, mode: .train))
        #expect(try isKept(holiday))
    }

    /// The kinds of finding a real review of a trip by train on foot showed as noise, with the places made up.
    private struct Noise {
        let title: String
        let summary: String
        let kind: FindingKind
    }

    private static let noisyFindings: [Noise] = [
        Noise(title: "Riverside Bridge traffic restriction",
              summary: "The section nearest Market Street is closed to road traffic except cycles.", kind: .closure),
        Noise(title: "Mill Lane closure",
              summary: "The council lists a road closure between High Road and Chapel Steps.", kind: .closure),
        Noise(title: "Overnight citybound closure at Mill Terrace",
              summary: "Manhole repairs close Mill Terrace to citybound traffic overnight.", kind: .transport),
        Noise(title: "Rail replacement buses on the Hillford route",
              summary: "Replacement buses run between Northgate and Hillford during engineering works.",
              kind: .transport)
    ]

    @Test(arguments: noisyFindings.indices)
    func dropsRoadAndRouteNoiseOnATrainTrip(index: Int) throws {
        let example = Self.noisyFindings[index]
        let noise = finding("f1", kind: example.kind, title: example.title, summary: example.summary,
                            placeName: nil)
        #expect(try !isKept(noise, mode: .train))
    }

    private func millLaneClosure() -> ResearchFinding {
        finding("f1", kind: .closure, title: "Mill Lane closure",
                summary: "The council lists a road closure between High Road and Chapel Steps.", placeName: nil)
    }

    @Test(arguments: [TravelMode.car, .coach])
    func keepsARoadClosureWhenDrivingOrByCoach(mode: TravelMode) throws {
        #expect(try isKept(millLaneClosure(), mode: mode))
    }

    @Test(arguments: [TravelMode.train, .flight])
    func dropsARoadClosureWhenNotDrivingOrByCoach(mode: TravelMode) throws {
        #expect(try !isKept(millLaneClosure(), mode: mode))
    }

    @Test func keepsARoadClosureWhenNoTravelIsRecorded() throws {
        #expect(try isKept(millLaneClosure()))
    }

    @Test func decidesARoadFindingBeforeLookingForTheArrivalStation() throws {
        let restriction = finding("f1", kind: .closure, title: "Riverside Bridge traffic restriction",
                                  summary: "Closed to road traffic except cycles.", placeName: nil)
        #expect(try !isKept(restriction, mode: .train))
    }

    @Test(arguments: ["Road closure on Mill Lane.", "Closed to traffic on Sunday.", "Closed to road traffic.",
                      "Citybound lane shut overnight.", "Outbound buses diverted.", "A diversion is in place.",
                      "Lane closure on the bridge.", "Manhole repairs.", "Roadworks near the square."])
    func roadTrafficWordingIsRecognised(text: String) {
        #expect(ResearchFactFilter.readsAsRoadTraffic(text))
    }

    @Test(arguments: ["Replacement buses run on Sunday.", "Trains are cancelled after 20:00.",
                      "The station closes at midnight.",
                      "Outbound trains are diverted via the coast line.", "Rail traffic is light on Sunday."])
    func otherTransportWordingIsNotRoadTraffic(text: String) {
        #expect(!ResearchFactFilter.readsAsRoadTraffic(text))
    }

    @Test func keepsAnEventAtAVisitedPlace() throws {
        let visited = try setting().visitedName
        let event = finding("f1", placeName: visited)
        #expect(texts(try filtered([event])).contains(ResearchFactFilter.factText(for: event)))
    }

    @Test func keepsAnEventWhoseTitleNamesAVisitedPlaceWhenThePlaceNameIsEmpty() throws {
        let visited = try setting().visitedName
        let event = finding("f1", title: "Stalls at \(visited)", placeName: "  ")
        #expect(texts(try filtered([event])).contains(ResearchFactFilter.factText(for: event)))
    }

    @Test func dropsAnEventAtAPlaceThePlanDoesNotVisit() throws {
        let event = finding("f1", placeName: "Quayside Pop-up Hall")
        #expect(!texts(try filtered([event])).contains(ResearchFactFilter.factText(for: event)))
    }

    @Test func dropsAFindingOffTheTripDates() throws {
        let visited = try setting().visitedName
        let event = finding("f1", kind: .market, placeName: visited, onTripDates: false)
        let result = try filtered([event])
        #expect(!texts(result).contains(ResearchFactFilter.factText(for: event)))
        #expect(!result.sources.contains { $0.id == "taba-research-0" })
    }

    @Test func dropsAFactThatInstructsThePlanner() throws {
        let visited = try setting().visitedName
        let instruction = finding("f1", summary: "Do not schedule the stalls for 14 November.", placeName: visited)
        #expect(!texts(try filtered([instruction])).contains(ResearchFactFilter.factText(for: instruction)))
    }

    @Test func alwaysKeepsFactsThatDidNotComeFromResearch() throws {
        let result = try filtered([])
        #expect(texts(result) == ["Bring a layer.", "Do not schedule the walk."])
        #expect(result.sources.map(\.id) == ["taba-assumptions"])
    }

    @Test(arguments: ["Do not schedule the stalls for 14 November.", "Good for the traveller's afternoon.",
                      "Add it to the itinerary.", "An outlying alternative, not a walking stop.",
                      "Don't include it in the day.", "Don\u{2019}t plan a visit on Monday.",
                      "Avoid scheduling it after dark."])
    func plannerInstructionsAreRecognised(text: String) {
        #expect(ResearchFactFilter.readsAsInstruction(text))
    }

    @Test(arguments: ["Stalls open 10:00 to 16:00 on Sundays.", "Engineering works close the platform on Saturday.",
                      "Tickets cost five pounds and need booking.", "The Christmas stalls are scheduled for Saturday.",
                      "Scheduled engineering works close the platform."])
    func factsForTheTravellerAreKept(text: String) {
        #expect(!ResearchFactFilter.readsAsInstruction(text))
    }
}
