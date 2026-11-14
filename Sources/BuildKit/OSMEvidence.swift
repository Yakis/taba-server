import ResponsesKit
import SourcesKit

/// The evidence written for the OpenStreetMap place sources.
enum OSMEvidence {
    /// The evidence event for the Overpass sweep. `error` is recorded only when the query failed.
    static func sweepEvent(_ report: OSMSweep.Report, seconds: Double) -> [String: JSONValue] {
        event(named: "osmSweep", report, seconds: seconds)
    }

    /// The evidence event for the Nominatim sweep. `error` is recorded only when a phrase failed.
    static func nominatimSweepEvent(_ report: OSMSweep.Report, seconds: Double) -> [String: JSONValue] {
        event(named: "nominatimSweep", report, seconds: seconds)
    }

    private static func event(named name: String, _ report: OSMSweep.Report, seconds: Double) -> [String: JSONValue] {
        var event: [String: JSONValue] = [
            "event": .string(name), "seconds": .number(seconds),
            "outcomes": .array(report.sweeps.map { .object(["kind": .string($0.label),
                                                            "returned": .integer($0.returned)]) })
        ]
        if let error = report.error {
            event["error"] = .string(String(describing: error))
        }
        return event
    }
}
