import Foundation

/// Escaping and links for the HTML renderer. Only web addresses (http and https) become links. Anything else is
/// shown as plain text, so a guide never links to a script or a dialler by accident.
enum HTML {
    /// The info symbol that marks uncertain hours. It is decorative, so screen readers skip it.
    static let infoMark = "<span class=\"info-mark\" aria-hidden=\"true\">ⓘ</span>"

    /// Escapes the characters that can end or change HTML text or an attribute value.
    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    /// The text with spaces and line breaks at both ends removed.
    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The trimmed text, or nil when nothing is left.
    static func nonBlank(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = trimmed(text)
        return value.isEmpty ? nil : value
    }

    /// Lower-case ASCII letters and digits kept, every other character turned into "-". Locale-free.
    static func slug(_ text: String) -> String {
        String(text.lowercased().map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "-"
        })
    }

    /// The id of a place's card on the page, for example "place-osm-node-2441578938".
    static func placeAnchor(_ placeId: String) -> String {
        "place-" + slug(placeId)
    }

    /// The id of a stop's row on the timeline, for example "stop-d1-s2".
    static func stopAnchor(_ stopId: String) -> String {
        "stop-" + slug(stopId)
    }

    /// The host of an http or https address, for example "example.com" for "https://example.com/a?b=c". Nil for any
    /// other address, or one with no host.
    static func host(of address: String) -> String? {
        let lower = address.lowercased()
        let rest: Substring
        if lower.hasPrefix("https://") {
            rest = address.dropFirst(8)
        } else if lower.hasPrefix("http://") {
            rest = address.dropFirst(7)
        } else {
            return nil
        }
        let end = rest.firstIndex(where: { "/?#".contains($0) }) ?? rest.endIndex
        let host = String(rest[..<end])
        guard !host.isEmpty, !host.contains("@") else { return nil }
        return host
    }

    /// The trimmed address when it is a usable http or https address: no spaces, quotes or angle brackets.
    static func webAddress(_ text: String?) -> String? {
        guard let value = nonBlank(text) else { return nil }
        guard !value.contains(where: { $0.isWhitespace || "\"'<>".contains($0) }) else { return nil }
        return host(of: value) == nil ? nil : value
    }

    /// The host as people read it, without a leading "www.": "example.com" for "https://www.example.com/page".
    static func displayHost(_ address: String) -> String? {
        guard let host = host(of: address) else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// An anchor to a web address, or the escaped label alone when the address is not a web address.
    static func link(_ label: String, to address: String?, class cssClass: String? = nil) -> String {
        let text = escape(label)
        guard let url = webAddress(address) else { return text }
        let classAttribute = cssClass.map { " class=\"\($0)\"" } ?? ""
        return "<a href=\"\(escape(url))\"\(classAttribute)>\(text)</a>"
    }

    /// An anchor to a place's card elsewhere on the page.
    static func placeLink(_ label: String, placeId: String) -> String {
        "<a href=\"#\(placeAnchor(placeId))\">\(escape(label))</a>"
    }
}
