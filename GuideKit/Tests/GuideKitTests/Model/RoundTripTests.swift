import Foundation
import GuideKit
import Testing

struct RoundTripTests {
    @Test func guideRoundTrips() throws {
        let guide = SampleGuide.make()
        let decoded = try roundTrip(guide)
        #expect(decoded == guide)
    }

    @Test(arguments: SampleGuide.placeIds)
    func placeRoundTrips(placeId: String) throws {
        let place = try #require(SampleGuide.samplePlaces()[placeId])
        let decoded = try roundTrip(place)
        #expect(decoded == place)
    }

    @Test(arguments: 0..<3)
    func stopRoundTrips(index: Int) throws {
        let stop = SampleGuide.stops()[index]
        let decoded = try roundTrip(stop)
        #expect(decoded == stop)
    }

    @Test func dayWithWeatherRoundTrips() throws {
        let plain = SampleGuide.day()
        let outlook = DayOutlook(
            summary: "Rain likely",
            highCelsius: 8,
            lowCelsius: 3,
            rainChance: 70,
            isForecast: false
        )
        let day = Day(date: plain.date, copy: plain.copy, stops: plain.stops, weather: outlook)
        #expect(try roundTrip(day) == day)
        let json = try encodedJSON(day)
        #expect(json.contains("\"weather\""))
        #expect(json.contains("\"rainChance\" : 70"))
    }

    @Test func placeWithWebsiteAndPhoneRoundTrips() throws {
        let plain = try #require(SampleGuide.samplePlaces().values.first)
        let place = Place(
            id: plain.id,
            name: plain.name,
            kind: plain.kind,
            location: plain.location,
            hours: plain.hours,
            priceLevel: plain.priceLevel,
            booking: plain.booking,
            indoor: plain.indoor,
            images: plain.images,
            facts: plain.facts,
            copy: plain.copy,
            website: "https://example.com/",
            phone: "+44 131 496 0000"
        )
        #expect(try roundTrip(place) == place)
        let json = try encodedJSON(place)
        #expect(json.contains("\"website\" : \"https://example.com/\""))
        #expect(json.contains("\"phone\" : \"+44 131 496 0000\""))
    }

    @Test func placeWithoutWebsiteOrPhoneOmitsTheKeys() throws {
        let place = try #require(SampleGuide.samplePlaces().values.first)
        let json = try encodedJSON(place)
        #expect(!json.contains("\"website\""))
        #expect(!json.contains("\"phone\""))
    }

    @Test func dayWithoutWeatherOmitsTheKey() throws {
        let day = SampleGuide.day()
        #expect(day.weather == nil)
        #expect(try roundTrip(day) == day)
        #expect(!(try encodedJSON(day)).contains("\"weather\""))
    }

    @Test func weatherOutlookOmitsUnknownNumbers() throws {
        let outlook = DayOutlook(
            summary: "Dry",
            highCelsius: nil,
            lowCelsius: nil,
            rainChance: nil,
            isForecast: true
        )
        #expect(try roundTrip(outlook) == outlook)
        let json = try encodedJSON(outlook)
        #expect(!json.contains("highCelsius"))
        #expect(!json.contains("lowCelsius"))
        #expect(!json.contains("rainChance"))
    }

    @Test func bookingRoundTrips() throws {
        let booking = SampleGuide.trainBooking()
        let decoded = try roundTrip(booking)
        #expect(decoded == booking)
    }

    @Test func planDraftRoundTrips() throws {
        let draft = SampleGuide.planDraft()
        let decoded = try roundTrip(draft)
        #expect(decoded == draft)
    }

    @Test func missingOptionalsAreOmittedFromJSON() throws {
        let stop = try #require(SampleGuide.stops().last)
        let json = try encodedJSON(stop)
        #expect(!json.contains("\"placeId\""))
        #expect(!json.contains("\"mealSlot\""))
        #expect(!json.contains("\"alternative\""))
        #expect(!json.contains("\"legFromPrevious\""))
    }

    @Test func encodingIsStable() throws {
        let guide = SampleGuide.make()
        let first = try encodedJSON(guide)
        let decoded = try roundTrip(guide)
        let second = try encodedJSON(decoded)
        #expect(first == second)
    }
}
