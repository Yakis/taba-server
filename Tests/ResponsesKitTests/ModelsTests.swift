import Foundation
import ResponsesKit
import Testing

struct ModelsTests {
    @Test func readsThePlanShapeAndTheStandardShape() throws {
        let plan = Data(#"{"models":[{"slug":"gpt-6.1-sol","title":"ignored"},{"slug":"gpt-6-luna"}]}"#.utf8)
        #expect(try ModelList.slugs(from: plan) == ["gpt-6.1-sol", "gpt-6-luna"])
        let standard = Data(#"{"object":"list","data":[{"id":"gpt-6-sol"},{"id":"gpt-6-terra"}]}"#.utf8)
        #expect(try ModelList.slugs(from: standard) == ["gpt-6-sol", "gpt-6-terra"])
    }

    @Test func rejectsOtherShapes() {
        #expect(throws: ModelListError.malformed) { try ModelList.slugs(from: Data("{}".utf8)) }
        #expect(throws: ModelListError.malformed) { try ModelList.slugs(from: Data("not json".utf8)) }
    }

    @Test func clientSendsAnAuthorizedGetAndReadsTheSlugs() async throws {
        let transport = FakeHTTPTransport { _ in (200, Data(#"{"models":[{"slug":"gpt-6.1-sol"}]}"#.utf8)) }
        let slugs = try await ModelsClient(transport: transport).slugs(accessToken: "access-token-not-real")
        #expect(slugs == ["gpt-6.1-sol"])
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token-not-real")
    }

    @Test func aFailedAnswerThrowsWithoutKeepingTheBody() async {
        let transport = FakeHTTPTransport { _ in (403, Data("echoed body".utf8)) }
        await #expect(throws: ModelsClientError.http(status: 403)) {
            try await ModelsClient(transport: transport).slugs(accessToken: "access-token-not-real")
        }
    }
}
