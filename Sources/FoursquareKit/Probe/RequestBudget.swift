/// Counts requests so the probe never exceeds its limit.
public actor RequestBudget {
    public let limit: Int
    private var spent = 0

    public init(limit: Int) {
        self.limit = limit
    }

    public var count: Int {
        spent
    }

    /// True once at least one request has been counted.
    public var hasSent: Bool {
        spent > 0
    }

    public func spend() throws(RequestBudgetError) {
        guard spent < limit else { throw RequestBudgetError(limit: limit) }
        spent += 1
    }
}

public struct RequestBudgetError: Error, Equatable {
    public let limit: Int

    public init(limit: Int) {
        self.limit = limit
    }
}
