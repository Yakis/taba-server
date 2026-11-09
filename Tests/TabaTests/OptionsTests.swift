@testable import Taba
import Testing

@Test func validOptions() throws {
    let options = try Options.parse(["build", "--destination", "Edinburgh", "--from", "2025-11-23",
                                     "--to", "2025-11-25"])
    #expect(options.model == "gpt-6.1-sol")
    #expect(options.from.description == "2025-11-23")
}

@Test(arguments: [
    ["build"],
    ["build", "--destination", "X", "--from", "2025-02-30", "--to", "2025-03-01"],
    ["build", "--destination", "X", "--from", "2025-03-02", "--to", "2025-03-01"],
    ["build", "--destination", "X", "--destination", "Y", "--from", "2025-03-01", "--to", "2025-03-02"]
]) func invalidOptions(arguments: [String]) {
    #expect(throws: (any Error).self) { try Options.parse(arguments) }
}
