/// Spaces requests out. Each `wait()` returns once its own slot has come round, and slots are `interval` apart.
///
/// The clock and the sleeper are injected, so tests run without waiting. A slot is reserved before the first
/// suspension, so calls that arrive together still queue in order.
public actor RequestPacer {
    public typealias Now = @Sendable () -> ContinuousClock.Instant
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    private let interval: Duration
    private let now: Now
    private let sleep: Sleep
    private var nextSlot: ContinuousClock.Instant?

    public init(
        interval: Duration,
        now: @escaping Now = { ContinuousClock.now },
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.interval = interval
        self.now = now
        self.sleep = sleep
    }

    public func wait() async throws {
        let current = now()
        let slot = max(current, nextSlot ?? current)
        nextSlot = slot.advanced(by: interval)
        let delay = current.duration(to: slot)
        if delay > .zero {
            try await sleep(delay)
        }
    }
}
