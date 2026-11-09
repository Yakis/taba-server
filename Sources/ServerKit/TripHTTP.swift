import Crypto
import Foundation
import GuideKit
import Hummingbird
import HummingbirdAuth

/// Safe public progress, deliberately separate from private build evidence.
public enum TripState: String, Codable, Sendable {
    case queued, running, completed, failed

    public var isTerminal: Bool { self == .completed || self == .failed }
}

public struct TripStatus: Codable, Sendable {
    public let id: UUID
    public let state: TripState
    public let stage: BuildStage
    public let copyReviewRequired: Bool

    public init(id: UUID, state: TripState, stage: BuildStage, copyReviewRequired: Bool = false) {
        self.id = id
        self.state = state
        self.stage = stage
        self.copyReviewRequired = copyReviewRequired
    }
}

public struct ProgressEvent: Codable, Sendable {
    public let id: Int64
    public let status: TripStatus

    public init(id: Int64, status: TripStatus) {
        self.id = id
        self.status = status
    }
}

public enum AdmissionError: Error { case full }

/// The implementation must provide durable, monotonically ordered events per trip.
public protocol TripHTTPStore: Sendable {
    func create(_ input: TripBuildInput) async throws -> TripStatus
    func status(_ id: UUID) async throws -> TripStatus?
    func guide(_ id: UUID) async throws -> Guide?
    func events(_ id: UUID, after: Int64) async throws -> [ProgressEvent]
    func reviews(_ id: UUID) async throws -> [CopyReviewFlag]
}

public extension TripHTTPStore {
    func reviews(_ id: UUID) async throws -> [CopyReviewFlag] { [] }
}

/// Router only; a durable store and worker must be supplied before running a server.
public enum TripHTTP {
    public enum ConfigurationError: Error { case invalidToken }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public static func router(store: any TripHTTPStore, token: String) throws -> Router<BasicRequestContext> {
        guard token.utf8.count >= 32 else { throw ConfigurationError.invalidToken }
        let digest = SHA256.hash(data: Data(token.utf8))
        let router = Router()
        router.get("/health") { _, _ in "ok" }
        router.post("/trips") { request, _ -> Response in
            try authorize(request, digest: digest)
            let input: TripBuildInput
            do {
                let bytes = try await request.body.collect(upTo: 1_048_576)
                input = try JSONDecoder().decode(TripBuildInput.self, from: Data(buffer: bytes))
            } catch { throw HTTPError(.badRequest) }
            do { return try json(await store.create(input), status: .accepted) } catch AdmissionError.full {
                throw HTTPError(.serviceUnavailable)
            } catch { throw HTTPError(.internalServerError) }
        }
        router.get("/trips/:id") { request, context -> Response in
            try authorize(request, digest: digest)
            let id = try context.parameters.require("id", as: UUID.self)
            do {
                guard let status = try await store.status(id) else { throw HTTPError(.notFound) }
                return try json(status)
            } catch let error as HTTPError { throw error } catch { throw HTTPError(.internalServerError) }
        }
        router.get("/trips/:id/guide") { request, context -> Response in
            try authorize(request, digest: digest)
            let id = try context.parameters.require("id", as: UUID.self)
            do {
                guard let status = try await store.status(id) else { throw HTTPError(.notFound) }
                guard status.state == .completed, let guide = try await store.guide(id) else {
                    throw HTTPError(.conflict)
                }
                return try json(guide)
            } catch let error as HTTPError { throw error } catch { throw HTTPError(.internalServerError) }
        }
        router.get("/trips/:id/review") { request, context -> Response in
            try authorize(request, digest: digest)
            let id = try context.parameters.require("id", as: UUID.self)
            do {
                guard try await store.status(id) != nil else { throw HTTPError(.notFound) }
                return try json(await store.reviews(id))
            } catch let error as HTTPError { throw error } catch { throw HTTPError(.internalServerError) }
        }
        router.get("/trips/:id/events") { request, context -> Response in
            try authorize(request, digest: digest)
            let id = try context.parameters.require("id", as: UUID.self)
            let header = request.headers[.init("Last-Event-ID")!]
            let cursor: Int64
            if let header {
                guard let parsed = Int64(header), parsed >= 0 else { throw HTTPError(.badRequest) }
                cursor = parsed
            } else {
                cursor = 0
            }
            do {
                guard try await store.status(id) != nil else { throw HTTPError(.notFound) }
            } catch let error as HTTPError { throw error } catch { throw HTTPError(.internalServerError) }
            var headers = HTTPFields()
            headers[.contentType] = "text/event-stream"
            headers[.cacheControl] = "no-store"
            headers[.init("X-Accel-Buffering")!] = "no"
            return Response(status: .ok, headers: headers, body: ResponseBody { writer in
                var lastID = cursor
                var heartbeat = 0
                while !Task.isCancelled {
                    let events = try await store.events(id, after: lastID)
                    for event in events {
                        guard event.id > lastID else { continue }
                        let data = try JSONEncoder().encode(event.status)
                        guard let encoded = String(data: data, encoding: .utf8) else {
                            throw HTTPError(.internalServerError)
                        }
                        let payload = "id: \(event.id)\ndata: \(encoded)\n\n"
                        try await writer.write(ByteBuffer(string: payload))
                        lastID = event.id
                        if event.status.state.isTerminal {
                            try await writer.finish(nil)
                            return
                        }
                    }
                    // A reconnect after the last terminal event must also close.
                    if let status = try await store.status(id), status.state.isTerminal,
                       try await store.events(id, after: lastID).isEmpty {
                        try await writer.finish(nil)
                        return
                    }
                    heartbeat += 1
                    if heartbeat >= 15 {
                        try await writer.write(ByteBuffer(string: ": heartbeat\n\n"))
                        heartbeat = 0
                    }
                    try await Task.sleep(for: .seconds(1))
                }
                try await writer.finish(nil)
            })
        }
        return router
    }

    private static func authorize(_ request: Request, digest: SHA256.Digest) throws {
        let candidate = request.headers.bearer?.token ?? ""
        guard SHA256.hash(data: Data(candidate.utf8)) == digest else { throw HTTPError(.unauthorized) }
    }

    private static func json<T: Encodable>(_ value: T, status: HTTPResponse.Status = .ok) throws -> Response {
        let data = try JSONEncoder().encode(value)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        headers[.cacheControl] = "no-store"
        return Response(status: status, headers: headers, body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }
}
