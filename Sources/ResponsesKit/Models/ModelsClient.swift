import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ModelListError: Error, Sendable, Equatable {
    /// The body is neither the plan's `models` list nor the standard `data` list.
    case malformed
}

public enum ModelsClientError: Error, Sendable, Equatable {
    case invalidEndpoint
    /// A non-2xx answer. The body is never kept, because it may echo request details.
    case http(status: Int)
}

/// Reads the slugs of the models the signed-in plan can use.
public enum ModelList {
    private struct Entry: Decodable {
        let slug: String?
        let id: String?
    }

    private struct Root: Decodable {
        let models: [Entry]?
        let data: [Entry]?
    }

    /// Accepts `{"models":[{"slug":"..."}]}`, the plan's shape, and the standard `{"data":[{"id":"..."}]}`.
    public static func slugs(from data: Data) throws -> [String] {
        let root: Root
        do {
            root = try JSONDecoder().decode(Root.self, from: data)
        } catch {
            throw ModelListError.malformed
        }
        if let models = root.models {
            return models.compactMap { $0.slug ?? $0.id }
        }
        if let entries = root.data {
            return entries.compactMap { $0.id ?? $0.slug }
        }
        throw ModelListError.malformed
    }
}

/// Fetches the model list over the same transport the sign-in uses. Tests replace the transport.
public struct ModelsClient: Sendable {
    public static let endpoint = "https://api.openai.com/v1/models"

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }

    /// GETs the list with the bearer access token. The token is set on the request only, never logged.
    public func slugs(accessToken: String) async throws -> [String] {
        guard let url = URL(string: Self.endpoint) else {
            throw ModelsClientError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ModelsClientError.http(status: response.statusCode)
        }
        return try ModelList.slugs(from: data)
    }
}
