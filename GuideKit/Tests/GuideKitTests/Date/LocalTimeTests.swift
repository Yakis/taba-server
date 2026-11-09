import GuideKit
import Testing

struct LocalTimeTests {
    @Test(arguments: ["00:00", "09:30", "13:15", "23:59"])
    func parsesValidTimes(text: String) throws {
        #expect(try #require(LocalTime(text)).description == text)
    }

    @Test(arguments: ["24:00", "23:60", "9:30", "09:3", "0930", "", "12:5a", "+1:00", "-1:00", "12:00:00"])
    func rejectsInvalidTimes(text: String) {
        #expect(LocalTime(text) == nil)
    }

    @Test func addsMinutes() throws {
        let start = try #require(LocalTime("13:15"))
        #expect(start.adding(minutes: 45) == LocalTime("14:00"))
        #expect(start.adding(minutes: 0) == start)
        #expect(start.adding(minutes: -15) == LocalTime("13:00"))
    }

    @Test func addingReturnsNilInsteadOfPassingMidnight() throws {
        let late = try #require(LocalTime("23:50"))
        #expect(late.adding(minutes: 9) == LocalTime("23:59"))
        #expect(late.adding(minutes: 10) == nil)
        let early = try #require(LocalTime("00:10"))
        #expect(early.adding(minutes: -10) == LocalTime("00:00"))
        #expect(early.adding(minutes: -11) == nil)
    }

    @Test func comparesByTimeOfDay() throws {
        let morning = try #require(LocalTime("09:00"))
        let afternoon = try #require(LocalTime("13:15"))
        #expect(morning < afternoon)
        #expect(!(afternoon < morning))
        #expect(afternoon.hour == 13)
        #expect(afternoon.minute == 15)
    }
}
