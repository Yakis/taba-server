import Foundation
import GuideKit
import Testing

struct GuideHTMLGoldenTests {
    /// The committed page, found from this file: .../Tests/GuideKitTests/Render/ -> .../Tests/GuideKitTests/Fixtures.
    private static let fixtureURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Fixtures/edinburgh-guide.html")

    private func loadGuide() throws -> Guide {
        try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghGuideData())
    }

    @Test func committedPageMatchesTheSampleGuide() throws {
        let html = GuideHTMLRenderer().render(try loadGuide())
        if ProcessInfo.processInfo.environment["TABA_WRITE_FIXTURES"] == "1" {
            try html.write(to: Self.fixtureURL, atomically: true, encoding: .utf8)
            Issue.record("Rewrote edinburgh-guide.html; run the tests again without TABA_WRITE_FIXTURES")
            return
        }
        let committed = try String(contentsOf: Self.fixtureURL, encoding: .utf8)
        #expect(html == committed)
    }
}
