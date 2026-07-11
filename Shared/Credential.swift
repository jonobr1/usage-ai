import Foundation

/// How a provider is authenticated. A provider is stored as exactly one of
/// these in the shared keychain.
enum Credential: Codable, Equatable {
    case apiKey(String)
    case oauth(OAuthToken)

    var isOAuth: Bool { if case .oauth = self { return true }; return false }
}

/// Persists a `Credential` per provider as JSON in the shared keychain.
enum CredentialStore {
    private static func account(_ provider: ProviderID) -> String {
        "credential.\(provider.rawValue)"
    }

    static func save(_ credential: Credential, for provider: ProviderID) {
        guard let data = try? JSONEncoder().encode(credential),
              let json = String(data: data, encoding: .utf8) else { return }
        KeychainStore.save(json, account: account(provider))
    }

    static func read(_ provider: ProviderID) -> Credential? {
        guard let json = KeychainStore.read(account: account(provider)),
              let data = json.data(using: .utf8),
              let credential = try? JSONDecoder().decode(Credential.self, from: data) else {
            return nil
        }
        return credential
    }

    static func delete(_ provider: ProviderID) {
        KeychainStore.delete(account: account(provider))
    }

    static func isConnected(_ provider: ProviderID) -> Bool {
        read(provider) != nil
    }
}

/// Resolves a provider's credential to a *fresh* one, transparently refreshing
/// an expiring OAuth access token and persisting the new token. No UI, so it
/// works from the widget as well as the app.
enum CredentialManager {
    static func resolve(_ provider: ProviderID) async -> Credential? {
        guard var credential = CredentialStore.read(provider) else { return nil }
        if case .oauth(let token) = credential,
           token.isExpiringSoon,
           let config = OAuthConfig.config(for: provider),
           let refreshed = try? await OAuthClient.refresh(config: config, token: token) {
            credential = .oauth(refreshed)
            CredentialStore.save(credential, for: provider)
        }
        return credential
    }
}
