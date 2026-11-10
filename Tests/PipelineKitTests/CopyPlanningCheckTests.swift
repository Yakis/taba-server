import Foundation
import GuideKit
import PipelineKit
import Testing

/// The card and plan checks: opening hours, walks, plan talk and transport words. Sits beside `CopyCheckerTests`, with
/// its own copy builder.
struct CopyPlanningCheckTests {
    private let checker = CopyChecker()
    private let date = LocalDate("2025-11-23")!

    private var expected: Set<CopyTarget> { [.day(date), .stop("s"), .place("p"), .list(.eat)] }

    /// A valid copy with `text` in one field. `group` is `days`, `stops`, `places`, or a single object such as `notes`.
    private func copy(_ text: String, group: String, field: String) throws -> GuideCopy {
        var object: [String: Any] = [
            "hero": ["title": "City walks", "subtitle": "A gentle wander.", "tagline": "Take it easy"],
            "days": [["date": "2025-11-23", "title": "Market day", "summary": "Visit the market."]],
            "stops": [["id": "s", "title": "Market", "body": "Visit the stalls.", "actionLabel": "Walk there"]],
            "places": [["id": "p", "tag": "Good food", "blurb": "Explore the market."]],
            "lists": [["key": "eat", "title": "Food", "caption": "Find a meal."]],
            "tasting": Array(repeating: ["name": "Oats", "note": "A warming dish."], count: 6),
            "notes": ["weather": "Bring a layer.", "light": "Enjoy the light.",
                      "backupPlan": "Take shelter.", "rules": "Take your time."]
        ]
        if var item = object[group] as? [String: Any] {
            item[field] = text
            object[group] = item
        } else if var items = object[group] as? [[String: Any]] {
            items[0][field] = text
            object[group] = items
        }
        return try JSONDecoder().decode(GuideCopy.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// Only the four card and plan kinds, so other copy problems do not matter here.
    private func planningIssues(_ text: String, group: String = "stops", field: String = "body",
                                input: String = "{}") throws -> [CopyCheckIssue] {
        checker.check(try copy(text, group: group, field: field), expected: expected, input: input).filter { issue in
            switch issue.kind {
            case .hoursInBody, .walkInBody, .planTalk, .inventedTransport: true
            default: false
            }
        }
    }

    @Test(arguments: [
        "It opens at 10:00.",
        "It closes at 18:00, so this is its slot.",
        "A Grassmarket pub that's open until 23:00.",
        "Check-in opens at 15:00.",
        "Start gently with breakfast at a café that opens at 09:00.",
        "It's Sunday-only and closes at 16:00, so lunch comes first.",
        "Opening hours and booking could not be confirmed, so check the website before you go.",
        "A pub known for folk music, open late on a Sunday.",
        "The market shuts at 4pm."
    ])
    func openingHoursInCardCopyAreFlagged(text: String) throws {
        let issues = try planningIssues(text)
        #expect(issues.contains { if case .hoursInBody = $0.kind { $0.path == "stops[0].body" } else { false } })
        #expect(issues.allSatisfy { $0.text == text })
    }

    @Test(arguments: [
        "There's a café two minutes from the flat.",
        "The market is 5 minutes' walk away.",
        "Keep a 10-minute walk in mind.",
        "A pub fifteen minutes away.",
        "Walk 5 minutes to the castle.",
        "Keep walking for about ten minutes.",
        "Walk for 50 minutes."
    ])
    func walkMinutesInCardCopyAreFlagged(text: String) throws {
        #expect(try planningIssues(text).contains { if case .walkInBody = $0.kind { true } else { false } })
    }

    @Test(arguments: [
        "Today's times are suggestions, not a stopwatch.",
        "Treat the times as suggestions, not appointments.",
        "Check out before the assumed 11:00 deadline.",
        "The 16:45 visit is provisional.",
        "Follow the plan from here.",
        "Your planner has the rest."
    ])
    func planTalkIsFlagged(text: String) throws {
        #expect(try planningIssues(text).contains { if case .planTalk = $0.kind { true } else { false } })
    }

    @Test(arguments: [
        "Sunset is at 15:53.",
        "Check out before 11:00.",
        "It's Sunday only.",
        "A market that runs one day a week.",
        "Stay 50 minutes, then walk on.",
        "Give it twenty minutes.",
        "Climb a flight of steps to the viewpoint.",
        "Bring a layer for the sunrise at 07:45 and the sunset at 15:53."
    ])
    func allowedCardCopyGivesNoPlanningIssue(text: String) throws {
        #expect(try planningIssues(text).isEmpty)
    }

    @Test(arguments: [
        "Slack before the run to the station.",
        "Allow time afterwards to reach the station.",
        "Wait on the platform.",
        "Your flight leaves from the airport."
    ])
    func transportWithoutAMatchingBookingIsFlagged(text: String) throws {
        let issues = try planningIssues(text, input: #"{"anchors":{"bookings":[{"kind":"stay"}]}}"#)
        #expect(issues.contains { if case .inventedTransport = $0.kind { true } else { false } })
    }

    @Test(arguments: [
        ("Take the train from the station.", #"{"anchors":{"bookings":[{"kind":"train"}]}}"#),
        ("Get the bus from the station.", #"{"anchors":{"bookings":[{"kind":"bus"}]}}"#),
        ("Your flight leaves from the airport.", #"{"anchors":{"bookings":[{"kind":"flight"}]}}"#),
        ("Walk to the station.", #"{"anchors":{"bookings":[{"kind":"train"}]}}"#)
    ])
    func transportWithAMatchingBookingIsAllowed(text: String, input: String) throws {
        #expect(try planningIssues(text, input: input).isEmpty)
    }

    @Test func planTalkAnywhereAndUnconfirmedHoursInNotes() throws {
        let talk = try planningIssues("Times are suggestions, so take them loosely.", group: "notes", field: "rules")
        #expect(talk.contains { if case .planTalk = $0.kind { $0.path == "notes.rules" } else { false } })
        // Notes may say that opening hours are unconfirmed: the card does not show that, so it is not a claim.
        let notice = try planningIssues("Some opening hours could not be confirmed, so take a look on the day.",
                                        group: "notes", field: "rules")
        #expect(notice.isEmpty)
    }

    @Test func issuesQuoteTheSentenceAndSayWhatToRemove() throws {
        let issue = try #require(planningIssues("It opens at 10:00.").first)
        #expect(issue.kind == .hoursInBody("opens at 10:00"))
        #expect(issue.message
            == "Remove the opening time from this sentence, since the card shows it: 'It opens at 10:00.'")
        let transport = try #require(planningIssues("Walk to the station.").first)
        #expect(transport.message.hasPrefix("Remove 'station' from this sentence"))
    }
}
