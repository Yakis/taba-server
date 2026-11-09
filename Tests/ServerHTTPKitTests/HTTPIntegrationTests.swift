import AsyncHTTPClient
import Dispatch
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import ServerHTTPKit
import Testing

@Suite struct HTTPIntegrationTests {
    @Test func fetchAndOAuthReturnStatusHeadersAndBody() async throws {
        let response = "HTTP/1.1 201 Created\r\nContent-Length: 5\r\nX-Test: present\r\nConnection: close\r\n\r\nhello"
        let client = HTTPClient(
            eventLoopGroupProvider: .singleton, configuration: .init(redirectConfiguration: .disallow)
        )
        do {
            let fetchURL = try localServer(response: response)
            let fetched = try await AHCFetching(client: client).send(URLRequest(url: fetchURL))
            #expect(fetched.status == 201)
            #expect(fetched.header("X-Test") == "present")
            #expect(String(data: fetched.body, encoding: .utf8) == "hello")

            let oauthURL = try localServer(response: response)
            let (body, http) = try await AHCOAuthTransport(client: client).data(for: URLRequest(url: oauthURL))
            #expect(http.statusCode == 201)
            #expect(http.value(forHTTPHeaderField: "x-test") == "present")
            #expect(String(data: body, encoding: .utf8) == "hello")
            try await client.shutdown()
        } catch {
            try? await client.shutdown()
            throw error
        }
    }

    @Test func fetchRespectsTimeout() async throws {
        let client = HTTPClient(
            eventLoopGroupProvider: .singleton, configuration: .init(redirectConfiguration: .disallow)
        )
        do {
            var request = URLRequest(url: try localServer(response: "", delay: 0.3))
            request.timeoutInterval = 0.05
            await #expect(throws: ServerHTTPError.requestFailed) { try await AHCFetching(client: client).send(request) }
            try await client.shutdown()
        } catch {
            try? await client.shutdown()
            throw error
        }
    }

    @Test func cancellingFetchPropagatesCancellation() async throws {
        let client = HTTPClient(
            eventLoopGroupProvider: .singleton, configuration: .init(redirectConfiguration: .disallow)
        )
        do {
            let request = URLRequest(url: try localServer(response: "", delay: 0.3))
            let task = Task { try await AHCFetching(client: client).send(request) }
            try await Task.sleep(for: .milliseconds(30))
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
            try await client.shutdown()
        } catch {
            try? await client.shutdown()
            throw error
        }
    }

    @Test func oauthBodyIsNotReplayedOnRedirectEvenWithDefaultClient() async throws {
        let redirect = "HTTP/1.1 307 Temporary Redirect\r\nLocation: http://127.0.0.1:1/\r\n" +
            "Content-Length: 0\r\nConnection: close\r\n\r\n"
        let client = HTTPClient(eventLoopGroupProvider: .singleton)
        do {
            var request = URLRequest(url: try localServer(response: redirect))
            request.httpMethod = "POST"
            request.httpBody = Data("test-body".utf8)
            let (_, response) = try await AHCOAuthTransport(client: client).data(for: request)
            #expect(response.statusCode == 307)
            try await client.shutdown()
        } catch {
            try? await client.shutdown()
            throw error
        }
    }

    @Test func streamingPreservesEmptyLinesOverHTTP() async throws {
        let body = "data: one\r\n\r\ndata: two\n\n"
        let response = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let client = HTTPClient(
            eventLoopGroupProvider: .singleton, configuration: .init(redirectConfiguration: .disallow)
        )
        do {
            let url = try localServer(response: response)
            let stream = try await AHCStreamTransport(client: client).stream(for: URLRequest(url: url))
            var lines: [String] = []
            for try await line in stream.lines { lines.append(line) }
            #expect(stream.status == 200)
            #expect(lines == ["data: one", "", "data: two", ""])
            try await client.shutdown()
        } catch {
            try? await client.shutdown()
            throw error
        }
    }
}

private enum LocalServerError: Error { case socket }

/// A single-use loopback server: no external network or third-party service is contacted.
private func localServer(response: String, delay: TimeInterval = 0) throws -> URL {
    #if canImport(Darwin)
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    #else
    let descriptor = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
    #endif
    guard descriptor >= 0 else { throw LocalServerError.socket }
    var address = sockaddr_in()
    #if canImport(Darwin)
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    #endif
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: in_addr_t(0x7f000001).bigEndian)
    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bound == 0, listen(descriptor, 1) == 0 else {
        close(descriptor)
        throw LocalServerError.socket
    }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
    }
    guard named == 0, let url = URL(string: "http://127.0.0.1:\(UInt16(bigEndian: address.sin_port))/") else {
        close(descriptor)
        throw LocalServerError.socket
    }
    DispatchQueue.global().async {
        let connection = accept(descriptor, nil, nil)
        if connection >= 0 {
            var request = [UInt8](repeating: 0, count: 4096)
            _ = recv(connection, &request, request.count, 0)
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            if !response.isEmpty {
                let bytes = Array(response.utf8)
                bytes.withUnsafeBytes { buffer in
                    _ = send(connection, buffer.baseAddress, buffer.count, 0)
                }
            }
            close(connection)
        }
        close(descriptor)
    }
    return url
}
