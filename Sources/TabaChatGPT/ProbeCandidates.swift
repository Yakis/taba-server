import Foundation
import ResponsesKit

/// The hand-made inputs for the probe. The candidates are a small, invented one-day set; their ids are public
/// Foursquare-style and OpenStreetMap-style ids, and the stay is a made-up apartment.
enum ProbeCandidates {
    struct Candidate {
        let id: String
        let name: String
        let kind: String
        let hours: String
    }

    static let all: [Candidate] = [
        Candidate(id: "osm:node/2338447599", name: "Stockbridge Market", kind: "market", hours: "Sunday 10:00-16:00"),
        Candidate(id: "osm:node/1367337816", name: "The Abbotsford", kind: "pub", hours: "unknown"),
        Candidate(id: "osm:node/2339288064", name: "Oink Victoria Street", kind: "restaurant", hours: "unknown"),
        Candidate(id: "osm:node/33185107", name: "The Guildford Arms", kind: "pub", hours: "unknown"),
        Candidate(id: "manual:stay-new-town", name: "New Town Test Apartment", kind: "lodging", hours: "always")
    ]

    static var planInput: String {
        let list = all.map { "- \($0.id): \($0.name), kind \($0.kind), hours \($0.hours)" }
            .joined(separator: "\n")
        return """
        Trip: Edinburgh, one day, Sunday 2025-11-23. Pace: unhurried. Interests: food, pubs.
        Day window: 09:00 to 20:00. Sunrise 08:05, sunset 15:53, blueHourEnds 16:36. Rain chance 10.
        Arrival: none on this day. Stay check-in 15:00, check-out 11:00.
        Candidates (use only these placeIds):
        \(list)
        Plan this one day and return only the JSON object.
        """
    }

    static let researchInput = """
    Destination: Edinburgh, Scotland (time zone Europe/London).
    Exact dates: 2025-11-23 to 2025-11-23.
    Stay area: New Town.
    Interests: food, pubs, photography.
    Search the web and return only the JSON object.
    """

    /// The answer text from a recorded stream body, or nil when the stream did not complete.
    static func outputText(fromRawBody body: String) -> String? {
        parseStream(body)?.text
    }

    struct Parsed {
        let text: String
        let sources: [String]
        let searchCalls: Int
    }

    /// Reads a recorded stream body (lines joined by newlines) the same way the client does.
    static func parseStream(_ body: String) -> Parsed? {
        var parser = SSEParser()
        var accumulator = ResponsesAccumulator()
        do {
            for line in body.components(separatedBy: "\n") {
                if let event = parser.consume(line: line) {
                    try accumulator.consume(event)
                }
            }
            if let event = parser.finish() {
                try accumulator.consume(event)
            }
            let result = try accumulator.result()
            return Parsed(text: result.text, sources: result.sourceURLs, searchCalls: result.webSearchCount)
        } catch {
            return nil
        }
    }
}

/// Loads the instructions of a prompt file from the repo's Prompts folder, without its front matter.
enum PromptLoader {
    static func instructions(named name: String) async -> String? {
        let url = URL(fileURLWithPath: "Prompts/\(name)")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return PromptFile.body(of: text)
    }
}
