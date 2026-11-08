import Foundation
import GuideKit

/// Weather from Open-Meteo.
///
/// When every date from `start` to `end` lies between today and 15 days ahead, the forecast API is used, with a rain
/// chance for each day. Otherwise each date is taken from the same date in each of the last three years, from the
/// archive API. Those days are typical, not forecasts. Their rain chance is the share of the three years' days with at
/// least 1.0 mm of precipitation, and their temperatures are the averages over those years.
public struct OpenMeteoWeatherSource: Sendable {
    public static let forecastHorizonDays = 15
    public static let maximumDays = 366
    /// How many past years the typical days are taken from.
    public static let typicalYears = 3
    /// A day counts as rainy from this much precipitation, in millimetres.
    public static let rainyDayMillimetres = 1.0
    public static let typicalSummary = "typical (last 3 years)"

    private static let forecastVariables = [
        "weather_code", "temperature_2m_max", "temperature_2m_min", "precipitation_probability_max"
    ]
    private static let archiveVariables = ["temperature_2m_max", "temperature_2m_min", "precipitation_sum"]

    private enum Service {
        case forecast
        case archive

        var host: String {
            switch self {
            case .forecast: return "api.open-meteo.com"
            case .archive: return "archive-api.open-meteo.com"
            }
        }

        var path: String {
            switch self {
            case .forecast: return "/v1/forecast"
            case .archive: return "/v1/archive"
            }
        }
    }

    private let fetcher: any HTTPFetching
    private let pacer: RequestPacer

    /// The pacer spaces out every request this source makes, so archive years are fetched one after another.
    public init(
        fetcher: any HTTPFetching,
        interval: Duration = .seconds(1),
        now: @escaping RequestPacer.Now = { ContinuousClock.now },
        sleep: @escaping RequestPacer.Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.fetcher = fetcher
        self.pacer = RequestPacer(interval: interval, now: now, sleep: sleep)
    }

    /// The outlook for `start` through `end`, inclusive. `today` is the local date at the place.
    public func outlook(
        at coordinate: Coordinate,
        from start: LocalDate,
        to end: LocalDate,
        today: LocalDate
    ) async throws -> WeatherOutlook {
        guard start <= end else {
            throw SourcesError.invalidRequest("the weather range ends before it starts")
        }
        guard let dates = Self.dates(from: start, to: end) else {
            throw SourcesError.invalidRequest("the weather range is too long")
        }
        guard let horizon = today.adding(days: Self.forecastHorizonDays) else {
            throw SourcesError.invalidRequest("the forecast horizon is out of range")
        }
        if start >= today && end <= horizon {
            return try await forecast(at: coordinate, from: start, to: end, dates: dates)
        }
        return try await typical(at: coordinate, dates: dates)
    }

    private func forecast(
        at coordinate: Coordinate,
        from start: LocalDate,
        to end: LocalDate,
        dates: [LocalDate]
    ) async throws -> WeatherOutlook {
        let decoded = try await fetch(.forecast, at: coordinate, from: start, to: end, daily: Self.forecastVariables)
        guard let zone = decoded.timezone, let daily = decoded.daily, daily.time.count == dates.count else {
            throw SourcesError.malformed("the forecast does not cover the requested days")
        }
        let days = dates.indices.map { index in
            DayWeather(
                date: dates[index],
                rainChance: Self.percentage(Self.value(daily.precipitationProbabilityMax, at: index)),
                tempMax: Self.value(daily.temperatureMax, at: index),
                tempMin: Self.value(daily.temperatureMin, at: index),
                summary: WeatherSummary.text(for: Self.value(daily.weatherCode, at: index).map { Int($0) }),
                isForecast: true
            )
        }
        return WeatherOutlook(timeZoneId: zone, days: days)
    }

    /// The same dates in each of the last `typicalYears` years, summarised day by day.
    private func typical(at coordinate: Coordinate, dates: [LocalDate]) async throws -> WeatherOutlook {
        guard let first = dates.first else {
            throw SourcesError.invalidRequest("the weather range is empty")
        }
        var samples: [[ArchiveSample]] = Array(repeating: [], count: dates.count)
        var zone: String?
        for yearsBack in 1...Self.typicalYears {
            guard let start = Self.shift(first, years: -yearsBack),
                  let end = start.adding(days: dates.count - 1)
            else {
                throw SourcesError.invalidRequest("the archive dates are out of range")
            }
            let decoded = try await fetch(.archive, at: coordinate, from: start, to: end, daily: Self.archiveVariables)
            guard let timezone = decoded.timezone, let daily = decoded.daily, daily.time.count == dates.count else {
                throw SourcesError.malformed("the archive does not cover the requested days")
            }
            zone = zone ?? timezone
            for index in dates.indices {
                samples[index].append(ArchiveSample(
                    precipitation: Self.value(daily.precipitationSum, at: index),
                    tempMax: Self.value(daily.temperatureMax, at: index),
                    tempMin: Self.value(daily.temperatureMin, at: index)
                ))
            }
        }
        guard let timeZoneId = zone else {
            throw SourcesError.malformed("the archive gave no time zone")
        }
        let days = dates.indices.map { index in Self.typicalDay(dates[index], samples[index]) }
        return WeatherOutlook(timeZoneId: timeZoneId, days: days)
    }

    /// One year's values for one calendar date.
    struct ArchiveSample: Equatable {
        let precipitation: Double?
        let tempMax: Double?
        let tempMin: Double?
    }

    /// The typical day from one date's samples. The rain chance uses the days that have a precipitation value.
    static func typicalDay(_ date: LocalDate, _ samples: [ArchiveSample]) -> DayWeather {
        let amounts = samples.compactMap(\.precipitation)
        let rainyDays = amounts.filter { $0 >= rainyDayMillimetres }.count
        let rainChance: Int? = amounts.isEmpty
            ? nil
            : Int((Double(rainyDays) / Double(amounts.count) * 100).rounded())
        return DayWeather(
            date: date,
            rainChance: rainChance,
            tempMax: mean(samples.compactMap(\.tempMax)),
            tempMin: mean(samples.compactMap(\.tempMin)),
            summary: typicalSummary,
            isForecast: false
        )
    }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func fetch(
        _ service: Service,
        at coordinate: Coordinate,
        from start: LocalDate,
        to end: LocalDate,
        daily: [String]
    ) async throws -> OpenMeteoResponse {
        let built = Self.makeRequest(service, coordinate: coordinate, start: start, end: end, daily: daily)
        guard let request = built else {
            throw SourcesError.invalidRequest("could not build the weather request")
        }
        try await pacer.wait()
        let response = try await fetcher.send(request)
        guard response.isSuccess else {
            throw SourcesError.http(status: response.status)
        }
        do {
            return try JSONDecoder().decode(OpenMeteoResponse.self, from: response.body)
        } catch {
            throw SourcesError.malformed("the Open-Meteo response")
        }
    }

    private static func makeRequest(
        _ service: Service,
        coordinate: Coordinate,
        start: LocalDate,
        end: LocalDate,
        daily: [String]
    ) -> URLRequest? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = service.host
        components.path = service.path
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(name: "daily", value: daily.joined(separator: ",")),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: start.description),
            URLQueryItem(name: "end_date", value: end.description)
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(TABAClient.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func value<Element>(_ values: [Element?]?, at index: Int) -> Element? {
        guard let values, values.indices.contains(index) else { return nil }
        return values[index]
    }

    /// A rain chance from a percentage value. Values outside 0 to 100 are not used.
    private static func percentage(_ value: Double?) -> Int? {
        guard let value else { return nil }
        let rounded = Int(value.rounded())
        return (0...100).contains(rounded) ? rounded : nil
    }

    static func dates(from start: LocalDate, to end: LocalDate) -> [LocalDate]? {
        var result: [LocalDate] = []
        var day = start
        while day <= end {
            result.append(day)
            if result.count > maximumDays {
                return nil
            }
            guard let next = day.adding(days: 1) else { return nil }
            day = next
        }
        return result
    }

    /// The same month and day, `years` years away. 29 February becomes 28 February when the year has none.
    static func shift(_ date: LocalDate, years: Int) -> LocalDate? {
        let year = date.year + years
        return LocalDate(year: year, month: date.month, day: date.day)
            ?? LocalDate(year: year, month: date.month, day: 28)
    }
}

/// The Open-Meteo JSON for daily values: a top-level `timezone` and a `daily` object with parallel arrays. Values
/// can be null.
struct OpenMeteoResponse: Decodable {
    let timezone: String?
    let daily: OpenMeteoDaily?
}

/// The daily arrays. Each is parallel to `time`, and a missing requested variable reads as nil.
struct OpenMeteoDaily: Decodable {
    let time: [String]
    let weatherCode: [Double?]?
    let temperatureMax: [Double?]?
    let temperatureMin: [Double?]?
    let precipitationProbabilityMax: [Double?]?
    let precipitationSum: [Double?]?

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperatureMax = "temperature_2m_max"
        case temperatureMin = "temperature_2m_min"
        case precipitationProbabilityMax = "precipitation_probability_max"
        case precipitationSum = "precipitation_sum"
    }
}
