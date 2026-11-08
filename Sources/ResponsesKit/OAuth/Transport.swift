import Foundation

/// Sends one request and returns the body and response. Tests replace this with a fake.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The production transport, on URLSession.
public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TransportError.notHTTP
        }
        return (data, http)
    }
}

public enum TransportError: Error, Sendable, Equatable {
    case notHTTP
}

/// Percent-encoding for form and query values: only unreserved characters are left as they are.
enum FormEncoding {
    static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    static func body(_ pairs: [(String, String)]) -> Data {
        let text = pairs.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
        return Data(text.utf8)
    }
}
