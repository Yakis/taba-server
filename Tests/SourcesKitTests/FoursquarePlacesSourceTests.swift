import Foundation
import FoursquareKit
import GuideKit
import SourcesKit
import Testing

struct FoursquarePlacesSourceTests {
    private let checkedAt = Samples.date("2026-11-08")
    private let centre = Samples.coordinate(55.9533, -3.1883)
    private let cafeCategory = "63be6904847c3692a84b9bb6"
    private let pubCategory = "4bf58dd8d48988d11b941735"

    private var cafeResponse: String {
        HitJSON.search([
            HitJSON.place(
                id: "a1", name: "Cafe Alpha", latitude: 55.95340, longitude: -3.18830,
                category: "Cafes, Coffee, and Tea Houses", categoryId: cafeCategory
            ),
            HitJSON.place(
                id: "b2", name: "Cafe Beta", latitude: 55.95360, longitude: -3.18810,
                category: "Cafes, Coffee, and Tea Houses", categoryId: cafeCategory,
                website: "https://example.com/beta"
            )
        ])
    }

    private var pubResponse: String {
        HitJSON.search([
            HitJSON.place(
                id: "b2", name: "Cafe Beta", latitude: 55.95360, longitude: -3.18810,
                category: "Pubs", categoryId: pubCategory, website: "https://example.com/beta"
            ),
            HitJSON.place(
                id: "c3", name: "Bow Bar Pub", latitude: 55.95400, longitude: -3.18900,
                category: "Pubs", categoryId: pubCategory, dateClosed: "2025-01-01"
            )
        ])
    }

    /// Answers cafe and pub searches by their category id.
    private func fetcher(pubStatus: Int = 200) -> RecordingFetcher {
        let cafe = cafeResponse
        let pub = pubResponse
        return RecordingFetcher { request in
            let ids = Samples.query(request)["fsq_category_ids"] ?? ""
            if ids == self.cafeCategory {
                return Samples.response(cafe)
            }
            return Samples.response(pubStatus == 200 ? pub : "{}", status: pubStatus)
        }
    }

    @Test func placesFromSeveralKindsAreDeduplicatedByFoursquareId() async {
        let source = FoursquarePlacesSource(fetcher: fetcher(), apiKey: "test-key-not-real")
        let report = await source.sweep(kinds: [.cafe, .pub], around: centre, checkedAt: checkedAt)
        #expect(report.places.map(\.id) == ["fsq:a1", "fsq:b2"])
        #expect(report.sweeps.allSatisfy { $0.failure == nil })
    }

    @Test func closedPlacesAreSkipped() async {
        let source = FoursquarePlacesSource(fetcher: fetcher(), apiKey: "test-key-not-real")
        let report = await source.sweep(kinds: [.pub], around: centre, checkedAt: checkedAt)
        #expect(!report.places.contains { $0.id == "fsq:c3" })
    }

    @Test func aWebsiteBecomesAFactAndHoursStayUnknown() async throws {
        let source = FoursquarePlacesSource(fetcher: fetcher(), apiKey: "test-key-not-real")
        let report = await source.sweep(kinds: [.cafe], around: centre, checkedAt: checkedAt)
        let beta = try #require(report.places.first { $0.id == "fsq:b2" })
        #expect(beta.facts == [Fact(
            text: "Website: https://example.com/beta",
            sourceId: FoursquarePlacesSource.sourceId,
            checkedAt: checkedAt
        )])
        let alpha = try #require(report.places.first { $0.id == "fsq:a1" })
        #expect(alpha.facts.isEmpty)
        #expect(!alpha.hours.hoursKnown)
        #expect(alpha.kind == .cafe)
    }

    @Test func aFailedKindIsReportedAndTheOthersStillRun() async {
        let source = FoursquarePlacesSource(fetcher: fetcher(pubStatus: 429), apiKey: "test-key-not-real")
        let report = await source.sweep(kinds: [.cafe, .pub], around: centre, checkedAt: checkedAt)
        #expect(report.places.map(\.id) == ["fsq:a1", "fsq:b2"])
        let pub = report.sweeps.first { $0.label == "pub" }
        #expect(pub?.failure?.contains("429") == true)
        #expect(report.sweeps.first { $0.label == "cafe" }?.failure == nil)
    }

    @Test func aKindWithNoCategoryIsReportedNotSearched() async {
        let recorder = fetcher()
        let source = FoursquarePlacesSource(fetcher: recorder, apiKey: "test-key-not-real")
        let report = await source.sweep(kinds: [.other], around: centre, checkedAt: checkedAt)
        #expect(report.places.isEmpty)
        #expect(report.sweeps.first?.failure != nil)
        #expect(await recorder.requests.isEmpty)
    }

    @Test func searchesSendTheCategoryAndTheVersionHeaderAndNoKeyInTheURL() async throws {
        let recorder = fetcher()
        let source = FoursquarePlacesSource(fetcher: recorder, apiKey: "test-key-not-real")
        _ = await source.sweep(kinds: [.cafe], around: centre, limit: 10, checkedAt: checkedAt)
        let request = try #require(await recorder.requests.first)
        #expect(request.value(forHTTPHeaderField: "X-Places-Api-Version") == "2025-06-17")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-not-real")
        #expect(Samples.query(request)["fsq_category_ids"] == cafeCategory)
        #expect(Samples.query(request)["limit"] == "10")
        #expect(!(request.url?.absoluteString.contains("test-key-not-real") ?? true))
    }

    @Test func aVenueKindSearchesTheMusicVenueCategory() async throws {
        let recorder = fetcher()
        let source = FoursquarePlacesSource(fetcher: recorder, apiKey: "test-key-not-real")
        let report = await source.sweep(kinds: [.venue], around: centre, checkedAt: checkedAt)
        let request = try #require(await recorder.requests.first)
        #expect(Samples.query(request)["fsq_category_ids"] == "4bf58dd8d48988d1e5931735")
        #expect(report.sweeps.map(\.label) == ["venue"])
    }

    @Test func kindsBecomeOneLabelledSearchEachAndKindsWithoutACategoryAreLeftOut() {
        let searches = FoursquarePlacesSource.searches(for: [.cafe, .other, .venue])
        #expect(searches.map(\.label) == ["cafe", "venue"])
        #expect(searches.last?.categoryIds == ["4bf58dd8d48988d1e5931735"])
    }

    @Test func aSearchIsSentWithItsOwnCategoriesAndLabelledOutcome() async throws {
        let recorder = fetcher()
        let source = FoursquarePlacesSource(fetcher: recorder, apiKey: "test-key-not-real")
        let search = FoursquarePlacesSource.CategorySearch(
            label: "parks", categoryIds: ["4bf58dd8d48988d163941735", "4bf58dd8d48988d15a941735"]
        )
        let report = await source.sweep(searches: [search], around: centre, limit: 6, checkedAt: checkedAt)
        let request = try #require(await recorder.requests.first)
        #expect(Samples.query(request)["fsq_category_ids"] == "4bf58dd8d48988d163941735,4bf58dd8d48988d15a941735")
        #expect(Samples.query(request)["limit"] == "6")
        #expect(report.sweeps.map(\.label) == ["parks"])
        #expect(report.sweeps.first?.failure == nil)
    }

    @Test func eachSearchRecordsTheIdsItReturned() async {
        let source = FoursquarePlacesSource(fetcher: fetcher(), apiKey: "test-key-not-real")
        let cafe = FoursquarePlacesSource.CategorySearch(label: "cafe", categoryIds: [cafeCategory])
        let pubs = FoursquarePlacesSource.CategorySearch(label: "pubs", categoryIds: [pubCategory])
        let report = await source.sweep(searches: [cafe, pubs], around: centre, limit: 6, checkedAt: checkedAt)
        let cafeIds = report.sweeps[0].placeIds
        #expect(cafeIds.count == 2)
        // Beta is returned by both searches, so the pub search lists it too. The closed pub is not listed.
        #expect(report.sweeps[1].placeIds == [cafeIds[1]])
        #expect(report.sweeps.flatMap(\.placeIds).allSatisfy { id in report.places.contains { $0.id == id } })
        #expect(report.places.count == 2)
    }

    @Test func aHitWithoutACoordinateIsLeftOut() async {
        let category = "{\"fsq_category_id\":\"\(cafeCategory)\",\"name\":\"Cafe\"}"
        let noPoint = HitJSON.search([
            "{\"fsq_place_id\":\"np1\",\"name\":\"Nowhere Cafe\",\"categories\":[\(category)]}"
        ])
        let recorder = RecordingFetcher { _ in Samples.response(noPoint) }
        let source = FoursquarePlacesSource(fetcher: recorder, apiKey: "test-key-not-real")
        let report = await source.sweep(kinds: [.cafe], around: centre, checkedAt: checkedAt)
        #expect(report.places.isEmpty)
        #expect(report.sweeps.first?.returned == 1)
    }
}
