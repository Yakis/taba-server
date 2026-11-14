import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The status code and body the server answered with.
public struct TripResponse: Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Sends one request to the server. The live one is `URLSessionTransport`; tests pass a fake.
public protocol TripTransport: Sendable {
    func send(_ request: URLRequest) async throws -> TripResponse
}

/// The live transport, over `URLSession`.
public struct URLSessionTransport: TripTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> TripResponse {
        let (body, response) = try await URLSession.shared.data(for: request)
        return TripResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: body)
    }
}
