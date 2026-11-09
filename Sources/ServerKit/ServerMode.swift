import Foundation

public enum ServerMode: Sendable, Equatable {
    case live
    case replay(URL)

    public enum ConfigurationError: Error { case emptyReplayDirectory }

    public static func parse(_ environment: [String: String]) throws -> ServerMode {
        guard let directory = environment["TABA_REPLAY_DIRECTORY"] else { return .live }
        guard !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigurationError.emptyReplayDirectory
        }
        return .replay(URL(fileURLWithPath: directory))
    }
}
