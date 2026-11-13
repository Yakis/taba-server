import GuideKit
import Testing

/// Words about somewhere to sleep, and about checking in or out, in the guide's prose.
struct StayTalkTests {
    @Test(arguments: [
        "The hotel is on the high street.",
        "Hotels line the square.",
        "Find accommodation near the station.",
        "Try a B&B on the hill.",
        "Try a B & B on the hill.",
        "A guest house by the river.",
        "Book an Airbnb for the night.",
        "Rest at the stay before dinner.",
        "Ask where you're staying tonight.",
        "Ask where you’re staying tonight.",
        "A hostel near the quay.",
        "Walk back to your room.",
        "Confirm the bed and breakfast."
    ])
    func accommodationWordsAreFound(text: String) {
        #expect(StayTalk.accommodation(in: text) != nil)
    }

    @Test(arguments: [
        "Check-in is at 15:00.",
        "Check in at the desk.",
        "Please check in early.",
        "Checking in takes a minute.",
        "Your checkout is at noon.",
        "Check-out is at 11:00.",
        "Check out of the flat by ten.",
        "Checking out of the flat by ten."
    ])
    func checkInAndCheckOutWordsAreFound(text: String) {
        #expect(StayTalk.checkInOrOut(in: text) != nil)
    }

    @Test(arguments: [
        "Check out the market.",
        "Your stay in Leeds is short.",
        "A flight of steps leads up.",
        "Check the platform on the day.",
        "Check in for your flight two hours ahead.",
        "Online check-in opens the day before.",
        "The check-in desk is on the left."
    ])
    func ordinaryWordsAreNotFound(text: String) {
        #expect(StayTalk.accommodation(in: text) == nil)
        #expect(StayTalk.checkInOrOut(in: text) == nil)
    }

    @Test func aPlaceNameWithHotelInItIsIgnoredWhenGiven() {
        let text = "Lunch at The Queens Hotel."
        #expect(StayTalk.accommodation(in: text, ignoring: ["The Queens Hotel"]) == nil)
    }

    @Test func aPlaceNameWithHotelInItIsFoundWhenNotGiven() {
        #expect(StayTalk.accommodation(in: "Lunch at The Queens Hotel.") == "Hotel")
    }

    @Test func theMatchedWordsAreReturned() {
        #expect(StayTalk.accommodation(in: "Book an Airbnb for the night.") == "Airbnb")
        #expect(StayTalk.checkInOrOut(in: "Check-out is at 11:00.") == "Check-out")
    }
}
