import Foundation
import ResponsesKit
import Synchronization

/// Replays scripted replies in order and keeps every request it was given. Tests use it in place of the network.
final class ScriptedStreamTransport: StreamTransport, Sendable {
    struct Reply: Sendable {
        let status: Int
        let headers: [String: String]
        let lines: [String]

        init(status: Int, headers: [String: String] = [:], lines: [String]) {
            self.status = status
            self.headers = headers
            self.lines = lines
        }
    }

    enum Failure: Error { case noReplyScripted }

    private let replies: Mutex<[Reply]>
    private let seen = Mutex<[URLRequest]>([])

    init(_ replies: [Reply]) {
        self.replies = Mutex(replies)
    }

    var requests: [URLRequest] { seen.withLock { $0 } }

    func stream(for request: URLRequest) async throws -> StreamResponse {
        seen.withLock { $0.append(request) }
        let reply = try replies.withLock { queue -> Reply in
            guard !queue.isEmpty else { throw Failure.noReplyScripted }
            return queue.removeFirst()
        }
        let (lines, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        for line in reply.lines {
            continuation.yield(line)
        }
        continuation.finish()
        return StreamResponse(status: reply.status, lines: lines, headers: reply.headers)
    }
}

/// Records the waits the code asked for, instead of waiting.
final class SleepRecorder: Sendable {
    private let waits = Mutex<[Duration]>([])

    var all: [Duration] { waits.withLock { $0 } }

    func sleep(_ duration: Duration) async throws {
        waits.withLock { $0.append(duration) }
    }
}

/// The server-sent lines of a stream: one `data:` line per event, each followed by the blank line that ends it.
func sseLines(_ events: [String]) -> [String] {
    events.flatMap { ["data: \($0)", ""] }
}
