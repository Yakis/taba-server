import Foundation
import GuideKit
import PipelineKit

/// What the guide says: the tasting list, the facts, and how the stop texts read.
public struct ContentScore: Codable, Sendable, Equatable {
    public let tasting: Int
    /// Tasting names that are only a category, such as "Bread" (see `GenericTasting`).
    public let genericTasting: [String]
    public let practicalFacts: Int
    public let openQuestions: Int
    /// The most repeated three-word phrases: in three or more stop bodies, the top ten.
    public let repeatedPhrases: [RepeatedPhrase]
    /// Stops whose body is longer than 60 words.
    public let longBodyStops: [String]
    /// Notes fields with no text. Every notes field is listed when the guide has no notes.
    public let emptyNotes: [String]
}

public struct RepeatedPhrase: Codable, Sendable, Equatable {
    /// Three lowercase words, letters only, such as "old town walk".
    public let phrase: String
    /// How many different stop bodies use it.
    public let stops: Int
}

extension ContentScore {
    /// A phrase must appear in at least this many stop bodies to be reported.
    static let repeatThreshold = 3
    static let repeatLimit = 10
    static let longBodyWords = 60

    static func make(_ context: GuideScoreContext) -> ContentScore {
        let guide = context.guide
        let bodies = guide.days.flatMap(\.stops).map(\.copy.body)
        return ContentScore(
            tasting: guide.tasting.count,
            genericTasting: guide.tasting.map(\.name).filter { GenericTasting.isGeneric($0) },
            practicalFacts: guide.practical.count,
            openQuestions: guide.openQuestions?.count ?? 0,
            repeatedPhrases: repeatedPhrases(bodies),
            longBodyStops: guide.days.flatMap(\.stops).filter { wordCount($0.copy.body) > longBodyWords }.map(\.id),
            emptyNotes: emptyNotes(guide.notes)
        )
    }

    /// Three-word phrases (lowercased, letters only) found in the bodies of enough different stops, most used first.
    static func repeatedPhrases(_ bodies: [String]) -> [RepeatedPhrase] {
        var stopsPerPhrase: [String: Int] = [:]
        for body in bodies {
            let words = body.lowercased().split { !$0.isLetter }.map(String.init)
            let phrases = Set((0..<max(0, words.count - 2)).map { words[$0..<$0 + 3].joined(separator: " ") })
            for phrase in phrases {
                stopsPerPhrase[phrase, default: 0] += 1
            }
        }
        return stopsPerPhrase
            .filter { $0.value >= repeatThreshold }
            .map { RepeatedPhrase(phrase: $0.key, stops: $0.value) }
            .sorted { $0.stops != $1.stops ? $0.stops > $1.stops : $0.phrase < $1.phrase }
            .prefix(repeatLimit)
            .map { $0 }
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func emptyNotes(_ notes: GuideNotes?) -> [String] {
        let fields = [
            ("weather", notes?.weather ?? ""), ("light", notes?.light ?? ""),
            ("backupPlan", notes?.backupPlan ?? ""), ("rules", notes?.rules ?? "")
        ]
        return fields.filter { $0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.0)
    }
}
