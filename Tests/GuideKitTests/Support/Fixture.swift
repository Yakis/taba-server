import Foundation

/// Loads the test resources bundled from Tests/GuideKitTests/Fixtures.
enum Fixture {
    /// The mock Edinburgh guide: the public venues from a real guide, with personal details replaced.
    static func edinburghMockData() throws -> Data {
        guard let url = Bundle.module.url(
            forResource: "edinburgh-mock",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw MissingFixtureError()
        }
        return try Data(contentsOf: url)
    }
}

struct MissingFixtureError: Error {}
