import FoursquareKit
import Testing

struct ProbeOptionsTests {
    @Test func fixtureOnlyUsesTheDefaults() throws {
        let options = try ProbeOptions.parse(["fixture.json"])
        let expected = ProbeOptions(fixturePath: "fixture.json", premium: false, outputPath: "probe-output/foursquare")
        #expect(options == expected)
    }

    @Test func premiumAndOutputAreRead() throws {
        let options = try ProbeOptions.parse(["fixture.json", "--premium", "--out", "elsewhere"])
        #expect(options.premium)
        #expect(options.outputPath == "elsewhere")
    }

    @Test func missingFixtureIsAnError() {
        #expect(throws: ProbeOptionsError.missingFixture) {
            _ = try ProbeOptions.parse(["--premium"])
        }
    }

    @Test func unknownOptionIsAnError() {
        #expect(throws: ProbeOptionsError.unknownOption("--verbose")) {
            _ = try ProbeOptions.parse(["fixture.json", "--verbose"])
        }
    }

    @Test func outWithoutAValueIsAnError() {
        #expect(throws: ProbeOptionsError.missingValue("--out")) {
            _ = try ProbeOptions.parse(["fixture.json", "--out"])
        }
    }

    @Test func secondPositionalArgumentIsAnError() {
        #expect(throws: ProbeOptionsError.unexpectedArgument("other.json")) {
            _ = try ProbeOptions.parse(["fixture.json", "other.json"])
        }
    }
}
