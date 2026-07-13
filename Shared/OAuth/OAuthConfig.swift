import Foundation

/// Per-provider OAuth 2.0 endpoints and client configuration.
struct OAuthConfig {
    let provider: ProviderID
    let authorizeURL: URL
    let tokenURL: URL
    let clientID: String
    let scopes: [String]
    let redirectURI: String
    /// Custom URL scheme `ASWebAuthenticationSession` should intercept, or nil
    /// when the provider uses the manual copy-the-code flow below.
    let callbackScheme: String?
    /// When true, the provider's registered redirect can't be captured by this
    /// app (it's a first-party client), so the user copies an authorization code
    /// shown in the browser and pastes it back in.
    let usesManualCodeEntry: Bool
    /// Extra query items appended to the authorize URL.
    let extraAuthorizeParams: [String: String]

    static func config(for provider: ProviderID) -> OAuthConfig? {
        switch provider {
        case .anthropic:
            // The OAuth client used by Claude Code to log in with a Claude
            // subscription. This is Anthropic's *first-party* client, so the
            // redirect is fixed to a console page that displays the code —
            // hence the manual copy-and-paste flow. Using it from a third-party
            // app is an undocumented / ToS-gray path; it exists to surface the
            // 5-hour session window and may change without notice.
            return OAuthConfig(
                provider: .anthropic,
                authorizeURL: URL(string: "https://claude.ai/oauth/authorize")!,
                tokenURL: URL(string: "https://console.anthropic.com/v1/oauth/token")!,
                clientID: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
                scopes: ["org:create_api_key", "user:profile", "user:inference"],
                redirectURI: "https://console.anthropic.com/oauth/code/callback",
                callbackScheme: nil,
                usesManualCodeEntry: true,
                extraAuthorizeParams: ["code": "true"]
            )
        case .google:
            // Bring-your-own OAuth client. Create an **iOS** OAuth client ID in
            // the Google Cloud console, enable the Generative Language API, and
            // paste the client ID below. The redirect scheme is the reversed
            // client ID, which `ASWebAuthenticationSession` intercepts directly.
            let clientID = "YOUR_GOOGLE_IOS_CLIENT_ID.apps.googleusercontent.com"
            let reversed = clientID
                .replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
                .split(separator: ".")
                .reversed()
                .joined(separator: ".")
            let scheme = "com.googleusercontent.apps.\(reversed)"
            return OAuthConfig(
                provider: .google,
                authorizeURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
                clientID: clientID,
                scopes: ["https://www.googleapis.com/auth/cloud-platform"],
                redirectURI: "\(scheme):/oauthredirect",
                callbackScheme: scheme,
                usesManualCodeEntry: false,
                extraAuthorizeParams: ["access_type": "offline", "prompt": "consent"]
            )
        case .openai:
            // "Sign in with ChatGPT" — the OAuth flow the Codex CLI uses to read
            // the 5-hour and weekly plan windows. The client ID is not published,
            // so supply your own (or Codex's, if you have it) below; the token
            // endpoint and PKCE mechanics are standard. Wiring the private usage
            // endpoint that returns the 5h/weekly numbers is left as a TODO in
            // OpenAIUsageProvider.
            return OAuthConfig(
                provider: .openai,
                authorizeURL: URL(string: "https://auth.openai.com/oauth/authorize")!,
                tokenURL: URL(string: "https://auth.openai.com/oauth/token")!,
                clientID: "YOUR_OPENAI_OAUTH_CLIENT_ID",
                scopes: ["openid", "profile", "email", "offline_access"],
                redirectURI: "usageai://oauth/openai",
                callbackScheme: "usageai",
                usesManualCodeEntry: false,
                extraAuthorizeParams: [:]
            )
        }
    }

    var isConfigured: Bool {
        !clientID.hasPrefix("YOUR_")
    }

    /// Builds the full authorize URL for a PKCE flow.
    func buildAuthorizeURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state)
        ]
        for (key, value) in extraAuthorizeParams {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items
        return components.url!
    }
}
