import FoursquareKit
import GuideKit
import Testing

struct MatchingTests {
    @Test func normalisesNamesForComparison() {
        #expect(NameMatch.normalised("The Abbotsford") == "abbotsford")
        #expect(NameMatch.normalised("Oink, Hanover Street") == "oink hanover street")
        #expect(NameMatch.normalised("M&S Food Stockbridge") == "m and s food stockbridge")
        #expect(NameMatch.normalised("Café Lumière") == "cafe lumiere")
    }

    @Test func equalNamesMatchAfterNormalising() {
        #expect(NameMatch.matches("M&S Food Stockbridge", "M and S Food Stockbridge"))
        #expect(NameMatch.matches("The Abbotsford", "Abbotsford"))
    }

    @Test func oneNameInsideTheOtherMatches() {
        #expect(NameMatch.matches("Calton Hill", "Calton Hill Park"))
    }

    @Test func unrelatedNamesDoNotMatch() {
        #expect(!NameMatch.matches("Bow Bar", "Cafe Bar"))
    }

    @Test func tooShortASubstringDoesNotMatch() {
        #expect(!NameMatch.matches("Oak", "Oakland Cafe"))
    }

    @Test func distanceForOneThousandthOfALatitudeIsAboutOneHundredAndElevenMetres() throws {
        let origin = Samples.coordinate(0, 0)
        let north = Samples.coordinate(0.001, 0)
        let metres = Geo.metres(from: origin, to: north)
        #expect(abs(metres - 111.2) < 0.5)
    }
}
