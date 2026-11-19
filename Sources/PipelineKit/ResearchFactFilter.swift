import Foundation
import GuideKit
import SourcesKit

/// Decides which research findings become "Good to know" facts in the finished guide. The planner and the writer see
/// every finding. Only the guide's own practical facts are filtered, when the guide is assembled.
///
/// A research fact is kept only when its finding happens on the trip dates and its fact reads as a fact for the
/// traveller. Then:
/// - a holiday is always kept;
/// - a transport or closure finding about road traffic (a road closure, a diversion, citybound or outbound traffic) is
///   kept only when the traveller drives or takes a coach, or when no way of travelling is recorded;
/// - any other transport or closure finding is kept only when it names the place where the traveller arrives, the
///   stay, or a place that a non-travel stop visits. It is dropped when it names none of them;
/// - any other kind of finding is kept only when it names a place that a non-travel stop visits.
///
/// Facts that did not come from research are always kept.
enum ResearchFactFilter {
    /// Phrases that address the planner rather than the traveller, matched case-insensitively. A research summary such
    /// as "Do not schedule the stalls for 14 November" is an instruction, not a fact. A fact that a closure is
    /// "scheduled" is kept: only telling someone not to schedule is an instruction. The apostrophe may be typographic.
    static let plannerInstructionPatterns: [String] = [
        #"\b(?:avoid|not) schedul"#, #"\bthe travell?er"#, #"\bitinerar"#, #"\bwalking stop\b"#,
        #"\bdo not (plan|include|visit|schedule)\b"#, #"\bdon['’]t (plan|include|schedule)\b"#
    ]

    /// Wording that is about vehicles on roads, matched case-insensitively on a finding's title and summary. Such a
    /// finding matters to someone who drives or takes a coach, and to nobody who walks.
    static let roadTrafficPatterns: [String] = [
        #"\broad closure"#, #"\bclosed to (road )?traffic"#, #"\btraffic\b"#, #"\bcitybound\b"#,
        #"\boutbound\b"#, #"\bdiversion"#, #"\blane closure"#, #"\bmanhole"#, #"\broadworks"#
    ]

    /// The text of the "Good to know" fact a finding becomes. The pipeline and the filter both use it, so they match.
    static func factText(for finding: ResearchFinding) -> String {
        "\(finding.title): \(finding.summary)"
    }

    /// The guide's facts with the research facts that do not belong in it removed. A source that only a removed fact
    /// cited is removed too. The draft's non-travel stops decide which places count as visited.
    static func filtered(_ facts: TripFacts, findings: [ResearchFinding], draft: PlanDraft) -> TripFacts {
        let visited = visitedNames(draft, facts: facts)
        let cityName = facts.trip.destination.name
        let travelMode = facts.trip.travel?.mode
        let anchors = anchorNames(facts)
        var practical: [Fact] = []
        var removedSources: Set<String> = []
        for fact in facts.practical {
            if let finding = finding(for: fact, facts: facts, findings: findings),
               !keeps(finding, text: fact.text, visitedNames: visited, cityName: cityName,
                      travelMode: travelMode, anchorNames: anchors) {
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
    /// `travelMode` is how the traveller gets there, nil when not recorded. `anchorNames` are the names of the place
    /// where the traveller arrives and of the stay, for those that are known.
    static func keeps(_ finding: ResearchFinding, text: String, visitedNames: [String], cityName: String?,
                      travelMode: TravelMode? = nil, anchorNames: [String] = []) -> Bool {
        guard finding.onTripDates, !readsAsInstruction(text) else { return false }
        let named = finding.placeName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? finding.title
        let namesVisited = visitedNames.contains { namesPlace(named, placeName: $0, cityName: cityName) }
        switch finding.kind {
        case .holiday:
            return true
        case .transport, .closure:
            if readsAsRoadTraffic(text) { return travelMode.map { $0 == .car || $0 == .coach } ?? true }
            if namesVisited || visitedNames.contains(where: { namesPlace(text, placeName: $0, cityName: cityName) }) {
                return true
            }
            return anchorNames.contains { namesAnchor(text, anchorName: $0, cityName: cityName) }
        default:
            return namesVisited
        }
    }

    /// Whether a fact's wording is an instruction to the planner, by the patterns in `plannerInstructionPatterns`.
    static func readsAsInstruction(_ text: String) -> Bool {
        matchesAny(plannerInstructionPatterns, text)
    }

    /// Whether a finding's wording is about vehicles on roads, by the patterns in `roadTrafficPatterns`.
    /// Rail and tram wording wins, so "outbound trains" or "rail traffic" is never road news.
    static func readsAsRoadTraffic(_ text: String) -> Bool {
        !matchesAny(railPatterns, text) && matchesAny(roadTrafficPatterns, text)
    }

    /// Words that make a transport finding about rail or trams rather than roads.
    static let railPatterns: [String] = [#"\b(trains?|rail|railway|tram|trams|platforms?|line)\b"#]

    /// The names of the places that non-travel stops visit, in plan order.
    static func visitedNames(_ draft: PlanDraft, facts: TripFacts) -> [String] {
        draft.days.flatMap(\.stops).filter { $0.kind != .travel }.compactMap { stop in
            stop.placeId.flatMap { facts.places[$0]?.name }
        }
    }

    /// The names of the place where the traveller arrives and of the stay, for those the facts know.
    static func anchorNames(_ facts: TripFacts) -> [String] {
        [facts.trip.travel?.arrivalPlaceId, facts.stay.placeId].compactMap { id in
            id.flatMap { facts.places[$0]?.name }
        }
    }

    private static func matchesAny(_ patterns: [String], _ text: String) -> Bool {
        patterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
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

    /// True when the text names the arrival place or the stay. Words that only say what kind of place it is
    /// ("station", "hotel") may be missing, so "Riverside Station" is named by a text about "Riverside" trains. A name
    /// made only of such words must match in full.
    private static func namesAnchor(_ text: String, anchorName: String, cityName: String?) -> Bool {
        let all = NameTokens.significant(anchorName, cityName: cityName)
        let distinctive = all.filter { !NameTokens.placeTypeWords.contains($0) && $0 != "hotel" }
        let wanted = distinctive.isEmpty ? all : distinctive
        let found = Set(NameTokens.significant(text, cityName: cityName))
        return !wanted.isEmpty && wanted.allSatisfy(found.contains)
    }
}
