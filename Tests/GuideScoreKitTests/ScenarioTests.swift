import Foundation
import GuideKit
@testable import GuideScoreKit
import ServerKit
import Testing

struct ScenarioTests {
    private static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let scenarioFolder = root.appending(path: "Evaluation/scenarios", directoryHint: .isDirectory)
    private static let today = TestGuides.date("2026-11-14")

    @Test func everyScenarioFileDecodesAsATripBuildInput() throws {
        let scenarios = try Scenario.load(from: Self.scenarioFolder)
        #expect(scenarios.count == 11)
        #expect(Set(scenarios.map(\.name)).count == scenarios.count)
        for scenario in scenarios {
            let body = try scenario.requestBody(today: Self.today)
            let input = try JSONDecoder().decode(TripBuildInput.self, from: body)
            let expectedStart = try #require(Self.today.adding(days: scenario.startInDays))
            #expect(input.from == expectedStart, "\(scenario.name) starts on its day")
        }
    }

    @Test func requestBodyKeepsTheLengthOfTheTrip() throws {
        let scenario = try decodeScenario(from: "2026-01-01", to: "2026-01-03", startInDays: 5)
        let input = try JSONDecoder().decode(TripBuildInput.self, from: scenario.requestBody(today: Self.today))
        #expect(input.from.description == "2026-11-19")
        #expect(input.to.description == "2026-11-21")
    }

    @Test func aScenarioNameMustBeASafeFileName() throws {
        let folder = try makeFolder()
        let bad = try decodeScenario(name: "../escape", from: "2026-01-01", to: "2026-01-01", startInDays: 1)
        try JSONEncoder().encode(bad).write(to: folder.appending(path: "bad.json"))
        #expect(throws: Scenario.ScenarioError.badName("../escape")) {
            try Scenario.load(from: folder)
        }
    }

    @Test func aScenarioWithBackwardsDatesIsRefused() throws {
        let scenario = try decodeScenario(from: "2026-01-03", to: "2026-01-01", startInDays: 1)
        #expect(throws: Scenario.ScenarioError.badDates("backwards")) {
            try scenario.requestBody(today: Self.today)
        }
    }

    private func decodeScenario(name: String = "backwards", from: String, to: String,
                                startInDays: Int) throws -> Scenario {
        let json = """
        {"name": "\(name)", "description": "Test.", "startInDays": \(startInDays),
         "input": {"destination": "Leeds", "from": "\(from)", "to": "\(to)", "pace": "relaxed"}}
        """
        return try JSONDecoder().decode(Scenario.self, from: Data(json.utf8))
    }
}

/// A new empty folder in the system's temporary directory.
func makeFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}
