import Foundation
import CryptoKit
import Security

/// A PKCE (Proof Key for Code Exchange, RFC 7636) verifier/challenge pair.
struct PKCE {
    let verifier: String
    let challenge: String
    let method = "S256"

    init() {
        verifier = Self.randomURLSafeString(byteCount: 32)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        challenge = Data(digest).base64URLEncodedString()
    }

    /// Cryptographically random, base64url-encoded string (no padding).
    static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

extension Data {
    /// Base64url encoding without padding, per RFC 4648 §5.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
