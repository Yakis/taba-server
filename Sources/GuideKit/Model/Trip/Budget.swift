/// Spending limits. `stayMaxPerNight` is in whole units of `currencyCode`.
public struct Budget: Hashable, Sendable, Codable {
    public let currencyCode: String
    public let stayMaxPerNight: Int
    public let dailySpend: DailySpend

    public init(currencyCode: String, stayMaxPerNight: Int, dailySpend: DailySpend) {
        self.currencyCode = currencyCode
        self.stayMaxPerNight = stayMaxPerNight
        self.dailySpend = dailySpend
    }
}
