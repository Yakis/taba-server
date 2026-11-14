import GuideKit
import SourcesKit
import Testing

struct GeoTests {
    @Test func distanceForOneThousandthOfALatitudeIsAboutOneHundredAndElevenMetres() {
        let origin = Samples.coordinate(0, 0)
        let north = Samples.coordinate(0.001, 0)
        let metres = Geo.metres(from: origin, to: north)
        #expect(abs(metres - 111.2) < 0.5)
    }
}
