import FoursquareKit
import GuideKit
import Testing

struct ProbePlanTests {
    @Test func searchesOnlyForeignNamedPlacesOfSearchableKinds() {
        let guide = Samples.guide(places: [
            Samples.place("osm:node/2", name: "Pub", kind: .pub, hours: unknownHours),
            Samples.place("osm:node/1", name: "Cafe", kind: .cafe, hours: unknownHours),
            Samples.place("manual:stay", name: "Stay", kind: .lodging, hours: unknownHours),
            Samples.place("osm:node/3", name: "Station", kind: .station, hours: unknownHours),
            Samples.place("manual:square", name: "Square", kind: .street, hours: unknownHours),
            Samples.place("osm:node/4", name: "Store", kind: .luggage, hours: unknownHours)
        ])
        let targets = ProbePlan.searchTargets(in: guide)
        #expect(targets.map(\.fixtureId) == ["osm:node/1", "osm:node/2"])
    }

    @Test func aNearbyHitWithTheSameNameMatches() throws {
        let target = searchTarget()
        let hit = try Samples.decodePlace(Samples.abbotsfordJSON)
        let probe = ProbePlan.evaluate(target: target, hits: [hit])
        #expect(probe.matched)
        #expect(probe.topHit?.fsqPlaceId == "4b5f2d1e0000000000000001")
        #expect(probe.hitCount == 1)
        #expect(probe.topHit?.fieldsReturned.contains("categories") == true)
    }

    @Test func aHitFarAwayDoesNotMatchEvenWithTheSameName() throws {
        // About 0.0045 degrees of latitude is roughly 500 m.
        let far = """
        {"fsq_place_id":"far","name":"The Abbotsford","latitude":55.9578,"longitude":-3.1883,"categories":[]}
        """
        let probe = ProbePlan.evaluate(target: searchTarget(), hits: [try Samples.decodePlace(far)])
        #expect(!probe.matched)
        let distance = Double(probe.topHit?.distanceMetres ?? 0)
        #expect(distance > ProbePlan.matchDistanceMetres)
    }

    @Test func aNearbyHitWithADifferentNameDoesNotMatch() throws {
        let other = """
        {"fsq_place_id":"other","name":"Corner Shop","latitude":55.95327,"longitude":-3.19465,"categories":[]}
        """
        #expect(!ProbePlan.evaluate(target: searchTarget(), hits: [try Samples.decodePlace(other)]).matched)
    }

    @Test func noHitsIsNotAMatch() {
        let probe = ProbePlan.evaluate(target: searchTarget(), hits: [])
        #expect(!probe.matched)
        #expect(probe.topHit == nil)
        #expect(probe.hitCount == 0)
    }

    @Test func fieldReportListsOnlyFieldsThatCameBack() throws {
        let json = "{\"fsq_place_id\":\"x\",\"name\":\"X\",\"latitude\":55.9,\"longitude\":-3.1}"
        let place = try Samples.decodePlace(json)
        #expect(FieldReport.returnedFields(in: place) == ["latitude", "longitude"])
    }

    private var unknownHours: OpeningHours {
        OpeningHours(hoursKnown: false, weekly: [], exceptions: [])
    }

    private func searchTarget() -> SearchTarget {
        SearchTarget(
            fixtureId: "osm:node/1367337816",
            name: "The Abbotsford",
            kind: .pub,
            coordinate: Samples.coordinate(55.9533, -3.1946)
        )
    }
}
