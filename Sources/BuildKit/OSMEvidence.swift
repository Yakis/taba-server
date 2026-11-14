import ResponsesKit
import SourcesKit

/// The evidence written for the OpenStreetMap fallback.
enum OSMEvidence {
    /// The evidence event for the OpenStreetMap fallback sweep. `error` is recorded only when the query failed.
    static func sweepEvent(_ report: OverpassPlacesSource.SweepReport, seconds: Double) -> [String: JSONValue] {
        var event: [String: JSONValue] = [
            "event": .string("osmSweep"), "seconds": .number(seconds),
            "outcomes": .array(report.sweeps.map { .object(["kind": .string($0.label),
                                                            "returned": .integer($0.returned)]) })
        ]
        if let error = report.error {
            event["error"] = .string(String(describing: error))
        }
        return event
    }
}
