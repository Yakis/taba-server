import Foundation

/// Wraps another fetcher and refuses to send more than `limit` requests, so a run cannot exceed its budget.
public actor CappedFetcher: HTTPFetching {
    private let inner: any HTTPFetching
    public let limit: Int
    public private(set) var sentCount = 0

    public init(inner: any HTTPFetching, limit: Int) {
        self.inner = inner
        self.limit = limit
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        guard sentCount < limit else {
            throw SourcesError.refused("the \(limit)-request limit was reached")
        }
        sentCount += 1
        return try await inner.send(request)
    }
}
