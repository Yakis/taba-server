#if canImport(Network)
import Foundation
import Network

/// One accepted connection on the loopback callback, kept open until the page can be answered.
final class LoopbackConnection: @unchecked Sendable {
    private let connection: NWConnection

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    /// Answers with a plain page and closes the connection.
    func respond(_ message: String) async {
        let body = "<!doctype html><meta charset=\"utf-8\"><title>TABA</title><p>\(message)</p>"
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)"
            + "\r\nConnection: close\r\n\r\n"
        let data = Data((head + body).utf8)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: data, completion: .contentProcessed { _ in
                self.connection.cancel()
                continuation.resume()
            })
        }
    }
}

/// A one-shot listener on 127.0.0.1 for the OAuth callback. It answers any other path with 404 and keeps waiting.
enum LoopbackCallbackServer {
    enum ListenerError: Error {
        case badPort
        case timedOut
        case failed(String)
    }

    static func waitForCallback(
        port: UInt16,
        timeout: Double
    ) async throws -> (target: String, connection: LoopbackConnection) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw ListenerError.badPort }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "taba.chatgpt.loopback")
        return try await withCheckedThrowingContinuation { continuation in
            let gate = Gate(continuation)
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    listener.cancel()
                    gate.fail(ListenerError.failed("\(error)"))
                }
            }
            listener.newConnectionHandler = { connection in
                connection.start(queue: queue)
                receiveRequest(on: connection, listener: listener, gate: gate)
            }
            queue.asyncAfter(deadline: .now() + timeout) {
                listener.cancel()
                gate.fail(ListenerError.timedOut)
            }
            listener.start(queue: queue)
        }
    }

    private static func receiveRequest(on connection: NWConnection, listener: NWListener, gate: Gate) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let target = text.components(separatedBy: " ").dropFirst().first ?? ""
            if target.hasPrefix("/auth/callback") {
                listener.cancel()
                gate.succeed((target: target, connection: LoopbackConnection(connection)))
            } else {
                connection.send(content: Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8),
                                completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    /// Resumes the continuation once. Every call comes from the listener's serial queue.
    final class Gate: @unchecked Sendable {
        private var continuation: CheckedContinuation<(target: String, connection: LoopbackConnection), any Error>?

        init(_ continuation: CheckedContinuation<(target: String, connection: LoopbackConnection), any Error>) {
            self.continuation = continuation
        }

        func succeed(_ value: (target: String, connection: LoopbackConnection)) {
            continuation?.resume(returning: value)
            continuation = nil
        }

        func fail(_ error: any Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
#endif
