import Foundation
import ResponsesKit
import Testing

struct IDTokenTests {
    private var jwks: JWKS {
        get throws {
            let json = """
            {"keys":[{"kty":"RSA","alg":"RS256","use":"sig","kid":"\(JWTVector.kid)",
            "n":"\(JWTVector.modulus)","e":"\(JWTVector.exponent)"}]}
            """
            return try JSONDecoder().decode(JWKS.self, from: Data(json.utf8))
        }
    }

    private let now = Date(timeIntervalSince1970: 1_767_300_000)

    @Test func aValidTokenVerifiesAndGivesTheClaims() throws {
        let claims = try IDTokenVerifier.verify(
            JWTVector.token,
            jwks: try jwks,
            clientId: JWTVector.clientId,
            nonce: JWTVector.nonce,
            now: now
        )
        #expect(claims.subject == "test-subject-0001")
        #expect(claims.issuer == "https://auth.openai.com")
        #expect(claims.email == "tester@example.com")
        #expect(claims.audiences == [JWTVector.clientId])
    }

    @Test func aWrongNonceIsRejected() throws {
        #expect(throws: IDTokenError.nonceMismatch) {
            _ = try IDTokenVerifier.verify(JWTVector.token, jwks: try jwks, clientId: JWTVector.clientId,
                                           nonce: "other-nonce", now: now)
        }
    }

    @Test func aWrongAudienceIsRejected() throws {
        #expect(throws: IDTokenError.wrongAudience) {
            _ = try IDTokenVerifier.verify(JWTVector.token, jwks: try jwks, clientId: "some-other-client",
                                           nonce: JWTVector.nonce, now: now)
        }
    }

    @Test func anExpiredTokenIsRejected() throws {
        let later = Date(timeIntervalSince1970: 4_102_444_800 + 3_600)
        #expect(throws: IDTokenError.expired) {
            _ = try IDTokenVerifier.verify(JWTVector.token, jwks: try jwks, clientId: JWTVector.clientId,
                                           nonce: JWTVector.nonce, now: later)
        }
    }

    @Test func aChangedSignatureIsRejected() throws {
        var parts = JWTVector.token.split(separator: ".").map(String.init)
        var signature = Array(parts[2])
        signature[20] = signature[20] == "A" ? "B" : "A"
        parts[2] = String(signature)
        let tampered = parts.joined(separator: ".")
        #expect(throws: IDTokenError.badSignature) {
            _ = try IDTokenVerifier.verify(tampered, jwks: try jwks, clientId: JWTVector.clientId,
                                           nonce: JWTVector.nonce, now: now)
        }
    }

    @Test func aKeyWithAnotherIdIsNotUsed() throws {
        let json = """
        {"keys":[{"kty":"RSA","alg":"RS256","kid":"other-kid","n":"\(JWTVector.modulus)","e":"\(JWTVector.exponent)"}]}
        """
        let other = try JSONDecoder().decode(JWKS.self, from: Data(json.utf8))
        #expect(throws: IDTokenError.unknownKey) {
            _ = try IDTokenVerifier.verify(JWTVector.token, jwks: other, clientId: JWTVector.clientId,
                                           nonce: JWTVector.nonce, now: now)
        }
    }

    @Test func aMalformedTokenIsRejected() throws {
        #expect(throws: IDTokenError.malformed) {
            _ = try IDTokenVerifier.verify("not-a-jwt", jwks: try jwks, clientId: JWTVector.clientId,
                                           nonce: JWTVector.nonce, now: now)
        }
    }
}
