import Foundation
import ResponsesKit

/// `probe`: runs the five checks on the ChatGPT plan route and writes report.md with the raw bodies. It never falls
/// back to an API key, and it stops at eight requests.
enum ProbeCommand {
    static let requestLimit = 8
    static let defaultOutput = "probe-output/chatgpt"

    struct Options {
        let model: String?
        let outputPath: String
    }

    struct ParseFailure: Error {
        let text: String
    }

    static func run(arguments: [String]) async -> Int32 {
        let options: Options
        switch parse(arguments) {
        case .success(let parsed):
            options = parsed
        case .failure(let failure):
            complain(failure.text)
            return 2
        }

        // Credentials come first, so a missing sign-in gets its own message even without --model.
        let store = CredentialStore.defaultStore
        let file: CredentialFile?
        do {
            file = try store.load()
        } catch {
            complain("The credentials file at \(store.url.path) cannot be read.")
            return 1
        }
        guard file?.credentials != nil else {
            complain("No ChatGPT credentials at \(store.url.path). Run `swift run taba-chatgpt sign-in` first.")
            return 1
        }
        guard let model = options.model else {
            complain("--model is required: the docs name no default model for this route.")
            return 2
        }

        let context = ProbeContext(
            model: model,
            session: CredentialSession(store: store, tokenClient: TokenClient()),
            client: ResponsesClient(),
            store: store,
            budget: ProbeBudget(limit: requestLimit)
        )
        var records: [ProbeRecord] = []
        records.append(await context.basic())
        records.append(await context.planSchema())
        records.append(await context.webSearchSchema())
        records.append(await context.forcedRefresh())
        records.append(await context.basic(key: "d-after-refresh", title: "d. basic after refresh"))
        records.append(await context.rejectedTemperature())

        for record in records {
            print("\(record.title): \(record.line)")
        }
        return ProbeReport.write(
            records: records,
            model: model,
            outputPath: options.outputPath,
            requestLimit: requestLimit
        )
    }

    static func parse(_ arguments: [String]) -> Result<Options, ParseFailure> {
        var model: String?
        var outputPath = defaultOutput
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument == "--model" || argument == "--out" else {
                return .failure(ParseFailure(text: "Unknown option \(argument)."))
            }
            index += 1
            guard index < arguments.count else {
                return .failure(ParseFailure(text: "\(argument) needs a value."))
            }
            if argument == "--model" {
                model = arguments[index]
            } else {
                outputPath = arguments[index]
            }
            index += 1
        }
        return .success(Options(model: model, outputPath: outputPath))
    }
}
