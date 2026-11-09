import Foundation
import GuideKit

/// Encodes with the shared TABA encoder and decodes with the shared decoder.
func roundTrip<Value: Codable & Equatable>(_ value: Value) throws -> Value {
    let data = try GuideKit.jsonEncoder().encode(value)
    return try GuideKit.jsonDecoder().decode(Value.self, from: data)
}

/// The JSON text that the shared TABA encoder produces for a value.
func encodedJSON<Value: Encodable>(_ value: Value) throws -> String {
    let data = try GuideKit.jsonEncoder().encode(value)
    guard let text = String(data: data, encoding: .utf8) else {
        throw NotUTF8Error()
    }
    return text
}

struct NotUTF8Error: Error {}
