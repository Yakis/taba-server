/// One server-sent event: the optional `event:` name and the joined `data:` lines.
public struct SSEEvent: Sendable, Equatable {
    public let name: String?
    public let data: String

    public init(name: String?, data: String) {
        self.name = name
        self.data = data
    }
}

/// Reads server-sent events line by line, as the text/event-stream format defines. A blank line ends an event.
public struct SSEParser: Sendable {
    private var name: String?
    private var dataLines: [String] = []

    public init() {}

    /// Feeds one line. Returns an event when the line ends one.
    public mutating func consume(line: String) -> SSEEvent? {
        if line.isEmpty {
            return flush()
        }
        if line.hasPrefix(":") {
            return nil
        }
        let field: String
        let value: String
        if let colon = line.firstIndex(of: ":") {
            field = String(line[..<colon])
            var rest = line[line.index(after: colon)...]
            if rest.first == " " {
                rest = rest.dropFirst()
            }
            value = String(rest)
        } else {
            field = line
            value = ""
        }
        switch field {
        case "event": name = value
        case "data": dataLines.append(value)
        default: break
        }
        return nil
    }

    /// Ends the stream. Returns any event still waiting for its blank line.
    public mutating func finish() -> SSEEvent? {
        flush()
    }

    private mutating func flush() -> SSEEvent? {
        defer {
            name = nil
            dataLines = []
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(name: name, data: dataLines.joined(separator: "\n"))
    }
}
