import Foundation
import GuideKit

/// Everything the Markdown report shows, gathered by the runner.
public struct ProbeReport: Sendable {
    public let generatedAt: String
    public let fixtureName: String
    public let premiumRequested: Bool
    public let requestsMade: Int
    public let places: [PlaceProbe]
    public let sweeps: [SweepResult]
    public let premiumPlanned: Int
    public let premium: [PremiumResult]

    public init(
        generatedAt: String,
        fixtureName: String,
        premiumRequested: Bool,
        requestsMade: Int,
        places: [PlaceProbe],
        sweeps: [SweepResult],
        premiumPlanned: Int,
        premium: [PremiumResult]
    ) {
        self.generatedAt = generatedAt
        self.fixtureName = fixtureName
        self.premiumRequested = premiumRequested
        self.requestsMade = requestsMade
        self.places = places
        self.sweeps = sweeps
        self.premiumPlanned = premiumPlanned
        self.premium = premium
    }
}

/// Writes the probe report as Markdown. Pure: it only formats what the runner collected.
public enum ReportWriter {
    public static func markdown(_ report: ProbeReport) -> String {
        var lines: [String] = []
        lines.append("# Foursquare probe report")
        lines.append("")
        lines.append("- Generated: \(report.generatedAt)")
        lines.append("- Fixture: \(report.fixtureName)")
        lines.append("- Premium fields requested: \(report.premiumRequested ? "yes" : "no")")
        lines.append("- Requests made: \(report.requestsMade) of \(ProbePlan.requestLimit)")
        lines.append("")
        appendMatchRate(report, to: &lines)
        appendPlaces(report, to: &lines)
        appendSweeps(report, to: &lines)
        appendPremium(report, to: &lines)
        appendErrors(report, to: &lines)
        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendMatchRate(_ report: ProbeReport, to lines: inout [String]) {
        lines.append("## Match rate")
        lines.append("")
        let searched = report.places.count
        let matched = report.places.filter(\.matched).count
        if searched == 0 {
            lines.append("No places were searched.")
        } else {
            let percent = Int((Double(matched) / Double(searched) * 100).rounded())
            let threshold = Int(ProbePlan.matchDistanceMetres)
            lines.append("Matched \(matched) of \(searched) searched places (\(percent)%). "
                + "A match needs the top hit's name to match and to lie within \(threshold) m.")
        }
        lines.append("")
    }

    private static func appendPlaces(_ report: ProbeReport, to lines: inout [String]) {
        lines.append("## Places")
        lines.append("")
        lines.append("| Fixture place | Kind | Matched | Top hit | Distance (m) | Foursquare id "
            + "| Categories | Fields returned | Hits |")
        lines.append("|---|---|---|---|---|---|---|---|---|")
        for place in report.places {
            lines.append(placeRow(place))
        }
        lines.append("")
    }

    private static func placeRow(_ place: PlaceProbe) -> String {
        let hit = place.topHit
        let name = "\(place.fixtureName) (`\(place.fixtureId)`)"
        let matchText = place.matched ? "yes" : (place.error == nil ? "no" : "error")
        let distance = hit?.distanceMetres.map(String.init) ?? "-"
        let categories = hit.map { $0.categoryNames.joined(separator: ", ") } ?? "-"
        let fields = hit.map { $0.fieldsReturned.joined(separator: ", ") } ?? "-"
        let cells: [String] = [
            name,
            place.fixtureKind.rawValue,
            matchText,
            hit?.name ?? "-",
            distance,
            hit?.fsqPlaceId ?? "-",
            categories,
            fields,
            String(place.hitCount)
        ]
        return row(cells)
    }

    private static func appendSweeps(_ report: ProbeReport, to lines: inout [String]) {
        lines.append("## Category sweep (\(ProbePlan.sweepRadiusMetres) m around the destination centre)")
        lines.append("")
        lines.append("| Category | Id | Results | Top 10 names |")
        lines.append("|---|---|---|---|")
        for sweep in report.sweeps {
            let count = sweep.error == nil ? String(sweep.resultCount) : "error"
            let names = sweep.topNames.prefix(10).joined(separator: "; ")
            let cells: [String] = [sweep.sweep.label, sweep.sweep.categoryId, count, names.isEmpty ? "-" : names]
            lines.append(row(cells))
        }
        lines.append("")
    }

    private static func appendPremium(_ report: ProbeReport, to lines: inout [String]) {
        lines.append("## Hours and rating (premium)")
        lines.append("")
        guard report.premiumRequested else {
            lines.append("Not requested. Run with `--premium` to fetch hours and rating for matched places.")
            lines.append("")
            return
        }
        lines.append("Premium detail requests planned: \(report.premiumPlanned) (cap \(ProbePlan.premiumLimit)).")
        let withHours = report.premium.filter { $0.regularEntries > 0 }.count
        lines.append("Places with regular hours: \(withHours) of \(report.premium.count).")
        lines.append("")
        lines.append("| Fixture place | Foursquare id | Regular entries | Complete entries | Open now "
            + "| Display | Rating | Error |")
        lines.append("|---|---|---|---|---|---|---|---|")
        for result in report.premium {
            lines.append(premiumRow(result))
        }
        lines.append("")
    }

    private static func premiumRow(_ result: PremiumResult) -> String {
        let openNow = result.openNow.map { $0 ? "yes" : "no" } ?? "-"
        let rating = result.rating.map { String($0) } ?? "-"
        let error = result.error.map(describe) ?? "-"
        let cells: [String] = [
            result.fixtureId,
            result.fsqPlaceId,
            String(result.regularEntries),
            String(result.entriesWithAllFields),
            openNow,
            result.display ?? "-",
            rating,
            error
        ]
        return row(cells)
    }

    private static func appendErrors(_ report: ProbeReport, to lines: inout [String]) {
        lines.append("## Errors")
        lines.append("")
        var rows: [String] = []
        for place in report.places {
            if let error = place.error {
                rows.append(row(["search: \(place.fixtureId)", status(error), message(error)]))
            }
        }
        for sweep in report.sweeps {
            if let error = sweep.error {
                rows.append(row(["sweep: \(sweep.sweep.label)", status(error), message(error)]))
            }
        }
        for result in report.premium {
            if let error = result.error {
                rows.append(row(["details: \(result.fixtureId)", status(error), message(error)]))
            }
        }
        if rows.isEmpty {
            lines.append("None.")
        } else {
            lines.append("| Request | HTTP status | Foursquare message |")
            lines.append("|---|---|---|")
            lines.append(contentsOf: rows)
        }
        lines.append("")
    }

    private static func status(_ error: ProbeError) -> String {
        error.status.map(String.init) ?? "none (\(error.detail))"
    }

    private static func message(_ error: ProbeError) -> String {
        error.message ?? "-"
    }

    private static func describe(_ error: ProbeError) -> String {
        guard let status = error.status else {
            return error.detail
        }
        return "HTTP \(status): \(message(error))"
    }

    private static func row(_ cells: [String]) -> String {
        "| " + cells.map(escape).joined(separator: " | ") + " |"
    }

    /// Keeps a table cell on one line and stops it from ending the row.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}
