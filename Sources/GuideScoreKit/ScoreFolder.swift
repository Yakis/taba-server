import Foundation
import GuideKit

/// A folder of guide JSON files, scored in one go. The folder's own `scores.json` is never read as a guide.
public enum ScoreFolder {
    public static let scoresFileName = "scores.json"

    /// Scores every guide in the folder, keyed by file name. Files that are not guides are named in `skipped`.
    public static func summarize(_ folder: URL) throws -> (scores: [String: GuideScore], skipped: [String]) {
        var scores: [String: GuideScore] = [:]
        var skipped: [String] = []
        for file in try guideFiles(in: folder) {
            let name = file.lastPathComponent
            guard let guide = try? GuideKit.jsonDecoder().decode(Guide.self, from: Data(contentsOf: file)) else {
                skipped.append(name)
                continue
            }
            scores[name] = GuideScorer.score(guide)
        }
        return (scores, skipped)
    }

    /// Writes the scores as `scores.json` in the folder, with sorted keys so that two runs can be diffed.
    public static func write(_ scores: [String: GuideScore], to folder: URL) throws {
        let data = try GuideKit.jsonEncoder().encode(scores)
        try data.write(to: folder.appending(path: scoresFileName))
    }

    /// The `.json` files in the folder, by name, except `scores.json`.
    static func guideFiles(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != scoresFileName }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
