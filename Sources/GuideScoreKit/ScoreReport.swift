import Foundation

/// Plain-text reports for people: one score, one comparison, and the summary table. Short and aligned, with the
/// things to look at listed last under "Attention".
public enum ScoreReport {
    private static let labelWidth = 24

    public static func text(_ score: GuideScore) -> String {
        var lines = ["Guide \(score.guideId)", ""]
        lines += section("Constraints", constraintLines(score.constraints))
        lines += section("Interests (\(score.interests.source.rawValue))", interestLines(score.interests))
        lines += section("Pace (\(score.pace.pace))", paceLines(score.pace))
        let ceiling = score.spend.ceiling.map(String.init) ?? "none"
        lines += section("Spend (\(score.spend.dailySpend), ceiling \(ceiling))", spendLines(score.spend))
        lines += section("Feasibility", feasibilityLines(score.feasibility))
        lines += section("Content", contentLines(score.content))
        lines += section("Consistency", consistencyLines(score.consistency))
        let flags = attention(score).map { "  - " + $0 }
        lines += section("Attention", flags.isEmpty ? ["  none"] : flags)
        return lines.joined(separator: "\n")
    }

    /// The things to look at, one sentence each. Empty when nothing needs a look.
    public static func attention(_ score: GuideScore) -> [String] {
        constraintFlags(score) + interestFlags(score.interests) + paceFlags(score.pace) + spendFlags(score.spend)
            + feasibilityFlags(score.feasibility) + contentFlags(score.content) + consistencyFlags(score.consistency)
    }

    public static func comparison(_ comparison: GuideComparison, labelA: String, labelB: String) -> String {
        var lines = [
            row("Visited places in common", String(comparison.visitedSimilarity)),
            row("All stops in common", String(comparison.stopSimilarity)),
            "",
            "Interest".padded(18) + labelA.padded(12) + labelB
        ]
        for item in comparison.interests {
            lines.append(item.name.padded(18) + String(item.minutesA).padded(12) + String(item.minutesB))
        }
        lines += [
            "",
            row("Order in \(labelA)", comparison.orderA.joined(separator: ", ")),
            row("Order in \(labelB)", comparison.orderB.joined(separator: ", "))
        ]
        return lines.joined(separator: "\n")
    }

    /// The summary table: one row per guide with the numbers worth diffing between pipeline versions.
    public static func summaryTable(_ scores: [String: GuideScore]) -> String {
        let header = ["guide", "contra", "errors", "warn", "rankAgr", "missed", "paceOff", "spendOver", "consist",
                      "hoursUnk"]
        var lines = [tableRow(header)]
        for (name, score) in scores.sorted(by: { $0.key < $1.key }) {
            let spendOver = score.spend.mealAndDrink.aboveCeiling.count + score.spend.sights.aboveCeiling.count
            let values = [
                name,
                String(score.constraints.contradictions),
                String(score.constraints.findingsBySeverity["error"] ?? 0),
                String(score.constraints.findingsBySeverity["warning"] ?? 0),
                String(score.interests.rankAgreement),
                String(score.interests.missed.count),
                String(offPace(score.pace).count),
                String(spendOver),
                String(score.consistency.problemCount),
                String(score.feasibility.hoursUnknownStops.count)
            ]
            lines.append(tableRow(values))
        }
        return lines.joined(separator: "\n")
    }

    /// One table row: the first column is wide for file names, the rest hold numbers.
    private static func tableRow(_ cells: [String]) -> String {
        cells.enumerated().map { index, cell in cell.padded(index == 0 ? 26 : 12) }.joined()
    }

    // MARK: Sections

    private static func section(_ title: String, _ body: [String]) -> [String] {
        [title] + body + [""]
    }

    private static func constraintLines(_ constraints: ConstraintsScore) -> [String] {
        let severities = ["error", "warning", "info"].map { "\($0) \(constraints.findingsBySeverity[$0] ?? 0)" }
        let base = constraints.base.map { "\($0.name) (\($0.kind))" } ?? "none"
        return ([
            row("contradictions", String(constraints.contradictions)),
            row("structure", constraints.structureError.map { "error: \($0)" } ?? "ok"),
            row("findings", severities.joined(separator: ", ")),
            row("findings by kind", kindText(constraints.findingsByKind)),
            row("stops before arrival", String(constraints.stopsBeforeArrival)),
            row("stops after departure", String(constraints.stopsAfterDeparture)),
            row("stay", constraints.stayArrangement),
            row("base", base)
        ])
    }

    private static func interestLines(_ interests: InterestsScore) -> [String] {
        let rows = interests.byRank.map { item in
            "  \(item.rank). " + item.name.padded(14)
                + "main \(item.mainStops)  meal \(item.mealStops)  \(item.minutes) min  share \(item.share)"
                + "  first \(item.earliestStart ?? "-")"
        }
        let missed = interests.missed.isEmpty ? "none" : interests.missed.joined(separator: ", ")
        return rows + ([
            row("rankAgreement", String(interests.rankAgreement)),
            row("topShare", String(interests.topShare)),
            row("missed", missed)
        ])
    }

    private static func paceLines(_ pace: PaceScore) -> [String] {
        let target = pace.target
        let range = target.mainStopsMax.map { "\(target.mainStopsMin)-\($0)" } ?? "\(target.mainStopsMin)+"
        let first = target.firstStartNotBefore.map { ", first from \($0)" } ?? ""
        let targetLine = "  target: \(range) main stops\(first), about \(target.walkingMinutes) min walking"
        return [targetLine] + pace.days.map(dayPaceLine)
    }

    private static func dayPaceLine(_ day: DayPace) -> String {
        let kind = day.fullDay ? "full" : "partial"
        let main = day.withinTarget.mainStops ? "ok" : "off"
        let walk = day.withinTarget.walking ? "ok" : "off"
        return "  \(day.date) \(kind.padded(9))main \(day.mainStops)  first \(day.firstMainStart ?? "-")"
            + "  walk \(day.walkingMinutes) min  rest \(day.restStops) (\(day.restMinutes) min)"
            + "  unplanned \(day.unplannedMinutes) min  [main \(main), walk \(walk)]"
    }

    private static func spendLines(_ spend: SpendScore) -> [String] {
        ([
            row("meal and drink", levelText(spend.mealAndDrink.byLevel)),
            row("  above ceiling", String(spend.mealAndDrink.aboveCeiling.count)),
            row("sights", levelText(spend.sights.byLevel)),
            row("  above ceiling", String(spend.sights.aboveCeiling.count))
        ])
    }

    private static func feasibilityLines(_ feasibility: FeasibilityScore) -> [String] {
        let days = feasibility.days.map { "  \($0.date)  \($0.firstStart ?? "-") to \($0.lastEnd ?? "-")" }
        return ([
            row("hours unknown (stops)", String(feasibility.hoursUnknownStops.count)),
            row("closed", String(feasibility.closedFindings)),
            row("outside hours", String(feasibility.outsideHoursFindings)),
            row("hours unknown findings", String(feasibility.hoursUnknownFindings)),
            row("durations out of range", String(feasibility.durationsOutOfRange.count)),
            row("legs over 30 min", String(feasibility.longLegs.count))
        ]) + days
    }

    private static func contentLines(_ content: ContentScore) -> [String] {
        let generic = content.genericTasting.isEmpty ? "none" : content.genericTasting.joined(separator: ", ")
        let phrases = content.repeatedPhrases.prefix(3).map { "\"\($0.phrase)\" (\($0.stops) stops)" }
        return ([
            row("tasting", "\(content.tasting), generic: \(generic)"),
            row("practical facts", String(content.practicalFacts)),
            row("open questions", String(content.openQuestions)),
            row("repeated phrases", phrases.isEmpty ? "none" : phrases.joined(separator: ", ")),
            row("long stop bodies", String(content.longBodyStops.count)),
            row("empty notes", content.emptyNotes.isEmpty ? "none" : content.emptyNotes.joined(separator: ", "))
        ])
    }

    private static func consistencyLines(_ consistency: ConsistencyScore) -> [String] {
        ([
            row("problems", String(consistency.problemCount)),
            row("list places missing", String(consistency.listPlaceIdsMissing.count)),
            row("stop places missing", String(consistency.stopPlaceIdsMissing.count)),
            row("list kind mismatches", String(consistency.listKindMismatches.count)),
            row("spare places", String(consistency.unusedPlaceIds.count)),
            row("sources missing", String(consistency.practicalSourcesMissing.count))
        ])
    }

    // MARK: Attention

    private static func constraintFlags(_ score: GuideScore) -> [String] {
        let constraints = score.constraints
        var flags: [String] = []
        if constraints.contradictions > 0 {
            flags.append("\(constraints.contradictions) contradiction(s) between the words and the facts.")
        }
        if !constraints.structureValid {
            flags.append("The guide's structure is not valid.")
        }
        let errors = constraints.findingsBySeverity["error"] ?? 0
        if errors > 0 {
            flags.append("\(errors) plan error(s) from the plan checker.")
        }
        return flags
    }

    private static func interestFlags(_ interests: InterestsScore) -> [String] {
        var flags: [String] = []
        if !interests.missed.isEmpty {
            flags.append("No stop serves: \(interests.missed.joined(separator: ", ")).")
        }
        if interests.rankAgreement < 1 {
            flags.append("Rank agreement \(interests.rankAgreement): a lower-ranked interest got more minutes.")
        }
        return flags
    }

    private static func paceFlags(_ pace: PaceScore) -> [String] {
        offPace(pace).map { day in
            "\(day.date) is off pace: \(day.mainStops) main stops, \(day.walkingMinutes) min walking."
        }
    }

    private static func spendFlags(_ spend: SpendScore) -> [String] {
        let above = spend.mealAndDrink.aboveCeiling + spend.sights.aboveCeiling
        guard !above.isEmpty else { return [] }
        return ["\(above.count) stop(s) above the spend ceiling: \(above.joined(separator: ", "))."]
    }

    private static func feasibilityFlags(_ feasibility: FeasibilityScore) -> [String] {
        var flags: [String] = []
        if !feasibility.durationsOutOfRange.isEmpty {
            flags.append("\(feasibility.durationsOutOfRange.count) stop(s) have an unusual length.")
        }
        if !feasibility.longLegs.isEmpty {
            flags.append("\(feasibility.longLegs.count) leg(s) take over 30 minutes.")
        }
        if !feasibility.hoursUnknownStops.isEmpty {
            flags.append("\(feasibility.hoursUnknownStops.count) stop(s) have unknown opening hours.")
        }
        return flags
    }

    private static func contentFlags(_ content: ContentScore) -> [String] {
        var flags: [String] = []
        if !content.genericTasting.isEmpty {
            flags.append("Generic tasting names: \(content.genericTasting.joined(separator: ", ")).")
        }
        if !content.repeatedPhrases.isEmpty {
            flags.append("\(content.repeatedPhrases.count) phrase(s) repeat across stops.")
        }
        if !content.longBodyStops.isEmpty {
            flags.append("\(content.longBodyStops.count) stop body(ies) are over 60 words.")
        }
        return flags
    }

    private static func consistencyFlags(_ consistency: ConsistencyScore) -> [String] {
        consistency.problemCount > 0 ? ["\(consistency.problemCount) consistency problem(s)."] : []
    }

    /// The full days that miss the pace target on main stops or on walking.
    private static func offPace(_ pace: PaceScore) -> [DayPace] {
        pace.days.filter { $0.fullDay && !($0.withinTarget.mainStops && $0.withinTarget.walking) }
    }

    // MARK: Helpers

    private static func row(_ label: String, _ value: String) -> String {
        "  " + label.padded(labelWidth) + value
    }

    private static func levelText(_ byLevel: [String: Int]) -> String {
        ["1", "2", "3", "4", "unknown"].map { "\($0): \(byLevel[$0] ?? 0)" }.joined(separator: "  ")
    }

    private static func kindText(_ byKind: [String: Int]) -> String {
        guard !byKind.isEmpty else { return "none" }
        return byKind.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }
}

extension String {
    /// The text padded with spaces to `width` characters, or with one space when it is already wider.
    func padded(_ width: Int) -> String {
        padding(toLength: max(width, count + 1), withPad: " ", startingAt: 0)
    }
}
