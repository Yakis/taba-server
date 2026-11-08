/// A signed test ID token and its public key. The private key was generated for this vector and discarded.
/// The token is for tests only: it names no real account. Its claims: iss https://auth.openai.com,
/// sub test-subject-0001, aud test-client-0001, nonce test-nonce-0001, exp 4102444800.
enum JWTVector {
    static let token =
"eyJhbGciOiJSUzI1NiIsImtpZCI6InRlc3Qta2lkLTEiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL2F1dGg"
        + "ub3BlbmFpLmNvbSIsInN1YiI6InRlc3Qtc3ViamVjdC0wMDAxIiwiYXVkIjpbInRlc3QtY2xpZW50LTAwMDEiXSwiZ"
        + "XhwIjo0MTAyNDQ0ODAwLCJpYXQiOjE3NjcyMjU2MDAsIm5vbmNlIjoidGVzdC1ub25jZS0wMDAxIiwiZW1haWwiOiJ"
        + "0ZXN0ZXJAZXhhbXBsZS5jb20ifQ.S4QKRahuYQOlIgzic09Pbm-AnGAZtRrAxWA6_bIccVttfuPACN1fszA3SG3_0m"
        + "S02VMAlJjcT5YqO3jiNHDcBCLNPzChlR_ik7CHgAjZ5O_TmHgNnVJiF5CxOVw-q2At5SDFeu1_mQomnQNh24_3QEQz"
        + "-z8xYa1NpnH_e_UgfBisKpSYA0yuJwtNFnGvHgurPNX3K2-D8XSJznY-QhDEUa4-FfOkptDmpC7KDqJTVKpwcy4lzq"
        + "ObVwkpPIuCFzIb9wSYgXjrH9MyyKfkGIeun_EFfp4kwpslFX2a07duemRQSx78ZPlWHm8QDdF-2WdV8uT47dexaKit"
        + "wLikgdykjA"
    static let modulus =
        "sgy44dZ7Yn3-xzWnEDA38izn7NFiO0OrknXvobllmY0Y9_ycvdKDTSaWnvdSTocG6m6AXHnvlcYU2WCEd-CZTVHJMf"
        + "LlYMtd_JpV6Q7dsnXvtHypnlXEhsfK9vagvVWjLXfgd_ULYLdvm1ffnkFIMonwyy_dynSN3BJfgBJw2IFNPS0T2g7m"
        + "-jVh1R4pf-FTuI8zWCO_ZvroWwhKlE-YQs0AdqHLyY0hFiZkUrcbNY2xDK06KROPDvrdJcXaZFB_KKlcILZbsFaY6U"
        + "IGsMEBucp264eBHU5EN2Uyae6SyQ0BduPk1XwHg8-7a5ANKcaFHXUOoSpvPylpg1PLU9cFDw"
    static let exponent = "AQAB"
    static let kid = "test-kid-1"
    static let clientId = "test-client-0001"
    static let nonce = "test-nonce-0001"
}
