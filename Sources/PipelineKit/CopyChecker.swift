import Foundation
import GuideKit

/// A deterministic screening result. Paths use JSON array indices, so duplicates remain distinguishable.
public struct CopyCheckIssue: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case missingID(CopyTarget), duplicateID(CopyTarget), extraID(CopyTarget)
        case bannedPhrase(String), emoji, exclamationLimit, wordLimit(min: Int, max: Int)
        case sentenceLimit(min: Int, max: Int), tastingCount, ungroundedNumber(String)
        /// Facts the guide's cards already show, plan talk, and transport the trip does not have. The payload is the
        /// matching words.
        case hoursInBody(String), walkInBody(String), planTalk(String), inventedTransport(String)
        /// Words in the guide's text that contradict its facts, such as a hotel on a trip with no stay. The payload is
        /// the words. `note` says what the facts say instead.
        case stayContradiction(String)
    }
    public let kind: Kind
    public let path: String
    /// The affected text (or sentence for a numerical claim), suitable for review and retry.
    public let text: String?
    /// What the facts say instead, for issues whose kind does not carry a reason. Nil for the others.
    public let note: String?

    public init(kind: Kind, path: String, text: String? = nil, note: String? = nil) {
        self.kind = kind
        self.path = path
        self.text = text
        self.note = note
    }

    /// What the writer is told to do about this issue. Kinds without a plain instruction keep their case name.
    public var message: String {
        let sentence = text ?? ""
        switch kind {
        case .hoursInBody:
            return "Remove the opening time from this sentence, since the card shows it: '\(sentence)'"
        case .walkInBody:
            return "Remove the walking time from this sentence, since the card shows it: '\(sentence)'"
        case .planTalk(let phrase):
            return "Remove the plan talk ('\(phrase)') from this sentence, and write about the place: '\(sentence)'"
        case .inventedTransport(let word):
            return "Remove '\(word)' from this sentence, since the trip has no matching booking: '\(sentence)'"
        case .stayContradiction(let words):
            return "Remove '\(words)' from this text: \(note ?? "the facts say otherwise.") '\(sentence)'"
        default:
            return String(describing: kind)
        }
    }
}

/// Screens visible copy, not IDs. Numeric grounding compares lexical tokens in decoded JSON values,
/// excluding identifier fields. Dates, times, currencies, percentages and compound number words must
/// match as whole tokens, not fragments; equivalent shorter forms may be flagged. Simple English
/// cardinal words match digits. This is not semantic verification: matching input can still be
/// irrelevant, and unsupported formats or language may be missed. Flagged claims need human review.
public struct CopyChecker: Sendable {
    public init() {}

    // Collecting every schema field in one place keeps the checked surface auditable.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public func check(_ copy: GuideCopy, expected: Set<CopyTarget>, input: String) -> [CopyCheckIssue] {
        var issues: [CopyCheckIssue] = []
        var seen: Set<CopyTarget> = []
        func checkID(_ target: CopyTarget, _ path: String) {
            if !seen.insert(target).inserted {
                issues.append(.init(kind: .duplicateID(target), path: path))
            }
            if !expected.contains(target) {
                issues.append(.init(kind: .extraID(target), path: path))
            }
        }
        for (index, day) in copy.days.enumerated() { checkID(.day(day.date), "days[\(index)].date") }
        for (index, stop) in copy.stops.enumerated() { checkID(.stop(stop.id), "stops[\(index)].id") }
        for (index, place) in copy.places.enumerated() { checkID(.place(place.id), "places[\(index)].id") }
        for (index, list) in copy.lists.enumerated() { checkID(.list(list.key), "lists[\(index)].key") }
        // Sorting makes retry output stable even though expected is a set.
        for target in expected.subtracting(seen).sorted(by: { String(describing: $0) < String(describing: $1) }) {
            let path: String
            switch target {
            case .day: path = "days"
            case .stop: path = "stops"
            case .place: path = "places"
            case .list: path = "lists"
            }
            issues.append(.init(kind: .missingID(target), path: path))
        }

        var fields: [CopyField] = []
        func add(_ path: String, _ text: String, _ minWords: Int = 0, _ maxWords: Int = .max,
                 _ minSentences: Int = 0, _ maxSentences: Int = .max) {
            fields.append(.init(path: path, text: text, minWords: minWords, maxWords: maxWords,
                                minSentences: minSentences, maxSentences: maxSentences))
        }
        add("hero.title", copy.hero.title, 2, 5)
        add("hero.subtitle", copy.hero.subtitle, 0, 18, 1, 1)
        add("hero.tagline", copy.hero.tagline, 0, 8)
        for (index, day) in copy.days.enumerated() {
            add("days[\(index)].title", day.title, 0, 6)
            add("days[\(index)].summary", day.summary, 0, 25, 1, 1)
        }
        for (index, stop) in copy.stops.enumerated() {
            add("stops[\(index)].title", stop.title, 0, 7)
            add("stops[\(index)].body", stop.body, 0, 55, 1, 3)
            if let label = stop.actionLabel { add("stops[\(index)].actionLabel", label, 0, 5) }
        }
        for (index, place) in copy.places.enumerated() {
            add("places[\(index)].tag", place.tag, 0, 3)
            add("places[\(index)].blurb", place.blurb, 0, 25, 1, 1)
        }
        for (index, list) in copy.lists.enumerated() {
            add("lists[\(index)].title", list.title, 0, 4)
            add("lists[\(index)].caption", list.caption, 0, 15, 1, 1)
        }
        if !(6...8).contains(copy.tasting.count) { issues.append(.init(kind: .tastingCount, path: "tasting")) }
        for (index, item) in copy.tasting.enumerated() {
            add("tasting[\(index)].name", item.name)
            add("tasting[\(index)].note", item.note, 0, 18, 1, 1)
        }
        add("notes.weather", copy.notes.weather, 0, .max, 1, 2)
        add("notes.light", copy.notes.light, 0, .max, 1, 2)
        add("notes.backupPlan", copy.notes.backupPlan, 0, .max, 1, 2)
        add("notes.rules", copy.notes.rules, 0, .max, 1, 2)
        issues += CopyTextChecks.check(fields, input: input)
        return issues
    }
}

struct CopyField {
    let path: String
    let text: String
    let minWords: Int
    let maxWords: Int
    let minSentences: Int
    let maxSentences: Int
}
