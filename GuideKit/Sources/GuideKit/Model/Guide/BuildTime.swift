/// How long the server took to make a guide.
public struct BuildTime: Hashable, Sendable, Codable {
    /// Seconds from the moment the trip was sent until the guide was ready, waiting in the queue included.
    public let totalSeconds: Int
    /// Seconds the server spent working on this guide, without the time it waited behind other guides.
    public let workSeconds: Int

    public init(totalSeconds: Int, workSeconds: Int) {
        self.totalSeconds = totalSeconds
        self.workSeconds = workSeconds
    }
}
