import GuideKit

/// The hard rules: contradictions, structure, the plan checker's findings, transit timing and the stay.
public struct ConstraintsScore: Codable, Sendable, Equatable {
    /// Words in the guide that contradict its facts (`Guide.contradictions`).
    public let contradictions: Int
    public let structureValid: Bool
    /// What `validateStructure` says is wrong, when it fails.
    public let structureError: String?
    /// Plan checker findings by severity. Every severity is listed, even when it is 0.
    public let findingsBySeverity: [String: Int]
    /// Plan checker findings by kind. Only kinds that occur are listed.
    public let findingsByKind: [String: Int]
    /// Stops that start before the traveller arrives (`beforeArrival`).
    public let stopsBeforeArrival: Int
    /// Stops that run past the time the traveller must leave for the train (`missedDeparture`).
    public let stopsAfterDeparture: Int
    /// "booked", "unknown" or "notNeeded": whether the travellers have a stay the guide knows about.
    public let stayArrangement: String
    /// The place distances are measured from, when there is one.
    public let base: BaseScore?

    public struct BaseScore: Codable, Sendable, Equatable {
        /// "stay", or "arrival:" and the travel mode, such as "arrival:train".
        public let kind: String
        public let name: String
    }
}

extension ConstraintsScore {
    static func make(_ context: GuideScoreContext) -> ConstraintsScore {
        let guide = context.guide
        let findings = context.findings
        var bySeverity = Dictionary(uniqueKeysWithValues: IssueSeverity.allCases.map { ($0.rawValue, 0) })
        for finding in findings {
            bySeverity[finding.severity.rawValue, default: 0] += 1
        }
        let byKind = Dictionary(grouping: findings, by: { $0.kind.rawValue }).mapValues(\.count)
        let structure = structureError(guide)
        return ConstraintsScore(
            contradictions: guide.contradictions.count,
            structureValid: structure == nil,
            structureError: structure,
            findingsBySeverity: bySeverity,
            findingsByKind: byKind,
            stopsBeforeArrival: byKind[IssueKind.beforeArrival.rawValue] ?? 0,
            stopsAfterDeparture: byKind[IssueKind.missedDeparture.rawValue] ?? 0,
            stayArrangement: guide.stayArrangement.rawValue,
            base: guide.base.map { BaseScore(kind: kindName($0.kind), name: $0.place.name) }
        )
    }

    /// The error text from `validateStructure`, or nil when the structure is valid.
    private static func structureError(_ guide: Guide) -> String? {
        do {
            try guide.validateStructure()
            return nil
        } catch {
            return String(describing: error)
        }
    }

    private static func kindName(_ kind: GuideBase.Kind) -> String {
        switch kind {
        case .stay: "stay"
        case .arrival(let mode): "arrival:\(mode.rawValue)"
        }
    }
}
