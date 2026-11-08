import Foundation
import GuideKit
import Testing

struct LocalDateTests {
    @Test(arguments: ["2026-11-22", "2024-02-29", "0001-01-01", "9999-12-31"])
    func parsesValidDates(text: String) throws {
        let date = try #require(LocalDate(text))
        #expect(date.description == text)
    }

    @Test(arguments: [
        "2026-02-30", "2025-02-29", "2026-13-01", "2026-00-10", "2026-11-00",
        "2026-4-01", "26-11-22", "2026/11/22", "+026-11-22", "2026-11-22 ",
        " 2026-11-22", "2026-11-22T13:15", "", "0000-01-01"
    ])
    func rejectsInvalidDates(text: String) {
        #expect(LocalDate(text) == nil)
    }

    @Test func weekdayComesFromTheCalendar() throws {
        #expect(try #require(LocalDate("2026-11-22")).weekday == .sunday)
        #expect(try #require(LocalDate("2026-11-23")).weekday == .monday)
        #expect(try #require(LocalDate("2024-02-29")).weekday == .thursday)
    }

    @Test func addsAndSubtractsDays() throws {
        #expect(try #require(LocalDate("2026-02-27")).adding(days: 2) == LocalDate("2026-03-01"))
        #expect(try #require(LocalDate("2026-03-01")).adding(days: -1) == LocalDate("2026-02-28"))
        #expect(try #require(LocalDate("2024-02-28")).adding(days: 1) == LocalDate("2024-02-29"))
        #expect(try #require(LocalDate("2026-12-31")).adding(days: 1) == LocalDate("2027-01-01"))
        #expect(try #require(LocalDate("2026-11-22")).adding(days: 0) == LocalDate("2026-11-22"))
    }

    @Test func addingReturnsNilOutsideSupportedYears() throws {
        #expect(try #require(LocalDate("9999-12-31")).adding(days: 1) == nil)
    }

    @Test func comparesChronologically() throws {
        let earlier = try #require(LocalDate("2026-11-22"))
        let later = try #require(LocalDate("2026-11-23"))
        #expect(earlier < later)
        #expect(later > earlier)
    }

    @Test func roundTripsAsPlainString() throws {
        let date = try #require(LocalDate("2026-11-22"))
        let json = try encodedJSON([date])
        #expect(json.contains("\"2026-11-22\""))
        #expect(try roundTrip([date]) == [date])
    }

    @Test func decodingRejectsImpossibleDates() {
        #expect(throws: DecodingError.self) {
            _ = try GuideKit.jsonDecoder().decode(LocalDate.self, from: Data(#""2026-02-30""#.utf8))
        }
    }
}
