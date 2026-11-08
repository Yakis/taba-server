import Foundation

/// Whether a plan-shaped answer decodes, passes the schema's own rules, and uses only the given candidates.
public struct PlanDraftCheck: Sendable, Equatable {
    public let decodes: Bool
    public let schemaValid: Bool
    public let placeIdsFromCandidates: Bool
    public let stopCount: Int
    public let problems: [String]
}

/// Whether a research-shaped answer decodes, and whether each finding's URL was among the sources the search returned.
public struct ResearchCheck: Sendable, Equatable {
    public let decodes: Bool
    public let findingCount: Int
    public let findingsWithSourceURL: Int
    public let unmatchedURLs: [String]
    public let problems: [String]
}

public enum ProbeChecks {
    private static let kinds: Set<String> = ["sight", "meal", "drink", "rest", "travel", "logistics"]

    private struct PlanDTO: Decodable {
        let days: [DayDTO]
        let openQuestions: [String]
    }

    private struct DayDTO: Decodable {
        let date: String
        let stops: [StopDTO]
    }

    private struct StopDTO: Decodable {
        let placeId: String
        let kind: String
        let start: String
        let minutes: Int
        let reason: String
    }

    private struct ResearchDTO: Decodable {
        let findings: [FindingDTO]
        let searchNotes: String
    }

    private struct FindingDTO: Decodable {
        let title: String
        let url: String
        let summary: String
    }

    public static func planDraft(_ text: String, candidateIds: Set<String>) -> PlanDraftCheck {
        guard let plan = try? JSONDecoder().decode(PlanDTO.self, from: Data(text.utf8)) else {
            return PlanDraftCheck(
                decodes: false,
                schemaValid: false,
                placeIdsFromCandidates: false,
                stopCount: 0,
                problems: ["the answer is not the plan JSON"]
            )
        }
        var problems: [String] = []
        let stops = plan.days.flatMap(\.stops)
        for stop in stops {
            if !kinds.contains(stop.kind) { problems.append("unknown kind \(stop.kind)") }
            if !isClock(stop.start) { problems.append("start \(stop.start) is not HH:MM") }
            if stop.minutes < 1 { problems.append("minutes \(stop.minutes) is not positive") }
        }
        let outside = stops.map(\.placeId).filter { !candidateIds.contains($0) }
        if !outside.isEmpty {
            problems.append("placeIds not in the candidates: \(outside.joined(separator: ", "))")
        }
        return PlanDraftCheck(
            decodes: true,
            schemaValid: problems.allSatisfy { !$0.hasPrefix("unknown kind") && !$0.hasPrefix("start") }
                && !problems.contains(where: { $0.hasPrefix("minutes") }),
            placeIdsFromCandidates: outside.isEmpty,
            stopCount: stops.count,
            problems: problems
        )
    }

    public static func research(_ text: String, sourceURLs: [String]) -> ResearchCheck {
        guard let result = try? JSONDecoder().decode(ResearchDTO.self, from: Data(text.utf8)) else {
            return ResearchCheck(
                decodes: false,
                findingCount: 0,
                findingsWithSourceURL: 0,
                unmatchedURLs: [],
                problems: ["the answer is not the research JSON"]
            )
        }
        let known = Set(sourceURLs.map(normalisedURL))
        let unmatched = result.findings.map(\.url).filter { !known.contains(normalisedURL($0)) }
        return ResearchCheck(
            decodes: true,
            findingCount: result.findings.count,
            findingsWithSourceURL: result.findings.count - unmatched.count,
            unmatchedURLs: unmatched,
            problems: unmatched.isEmpty ? [] : ["findings cite URLs that were not in the search sources"]
        )
    }

    static func normalisedURL(_ url: String) -> String {
        var text = url.trimmingWhitespace
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    static func isClock(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1])
        else {
            return false
        }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }
}
