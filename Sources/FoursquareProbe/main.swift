import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FoursquareKit
import GuideKit

/// Exits with a one-line message on stderr.
func fail(_ message: String, status: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(status)
}

// The key comes only from the environment. It is checked first, and it is never printed or written to disk.
guard let apiKey = ProcessInfo.processInfo.environment["FOURSQUARE_API_KEY"], !apiKey.isEmpty else {
    fail("FOURSQUARE_API_KEY is not set. Export your Foursquare service key and run again.", status: 2)
}

let options: ProbeOptions
do {
    options = try ProbeOptions.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("\(ProbeOptions.usage)\n\(error)", status: 2)
}

let guide: Guide
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: options.fixturePath))
    guide = try GuideKit.jsonDecoder().decode(Guide.self, from: data)
} catch {
    fail("could not read a guide from \(options.fixturePath): \(error)")
}

let outputDirectory = URL(fileURLWithPath: options.outputPath, isDirectory: true)
let rawDirectory = outputDirectory.appendingPathComponent("raw", isDirectory: true)
do {
    try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
} catch {
    fail("could not create \(options.outputPath): \(error)")
}

let runner = ProbeRunner(
    builder: FoursquareRequestBuilder(apiKey: apiKey),
    session: URLSession(configuration: .ephemeral),
    budget: RequestBudget(limit: ProbePlan.requestLimit),
    rawDirectory: rawDirectory
)

do {
    let report = try await runner.run(
        guide: guide,
        options: options,
        fixtureName: URL(fileURLWithPath: options.fixturePath).lastPathComponent
    )
    let markdown = ReportWriter.markdown(report)
    let reportURL = outputDirectory.appendingPathComponent("report.md")
    try markdown.write(to: reportURL, atomically: true, encoding: .utf8)
    print("Wrote \(reportURL.path) and raw responses in \(rawDirectory.path). Requests made: \(report.requestsMade).")
} catch {
    fail("probe stopped: \(error)")
}
