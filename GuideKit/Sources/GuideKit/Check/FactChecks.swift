extension PlanChecker {
    /// Words or stops that contradict what the traveller arranged (see `Guide.contradictions`). Each is an error, so
    /// the planner must fix it and a finished guide that still has one is rejected.
    func contradictionFindings(_ context: CheckContext) -> [Finding] {
        let guide = context.guide
        let stopsById = Dictionary(guide.days.flatMap { day in day.stops.map { ($0.id, (day.date, $0)) } },
                                   uniquingKeysWith: { first, _ in first })
        return guide.contradictions.map { contradiction in
            let stopId = Self.stopId(in: contradiction.path)
            let located = stopId.flatMap { stopsById[$0] }
            let message = "'\(contradiction.words)' in \(contradiction.path): \(contradiction.reason)"
            return Finding(.error, .stayContradiction, date: located?.0 ?? guide.trip.dates.start,
                           stop: located?.1, message: message)
        }
    }

    /// The kinds each pick list may hold. A market or food hall fits eating and groceries; photos are outdoor places.
    public static let listKinds: [ListKey: Set<PlaceKind>] = [
        .eat: [.market, .foodHall, .cafe, .restaurant, .pub],
        .drink: [.pub, .bar, .cafe, .venue, .foodHall],
        .photos: [.viewpoint, .street, .neighbourhood, .landmark, .market, .other],
        .groceries: [.grocery, .market, .foodHall, .shop]
    ]

    /// Places in a pick list whose kind does not fit the list.
    func listFindings(_ context: CheckContext) -> [Finding] {
        let guide = context.guide
        var findings: [Finding] = []
        for list in guide.lists {
            guard let key = list.key, let allowed = Self.listKinds[key] else { continue }
            for id in list.placeIds {
                guard let place = guide.places[id], !allowed.contains(place.kind) else { continue }
                let message = "\(place.name) is a \(place.kind.rawValue), which does not belong in the "
                    + "\(key.rawValue) list."
                findings.append(Finding(.warning, .listKindMismatch, date: guide.trip.dates.start, message: message))
            }
        }
        return findings
    }

    /// The stop id in a path such as "stops[d1-s3].body", or nil.
    private static func stopId(in path: String) -> String? {
        guard path.hasPrefix("stops["), let close = path.firstIndex(of: "]") else { return nil }
        return String(path[path.index(path.startIndex, offsetBy: 6)..<close])
    }
}
