import BuildKit
import Foundation
import GuideKit
import PipelineKit
import ResponsesKit
import SourcesKit

typealias Prepared = BuildKit.Prepared

enum SourcePreparation {
    static func input(_ options: Options, seed: Guide?) -> SourceInput {
        SourceInput(destination: options.destination, from: options.from, to: options.to,
                    stay: options.stay, facts: seed, luggage: options.luggage)
    }

    static func prepare(_ options: Options, fetcher: CappedFetcher, key: String,
                        record: RunRecord) async throws -> Prepared {
        let seed = try options.facts.map {
            try JSONDecoder().decode(Guide.self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
        }
        print("Preparing sources...")
        let result = try await BuildKit.SourcePreparation.prepare(input(options, seed: seed), fetcher: fetcher,
            key: key, record: SourceRecord { await record.append($0) })
        try await record.check()
        return result
    }

    // swiftlint:disable:next function_parameter_count
    static func assumptions(_ options: Options, seed: Guide?, country: String, today: LocalDate,
                            luggageFound: Bool, sources: inout [Source]) -> [Fact] {
        BuildKit.SourcePreparation.assumptions(input(options, seed: seed), seed: seed, country: country,
                                                today: today, luggageFound: luggageFound, sources: &sources)
    }

    // swiftlint:disable:next function_parameter_count
    static func baseFacts(_ options: Options, seed: Guide?, centre: Coordinate, country: String,
                          timeZone: String, geocoder: NominatimGeocoder) async throws -> TripFacts {
        try await BuildKit.SourcePreparation.baseFacts(input(options, seed: seed), seed: seed, centre: centre,
                                                       country: country, timeZone: timeZone, geocoder: geocoder)
    }

    static func currency(for country: String) -> String { BuildKit.SourcePreparation.currency(for: country) }
}
