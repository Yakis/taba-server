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
    private(set) var createdModels: [String] = []

    func create(_ input: TripBuildInput, model: String) async throws -> TripStatus {
        if full { throw AdmissionError.full }
        createdModels.append(model)
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

private struct FakeCatalog: TripModelCatalog {
    let defaultModel = "gpt-6.1-sol"

    func options() async -> [ModelOption] {
        [ModelOption(id: "gpt-6.1-sol", name: "Sol", provider: "ChatGPT"),
         ModelOption(id: "gpt-6.1-terra", name: "Terra", provider: "ChatGPT")]
    }
}

struct TripHTTPTests {
    private let token = String(repeating: "x", count: 32)
    private let input = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25"}"#

    @Test func authenticationAndAdmissions() async throws {
        let store = FakeHTTPStore()
        let app = Application(responder: try TripHTTP.router(store: store, token: token,
                                                            models: FakeCatalog()).buildResponder())
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
        let app = Application(responder: try TripHTTP.router(store: store, token: token,
                                                            models: FakeCatalog()).buildResponder())
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

    @Test func modelsRouteOffersChoicesAndOnlyOfferedModelsAreAccepted() async throws {
        let store = FakeHTTPStore()
        let app = Application(responder: try TripHTTP.router(store: store, token: token,
                                                            models: FakeCatalog()).buildResponder())
        let terraBody = ByteBuffer(string: String(input.dropLast()) + #","model":"gpt-6.1-terra"}"#)
        let lunaBody = ByteBuffer(string: String(input.dropLast()) + #","model":"gpt-6.1-luna"}"#)
        try await app.test(.router) { client in
            let headers: HTTPFields = [.authorization: "Bearer \(token)"]
            try await client.execute(uri: "/models", method: .get) { #expect($0.status == .unauthorized) }
            try await client.execute(uri: "/models", method: .get, headers: headers) { response in
                #expect(response.status == .ok)
                let list = try JSONDecoder().decode(ModelListResponse.self, from: Data(buffer: response.body))
                #expect(list.defaultModel == "gpt-6.1-sol")
                #expect(list.models.map(\.name) == ["Sol", "Terra"])
                #expect(list.models.map(\.id) == ["gpt-6.1-sol", "gpt-6.1-terra"])
                #expect(list.models.map(\.provider) == ["ChatGPT", "ChatGPT"])
            }
            try await client.execute(uri: "/trips", method: .post, headers: headers,
                                     body: terraBody) { #expect($0.status == .accepted) }
            try await client.execute(uri: "/trips", method: .post, headers: headers,
                                     body: lunaBody) { #expect($0.status == .badRequest) }
            try await client.execute(uri: "/trips", method: .post, headers: headers,
                                     body: ByteBuffer(string: input)) { #expect($0.status == .accepted) }
        }
        #expect(await store.createdModels == ["gpt-6.1-terra", "gpt-6.1-sol"])
    }

    @Test func terminalStreamResumesAfterCursor() async throws {
        let store = FakeHTTPStore()
        await store.complete()
        let id = store.id
        let app = Application(responder: try TripHTTP.router(store: store, token: token,
                                                            models: FakeCatalog()).buildResponder())
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
