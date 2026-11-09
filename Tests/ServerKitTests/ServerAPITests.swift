import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GuideKit
import ServerKit
import Testing

/// Runs against an explicitly started local replay server (including the Linux Docker image).
/// The app token is passed in memory by the caller, never embedded in saved API requests.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TABA_TEST_SERVER_URL"] != nil))
struct ServerAPITests {
    // One end-to-end sequence deliberately exercises the same persisted trip through every endpoint.
    // swiftlint:disable:next function_body_length
    @Test(.timeLimit(.minutes(2))) func buildsEdinburghThroughHTTP() async throws {
        let environment = ProcessInfo.processInfo.environment
        let base = try #require(environment["TABA_TEST_SERVER_URL"])
        let token = try #require(environment["TABA_APP_TOKEN"])
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("GuideKitTests/Fixtures/edinburgh-mock.json")
        let fixture = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: fixtureURL))
        let input = try TripBuildInput(destination: fixture.trip.destination.name,
            from: fixture.trip.dates.start, to: fixture.trip.dates.end, facts: fixture)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        func request(_ path: String, method: String = "GET", body: Data? = nil,
                     authorized: Bool = true, cursor: Int64? = nil) async throws -> (Data, Int) {
            var request = URLRequest(url: try #require(URL(string: base + path)))
            request.httpMethod = method
            request.httpBody = body
            request.timeoutInterval = 90
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if authorized { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            if let cursor { request.setValue(String(cursor), forHTTPHeaderField: "Last-Event-ID") }
            let (data, response) = try await session.data(for: request)
            return (data, try #require(response as? HTTPURLResponse).statusCode)
        }
        let (_, unauthorized) = try await request("/trips", method: "POST", authorized: false)
        #expect(unauthorized == 401)
        let (created, accepted) = try await request("/trips", method: "POST", body: JSONEncoder().encode(input))
        #expect(accepted == 202)
        let status = try JSONDecoder().decode(TripStatus.self, from: created)
        let path = "/trips/" + status.id.uuidString
        let (stream, streamStatus) = try await request(path + "/events")
        #expect(streamStatus == 200)
        let text = try #require(String(data: stream, encoding: .utf8))
        let ids = text.split(separator: "\n").compactMap { line -> Int64? in
            guard line.hasPrefix("id: ") else { return nil }
            return Int64(line.dropFirst(4))
        }
        #expect(ids.count == 15) // admission + running/checkpoint transition for seven stages
        #expect(ids == ids.sorted())
        #expect(Set(ids).count == ids.count)
        #expect(text.contains("completed"))
        #expect(!text.contains("Edinburgh")) // progress contains no trip inputs or private AI output
        let (finished, statusCode) = try await request(path)
        #expect(statusCode == 200)
        let final = try JSONDecoder().decode(TripStatus.self, from: finished)
        #expect(final.state == .completed)
        #expect(final.copyReviewRequired)
        let (guideData, guideCode) = try await request(path + "/guide")
        #expect(guideCode == 200)
        let guide = try JSONDecoder().decode(Guide.self, from: guideData)
        try guide.validateStructure()
        #expect(!PlanChecker().check(guide).contains { $0.severity == .error })
        #expect(guide.id == status.id.uuidString)
        let (reviews, reviewCode) = try await request(path + "/review")
        #expect(reviewCode == 200)
        #expect(try JSONDecoder().decode([CopyReviewFlag].self, from: reviews).count == 7)
        let lastID = try #require(ids.last)
        let (empty, resumeCode) = try await request(path + "/events", cursor: lastID)
        #expect(resumeCode == 200)
        #expect(empty.isEmpty)
    }
}
