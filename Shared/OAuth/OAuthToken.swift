import Foundation

/// An OAuth 2.0 token set persisted for a provider.
struct OAuthToken: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var scope: String?

    /// True when the access token is missing an expiry or is within two minutes
    /// of expiring — refresh before use.
    var isExpiringSoon: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 120
    }

    init(accessToken: String,
         refreshToken: String? = nil,
         expiresIn: TimeInterval? = nil,
         scope: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresIn.map { Date().addingTimeInterval($0) }
        self.scope = scope
    }
}

/// The raw JSON shape returned by an OAuth token endpoint.
struct OAuthTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: TimeInterval?
    let scope: String?

    func asToken(fallbackRefresh: String?) -> OAuthToken {
        OAuthToken(accessToken: access_token,
                   refreshToken: refresh_token ?? fallbackRefresh,
                   expiresIn: expires_in,
                   scope: scope)
    }
}
