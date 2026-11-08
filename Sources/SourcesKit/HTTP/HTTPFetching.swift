import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The User-Agent every outside service request sends, as the public APIs ask.
public enum TABAClient {
    public static let userAgent = "TABA/0.1 (personal travel guide)"
}

/// The status, body and headers of an HTTP response.
public struct HTTPResponse: Sendable, Equatable {
    public let status: Int
    public let body: Data
    /// Header names in lower case, so lookups do not depend on how the server spelled them.
    public let headers: [String: String]

    public init(status: Int, body: Data, headers: [String: String]) {
        self.status = status
        self.body = body
        self.headers = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public var isSuccess: Bool {
        (200..<300).contains(status)
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// Sends one HTTP request and returns its response. The app uses `URLSessionFetcher`; tests use a fake.
public protocol HTTPFetching: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

/// Errors from the sources. They never carry a request, so they cannot leak a key.
public enum SourcesError: Error, Equatable, Sendable {
    /// The server answered with a status outside 2xx.
    case http(status: Int)
    /// The response did not have the documented shape.
    case malformed(String)
    /// The service answered 200 but reported a failure in its body.
    case remote(String)
    /// The request did not finish in time, either at the connection or as reported by the service.
    case timedOut
    /// The request failed before any response, such as a lost connection or a certificate error.
    case network(String)
    /// The request was not sent, such as when a budget is used up.
    case refused(String)
    /// The request asked for something the source cannot do, such as a date range that ends before it starts.
    case invalidRequest(String)
}

/// The URLSession implementation. It uses `data(for:)`, which also exists on Linux.
public struct URLSessionFetcher: HTTPFetching {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw SourcesError.timedOut
        } catch {
            throw SourcesError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw SourcesError.malformed("the response was not HTTP")
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let name = key as? String, let text = value as? String {
                headers[name] = text
            }
        }
        return HTTPResponse(status: http.statusCode, body: data, headers: headers)
    }
}
