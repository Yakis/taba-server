import Foundation
import GuideKit

/// The accepted research and the provider-resolved places that may be added to the candidates.
public struct VerifiedResearch: Sendable {
    public let result: ResearchResult
    public let places: [Place]
}

/// Treat model output as untrusted: only reported web-search URLs and resolved places survive.
public enum ResearchVerification {
    public static func verify(
        _ research: ResearchResult,
        sourceURLs: [String],
        resolve: @Sendable (SuggestedPlace) async throws -> Place?
    ) async throws -> VerifiedResearch {
        let reported = Set(sourceURLs.filter(isWebURL))
        var seen: Set<String> = []
        let findings = research.findings.filter {
            !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && isWebURL($0.url) && reported.contains($0.url) && seen.insert($0.id).inserted
        }
        var suggestions: [SuggestedPlace] = []
        var places: [Place] = []
        var placeIDs: Set<String> = []
        for suggestion in research.suggestedPlaces {
            try Task.checkCancellation()
            if let place = try await resolve(suggestion),
               !place.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               placeIDs.insert(place.id).inserted {
                suggestions.append(suggestion)
                places.append(place)
            }
        }
        try Task.checkCancellation()
        return VerifiedResearch(result: ResearchResult(findings: findings, suggestedPlaces: suggestions,
                                                        searchNotes: research.searchNotes), places: places)
    }

    /// Suggested venues for dated events and markets on the trip dates, so the planner can schedule them even when
    /// research did not list the venue itself. Only findings whose source was among the reported search results count.
    /// Each venue is named by the finding's `placeName`, with `why` set to the finding's title. An event's venue is a
    /// landmark (public spaces are mapped to landmarks) and a market's venue is a market. A venue that an existing
    /// suggestion already names (ignoring case, either name containing the other) is not added twice.
    public static func venueSuggestions(
        for findings: [ResearchFinding],
        reportedURLs: [String],
        existing: [SuggestedPlace]
    ) -> [SuggestedPlace] {
        let reported = Set(reportedURLs.filter(isWebURL))
        var names = existing.map { normalised($0.name) }.filter { !$0.isEmpty }
        var venues: [SuggestedPlace] = []
        for finding in findings where finding.onTripDates && reported.contains(finding.url) {
            guard let kind = venueKind(for: finding.kind) else { continue }
            let name = (finding.placeName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalised(name)
            guard !key.isEmpty, !names.contains(where: { $0.contains(key) || key.contains($0) }) else { continue }
            names.append(key)
            venues.append(SuggestedPlace(name: name,
                                         area: (finding.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                         kind: kind,
                                         why: finding.title.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return venues
    }

    private static func venueKind(for kind: FindingKind) -> PlaceKind? {
        switch kind {
        case .market: .market
        case .event: .landmark
        case .closure, .transport, .holiday, .other: nil
        }
    }

    private static func normalised(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isWebURL(_ value: String) -> Bool {
        guard let url = URLComponents(string: value), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return false }
        return true
    }
}
