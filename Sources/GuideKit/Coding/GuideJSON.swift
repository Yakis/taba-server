import Foundation

extension GuideKit {
    /// The encoder used for every TABA JSON file. Sorted keys and pretty printing keep output stable and diffable.
    public static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// The decoder used for every TABA JSON file. Dates, times and coordinates are validated while decoding.
    public static func jsonDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}
