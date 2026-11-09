import GuideKit
import Testing

struct StructureTests {
    @Test func sampleGuideHasNoProblems() throws {
        let guide = SampleGuide.make()
        #expect(guide.structureProblems.isEmpty)
        try guide.validateStructure()
    }

    @Test func flagsPlaceKeyThatDoesNotMatchItsId() {
        var places = SampleGuide.samplePlaces()
        places[SampleGuide.cafeId] = SampleGuide.cafe(id: "manual:typo")
        let guide = SampleGuide.make(places: places)
        #expect(guide.structureProblems == [.placeKeyMismatch(key: SampleGuide.cafeId, placeId: "manual:typo")])
    }

    @Test func validateStructureThrowsEveryProblem() throws {
        var places = SampleGuide.samplePlaces()
        places[SampleGuide.cafeId] = SampleGuide.cafe(id: "manual:typo")
        let guide = SampleGuide.make(places: places)
        let error = try #require(throws: GuideStructureError.self) {
            try guide.validateStructure()
        }
        #expect(error.problems == [.placeKeyMismatch(key: SampleGuide.cafeId, placeId: "manual:typo")])
    }

    @Test func decoderAcceptsWhatValidationRejects() throws {
        var places = SampleGuide.samplePlaces()
        places[SampleGuide.cafeId] = SampleGuide.cafe(id: "manual:typo")
        let guide = SampleGuide.make(places: places)
        let decoded = try roundTrip(guide)
        #expect(decoded == guide)
        #expect(!decoded.structureProblems.isEmpty)
    }

    @Test func flagsTripThatEndsBeforeItStarts() {
        // The sample day (22 Nov) also falls outside a trip that runs 24 Nov back to 22 Nov.
        let guide = SampleGuide.make(trip: SampleGuide.trip(start: "2026-11-24", end: "2026-11-22"))
        #expect(guide.structureProblems.contains(.tripEndsBeforeStart))
    }

    @Test func flagsPriceLevelOutsideOneToFour() {
        var places = SampleGuide.samplePlaces()
        places[SampleGuide.hotelId] = SampleGuide.hotel(priceLevel: 7)
        let guide = SampleGuide.make(places: places)
        #expect(guide.structureProblems == [.priceLevelOutOfRange(placeId: SampleGuide.hotelId, level: 7)])
    }

    @Test func overnightOpeningIsNotAProblem() {
        // Open 08:00 and close 01:00 the next day is a valid overnight period.
        var places = SampleGuide.samplePlaces()
        places[SampleGuide.cafeId] = SampleGuide.cafe(closesAt: "01:00")
        let guide = SampleGuide.make(places: places)
        #expect(guide.structureProblems.isEmpty)
    }

    @Test func twentyFourHourOpeningIsNotAProblem() {
        // Open 08:00 and close 08:00 means open 24 hours.
        var places = SampleGuide.samplePlaces()
        places[SampleGuide.cafeId] = SampleGuide.cafe(closesAt: "08:00")
        let guide = SampleGuide.make(places: places)
        #expect(guide.structureProblems.isEmpty)
    }

    @Test(arguments: [0, -15])
    func flagsStopWithNonPositiveMinutes(minutes: Int) {
        let stop = SampleGuide.sightStop(id: "bad", minutes: minutes)
        let guide = SampleGuide.make(days: [SampleGuide.day(stops: [stop])])
        #expect(guide.structureProblems == [.stopMinutesNotPositive(stopId: "bad")])
    }

    @Test func flagsBookingThatArrivesBeforeItDeparts() {
        let booking = SampleGuide.trainBooking(departs: "2026-11-22T12:30", arrives: "2026-11-22T08:10")
        let guide = SampleGuide.make(bookings: [booking])
        #expect(guide.structureProblems == [.bookingArrivesBeforeDeparts(bookingId: "booking-train-out")])
    }
}
