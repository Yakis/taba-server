import Foundation
import ServerKit
import Testing

struct ServerModeTests {
    @Test func replayRequiresAnExplicitNonemptyDirectory() throws {
        #expect(try ServerMode.parse([:]) == .live)
        #expect(try ServerMode.parse(["TABA_REPLAY_DIRECTORY": "/tmp/example-replay"]) ==
                .replay(URL(fileURLWithPath: "/tmp/example-replay")))
        for value in ["", " ", "\n"] {
            #expect(throws: ServerMode.ConfigurationError.self) {
                try ServerMode.parse(["TABA_REPLAY_DIRECTORY": value, "FOURSQUARE_API_KEY": "test-key-not-real"])
            }
        }
    }
}
