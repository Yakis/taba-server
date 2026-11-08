import Foundation
import GuideKit
import PipelineKit
import Testing

struct CopyCheckerTests {
    private let checker = CopyChecker()
    private let date = LocalDate("2025-11-23")!

    private var expected: Set<CopyTarget> { [.day(date), .stop("s"), .place("p"), .list(.eat)] }

    private func copy(_ edit: (inout [String: Any]) -> Void = { _ in }) throws -> GuideCopy {
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
        edit(&object)
        return try JSONDecoder().decode(GuideCopy.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func replacing(_ object: inout [String: Any], group: String, field: String, value: String) {
        if var item = object[group] as? [String: Any] {
            item[field] = value
            object[group] = item
        } else if var items = object[group] as? [[String: Any]] {
            items[0][field] = value
            object[group] = items
        }
    }

    @Test func validCopyPasses() throws {
        #expect(checker.check(try copy(), expected: expected, input: "{}").isEmpty)
    }

    @Test func idsMissingDuplicateAndExtraForEveryKind() throws {
        let original = try copy()
        let otherDate = try #require(LocalDate("2025-11-24"))
        let altered = GuideCopy(hero: original.hero,
            days: [original.days[0], original.days[0], .init(date: otherDate, title: "Day", summary: "Walk.")],
            stops: [original.stops[0], original.stops[0],
                    .init(id: "other", title: "Stop", body: "Walk.", actionLabel: nil)],
            places: [original.places[0], original.places[0], .init(id: "other", tag: "Tag", blurb: "Walk.")],
            lists: [original.lists[0], original.lists[0], .init(key: .drink, title: "Drink", caption: "Walk.")],
            tasting: original.tasting, notes: original.notes)
        let missing: Set<CopyTarget> = [.day(otherDate), .stop("missing"), .place("missing"), .list(.photos)]
        let targets = expected.union(missing).subtracting([.day(otherDate)])
        let issues = checker.check(altered, expected: targets, input: "{}")
        #expect(issues.filter { if case .duplicateID = $0.kind { true } else { false } }.count == 4)
        #expect(issues.filter { if case .extraID = $0.kind { true } else { false } }.count == 4)
        // A separate check exercises a missing day as well.
        let absent = checker.check(original, expected: expected.union(missing), input: "{}")
        #expect(absent.filter { if case .missingID = $0.kind { true } else { false } }.count == 4)
    }

    @Test(arguments: ["hidden gem", "must-see", "must-visit", "bustling", "nestled", "vibrant", "breathtaking",
                      "boasts", "unforgettable", "immerse yourself", "a feast for the senses", "something for everyone",
                      "look no further", "WHETHER YOU’RE eating OR walking", "iconic"])
    func bannedPhrases(_ phrase: String) throws {
        let value = try copy { replacing(&$0, group: "notes", field: "rules", value: phrase) }
        #expect(checker.check(value, expected: expected, input: "{}").contains {
            if case .bannedPhrase = $0.kind { $0.path == "notes.rules" } else { false }
        })
    }

    @Test func iconicMustComeFromFactsAndHeartIsGlobal() throws {
        let value = try copy {
            replacing(&$0, group: "notes", field: "rules", value: "Iconic and in the heart of town.")
            replacing(&$0, group: "notes", field: "light", value: "In the heart of town.")
        }
        let noFact = checker.check(value, expected: expected, input: #"{"voice":"iconic"}"#)
        #expect(noFact.contains { $0.kind == .bannedPhrase("iconic") })
        let fact = checker.check(value, expected: expected, input: #"{"places":[{"facts":["An iconic building"]}]}"#)
        #expect(fact.contains { $0.kind == .bannedPhrase("iconic") } == false)
        #expect(fact.filter { $0.kind == .bannedPhrase("in the heart of") }.count == 1)
    }

    @Test func emojiAndExclamationAcrossFields() throws {
        let value = try copy {
            replacing(&$0, group: "hero", field: "tagline", value: "Walk 123!")
            replacing(&$0, group: "notes", field: "rules", value: "Enjoy! 👋")
        }
        let issues = checker.check(value, expected: expected, input: #"{"n":123}"#)
        #expect(issues.filter { $0.kind == .emoji }.map(\.path) == ["notes.rules"])
        #expect(issues.filter { $0.kind == .exclamationLimit }.map(\.path) == ["notes.rules"])
    }

    @Test(arguments: [("hero", "title", 5), ("hero", "subtitle", 18), ("hero", "tagline", 8),
                      ("days", "title", 6), ("days", "summary", 25), ("stops", "title", 7),
                      ("stops", "body", 55), ("stops", "actionLabel", 5), ("places", "tag", 3),
                      ("places", "blurb", 25), ("lists", "title", 4), ("lists", "caption", 15),
                      ("tasting", "note", 18)])
    func wordLimits(group: String, field: String, limit: Int) throws {
        let tooLong = Array(repeating: "word", count: limit + 1).joined(separator: " ")
        let value = try copy { replacing(&$0, group: group, field: field, value: tooLong) }
        let issues = checker.check(value, expected: expected, input: "{}")
        #expect(issues.contains { if case .wordLimit(_, let max) = $0.kind { max == limit } else { false } })
    }

    @Test func minimumTitleTastingAndSentenceLimits() throws {
        let value = try copy {
            replacing(&$0, group: "hero", field: "title", value: "Alone")
            replacing(&$0, group: "hero", field: "subtitle", value: "First. Second.")
            replacing(&$0, group: "stops", field: "body", value: "One. Two. Three. Four.")
            replacing(&$0, group: "notes", field: "weather", value: "")
            $0["tasting"] = []
        }
        let issues = checker.check(value, expected: expected, input: "{}")
        #expect(issues.contains { $0.path == "hero.title" && $0.kind == .wordLimit(min: 2, max: 5) })
        #expect(issues.contains { $0.path == "tasting" && $0.kind == .tastingCount })
        for path in ["hero.subtitle", "stops[0].body", "notes.weather"] {
            #expect(issues.contains { if case .sentenceLimit = $0.kind { $0.path == path } else { false } })
        }
    }

    @Test(arguments: [("hero", "subtitle"), ("days", "summary"), ("places", "blurb"),
                      ("lists", "caption"), ("tasting", "note"), ("notes", "weather"),
                      ("notes", "light"), ("notes", "backupPlan"), ("notes", "rules"), ("stops", "body")])
    func sentenceLimits(group: String, field: String) throws {
        let value = try copy { replacing(&$0, group: group, field: field, value: "Alpha. Beta. Gamma. Delta.") }
        let issues = checker.check(value, expected: expected, input: "{}")
        let path = ["hero", "notes"].contains(group) ? "\(group).\(field)" : "\(group)[0].\(field)"
        #expect(issues.contains { if case .sentenceLimit = $0.kind { $0.path == path } else { false } })
    }

    @Test(arguments: [
        (#"{"text":"10\nminutes"}"#, "Walk 10 minutes.", false),
        (#"{"1":"none","id":"d1-s1","sourceID":"1"}"#, "Walk 1 minute.", true),
        (#"{"walk":10}"#, "Walk ten minutes.", false),
        (#"{"name":"3 Bridges"}"#, "See 3 bridges.", false),
        (#"{"date":"2025-11-23"}"#, "Visit on 2025-11-23.", false),
        (#"{"date":"2025-11-23"}"#, "Visit on 2025-11-24.", true),
        (#"{"date":"2025-11-23"}"#, "Visit on 23.", true),
        (#"{"time":"16:00"}"#, "Visit at 16:00.", false),
        (#"{"time":"16:00"}"#, "Visit at 16:01.", true),
        (#"{"time":"16:00"}"#, "Visit at 16.", true),
        (#"{"price":"£1000"}"#, "Pay £1000.", false),
        (#"{"price":"£1000"}"#, "Pay £1001.", true),
        (#"{"amount":1000}"#, "Pay £1000.", true),
        (#"{"rate":"60%"}"#, "Expect 60%.", false),
        (#"{"rate":60}"#, "Expect 60%.", true),
        (#"{"rate":"60%"}"#, "Expect 60.", true),
        (#"{"floor":"21st"}"#, "Visit the 21st floor.", false),
        (#"{"floor":"21st"}"#, "Visit the 22nd floor.", true),
        (#"{"a":20,"b":1}"#, "Walk twenty one minutes.", true),
        (#"{"text":"one hundred and one"}"#, "Walk one hundred and one minutes.", false),
        (#"{"a":20,"b":1}"#, "Walk twenty-one minutes.", true),
        (#"{"text":"twenty-one"}"#, "Walk twenty-one minutes.", false),
        (#"{"a":20,"b":1}"#, "Visit the twenty-first stop.", true),
        (#"{"text":"twenty-first"}"#, "Visit the twenty-first stop.", false),
        (#"{"n":21}"#, "Walk twenty-one minutes.", true),
        (#"{"n":10}"#, "It’s 10 minutes.", false),
        (#"{"n":10}"#, "It’s 11 minutes.", true),
        ("not JSON 10", "Walk 10 minutes.", true)
    ])
    func numericTokenContract(input: String, text: String, flagged: Bool) throws {
        let value = try copy { replacing(&$0, group: "stops", field: "body", value: text) }
        let issues = checker.check(value, expected: expected, input: input)
        #expect(issues.contains { if case .ungroundedNumber = $0.kind { true } else { false } } == flagged)
    }

    @Test(arguments: [("hidden\n gem", "hidden gem"), ("must–see", "must-see"),
                      ("must—visit", "must-visit"), ("whether you’re walking or eating", "whether you're … or …")])
    func normalizedBannedPhrases(text: String, phrase: String) throws {
        let value = try copy { replacing(&$0, group: "notes", field: "rules", value: text) }
        let issues = checker.check(value, expected: expected, input: "{}")
        #expect(issues.contains { $0.kind == .bannedPhrase(phrase) && $0.text == text })
    }

    @Test(arguments: [
        (#"{"facts":[{"sourceID":"iconic"}]}"#, false),
        (#"{"facts":[{"text":"Not iconic."}]}"#, false),
        (#"{"facts":[{"statement":"An iconic building."}]}"#, true),
        (#"{"facts":[{"text":"An iconic building."}]}"#, true)
    ])
    func iconicRequiresFactText(input: String, allowed: Bool) throws {
        let value = try copy { replacing(&$0, group: "notes", field: "rules", value: "An iconic building.") }
        let issues = checker.check(value, expected: expected, input: input)
        #expect(issues.contains { $0.kind == .bannedPhrase("iconic") } == !allowed)
    }

    @Test func keycapEmojiIsDetected() throws {
        let value = try copy { replacing(&$0, group: "notes", field: "rules", value: "Number 1️⃣.") }
        #expect(checker.check(value, expected: expected, input: #"{"n":1}"#).contains { $0.kind == .emoji })
    }

    @Test func numericalClaimsAreCheckedAgainstActualInput() throws {
        let value = try copy {
            let text = "Walk ten minutes at 16:00 on 2025-11-23. Pay £12.50 or 99."
            replacing(&$0, group: "stops", field: "body", value: text)
        }
        let input = #"{"walk":10,"time":"16:00","date":"2025-11-23","price":"£12.50"}"#
        let issues = checker.check(value, expected: expected, input: input)
        let claims = issues.compactMap { issue -> String? in
            if case .ungroundedNumber(let claim) = issue.kind { return claim }
            return nil
        }
        #expect(claims == ["99"])
        #expect(issues.contains {
            $0.kind == .ungroundedNumber("99") && $0.path == "stops[0].body" && $0.text == "Pay £12.50 or 99."
        })
        let otherInput = #"{"walk":100,"time":"16:01","date":"2025-11-24","price":"£12.00"}"#
        let absent = checker.check(value, expected: expected, input: otherInput)
        #expect(absent.filter { if case .ungroundedNumber = $0.kind { true } else { false } }.count == 5)
    }
}
