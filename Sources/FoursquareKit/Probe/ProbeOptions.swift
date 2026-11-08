/// Command-line options: `<fixture.json> [--premium] [--out <directory>]`.
public struct ProbeOptions: Sendable, Equatable {
    public let fixturePath: String
    public let premium: Bool
    public let outputPath: String

    public static let defaultOutputPath = "probe-output/foursquare"
    public static let usage = "usage: foursquare-probe <fixture.json> [--premium] [--out <directory>]"

    public init(fixturePath: String, premium: Bool, outputPath: String) {
        self.fixturePath = fixturePath
        self.premium = premium
        self.outputPath = outputPath
    }

    public static func parse(_ arguments: [String]) throws(ProbeOptionsError) -> ProbeOptions {
        var fixturePath: String?
        var premium = false
        var outputPath = defaultOutputPath
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--premium":
                premium = true
            case "--out":
                index += 1
                guard index < arguments.count else { throw .missingValue("--out") }
                outputPath = arguments[index]
            default:
                if argument.hasPrefix("--") { throw .unknownOption(argument) }
                guard fixturePath == nil else { throw .unexpectedArgument(argument) }
                fixturePath = argument
            }
            index += 1
        }
        guard let fixturePath else { throw .missingFixture }
        return ProbeOptions(fixturePath: fixturePath, premium: premium, outputPath: outputPath)
    }
}

public enum ProbeOptionsError: Error, Equatable {
    case missingFixture
    case missingValue(String)
    case unknownOption(String)
    case unexpectedArgument(String)
}
