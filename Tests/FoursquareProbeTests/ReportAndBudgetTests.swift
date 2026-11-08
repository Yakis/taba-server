import FoursquareKit
import GuideKit
import Testing

struct ReportWriterTests {
    private func report(premium: Bool, withError: Bool) -> ProbeReport {
        let kind = PlaceKind.pub
        let matched = PlaceProbe(
            fixtureId: "osm:node/1",
            fixtureName: "The Abbotsford",
            fixtureKind: kind,
            hitCount: 1,
            topHit: TopHit(
                fsqPlaceId: "4b5f2d1e",
                name: "The Abbotsford | Rose Street",
                distanceMetres: 12,
                categoryNames: ["Pubs"],
                fieldsReturned: ["latitude", "categories"]
            ),
            matched: true,
            error: nil
        )
        let failed = PlaceProbe(
            fixtureId: "osm:node/2",
            fixtureName: "Oink",
            fixtureKind: .restaurant,
            hitCount: 0,
            topHit: nil,
            matched: false,
            error: withError ? ProbeError(status: 401, message: "Invalid credentials", detail: "HTTP 401") : nil
        )
        return ProbeReport(
            generatedAt: "2026-11-08T12:00:00Z",
            fixtureName: "edinburgh-mock.json",
            premiumRequested: premium,
            requestsMade: 2,
            places: [matched, failed],
            sweeps: [],
            premiumPlanned: 0,
            premium: []
        )
    }

    @Test func reportHasTheMatchRateAndTheTable() {
        let text = ReportWriter.markdown(report(premium: false, withError: false))
        #expect(text.contains("# Foursquare probe report"))
        #expect(text.contains("Matched 1 of 2 searched places (50%)"))
        #expect(text.contains("The Abbotsford \\| Rose Street"))
        #expect(text.contains("Premium fields requested: no"))
        #expect(text.contains("Not requested. Run with `--premium`"))
    }

    @Test func errorsShowTheHTTPStatusAndFoursquareMessage() {
        let text = ReportWriter.markdown(report(premium: false, withError: true))
        #expect(text.contains("| search: osm:node/2 | 401 | Invalid credentials |"))
    }

    @Test func noErrorsSaysNone() {
        #expect(ReportWriter.markdown(report(premium: false, withError: false)).contains("None."))
    }
}

struct RequestBudgetTests {
    @Test func stopsAtTheLimit() async throws {
        let budget = RequestBudget(limit: 2)
        try await budget.spend()
        try await budget.spend()
        #expect(await budget.count == 2)
        do {
            try await budget.spend()
            Issue.record("the third request should have been refused")
        } catch {
            #expect(error == RequestBudgetError(limit: 2))
        }
        #expect(await budget.count == 2)
    }

    @Test func safeNamesKeepOnlyFileSafeCharacters() {
        #expect(SafeName.make("osm:node/123") == "osm-node-123")
        #expect(SafeName.make("Cafés, Coffee") == "Cafés--Coffee")
    }
}
