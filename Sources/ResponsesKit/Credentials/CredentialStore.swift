import Foundation

public enum CredentialStoreError: Error, Sendable, Equatable {
    case unreadable
    case writeFailed
}

/// Reads and writes the credentials file. Writes are atomic, and the file is owner-only (0600) inside an owner-only
/// folder (0700), so a token is never readable by others, even briefly.
public struct CredentialStore: Sendable {
    public static let environmentVariable = "TABA_CHATGPT_CREDENTIALS"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The path from TABA_CHATGPT_CREDENTIALS, or ~/.config/taba/chatgpt.json.
    public static func defaultURL(environment: [String: String], home: URL) -> URL {
        if let override = environment[environmentVariable], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return home.appendingPathComponent(".config/taba/chatgpt.json")
    }

    public static var defaultStore: CredentialStore {
        CredentialStore(url: defaultURL(
            environment: ProcessInfo.processInfo.environment,
            home: FileManager.default.homeDirectoryForCurrentUser
        ))
    }

    public func exists() -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// The stored file, or nil when there is none. A file that cannot be read or decoded is an error, not nil.
    public func load() throws(CredentialStoreError) -> CredentialFile? {
        guard exists() else { return nil }
        guard let data = try? Data(contentsOf: url) else { throw .unreadable }
        guard let file = try? Self.decoder.decode(CredentialFile.self, from: data) else { throw .unreadable }
        return file
    }

    /// Writes the file atomically. The folder is created with 0700 if needed. The file is created with 0600 and
    /// then moved into place, so the old file is never half-written.
    public func save(_ file: CredentialFile) throws(CredentialStoreError) {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw .writeFailed
        }
        guard let data = try? Self.encoder.encode(file) else { throw .writeFailed }
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw .writeFailed
        }
        do {
            if exists() {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw .writeFailed
        }
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalFormatter.string(from: date))
        }
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = fractionalFormatter.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "bad date")
            }
            return date
        }
        return decoder
    }

    /// ISO 8601 in UTC with fractional seconds, so a saved date reads back exactly.
    static var fractionalFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
