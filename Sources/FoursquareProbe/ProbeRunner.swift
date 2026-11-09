import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FoursquareKit
import GuideKit

/// Runs the probe: one search per fixture place, one sweep per category, then details for matched places if asked.
/// Every request goes through the budget and waits 200 ms after the previous one. Only response bodies are written to
/// disk, never headers, and the key is never printed.
struct ProbeRunner {
    let builder: FoursquareRequestBuilder
    let session: URLSession
    let budget: RequestBudget
    let rawDirectory: URL

    enum Outcome {
        case succeeded(Data)
        case failed(ProbeError)
    }

    func run(guide: Guide, options: ProbeOptions, fixtureName: String) async throws -> ProbeReport {
        let targets = ProbePlan.searchTargets(in: guide)
        let radius = ProbePlan.searchRadiusMetres
        print("Searching \(targets.count) places within \(radius) m, limit \(ProbePlan.searchLimit).")
        var places: [PlaceProbe] = []
        for (index, target) in targets.enumerated() {
            print("[\(index + 1)/\(targets.count)] \(target.fixtureId) \(target.name): searching")
            let probe = await search(target)
            places.append(probe)
            print("  " + describe(probe))
        }

        let centre = guide.trip.destination.centre
        var sweeps: [SweepResult] = []
        for (index, sweep) in CategorySweeps.all.enumerated() {
            print("[sweep \(index + 1)/\(CategorySweeps.all.count)] \(sweep.label): \(sweep.categoryName)")
            let result = await sweepCategory(sweep, around: centre)
            sweeps.append(result)
            let line = result.error.map { "  error: \(describeError($0))" } ?? "  \(result.resultCount) results"
            print(line)
        }

        var premium: [PremiumResult] = []
        var premiumPlanned = 0
        if options.premium {
            let matched = places.filter { $0.matched && $0.topHit != nil }
            premiumPlanned = min(matched.count, ProbePlan.premiumLimit)
            let fields = ProbePlan.premiumFields.joined(separator: ", ")
            print("Premium detail requests planned: \(premiumPlanned) (cap \(ProbePlan.premiumLimit)), "
                + "for fields \(fields). Each may cost a premium call.")
            for probe in matched.prefix(ProbePlan.premiumLimit) {
                guard let hit = probe.topHit else { continue }
                print("[premium] \(probe.fixtureId): \(hit.name)")
                premium.append(await details(fixtureId: probe.fixtureId, fsqPlaceId: hit.fsqPlaceId))
            }
        }

        return ProbeReport(
            generatedAt: Date.now.formatted(.iso8601),
            fixtureName: fixtureName,
            premiumRequested: options.premium,
            requestsMade: await budget.count,
            places: places,
            sweeps: sweeps,
            premiumPlanned: premiumPlanned,
            premium: premium
        )
    }

    private func search(_ target: SearchTarget) async -> PlaceProbe {
        let parameters = SearchParameters(
            query: target.name,
            latitude: target.coordinate.latitude,
            longitude: target.coordinate.longitude,
            radius: ProbePlan.searchRadiusMetres,
            categoryIds: [],
            limit: ProbePlan.searchLimit
        )
        switch await send(builder.search(parameters), rawName: "search-\(SafeName.make(target.fixtureId))") {
        case .succeeded(let data):
            guard let decoded = try? JSONDecoder().decode(FoursquareSearchResponse.self, from: data) else {
                return failure(target, unreadable)
            }
            return ProbePlan.evaluate(target: target, hits: decoded.results)
        case .failed(let error):
            return failure(target, error)
        }
    }

    private func failure(_ target: SearchTarget, _ error: ProbeError) -> PlaceProbe {
        PlaceProbe(
            fixtureId: target.fixtureId,
            fixtureName: target.name,
            fixtureKind: target.kind,
            hitCount: 0,
            topHit: nil,
            matched: false,
            error: error
        )
    }

    private func sweepCategory(_ sweep: CategorySweep, around centre: Coordinate) async -> SweepResult {
        let parameters = SearchParameters(
            query: nil,
            latitude: centre.latitude,
            longitude: centre.longitude,
            radius: ProbePlan.sweepRadiusMetres,
            categoryIds: [sweep.categoryId],
            limit: ProbePlan.sweepLimit
        )
        switch await send(builder.search(parameters), rawName: "sweep-\(SafeName.make(sweep.label))") {
        case .succeeded(let data):
            guard let decoded = try? JSONDecoder().decode(FoursquareSearchResponse.self, from: data) else {
                return SweepResult(sweep: sweep, resultCount: 0, topNames: [], error: unreadable)
            }
            let names = decoded.results.prefix(10).map(\.name)
            return SweepResult(sweep: sweep, resultCount: decoded.results.count, topNames: names, error: nil)
        case .failed(let error):
            return SweepResult(sweep: sweep, resultCount: 0, topNames: [], error: error)
        }
    }

    private func details(fixtureId: String, fsqPlaceId: String) async -> PremiumResult {
        let request = builder.details(fsqPlaceId: fsqPlaceId, fields: ProbePlan.premiumFields)
        switch await send(request, rawName: "details-\(SafeName.make(fixtureId))") {
        case .succeeded(let data):
            guard let place = try? JSONDecoder().decode(FoursquarePlace.self, from: data) else {
                return PremiumResult.failed(fixtureId: fixtureId, fsqPlaceId: fsqPlaceId, error: unreadable)
            }
            let regular = place.hours?.regular ?? []
            let complete = regular.filter { (1...7).contains($0.day) && $0.open.count == 4 && $0.close.count == 4 }
            return PremiumResult(
                fixtureId: fixtureId,
                fsqPlaceId: fsqPlaceId,
                regularEntries: regular.count,
                entriesWithAllFields: complete.count,
                display: place.hours?.display,
                openNow: place.hours?.openNow,
                rating: place.rating,
                error: nil
            )
        case .failed(let error):
            return PremiumResult.failed(fixtureId: fixtureId, fsqPlaceId: fsqPlaceId, error: error)
        }
    }

    private var unreadable: ProbeError {
        ProbeError(status: nil, message: nil, detail: "response could not be read")
    }

    /// Sends one request, waiting first if one has already gone out. Writes the body to raw/ whatever the status.
    private func send(_ request: URLRequest, rawName: String) async -> Outcome {
        if await budget.hasSent {
            try? await Task.sleep(for: .milliseconds(ProbePlan.pauseMilliseconds))
        }
        do {
            try await budget.spend()
        } catch {
            let detail = "not sent: the \(ProbePlan.requestLimit)-request limit was reached"
            return .failed(ProbeError(status: nil, message: nil, detail: detail))
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed(ProbeError(status: nil, message: nil, detail: "response was not HTTP"))
            }
            writeRaw(data, named: rawName)
            if (200..<300).contains(http.statusCode) {
                return .succeeded(data)
            }
            let body = try? JSONDecoder().decode(FoursquareErrorBody.self, from: data)
            let detail = "HTTP \(http.statusCode)"
            return .failed(ProbeError(status: http.statusCode, message: body?.message, detail: detail))
        } catch {
            let detail = "network error: \(error.localizedDescription)"
            return .failed(ProbeError(status: nil, message: nil, detail: detail))
        }
    }

    private func writeRaw(_ data: Data, named name: String) {
        let url = rawDirectory.appendingPathComponent("\(name).json")
        try? data.write(to: url)
    }

    private func describe(_ probe: PlaceProbe) -> String {
        if let error = probe.error {
            return "error: \(describeError(error))"
        }
        guard let hit = probe.topHit else {
            return "no results"
        }
        let distance = hit.distanceMetres.map { "\($0) m" } ?? "distance unknown"
        return (probe.matched ? "matched" : "no match") + ": \(hit.name), \(distance)"
    }

    private func describeError(_ error: ProbeError) -> String {
        guard let message = error.message else {
            return error.detail
        }
        return "\(error.detail) - \(message)"
    }
}

extension PremiumResult {
    static func failed(fixtureId: String, fsqPlaceId: String, error: ProbeError) -> PremiumResult {
        PremiumResult(
            fixtureId: fixtureId,
            fsqPlaceId: fsqPlaceId,
            regularEntries: 0,
            entriesWithAllFields: 0,
            display: nil,
            openNow: nil,
            rating: nil,
            error: error
        )
    }
}
