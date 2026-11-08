import Foundation

/// Splits a byte stream into lines, keeping empty lines.
///
/// Server-sent events end each event with an empty line, so a splitter that skips empty lines (such as
/// Foundation's `AsyncLineSequence`) merges every event into one. Lines end at `\n`, and a trailing `\r` is
/// removed. A final line without a newline is still delivered.
enum StreamLines {
    static func split<Bytes: AsyncSequence>(
        _ bytes: Bytes,
        onLine: (String) -> Void
    ) async throws where Bytes.Element == UInt8 {
        var buffer: [UInt8] = []
        for try await byte in bytes {
            if byte == UInt8(ascii: "\n") {
                onLine(line(from: buffer))
                buffer.removeAll(keepingCapacity: true)
            } else {
                buffer.append(byte)
            }
        }
        if !buffer.isEmpty {
            onLine(line(from: buffer))
        }
    }

    private static func line(from buffer: [UInt8]) -> String {
        let trimmed = buffer.last == UInt8(ascii: "\r") ? buffer.dropLast() : buffer[...]
        // A line is whole (it was cut at a newline byte), so only a server sending bad UTF-8 gives "".
        return String(bytes: trimmed, encoding: .utf8) ?? ""
    }
}
