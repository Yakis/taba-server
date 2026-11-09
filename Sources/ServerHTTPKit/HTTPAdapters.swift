import AsyncHTTPClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOCore
import NIOHTTP1
import ResponsesKit
import SourcesKit

/// The supplied client MUST be configured with `redirectConfiguration: .disallow`.
/// AsyncHTTPClient configures redirects on the client, not on individual requests.
public enum ServerHTTPError: Error, Sendable, Equatable {
    case invalidRequest
    case requestFailed
    case responseTooLarge
    case lineTooLong
    case invalidResponse
}

enum Adapter {
    static let bodyLimit = 16 * 1024 * 1024

    static func request(_ request: URLRequest) throws -> HTTPClientRequest {
        guard let url = request.url, request.httpBodyStream == nil,
              request.timeoutInterval.isFinite, request.timeoutInterval > 0 else {
            throw ServerHTTPError.invalidRequest
        }
        var result = HTTPClientRequest(url: url.absoluteString)
        result.method = HTTPMethod(rawValue: request.httpMethod ?? "GET")
        for (name, value) in request.allHTTPHeaderFields ?? [:] {
            result.headers.add(name: name, value: value)
        }
        if let body = request.httpBody {
            // Defence in depth: AHC will not replay a streaming body on 307/308 redirects,
            // even if a caller accidentally supplies a client configured to follow them.
            let chunks = AsyncStream<ByteBuffer> { continuation in
                continuation.yield(ByteBuffer(bytes: body))
                continuation.finish()
            }
            result.body = .stream(chunks, length: .known(Int64(body.count)))
        }
        return result
    }

    static func execute(_ request: URLRequest, client: HTTPClient) async throws -> HTTPClientResponse {
        let converted = try self.request(request)
        // Clamp only to the largest timeout representable by NIO's nanoseconds.
        let seconds = min(request.timeoutInterval, Double(Int64.max / 1_000_000_000))
        do {
            return try await client.execute(converted, timeout: .nanoseconds(Int64(seconds * 1_000_000_000)))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw ServerHTTPError.requestFailed
        }
    }

    static func collect(_ body: HTTPClientResponse.Body) async throws -> Data {
        do {
            let buffer = try await body.collect(upTo: bodyLimit)
            return Data(buffer.readableBytesView)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw ServerHTTPError.requestFailed
        }
    }

    static func headers(_ headers: HTTPHeaders) -> [String: String] {
        var result: [String: String] = [:]
        for header in headers {
            let name = header.name.lowercased()
            if let previous = result[name] {
                result[name] = previous + ", " + header.value
            } else {
                result[name] = header.value
            }
        }
        return result
    }
}

/// Fetches bounded responses using a redirect-disabled AsyncHTTPClient.
public struct AHCFetching: HTTPFetching {
    private let client: HTTPClient
    public init(client: HTTPClient) { self.client = client }

    public func send(_ request: URLRequest) async throws -> SourcesKit.HTTPResponse {
        let response = try await Adapter.execute(request, client: client)
        let data = try await Adapter.collect(response.body)
        return SourcesKit.HTTPResponse(
            status: Int(response.status.code), body: data, headers: Adapter.headers(response.headers)
        )
    }
}

/// Performs OAuth requests using a redirect-disabled AsyncHTTPClient.
public struct AHCOAuthTransport: HTTPTransport {
    private let client: HTTPClient
    public init(client: HTTPClient) { self.client = client }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = try await Adapter.execute(request, client: client)
        let data = try await Adapter.collect(response.body)
        guard let url = request.url,
              let http = HTTPURLResponse(
                  url: url, statusCode: Int(response.status.code),
                  httpVersion: "HTTP/\(response.version.major).\(response.version.minor)",
                  headerFields: Adapter.headers(response.headers)
              ) else {
            throw ServerHTTPError.invalidResponse
        }
        return (data, http)
    }
}

/// Streams response lines on demand using a redirect-disabled AsyncHTTPClient.
public struct AHCStreamTransport: StreamTransport {
    private let client: HTTPClient
    public init(client: HTTPClient) { self.client = client }

    public func stream(for request: URLRequest) async throws -> StreamResponse {
        let response = try await Adapter.execute(request, client: client)
        let reader = LineReader(body: response.body)
        let lines = AsyncThrowingStream<String, any Error>(unfolding: { try await reader.next() })
        return StreamResponse(status: Int(response.status.code), lines: lines)
    }
}

actor LineReader {
    private var iterator: HTTPClientResponse.Body.AsyncIterator?
    private var buffer = ByteBuffer()
    private var line: [UInt8] = []
    private var total = 0
    private var ended = false
    private static let lineLimit = 1024 * 1024

    init(body: HTTPClientResponse.Body) {
        iterator = body.makeAsyncIterator()
    }

    func next() async throws -> String? {
        while true {
            while let byte = buffer.readInteger(as: UInt8.self) {
                total += 1
                guard total <= Adapter.bodyLimit else { throw ServerHTTPError.responseTooLarge }
                if byte == 10 { return takeLine() }
                line.append(byte)
                guard line.count <= Self.lineLimit else { throw ServerHTTPError.lineTooLong }
            }
            if ended {
                return line.isEmpty ? nil : takeLine()
            }
            if let chunk = try await readChunk() {
                buffer = chunk
            } else {
                ended = true
            }
        }
    }

    private func readChunk() async throws -> ByteBuffer? {
        // The iterator is exclusively removed from actor state across the suspension.
        // A concurrent next() is rejected rather than accessing it while in use.
        guard let saved = iterator else { throw ServerHTTPError.invalidResponse }
        iterator = nil
        nonisolated(unsafe) var current = saved
        do {
            let chunk = try await current.next()
            iterator = current
            return chunk
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw ServerHTTPError.requestFailed
        }
    }

    private func takeLine() -> String {
        if line.last == 13 { line.removeLast() }
        let result = String(bytes: line, encoding: .utf8) ?? ""
        line.removeAll(keepingCapacity: true)
        return result
    }
}
