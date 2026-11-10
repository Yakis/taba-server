import Foundation

/// Lets one caller at a time run its body, in the order they arrived. A caller cancelled while it waits leaves the
/// queue without running its body. Share one gate per outside service, so its requests never overlap across jobs.
public actor SerialGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var held = false
    private var waiters: [Waiter] = []
    /// Cancellations that arrived before their waiter was queued, or after it had already been let through.
    private var cancelled: Set<UUID> = []

    public init() {}

    public func run<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        return try await body()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        guard held else {
            held = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                enqueue(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
        cancelled.remove(id)
    }

    private func enqueue(_ waiter: Waiter) {
        if cancelled.remove(waiter.id) != nil {
            waiter.continuation.resume(throwing: CancellationError())
            return
        }
        waiters.append(waiter)
    }

    private func cancelWaiter(_ id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            waiters.remove(at: index).continuation.resume(throwing: CancellationError())
        } else {
            cancelled.insert(id)
        }
    }

    /// Hands the gate to the next waiter, which keeps it held; otherwise the gate is free.
    private func release() {
        guard !waiters.isEmpty else {
            held = false
            return
        }
        waiters.removeFirst().continuation.resume()
    }
}
