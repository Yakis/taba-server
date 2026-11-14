import Foundation
import GuideKit
import SourcesKit

/// Decides which research findings become "Good to know" facts in the finished guide. The planner and the writer see
/// every finding. Only the guide's own practical facts are filtered, when the guide is assembled.
///
/// A research fact is kept when its finding happens on the trip dates, its fact reads as a fact for the traveller, and
/// either it is a general warning for the day (transport, closure or holiday) or it names a place that a non-travel
/// stop visits. Facts that did not come from research are always kept.
enum ResearchFactFilter {
    /// Phrases that address the planner rather than the traveller, matched case-insensitively. A research summary such
    /// as "Do not schedule the stalls for 14 November" is an instruction, not a fact. A fact that a closure is
    /// "scheduled" is kept: only telling someone not to schedule is an instruction. The apostrophe may be typographic.
    static let plannerInstructionPatterns: [String] = [
        #"\b(?:avoid|not) schedul"#, #"\bthe travell?er"#, #"\bitinerar"#, #"\bwalking stop\b"#,
        #"\bdo not (plan|include|visit|schedule)\b"#, #"\bdon['’]t (plan|include|schedule)\b"#
    ]

    /// Kinds of finding that are general warnings for the day, so they are kept without a place to visit.
    static let dayWarningKinds: Set<FindingKind> = [.transport, .closure, .holiday]

    /// The text of the "Good to know" fact a finding becomes. The pipeline and the filter both use it, so they match.
    static func factText(for finding: ResearchFinding) -> String {
        "\(finding.title): \(finding.summary)"
    }

    /// The guide's facts with the research facts that do not belong in it removed. A source that only a removed fact
    /// cited is removed too. The draft's non-travel stops decide which places count as visited.
    static func filtered(_ facts: TripFacts, findings: [ResearchFinding], draft: PlanDraft) -> TripFacts {
        let visited = visitedNames(draft, facts: facts)
        let cityName = facts.trip.destination.name
        var practical: [Fact] = []
        var removedSources: Set<String> = []
        for fact in facts.practical {
            if let finding = finding(for: fact, facts: facts, findings: findings),
               !keeps(finding, text: fact.text, visitedNames: visited, cityName: cityName) {
                removedSources.insert(fact.sourceId)
            } else {
                practical.append(fact)
            }
        }
        let cited = Set(practical.map(\.sourceId)).union(facts.places.values.flatMap { $0.facts.map(\.sourceId) })
        let sources = facts.sources.filter { !removedSources.contains($0.id) || cited.contains($0.id) }
        return TripFacts(trip: facts.trip, bookings: facts.bookings, stay: facts.stay, places: facts.places,
                         practical: practical, sources: sources)
    }

    /// Whether a research fact belongs in the guide. `visitedNames` are the names of the places the plan visits.
    static func keeps(_ finding: ResearchFinding, text: String, visitedNames: [String], cityName: String?) -> Bool {
        guard finding.onTripDates, !readsAsInstruction(text) else { return false }
        if dayWarningKinds.contains(finding.kind) { return true }
        let named = finding.placeName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? finding.title
        return visitedNames.contains { namesPlace(named, placeName: $0, cityName: cityName) }
    }

    /// Whether a fact's wording is an instruction to the planner, by the patterns in `plannerInstructionPatterns`.
    static func readsAsInstruction(_ text: String) -> Bool {
        plannerInstructionPatterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    /// The names of the places that non-travel stops visit, in plan order.
    static func visitedNames(_ draft: PlanDraft, facts: TripFacts) -> [String] {
        draft.days.flatMap(\.stops).filter { $0.kind != .travel }.compactMap { stop in
            stop.placeId.flatMap { facts.places[$0]?.name }
        }
    }

    /// The finding a practical fact came from, if any. A fact matches a finding by its text and by the URL of its
    /// source, so checkpoints and replays written before this filter match as well.
    private static func finding(for fact: Fact, facts: TripFacts, findings: [ResearchFinding]) -> ResearchFinding? {
        guard let url = facts.sources.first(where: { $0.id == fact.sourceId })?.url else { return nil }
        return findings.first { factText(for: $0) == fact.text && $0.url == url }
    }

    /// True when every significant word of the place's name appears in the text. City words are left out of both, so
    /// "Riverside Market" names a place in "Riverside market, Christmas stalls".
    private static func namesPlace(_ text: String, placeName: String, cityName: String?) -> Bool {
        let wanted = NameTokens.significant(placeName, cityName: cityName)
        let found = Set(NameTokens.significant(text, cityName: cityName))
        return !wanted.isEmpty && wanted.allSatisfy(found.contains)
    }
}
