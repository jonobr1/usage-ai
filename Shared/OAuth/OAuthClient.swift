import Foundation

/// Networking for the OAuth 2.0 token endpoint: exchanging an authorization
/// code for tokens and refreshing an expired access token. No UI — usable from
/// both the app and the widget extension.
enum OAuthClient {
    enum OAuthClientError: LocalizedError {
        case tokenRequest(Int, String)
        case decoding

        var errorDescription: String? {
            switch self {
            case .tokenRequest(let code, let body):
                return "Token endpoint returned \(code): \(body.prefix(140))"
            case .decoding:
                return "Could not read token response"
            }
        }
    }

    /// Exchanges an authorization code (with its PKCE verifier) for tokens.
    static func exchange(config: OAuthConfig,
                         code: String,
                         verifier: String) async throws -> OAuthToken {
        // Anthropic returns the code as "code#state" on the callback page; keep
        // only the code portion.
        let cleanCode = code.split(separator: "#").first.map(String.init) ?? code
        var params = [
            "grant_type": "authorization_code",
            "code": cleanCode,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientID,
            "code_verifier": verifier
        ]
        if config.provider == .anthropic,
           let state = code.split(separator: "#").dropFirst().first {
            params["state"] = String(state)
        }
        return try await postToken(config: config, params: params, fallbackRefresh: nil)
    }

    /// Refreshes an access token using its refresh token.
    static func refresh(config: OAuthConfig, token: OAuthToken) async throws -> OAuthToken {
        guard let refreshToken = token.refreshToken else { return token }
        let params = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID
        ]
        return try await postToken(config: config, params: params, fallbackRefresh: refreshToken)
    }

    private static func postToken(config: OAuthConfig,
                                  params: [String: String],
                                  fallbackRefresh: String?) async throws -> OAuthToken {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw OAuthClientError.tokenRequest(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(OAuthTokenResponse.self, from: data) else {
            throw OAuthClientError.decoding
        }
        return decoded.asToken(fallbackRefresh: fallbackRefresh)
    }
}
