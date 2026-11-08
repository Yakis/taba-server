import _CryptoExtras
import Crypto
import Foundation

/// One key from the issuer's JWKS. Only RSA keys are used, as the discovery document lists RS256 only.
public struct JWK: Decodable, Sendable, Hashable {
    public let kty: String
    public let kid: String?
    public let alg: String?
    public let modulus: String?
    public let exponent: String?

    enum CodingKeys: String, CodingKey {
        case kty
        case kid
        case alg
        case modulus = "n"
        case exponent = "e"
    }
}

public struct JWKS: Decodable, Sendable, Hashable {
    public let keys: [JWK]
}

/// The claims this app checks. `aud` may be a string or a list in the token; both are read.
public struct IDTokenClaims: Sendable, Equatable {
    public let issuer: String
    public let subject: String
    public let audiences: [String]
    public let expiresAt: Date
    public let nonce: String?
    public let email: String?
}

public enum IDTokenError: Error, Sendable, Equatable {
    case malformed
    case unsupportedAlgorithm(String?)
    case unknownKey
    case badSignature
    case wrongIssuer
    case wrongAudience
    case expired
    case nonceMismatch
    case missingSubject
}

/// Verifies an ID token as the sign-in docs require: RS256 signature against the issuer's JWKS, then issuer,
/// audience (the issued client ID), expiry with a small clock skew, nonce and subject.
public enum IDTokenVerifier {
    public static let issuer = "https://auth.openai.com"
    public static let jwksURL = "https://auth.openai.com/.well-known/jwks.json"

    public static func verify(
        _ token: String,
        jwks: JWKS,
        clientId: String,
        nonce: String,
        now: Date,
        clockSkew: TimeInterval = 60
    ) throws(IDTokenError) -> IDTokenClaims {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let headerData = Base64URL.decode(parts[0]),
              let payloadData = Base64URL.decode(parts[1]), let signature = Base64URL.decode(parts[2])
        else {
            throw .malformed
        }
        let header = try decodeHeader(headerData)
        guard header.alg == "RS256" else { throw .unsupportedAlgorithm(header.alg) }
        try verifySignature(signed: "\(parts[0]).\(parts[1])", signature: signature, kid: header.kid, jwks: jwks)
        let claims = try decodeClaims(payloadData)
        try check(claims, clientId: clientId, nonce: nonce, now: now, clockSkew: clockSkew)
        return claims
    }

    private struct Header: Decodable {
        let alg: String?
        let kid: String?
    }

    private static func decodeHeader(_ data: Data) throws(IDTokenError) -> Header {
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { throw .malformed }
        return header
    }

    private static func verifySignature(
        signed: String,
        signature: Data,
        kid: String?,
        jwks: JWKS
    ) throws(IDTokenError) {
        guard let jwk = jwks.keys.first(where: { $0.kid == kid && $0.kty == "RSA" }),
              let modulus = jwk.modulus.flatMap(Base64URL.decode),
              let exponent = jwk.exponent.flatMap(Base64URL.decode)
        else {
            throw .unknownKey
        }
        let publicKey: _RSA.Signing.PublicKey
        do {
            publicKey = try _RSA.Signing.PublicKey(n: modulus, e: exponent)
        } catch {
            throw .unknownKey
        }
        let digest = SHA256.hash(data: Data(signed.utf8))
        let rsaSignature = _RSA.Signing.RSASignature(rawRepresentation: signature)
        let valid = publicKey.isValidSignature(rsaSignature, for: digest, padding: .insecurePKCS1v1_5)
        guard valid else { throw .badSignature }
    }

    private static func decodeClaims(_ data: Data) throws(IDTokenError) -> IDTokenClaims {
        struct Payload: Decodable {
            let iss: String?
            let sub: String?
            let aud: Audience?
            let exp: TimeInterval?
            let nonce: String?
            let email: String?
        }
        enum Audience: Decodable {
            case one(String)
            case many([String])

            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let value = try? container.decode(String.self) {
                    self = .one(value)
                } else {
                    self = .many(try container.decode([String].self))
                }
            }

            var values: [String] {
                switch self {
                case .one(let value): [value]
                case .many(let values): values
                }
            }
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { throw .malformed }
        guard let exp = payload.exp else { throw .malformed }
        return IDTokenClaims(
            issuer: payload.iss ?? "",
            subject: payload.sub ?? "",
            audiences: payload.aud?.values ?? [],
            expiresAt: Date(timeIntervalSince1970: exp),
            nonce: payload.nonce,
            email: payload.email
        )
    }

    private static func check(
        _ claims: IDTokenClaims,
        clientId: String,
        nonce: String,
        now: Date,
        clockSkew: TimeInterval
    ) throws(IDTokenError) {
        guard claims.issuer == issuer else { throw .wrongIssuer }
        guard claims.audiences.contains(clientId) else { throw .wrongAudience }
        guard claims.expiresAt.addingTimeInterval(clockSkew) > now else { throw .expired }
        guard claims.nonce == nonce else { throw .nonceMismatch }
        guard !claims.subject.isEmpty else { throw .missingSubject }
    }
}
