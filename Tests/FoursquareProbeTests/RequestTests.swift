import Foundation
import FoursquareKit
import Testing

struct RequestTests {
    private let builder = FoursquareRequestBuilder(apiKey: "test-key-not-real")

    private func query(_ request: URLRequest) -> [String: String] {
        let components = URLComponents(url: request.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)
        var result: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            result[item.name] = item.value
        }
        return result
    }

    @Test func searchGoesToTheCurrentHostWithTheVersionHeader() {
        let parameters = SearchParameters(
            query: "The Abbotsford",
            latitude: 55.9533,
            longitude: -3.1946,
            radius: 300,
            categoryIds: [],
            limit: 3
        )
        let request = builder.search(parameters)
        #expect(request.url?.host == "places-api.foursquare.com")
        #expect(request.url?.path == "/places/search")
        #expect(request.value(forHTTPHeaderField: "X-Places-Api-Version") == "2025-06-17")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-not-real")
        let items = query(request)
        #expect(items["ll"] == "55.9533,-3.1946")
        #expect(items["radius"] == "300")
        #expect(items["limit"] == "3")
        #expect(items["query"] == "The Abbotsford")
    }

    @Test func categorySweepsSendTheCategoryId() {
        let parameters = SearchParameters(
            query: nil,
            latitude: 55.9533,
            longitude: -3.1883,
            radius: 1500,
            categoryIds: ["4bf58dd8d48988d11b941735"],
            limit: 50
        )
        let request = builder.search(parameters)
        let items = query(request)
        #expect(items["fsq_category_ids"] == "4bf58dd8d48988d11b941735")
        #expect(items["query"] == nil)
    }

    @Test func detailsAskForTheRequestedFields() {
        let request = builder.details(fsqPlaceId: "4b5f2d1e0000000000000001", fields: ["hours", "rating"])
        #expect(request.url?.path == "/places/4b5f2d1e0000000000000001")
        #expect(query(request)["fields"] == "hours,rating")
    }

    @Test func theKeyIsRedactedWhenTheBuilderIsPrinted() {
        #expect(!"\(builder)".contains("test-key-not-real"))
        #expect("\(builder)".contains("redacted"))
    }
}
