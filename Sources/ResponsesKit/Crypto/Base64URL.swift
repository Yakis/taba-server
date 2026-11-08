import Foundation

/// Base64url without padding (RFC 4648 section 5), as OAuth and JWT use it.
public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ text: String) -> Data? {
        var standard = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % 4
        if remainder != 0 {
            standard += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: standard)
    }
}

/// Random bytes from the system generator, which is cryptographically secure on Apple and Linux.
public enum RandomBytes {
    public static func make(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    /// A random URL-safe string made from `count` random bytes.
    public static func base64URLString(count: Int) -> String {
        Base64URL.encode(make(count: count))
    }
}
