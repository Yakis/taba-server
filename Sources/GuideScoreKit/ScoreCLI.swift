import Foundation
import GuideKit

/// The `taba-score` command line. Each command prints its result and returns an exit status.
///
/// - `report <guide.json> [--json]`: one guide, as text or as the full score.
/// - `compare <a.json> <b.json>`: two guides side by side.
/// - `summary <folder>`: scores every guide in the folder into `scores.json` and prints a table.
/// - `build --server <url> --scenarios <folder> --out <folder>`: builds the scenarios on a server and saves the guides.
///   The app token is read from the `TABA_TOKEN` environment variable only.
public enum ScoreCLI {
    static let usage = """
        usage:
          taba-score report <guide.json> [--json]
          taba-score compare <a.json> <b.json>
          taba-score summary <folder>
          taba-score build --server <url> --scenarios <folder> --out <folder>
        """

    public static func run(_ arguments: [String], environment: [String: String]) async -> Int32 {
        do {
            return try await dispatch(arguments, environment: environment)
        } catch {
            printError("taba-score: \(error)")
            return 1
        }
    }

    private static func dispatch(_ arguments: [String], environment: [String: String]) async throws -> Int32 {
        let rest = Array(arguments.dropFirst())
        switch arguments.first {
        case "report":
            try report(rest)
        case "compare":
            try compare(rest)
        case "summary":
            try summary(rest)
        case "build":
            return try await build(rest, environment: environment)
        case nil, "help", "--help", "-h":
            print(usage)
        default:
            printError(usage)
            return 2
        }
        return 0
    }

    private static func report(_ arguments: [String]) throws {
        guard let path = arguments.first(where: { !$0.hasPrefix("--") }) else { throw CLIError(usage) }
        let score = GuideScorer.score(try loadGuide(path))
        if arguments.contains("--json") {
            let json = try GuideKit.jsonEncoder().encode(score)
            print(String(data: json, encoding: .utf8) ?? "")
        } else {
            print(ScoreReport.text(score))
        }
    }

    private static func compare(_ arguments: [String]) throws {
        guard arguments.count == 2 else { throw CLIError(usage) }
        let comparison = GuideScorer.compare(try loadGuide(arguments[0]), try loadGuide(arguments[1]))
        print(ScoreReport.comparison(comparison, labelA: "A", labelB: "B"))
    }

    private static func summary(_ arguments: [String]) throws {
        guard let folder = arguments.first else { throw CLIError(usage) }
        let folderURL = URL(filePath: folder, directoryHint: .isDirectory)
        let (scores, skipped) = try ScoreFolder.summarize(folderURL)
        try ScoreFolder.write(scores, to: folderURL)
        print(ScoreReport.summaryTable(scores))
        if !skipped.isEmpty {
            printError("Skipped (not guides): \(skipped.joined(separator: ", "))")
        }
        print("Wrote \(scores.count) score(s) to \(folderURL.appending(path: ScoreFolder.scoresFileName).path)")
    }

    private static func build(_ arguments: [String], environment: [String: String]) async throws -> Int32 {
        guard let serverText = value(of: "--server", in: arguments),
              let serverURL = URL(string: serverText), serverURL.scheme == "https" || serverURL.scheme == "http",
              let scenariosPath = value(of: "--scenarios", in: arguments),
              let outPath = value(of: "--out", in: arguments) else {
            throw CLIError(usage)
        }
        guard let token = environment["TABA_TOKEN"], !token.isEmpty else {
            throw CLIError("Set TABA_TOKEN to the app token. It is read from the environment and never printed.")
        }
        guard let today = londonToday() else { throw CLIError("The date could not be read.") }
        let scenarios = try Scenario.load(from: URL(filePath: scenariosPath, directoryHint: .isDirectory))
        let requests = try scenarios.map { ScenarioRequest(name: $0.name, body: try $0.requestBody(today: today)) }
        let runner = TripBuildRunner(server: serverURL, token: token)
        let results = await runner.build(requests, outFolder: URL(filePath: outPath, directoryHint: .isDirectory)) {
            print(line(for: $0))
        }
        return results.allSatisfy { $0.file != nil } ? 0 : 1
    }

    /// One line per scenario: the trip, its state and its build minutes, or what went wrong.
    static func line(for result: BuildResult) -> String {
        let trip = result.tripId ?? "no trip"
        if let problem = result.problem {
            return "\(result.scenario): \(trip), \(result.state): \(problem)"
        }
        let minutes = result.buildMinutes.map { String(format: "%.1f", $0) } ?? "?"
        return "\(result.scenario): trip \(trip), \(result.state), \(minutes) min, saved to \(result.file ?? "")"
    }

    /// The value after a flag, such as `--out folder`.
    static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func loadGuide(_ path: String) throws -> Guide {
        try GuideKit.jsonDecoder().decode(Guide.self, from: Data(contentsOf: URL(filePath: path)))
    }

    private static func printError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

/// A usage or input error, shown as it is.
struct CLIError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
