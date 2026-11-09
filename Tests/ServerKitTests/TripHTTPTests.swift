import Foundation
import GuideKit
import Hummingbird
import HummingbirdTesting
import ServerKit
import Testing

private actor FakeHTTPStore: TripHTTPStore {
    let id = UUID()
    var full = false
    var state: TripState = .queued

    func create(_ input: TripBuildInput) async throws -> TripStatus {
        if full { throw AdmissionError.full }
        return statusValue()
    }

    func status(_ id: UUID) async throws -> TripStatus? { id == self.id ? statusValue() : nil }
    func guide(_ id: UUID) async throws -> Guide? { nil }
    func events(_ id: UUID, after: Int64) async throws -> [ProgressEvent] {
        guard id == self.id else { return [] }
        return [ProgressEvent(id: 1, status: statusValue())].filter { $0.id > after }
    }
    func complete() { state = .completed }
    func setFull() { full = true }
    private func statusValue() -> TripStatus { .init(id: id, state: state, stage: .basics) }
}

struct TripHTTPTests {
    private let token = String(repeating: "x", count: 32)
    private let input = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25"}"#

    @Test func authenticationAndAdmissions() async throws {
        let store = FakeHTTPStore()
        let app = Application(responder: try TripHTTP.router(store: store, token: token).buildResponder())
        try await app.test(.router) { client in
            try await client.execute(uri: "/health", method: .get) { #expect($0.status == .ok) }
            try await client.execute(uri: "/trips", method: .post) { #expect($0.status == .unauthorized) }
            let headers: HTTPFields = [.authorization: "Bearer \(token)"]
            try await client.execute(uri: "/trips", method: .post, headers: headers,
                                     body: ByteBuffer(string: input)) { #expect($0.status == .accepted) }
            try await client.execute(uri: "/trips", method: .post, headers: headers,
                                     body: ByteBuffer(string: "{}")) { #expect($0.status == .badRequest) }
            await store.setFull()
            try await client.execute(uri: "/trips", method: .post, headers: headers,
                                     body: ByteBuffer(string: input)) { #expect($0.status == .serviceUnavailable) }
        }
    }

    @Test func acceptsPreferencesAndRejectsTooManyInterests() async throws {
        let store = FakeHTTPStore()
        let app = Application(responder: try TripHTTP.router(store: store, token: token).buildResponder())
        let preferred = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25","pace":"relaxed","#
            + #""interests":["Food","Museums"],"dailySpend":"low","adults":2,"children":1,"#
            + #""mobilityNotes":["Step-free access"]}"#
        let interests = (1...11).map { "\"Interest \($0)\"" }.joined(separator: ",")
        let tooMany = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25","interests":["#
            + interests + "]}"
        try await app.test(.router) { client in
            let headers: HTTPFields = [.authorization: "Bearer \(token)"]
            try await client.execute(uri: "/trips", method: .post, headers: headers,
                                     body: ByteBuffer(string: preferred)) { #expect($0.status == .accepted) }
            try await client.execute(uri: "/trips", method: .post, headers: headers,
                                     body: ByteBuffer(string: tooMany)) { #expect($0.status == .badRequest) }
        }
    }

    @Test func terminalStreamResumesAfterCursor() async throws {
        let store = FakeHTTPStore()
        await store.complete()
        let id = store.id
        let app = Application(responder: try TripHTTP.router(store: store, token: token).buildResponder())
        try await app.test(.router) { client in
            let headers: HTTPFields = [.authorization: "Bearer \(token)"]
            try await client.execute(uri: "/trips/\(id)/events", method: .get, headers: headers) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body).contains("id: 1\n"))
            }
            var resume = headers
            resume[.init("Last-Event-ID")!] = "1"
            try await client.execute(uri: "/trips/\(id)/events", method: .get, headers: resume) { response in
                #expect(response.status == .ok)
                #expect(response.body.readableBytes == 0)
            }
        }
    }
}
