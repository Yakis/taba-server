import Foundation
import GuideKit

struct Options: Sendable {
    let destination: String
    let from: LocalDate
    let to: LocalDate
    let stay: String?
    let model: String
    let out: String?
    let facts: String?

    static func parse(_ arguments: [String]) throws -> Options {
        guard arguments.first == "build" else { throw CLIError.usage }
        let allowed = Set(["--destination", "--from", "--to", "--stay", "--model", "--out", "--facts"])
        var values: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            guard allowed.contains(key), values[key] == nil, index + 1 < arguments.count,
                  !arguments[index + 1].hasPrefix("--"),
                  !arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CLIError.usage
            }
            values[key] = arguments[index + 1]
            index += 2
        }
        guard let destination = values["--destination"], let start = values["--from"].flatMap(LocalDate.init),
              let end = values["--to"].flatMap(LocalDate.init), start <= end else { throw CLIError.usage }
        return Options(destination: destination, from: start, to: end, stay: values["--stay"],
                       model: values["--model"] ?? "gpt-6.1-sol", out: values["--out"], facts: values["--facts"])
    }
}

enum CLIError: Error {
    case usage, factsMismatch, missingStay, geocoding, missingKey, noCandidates, output, service, recording
}
