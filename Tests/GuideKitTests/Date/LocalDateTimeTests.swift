import GuideKit
import Testing

struct LocalDateTimeTests {
    @Test(arguments: ["2026-11-22T13:15", "2026-11-22T00:00"])
    func parsesValidValues(text: String) throws {
        #expect(try #require(LocalDateTime(text)).description == text)
    }

    @Test(arguments: [
        "2026-11-22 13:15", "2026-11-22t13:15", "2026-11-22T24:00", "2026-02-30T10:00",
        "2026-11-22T13:15:00", "2026-11-22", "13:15"
    ])
    func rejectsInvalidValues(text: String) {
        #expect(LocalDateTime(text) == nil)
    }

    @Test func ordersByDateThenTime() throws {
        let first = try #require(LocalDateTime("2026-11-22T23:00"))
        let second = try #require(LocalDateTime("2026-11-23T00:00"))
        let third = try #require(LocalDateTime("2026-11-23T09:30"))
        #expect(first < second)
        #expect(second < third)
        #expect(!(third < first))
    }

    @Test func roundTripsAsPlainString() throws {
        let value = try #require(LocalDateTime("2026-11-22T13:15"))
        #expect(try roundTrip([value]) == [value])
    }
}
