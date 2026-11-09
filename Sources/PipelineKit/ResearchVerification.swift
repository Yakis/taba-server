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

    private static func isWebURL(_ value: String) -> Bool {
        guard let url = URLComponents(string: value), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return false }
        return true
    }
}
